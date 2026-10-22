// Builds the LVGL objects for one WatchFace and keeps them up to date. Everything a face allocates (hand bitmaps,
// gradient and pattern descriptors, fonts) belongs to its RenderedFace and is freed when its root object is deleted,
// whoever deletes it (the carousel, or the app framework deleting the screen).
//
// A face has a static layer (background, dial, ticks, numerals, fixed text) and moving parts (hands, time, date,
// steps, battery). Drawing the static layer is most of the work, so Baker draws it once into the memory-mapped slot
// (StaticSlot) and it is shown as one image from there; the moving parts are always drawn on top of it.

enum RenderMode {
    /// On screen: the static layer from the slot if it holds this face's, otherwise live static objects (and the
    /// Baker fills the slot)
    case live
    /// Just the static layer, for baking it. Radial/angled gradients come from `gradientStrip` (an image the Baker
    /// fills with the rows being drawn).
    case bakeStatic(gradientStrip: UnsafePointer<lv_image_dsc_t>?)
    /// The whole face frozen at `time`, for the switcher's thumbnail
    case bakeThumbnail(gradientStrip: UnsafePointer<lv_image_dsc_t>?, time: WallTime)
}

final class RenderedFace {
    let face: WatchFace
    let root: LVObj
    let mode: RenderMode
    /// The shortest update period this face needs (ms)
    private(set) var updatePeriod: UInt32 = 1000
    /// A smooth second hand (wants 10 updates a second)
    private(set) var hasSmoothSecondHand = false
    /// Live, with live static objects (the slot doesn't hold this face's layer yet)
    private(set) var needsBake = false
    /// The image the Baker moves along with the strip it draws (gradients)
    private(set) var gradientStrip: LVObj?
    private var stripSource: UnsafePointer<lv_image_dsc_t>?

    /// Holds the static objects while they are live (until the baked layer replaces them)
    private var staticRoot: LVObj?
    private var buffers: [UnsafeMutableRawPointer] = []
    private var fontIDs: [String] = []
    private var dials: [DialDrawing] = []
    private var times: [(label: LVObj, element: DigitalTime)] = []
    private var dates: [(label: LVObj, element: DateText)] = []
    private var hands: [(images: [LVObj], hand: Hand)] = []
    private var steps: [(label: LVObj, arc: LVObj?, element: Steps)] = []
    private var batteries: [(label: LVObj?, bar: LVObj?)] = []
    private var pendingImage: (image: LVObj, job: BackgroundJob)?
    private var lastSteps = -1
    private var lastBattery = -2
    private var lastBatteryCheck: UInt32 = 0
    private var released = false

    static func thumbnailPath(_ face: WatchFace) -> String { ImageWorker.cachePath(BakeKeys.thumbnailKey(face)) }

