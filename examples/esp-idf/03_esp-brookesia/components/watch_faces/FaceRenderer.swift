// Builds the LVGL objects for one WatchFace and keeps them up to date. Everything a face allocates (hand bitmaps,
// gradient and pattern descriptors, loaded fonts) belongs to its RenderedFace and is freed when its root object is
// deleted, whoever deletes it (a swipe, or the app framework deleting the screen).

final class RenderedFace {
    let face: WatchFace
    let root: LVObj
    /// The shortest update period this face needs (ms)
    private(set) var updatePeriod: UInt32 = 1000

    private var buffers: [UnsafeMutableRawPointer] = []
    private var fonts: [(id: String, font: UnsafeMutablePointer<lv_font_t>)] = []
    private var dials: [DialDrawing] = []
    private var times: [(label: LVObj, element: DigitalTime)] = []
    private var dates: [(label: LVObj, element: DateText)] = []
    private var hands: [(image: LVObj, hand: Hand)] = []
    private var steps: [(label: LVObj, arc: LVObj?, element: Steps)] = []
    private var batteries: [(label: LVObj?, bar: LVObj?)] = []
    private var pendingImage: (image: LVObj, assetID: String)?
    private var lastSteps = -1
    private var lastBattery = -2
    private var lastBatteryCheck: UInt32 = 0
    private var released = false

    init(face: WatchFace, parent: LVObj) {
        self.face = face
        root = lvPlainObject(parent)
        lv_obj_set_size(root, Int32(WatchScreen.width), Int32(WatchScreen.height))
        // Owned by the root object until it is deleted (see onDelete)
        lv_obj_add_event_cb(root, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            // Children still exist during LV_EVENT_DELETE: free what they use only after the deletion is done
            lv_async_call({ ud in
                guard let ud else { return }
                Unmanaged<RenderedFace>.fromOpaque(ud).takeRetainedValue().releaseResources()
            }, ud)
        }, LV_EVENT_DELETE, Unmanaged.passRetained(self).toOpaque())