    init(face: WatchFace, parent: LVObj, mode: RenderMode = .live) {
        self.face = face
        self.mode = mode
        root = lvPlainObject(parent)
        lv_obj_set_size(root, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_color(root, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(root, 255, partMain)
        // Owned by the root object until it is deleted
        lv_obj_add_event_cb(root, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            // Children still exist during LV_EVENT_DELETE: free what they use only after the deletion is done
            lv_async_call({ ud in
                guard let ud else { return }
                Unmanaged<RenderedFace>.fromOpaque(ud).takeRetainedValue().releaseResources()
            }, ud)
        }, LV_EVENT_DELETE, Unmanaged.passRetained(self).toOpaque())

        switch mode {
        case .live:
            if StaticSlot.holds(BakeKeys.staticKey(face)), let slot = StaticSlot.image() {
                showSlot(slot)
            } else {
                buildStatic()
                needsBake = true
            }
            buildMoving()
            update(currentWallTime())
        case .bakeStatic(let strip):
            stripSource = strip
            buildStatic()
        case .bakeThumbnail(let strip, let time):
            stripSource = strip
            buildStatic()
            buildMoving()
            update(time)
        }
    }

    /// The slot now holds this face's layer: show it instead of the live static objects
    func useSlot() {
        guard needsBake, let staticRoot, let slot = StaticSlot.image() else { return }
        needsBake = false
        lv_obj_delete(staticRoot)
        self.staticRoot = nil
        pendingImage = nil
        showSlot(slot)
    }

    private func showSlot(_ slot: UnsafePointer<lv_image_dsc_t>) {
        let image = lv_image_create(root)!
        lv_obj_set_pos(image, 0, 0)
        lv_image_set_src(image, slot)
        lv_obj_move_background(image)
    }

    /// The background is ready to be baked (a prepared image or gradient file exists, if it needs one)
    var isBackgroundReady: Bool { pendingImage == nil }

    private func releaseResources() {
        guard !released else { return }
        released = true
        for id in fontIDs {
            FontCache.release(id)
        }
        fontIDs.removeAll()
        for b in buffers {
            free(b)
        }
        buffers.removeAll()
        dials.removeAll()
    }

    private func allocate(_ size: Int) -> UnsafeMutableRawPointer? {
        guard let p = malloc(size) else {
            print("watch_faces: out of memory (\(size) bytes)")
            return nil
        }
        buffers.append(p)
        return p
    }

    // MARK: - Fonts

    private func font(_ ref: FontRef) -> UnsafePointer<lv_font_t> {
        switch ref {
        case .builtin(let size):
            return wf_builtin_font(Int32(FontRef.nearestBuiltinSize(size)))
        case .asset(let id):
            guard let font = FontCache.acquire(id) else { return wf_builtin_font(20) }
            fontIDs.append(id)
            return UnsafePointer(font)
        }
    }

    private func label(_ parent: LVObj, _ style: TextStyle, _ placement: Placement, _ text: String) -> LVObj {
        let label = lv_label_create(parent)!
        lv_obj_set_style_text_font(label, font(style.font), partMain)
        lv_obj_set_style_text_color(label, lvColor(style.color), partMain)
        lv_obj_set_style_text_opa(label, style.color.a, partMain)
        lv_obj_set_style_text_letter_space(label, Int32(style.letterSpacing), partMain)
        lv_obj_set_style_text_align(label, lvTextAlign(placement.anchor), partMain)
        lvSetText(label, text)
        lvPlace(label, placement)
        return label
    }

    // MARK: - Static layer

    private func buildStatic() {
        let layer = lvPlainObject(root)
        lv_obj_set_size(layer, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_opa(layer, 255, partMain)
        lv_obj_set_style_bg_color(layer, lv_color_black(), partMain)
        staticRoot = layer
        buildBackground(layer)
        for element in face.elements {
            switch element {
            case .analogClock(let e): buildDial(layer, e)
            case .text(let e): _ = label(layer, e.style, e.placement, e.text)
            default: break
            }
        }
    }

    private func gradient(_ stops: [GradientStop]) -> UnsafeMutablePointer<lv_grad_dsc_t>? {
        guard !stops.isEmpty, let raw = allocate(MemoryLayout<lv_grad_dsc_t>.size) else { return nil }
        let dsc = raw.bindMemory(to: lv_grad_dsc_t.self, capacity: 1)
        memset(dsc, 0, MemoryLayout<lv_grad_dsc_t>.size)
        let used = Array(stops.prefix(Int(LV_GRADIENT_MAX_STOPS)))
        let colors = used.map { lvColor($0.color) }
        let opas = used.map { $0.color.a }
        let fracs = used.map { UInt8(clamping: $0.location) }
        lv_grad_init_stops(dsc, colors, opas, fracs, Int32(used.count))
        return dsc
    }

    private func buildBackground(_ layer: LVObj) {
        switch face.background {
        case .color(let c):
            lv_obj_set_style_bg_color(layer, lvColor(c), partMain)
        case .linearGradient(let g) where GradientRaster.isCheap(g):
            // Top/bottom or left/right: LVGL fills these row by row (cheap). 0 and 270 are the reverse of 180 and 90.
            let reversed = g.angle == 0 || g.angle == 270
            let stops = reversed ? g.stops.reversed().map { GradientStop(color: $0.color, location: 255 - $0.location) }
                                 : g.stops
            guard let dsc = gradient(stops) else { return }
            if g.angle == 90 || g.angle == 270 {
                lv_grad_horizontal_init(dsc)
            } else {
                lv_grad_vertical_init(dsc)
            }
            lv_obj_set_style_bg_grad(layer, dsc, partMain)
        case .linearGradient(let g):
            if !showStrip(layer), let dsc = gradient(g.stops) {
                // Live until the static layer is baked: LVGL computes it (slower, and without dithering)
                let (from, to) = g.endpoints(width: WatchScreen.width, height: WatchScreen.height)
                lv_grad_linear_init(dsc, Int32(from.x), Int32(from.y), Int32(to.x), Int32(to.y), LV_GRAD_EXTEND_PAD)
                lv_obj_set_style_bg_grad(layer, dsc, partMain)
            }
        case .radialGradient(let g):
            if !showStrip(layer), let dsc = gradient(g.stops) {
                lv_grad_radial_init(dsc, Int32(g.centerX), Int32(g.centerY), Int32(g.centerX + max(1, g.radius)),
                                    Int32(g.centerY), LV_GRAD_EXTEND_PAD)
                lv_obj_set_style_bg_grad(layer, dsc, partMain)
            }
        case .pattern(let p):
            // Tiled: slow to draw (one small image per tile), but only drawn when baking the static layer
            lv_obj_set_style_bg_color(layer, lvColor(p.background), partMain)
            let tile = p.tile()
            let bytes = tile.pixels.count * 2
            guard let pixels = allocate(bytes), let raw = allocate(MemoryLayout<lv_image_dsc_t>.size) else { return }
            tile.pixels.withUnsafeBytes { pixels.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            let dsc = raw.bindMemory(to: lv_image_dsc_t.self, capacity: 1)
            wf_image_dsc_init(dsc, LV_COLOR_FORMAT_RGB565, UInt32(tile.width), UInt32(tile.height),
                              UInt32(tile.width * 2), pixels, UInt32(bytes))
            lv_obj_set_style_bg_image_src(layer, dsc, partMain)
            lv_obj_set_style_bg_image_tiled(layer, true, partMain)
        case .image(let i):
            showPrepared(layer, .asset(id: i.assetID, matte: i.fallback), placeholder: i.fallback)
            if i.dim > 0 {
                // A black layer over the image (and the fallback colour), under the elements
                let dim = lvPlainObject(layer)
                lv_obj_set_size(dim, Int32(WatchScreen.width), Int32(WatchScreen.height))
                lv_obj_set_style_bg_color(dim, lv_color_black(), partMain)
                lv_obj_set_style_bg_opa(dim, i.dimOpacity, partMain)
            }
        case .unknown:
            break
        }
    }

    /// Baking: the gradient comes from the Baker's strip image (dithered rows of the strip being drawn)
    private func showStrip(_ layer: LVObj) -> Bool {
        guard let stripSource else { return false }
        let image = lv_image_create(layer)!
        lv_image_set_src(image, stripSource)
        lv_obj_set_pos(image, 0, 0)
        gradientStrip = image
        return true
    }

    /// A full-screen image of the prepared file, the placeholder color until it's ready
    private func showPrepared(_ layer: LVObj, _ job: BackgroundJob, placeholder: FaceColor) {
        lv_obj_set_style_bg_color(layer, lvColor(placeholder), partMain)
        let image = lv_image_create(layer)!
        lv_obj_set_pos(image, 0, 0)
        if !ImageWorker.showIfReady(job.key, on: image) {
            pendingImage = (image, job)
            ImageWorker.request(job)
        }
    }

    private func buildDial(_ layer: LVObj, _ e: AnalogClock) {
        let r = Int32(e.radius)
        let dial = lvPlainObject(layer)
        lv_obj_set_size(dial, 2 * r, 2 * r)
        lv_obj_set_pos(dial, Int32(e.centerX) - r, Int32(e.centerY) - r)
        lv_obj_set_style_radius(dial, wf_radius_circle(), partMain)
        if e.dial.fill.a > 0 {
            lv_obj_set_style_bg_color(dial, lvColor(e.dial.fill), partMain)
            lv_obj_set_style_bg_opa(dial, e.dial.fill.a, partMain)
        }
        if e.dial.borderWidth > 0 {
            lv_obj_set_style_border_width(dial, Int32(e.dial.borderWidth), partMain)
            lv_obj_set_style_border_color(dial, lvColor(e.dial.borderColor), partMain)
            lv_obj_set_style_border_opa(dial, e.dial.borderColor.a, partMain)
        }
        let segments = e.tickSegments()
        if !segments.isEmpty {
            let drawing = DialDrawing(segments: segments, originX: e.centerX - e.radius, originY: e.centerY - e.radius)
            dials.append(drawing)
            lv_obj_add_event_cb(dial, { ev in
                guard let ud = lv_event_get_user_data(ev) else { return }
                Unmanaged<DialDrawing>.fromOpaque(ud).takeUnretainedValue().draw(ev)
            }, LV_EVENT_DRAW_MAIN, Unmanaged.passUnretained(drawing).toOpaque())
        }
        for numeral in e.numeralLabels() {
            _ = label(layer, e.numerals.style,
                      Placement(x: Int(numeral.center.x.rounded()), y: Int(numeral.center.y.rounded())), numeral.text)
        }
    }

    // MARK: - Moving parts

    private func buildMoving() {
        let t = currentWallTime()
        for element in face.elements {
            switch element {
            case .digitalTime(let e):
                times.append((label(root, e.style, e.placement, FaceText.time(e, t)), e))
                if e.showSeconds { updatePeriod = min(updatePeriod, 250) }
            case .date(let e):
                dates.append((label(root, e.style, e.placement, FaceText.date(e, t)), e))
            case .steps(let e):
                buildSteps(e)
            case .battery(let e):
                buildBattery(e)
            case .analogClock(let e):
                buildHands(e)
            case .text, .unknown:
                break
            }
        }
    }

    private func buildSteps(_ e: Steps) {
        guard e.style == .ring else {
            steps.append((label(root, e.text, e.placement, FaceText.steps(0)), nil, e))
            return
        }
        let arc = lv_arc_create(root)!
        let size = Int32(2 * e.radius)
        lv_obj_set_size(arc, size, size)
        lvPlace(arc, e.placement)
        lv_obj_remove_flag(arc, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_style(arc, nil, partKnob)
        lv_arc_set_rotation(arc, 270)
        lv_arc_set_bg_angles(arc, 0, 360)
        lv_arc_set_range(arc, 0, Int32(e.goal))
        lv_arc_set_value(arc, 0)
        lv_obj_set_style_arc_width(arc, Int32(e.ringWidth), partMain)
        lv_obj_set_style_arc_width(arc, Int32(e.ringWidth), partIndicator)
        lv_obj_set_style_arc_color(arc, lvColor(e.trackColor), partMain)
        lv_obj_set_style_arc_color(arc, lvColor(e.ringColor), partIndicator)
        lv_obj_set_style_arc_rounded(arc, true, partIndicator)
        let text = lv_label_create(arc)!
        lv_obj_set_style_text_font(text, font(e.text.font), partMain)
        lv_obj_set_style_text_color(text, lvColor(e.text.color), partMain)
        lv_obj_center(text)
        steps.append((text, arc, e))
    }

    private func buildBattery(_ e: Battery) {
        guard e.style == .bar else {
            batteries.append((label(root, e.text, e.placement, FaceText.battery(-1)), nil))
            return
        }
        let bar = lv_bar_create(root)!
        lv_obj_set_size(bar, 40, 18)
        lvPlace(bar, e.placement)
        lv_bar_set_range(bar, 0, 100)
        lv_obj_set_style_radius(bar, 4, partMain)
        lv_obj_set_style_bg_opa(bar, 0, partMain)
        lv_obj_set_style_border_width(bar, 2, partMain)
        lv_obj_set_style_border_color(bar, lvColor(e.text.color), partMain)
        lv_obj_set_style_pad_all(bar, 3, partMain)
        lv_obj_set_style_radius(bar, 2, partIndicator)
        lv_obj_set_style_bg_color(bar, lvColor(e.text.color), partIndicator)
        batteries.append((nil, bar))
    }

    private func buildHands(_ e: AnalogClock) {
        for hand in e.hands {
            let mask = HandMask(hand: hand)
            let bytes = mask.alpha.count
            guard let pixels = allocate(bytes) else { continue }
            mask.alpha.withUnsafeBytes { pixels.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            // A second hand moves all the time: in slices, each rotated around the same pivot, so an update redraws
            // narrow areas along the hand instead of its whole bounding box. The others move rarely: one image.
            // One image per hand: slices (HandSlices) made many small redraw areas, and LVGL draws and sends each
            // area to the display separately, which cost more than the larger area of a whole hand
            let slices = [(start: 0, count: mask.height)]
            var images: [LVObj] = []
            for slice in slices {
                guard let raw = allocate(MemoryLayout<lv_image_dsc_t>.size) else { continue }
                let dsc = raw.bindMemory(to: lv_image_dsc_t.self, capacity: 1)
                wf_image_dsc_init(dsc, LV_COLOR_FORMAT_A8, UInt32(mask.width), UInt32(slice.count), UInt32(mask.width),
                                  pixels + slice.start * mask.width, UInt32(slice.count * mask.width))
                let image = lv_image_create(root)!
                lv_image_set_src(image, dsc)
                lv_obj_set_pos(image, Int32(e.centerX - mask.pivotX), Int32(e.centerY - mask.pivotY + slice.start))
                lv_image_set_pivot(image, Int32(mask.pivotX), Int32(mask.pivotY - slice.start))
                lv_obj_set_style_image_recolor(image, lvColor(hand.color), partMain)
                lv_obj_set_style_image_recolor_opa(image, 255, partMain)
                lv_obj_set_style_image_opa(image, hand.color.a, partMain)
                images.append(image)
            }
            hands.append((images, hand))
            if hand.kind == .second {
                hasSmoothSecondHand = hasSmoothSecondHand || hand.smooth
                updatePeriod = min(updatePeriod, hand.smooth ? 100 : 250)
            }
        }
        if e.capRadius > 0 {
            let cap = lvPlainObject(root)
            let cr = Int32(e.capRadius)
            lv_obj_set_size(cap, 2 * cr, 2 * cr)
            lv_obj_set_pos(cap, Int32(e.centerX) - cr, Int32(e.centerY) - cr)
            lv_obj_set_style_radius(cap, wf_radius_circle(), partMain)
            lv_obj_set_style_bg_color(cap, lvColor(e.capColor), partMain)
            lv_obj_set_style_bg_opa(cap, e.capColor.a, partMain)
        }
    }

    // MARK: - Updates

    func update(_ t: WallTime) {
        for (label, e) in times {
            lvSetText(label, FaceText.time(e, t))
        }
        for (label, e) in dates {
            lvSetText(label, FaceText.date(e, t))
        }
        for (images, hand) in hands {
            let angle = Int32(hand.angleTenths(at: t))
            for image in images {
                lv_image_set_rotation(image, angle)
            }
        }
        if !steps.isEmpty {
            let count = Int(step_counter_today())
            if count != lastSteps {
                lastSteps = count
                for (label, arc, e) in steps {
                    lvSetText(label, FaceText.steps(count))
                    if let arc { lv_arc_set_value(arc, Int32(min(count, e.goal))) }
                }
            }
        }
        if !batteries.isEmpty && (lastBattery == -2 || lv_tick_elaps(lastBatteryCheck) > 30_000) {
            lastBatteryCheck = lv_tick_get()
            let percent = batteryPercent()
            if percent != lastBattery {
                lastBattery = percent
                for (label, bar) in batteries {
                    if let label { lvSetText(label, FaceText.battery(percent)) }
                    if let bar { lv_bar_set_value(bar, Int32(max(0, percent)), false) }
                }
            }
        }
        if let pending = pendingImage {
            if ImageWorker.showIfReady(pending.job.key, on: pending.image) {
                pendingImage = nil
            } else {
                ImageWorker.request(pending.job) // no-op while preparing
            }
        }
    }
}

/// Phone-made fonts, loaded once however many faces (live, and the ones being baked) use them
enum FontCache {
    nonisolated(unsafe) private static var entries: [(id: String, font: UnsafeMutablePointer<lv_font_t>, refs: Int)] = []

    static func acquire(_ id: String) -> UnsafeMutablePointer<lv_font_t>? {
        if let i = entries.firstIndex(where: { $0.id.utf8.elementsEqual(id.utf8) }) {
            entries[i].refs += 1
            return entries[i].font
        }
        guard let path = storePath(FILE_STORE_FACE_ASSET, id), fileExists(path),
              let font = ("S:" + path).withCString({ lv_binfont_create($0) }) else {
            print("watch_faces: font \(id) missing")
            return nil
        }
        // Phone-made fonts only hold the glyphs the face needs; fall back to Montserrat for anything else
        font.pointee.fallback = wf_builtin_font(Int32(FontRef.nearestBuiltinSize(Int(font.pointee.line_height))))
        entries.append((id, font, 1))
        return font
    }

    static func release(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id.utf8.elementsEqual(id.utf8) }) else { return }
        entries[i].refs -= 1
        if entries[i].refs <= 0 {
            lv_binfont_destroy(entries[i].font)
            entries.remove(at: i)
        }
    }
}

/// Draws an analog clock's ticks (lines) when LVGL redraws the dial
final class DialDrawing {
    let segments: [TickSegment]
    let originX: Int
    let originY: Int

    init(segments: [TickSegment], originX: Int, originY: Int) {
        self.segments = segments
        self.originX = originX
        self.originY = originY
    }

    func draw(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e), let obj = lv_event_get_current_target_obj(e) else { return }
        var area = lv_area_t()
        lv_obj_get_coords(obj, &area)
        // Segments are in screen coordinates of the face; the face may have moved (baking draws it in strips), so
        // go via the dial's current position
        let dx = Float(Int(area.x1) - originX)
        let dy = Float(Int(area.y1) - originY)
        var dsc = lv_draw_line_dsc_t()
        lv_draw_line_dsc_init(&dsc)
        for s in segments {
            dsc.p1 = wf_point(Int32((s.from.x + dx).rounded()), Int32((s.from.y + dy).rounded()))
            dsc.p2 = wf_point(Int32((s.to.x + dx).rounded()), Int32((s.to.y + dy).rounded()))
            dsc.width = Int32(s.width)
            dsc.color = lvColor(s.color)
            dsc.opa = s.color.a
            lv_draw_line(layer, &dsc)
        }
    }
}