        buildBackground()
        for element in face.elements {
            build(element)
        }
        update(currentWallTime())
    }

    private func releaseResources() {
        guard !released else { return }
        released = true
        for f in fonts {
            lv_binfont_destroy(f.font)
        }
        fonts.removeAll()
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
            if let loaded = fonts.first(where: { $0.id.utf8.elementsEqual(id.utf8) }) {
                return UnsafePointer(loaded.font)
            }
            guard let path = storePath(FILE_STORE_FACE_ASSET, id), fileExists(path),
                  let font = ("S:" + path).withCString({ lv_binfont_create($0) }) else {
                print("watch_faces: font \(id) missing")
                return wf_builtin_font(20)
            }
            // Phone-made fonts only hold the glyphs the face needs; fall back to Montserrat for anything else
            font.pointee.fallback = wf_builtin_font(Int32(FontRef.nearestBuiltinSize(Int(font.pointee.line_height))))
            fonts.append((id, font))
            return UnsafePointer(font)
        }
    }

    private func label(_ style: TextStyle, _ placement: Placement, _ text: String) -> LVObj {
        let label = lv_label_create(root)!
        lv_obj_set_style_text_font(label, font(style.font), partMain)
        lv_obj_set_style_text_color(label, lvColor(style.color), partMain)
        lv_obj_set_style_text_opa(label, style.color.a, partMain)
        lv_obj_set_style_text_letter_space(label, Int32(style.letterSpacing), partMain)
        lv_obj_set_style_text_align(label, lvTextAlign(placement.anchor), partMain)
        lvSetText(label, text)
        lvPlace(label, placement)
        return label
    }

    // MARK: - Background

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

    private func buildBackground() {
        lv_obj_set_style_bg_opa(root, 255, partMain)
        lv_obj_set_style_bg_color(root, lv_color_black(), partMain)
        switch face.background {
        case .color(let c):
            lv_obj_set_style_bg_color(root, lvColor(c), partMain)
        case .linearGradient(let g):
            guard let dsc = gradient(g.stops) else { return }
            let (from, to) = g.endpoints(width: WatchScreen.width, height: WatchScreen.height)
            lv_grad_linear_init(dsc, Int32(from.x), Int32(from.y), Int32(to.x), Int32(to.y), LV_GRAD_EXTEND_PAD)
            lv_obj_set_style_bg_grad(root, dsc, partMain)
        case .radialGradient(let g):
            guard let dsc = gradient(g.stops) else { return }
            lv_grad_radial_init(dsc, Int32(g.centerX), Int32(g.centerY), Int32(g.centerX + max(1, g.radius)),
                                Int32(g.centerY), LV_GRAD_EXTEND_PAD)
            lv_obj_set_style_bg_grad(root, dsc, partMain)
        case .pattern(let p):
            lv_obj_set_style_bg_color(root, lvColor(p.background), partMain)
            let tile = p.tile()
            let bytes = tile.pixels.count * 2
            guard let pixels = allocate(bytes), let raw = allocate(MemoryLayout<lv_image_dsc_t>.size) else { return }
            tile.pixels.withUnsafeBytes { pixels.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            let dsc = raw.bindMemory(to: lv_image_dsc_t.self, capacity: 1)
            wf_image_dsc_init(dsc, LV_COLOR_FORMAT_RGB565, UInt32(tile.width), UInt32(tile.height),
                              UInt32(tile.width * 2), pixels, UInt32(bytes))
            lv_obj_set_style_bg_image_src(root, dsc, partMain)
            lv_obj_set_style_bg_image_tiled(root, true, partMain)
        case .image(let i):
            lv_obj_set_style_bg_color(root, lvColor(i.fallback), partMain)
            let image = lv_image_create(root)!
            lv_obj_set_pos(image, 0, 0)
            if !ImageWorker.showIfReady(i.assetID, on: image) {
                pendingImage = (image, i.assetID)
                ImageWorker.request(i.assetID, matte: i.fallback)
            }
        case .unknown:
            break
        }
    }

    // MARK: - Elements

    private func build(_ element: Element) {
        let t = currentWallTime()
        switch element {
        case .digitalTime(let e):
            times.append((label(e.style, e.placement, FaceText.time(e, t)), e))
            if e.showSeconds { updatePeriod = min(updatePeriod, 250) }
        case .date(let e):
            dates.append((label(e.style, e.placement, FaceText.date(e, t)), e))
        case .text(let e):
            _ = label(e.style, e.placement, e.text)
        case .steps(let e):
            buildSteps(e)
        case .battery(let e):
            buildBattery(e)
        case .analogClock(let e):
            buildAnalogClock(e)
        case .unknown:
            break // from a newer app: nothing to draw
        }
    }

    private func buildSteps(_ e: Steps) {
        guard e.style == .ring else {
            steps.append((label(e.text, e.placement, FaceText.steps(0)), nil, e))
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
            batteries.append((label(e.text, e.placement, FaceText.battery(-1)), nil))
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

    private func buildAnalogClock(_ e: AnalogClock) {
        let r = Int32(e.radius)
        let dial = lvPlainObject(root)
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
            _ = label(e.numerals.style, Placement(x: Int(numeral.center.x.rounded()), y: Int(numeral.center.y.rounded())),
                      numeral.text)
        }

        for hand in e.hands {
            let mask = HandMask(hand: hand)
            let bytes = mask.alpha.count
            guard let pixels = allocate(bytes), let raw = allocate(MemoryLayout<lv_image_dsc_t>.size) else { continue }
            mask.alpha.withUnsafeBytes { pixels.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            let dsc = raw.bindMemory(to: lv_image_dsc_t.self, capacity: 1)
            wf_image_dsc_init(dsc, LV_COLOR_FORMAT_A8, UInt32(mask.width), UInt32(mask.height), UInt32(mask.width),
                              pixels, UInt32(bytes))
            let image = lv_image_create(root)!
            lv_image_set_src(image, dsc)
            lv_obj_set_pos(image, Int32(e.centerX - mask.pivotX), Int32(e.centerY - mask.pivotY))
            lv_image_set_pivot(image, Int32(mask.pivotX), Int32(mask.pivotY))
            lv_obj_set_style_image_recolor(image, lvColor(hand.color), partMain)
            lv_obj_set_style_image_recolor_opa(image, 255, partMain)
            lv_obj_set_style_image_opa(image, hand.color.a, partMain)
            hands.append((image, hand))
            if hand.kind == .second { updatePeriod = min(updatePeriod, hand.smooth ? 100 : 250) }
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
        for (image, hand) in hands {
            lv_image_set_rotation(image, Int32(hand.angleTenths(at: t)))
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
        if let pending = pendingImage, ImageWorker.showIfReady(pending.assetID, on: pending.image) {
            pendingImage = nil
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
        // Segments are in screen coordinates of the face; the face may be sliding (swipe), so go via the dial's
        // current position
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
