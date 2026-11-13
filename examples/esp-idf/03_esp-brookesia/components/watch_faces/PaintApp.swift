// Tegn: a small paint app. The drawing (WatchFaceKit PaintImage: 16 colours at half the screen's resolution, ~26 KB)
// fills the screen; a tab on the left edge opens the palette, tools down the right: pencil, brush, fill, undo, save
// (to the gallery, with a thumbnail) and open (the gallery: open or delete a saved drawing, or start a new one).
//
// The drawing is shown through an image decoder of its own (PaintDecoder): it converts the rows LVGL asks for to
// RGB565, doubling the pixels; a stroke redraws only the area it changed. Thumbnails are files read a few rows at a
// time. What is being drawn is kept in /store/paint/current.wpn (after each stroke, and when the app closes); undo
// keeps run-length encoded copies in RAM.

private let paintDir = "/store/paint"
private let currentPath = paintDir + "/current.wpn"
private let screenW = Int32(WatchScreen.width)
private let screenH = Int32(WatchScreen.height)
private let scale = 2
private let undoBudget = 20 * 1024      // Bytes of undo copies kept (the oldest go first)
private let toolbarX: Int32 = screenW - 66
private let buttonSize: Int32 = 54
private let paletteW: Int32 = 116
private let darkButton = FaceColor(r: 44, g: 44, b: 46)
private let orange = FaceColor(r: 255, g: 159, b: 10)

// MARK: - Showing drawings

/// An image decoder for the drawing being edited and for thumbnail files (lv_image_dsc_t sources it made)
private enum PaintDecoder {
    struct Thumbnail {
        let dsc: UnsafeMutablePointer<lv_image_dsc_t>
        let path: String
        let width: Int
        let height: Int
    }

    nonisolated(unsafe) static var decoder: UnsafeMutablePointer<lv_image_decoder_t>?
    nonisolated(unsafe) static var canvasDsc: UnsafeMutablePointer<lv_image_dsc_t>?
    nonisolated(unsafe) static var image: PaintImage?
    nonisolated(unsafe) static var thumbnails: [Thumbnail] = []
    nonisolated(unsafe) static var buffer: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var served: UnsafeMutablePointer<lv_draw_buf_t>?
    /// The thumbnail file read last, kept open (a thumbnail is read in a few strips)
    nonisolated(unsafe) static var openFile: (path: String, fd: Int32)?
    static let bufferBytes = 8 * WatchScreen.width * 2
    nonisolated(unsafe) static var dummy: UInt8 = 0
    nonisolated(unsafe) static var colors: [UInt16] = PaintPalette.colors.map {
        UInt16($0.r >> 3) << 11 | UInt16($0.g >> 2) << 5 | UInt16($0.b >> 3)
    }

    static func register() {
        guard decoder == nil else { return }
        decoder = lv_image_decoder_create()
        lv_image_decoder_set_info_cb(decoder, { _, dsc, header in PaintDecoder.info(dsc, header) })
        lv_image_decoder_set_open_cb(decoder, { _, dsc in
            guard PaintDecoder.size(dsc?.pointee.src) != nil else { return LV_RESULT_INVALID }
            dsc?.pointee.decoded = nil   // Drawn piece by piece through getArea
            return LV_RESULT_OK
        })
        lv_image_decoder_set_get_area_cb(decoder, { _, dsc, full, decoded in PaintDecoder.getArea(dsc, full, decoded) })
        lv_image_decoder_set_close_cb(decoder, { _, dsc in dsc?.pointee.decoded = nil })
    }

    /// A source with a non-null data pointer (LVGL skips variable images without data)
    static func makeDsc(width: Int, height: Int) -> UnsafeMutablePointer<lv_image_dsc_t> {
        let dsc = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
        dsc.initialize(to: lv_image_dsc_t())
        wf_image_dsc_init(dsc, LV_COLOR_FORMAT_RGB565, UInt32(width), UInt32(height), UInt32(width * 2), &dummy, 1)
        return dsc
    }

    static func canvasSource() -> UnsafeMutablePointer<lv_image_dsc_t> {
        if let canvasDsc { return canvasDsc }
        let dsc = makeDsc(width: PaintImage.canvasWidth * scale, height: PaintImage.canvasHeight * scale)
        canvasDsc = dsc
        return dsc
    }

    /// The source's size as shown, if it's one of ours
    static func size(_ src: UnsafeRawPointer?) -> (Int, Int)? {
        guard let src else { return nil }
        if let canvasDsc, UnsafeRawPointer(canvasDsc) == src {
            return (PaintImage.canvasWidth * scale, PaintImage.canvasHeight * scale)
        }
        if let t = thumbnails.first(where: { UnsafeRawPointer($0.dsc) == src }) { return (t.width, t.height) }
        return nil
    }

    static func info(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?,
                     _ header: UnsafeMutablePointer<lv_image_header_t>?) -> lv_result_t {
        guard let dsc, dsc.pointee.src_type == LV_IMAGE_SRC_VARIABLE, let header,
              let (w, h) = size(dsc.pointee.src) else { return LV_RESULT_INVALID }
        wf_image_header_set(header, UInt32(w), UInt32(h))
        return LV_RESULT_OK
    }

    static func closeFile() {
        if let f = openFile { close(f.fd) }
        openFile = nil
    }

    static func getArea(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?, _ full: UnsafePointer<lv_area_t>?,
                        _ decoded: UnsafeMutablePointer<lv_area_t>?) -> lv_result_t {
        guard let dsc, let full, let decoded, let (w, h) = size(dsc.pointee.src) else { return LV_RESULT_INVALID }
        if buffer == nil { buffer = malloc(bufferBytes) }
        if served == nil {
            served = UnsafeMutablePointer<lv_draw_buf_t>.allocate(capacity: 1)
            served!.initialize(to: lv_draw_buf_t())
        }
        guard let buffer, let served else { return LV_RESULT_INVALID }
        let y = decoded.pointee.y1 == wf_coord_min() ? max(0, Int(full.pointee.y1)) : Int(decoded.pointee.y2) + 1
        guard y <= Int(full.pointee.y2), y < h else { return LV_RESULT_INVALID }
        let x1 = max(0, Int(full.pointee.x1)), x2 = min(w - 1, Int(full.pointee.x2))
        guard x1 <= x2 else { return LV_RESULT_INVALID }
        let cols = x2 - x1 + 1
        let rows = min(bufferBytes / (cols * 2), Int(full.pointee.y2) - y + 1, h - y)
        let out = buffer.bindMemory(to: UInt16.self, capacity: rows * cols)

        if let canvasDsc, UnsafeRawPointer(canvasDsc) == dsc.pointee.src {
            guard let image else { return LV_RESULT_INVALID }
            image.pixels.withUnsafeBufferPointer { px in
                for r in 0..<rows {
                    let row = (y + r) / scale * image.stride
                    for c in 0..<cols {
                        let x = (x1 + c) / scale
                        let b = px[row + x / 2]
                        out[r * cols + c] = colors[Int(x & 1 == 0 ? b >> 4 : b & 0xF)]
                    }
                }
            }
        } else if let t = thumbnails.first(where: { UnsafeRawPointer($0.dsc) == dsc.pointee.src }) {
            if openFile.map({ !$0.path.utf8.elementsEqual(t.path.utf8) }) ?? true {
                closeFile()
                let fd = t.path.withCString { wf_open_read($0) }
                guard fd >= 0 else { return LV_RESULT_INVALID }
                openFile = (t.path, fd)
            }
            guard let fd = openFile?.fd else { return LV_RESULT_INVALID }
            let stride = (t.width + 1) / 2
            var line = [UInt8](repeating: 0, count: stride)
            for r in 0..<rows {
                guard pread(fd, &line, stride, 8 + (y + r) * stride) == stride else { return LV_RESULT_INVALID }
                for c in 0..<cols {
                    let x = x1 + c
                    let b = line[x / 2]
                    out[r * cols + c] = colors[Int(x & 1 == 0 ? b >> 4 : b & 0xF)]
                }
            }
        } else {
            return LV_RESULT_INVALID
        }
        lv_draw_buf_init(served, UInt32(cols), UInt32(rows), LV_COLOR_FORMAT_RGB565, UInt32(cols * 2), buffer,
                         UInt32(rows * cols * 2))
        decoded.pointee.x1 = Int32(x1)
        decoded.pointee.x2 = Int32(x2)
        decoded.pointee.y1 = Int32(y)
        decoded.pointee.y2 = Int32(y + rows - 1)
        dsc.pointee.decoded = UnsafePointer(served)
        return LV_RESULT_OK
    }

    static func releaseThumbnails() {
        closeFile()
        for t in thumbnails { t.dsc.deallocate() }
        thumbnails.removeAll()
    }
}

// MARK: - The app

private enum Tool {
    case pencil, brush, fill
}

private final class PaintUI {
    private let screen: LVObj
    private let image: PaintImage
    private var canvas: LVObj?
    private var tool = Tool.pencil
    private var color: UInt8 = 1
    private var last: (Int, Int)?
    private var undo: [[UInt8]] = []
    private var saveTimer: OpaquePointer?
    private var toolButtons: [(Tool, LVObj)] = []
    private var tab: LVObj?
    private var palette: LVObj?
    private var gallery: LVObj?
    private var sheet: LVObj?
    private var toast: LVObj?
    private var toastTimer: OpaquePointer?
    private var actions: [(PaintUI) -> Void] = []
    private var galleryIDs: [String] = []

    init(screen: LVObj, image: PaintImage) {
        self.screen = screen
        self.image = image
        PaintDecoder.register()
        PaintDecoder.image = image
        lv_obj_set_style_bg_color(screen, lv_color_white(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)

        let c = lv_image_create(screen)!
        lv_image_set_src(c, PaintDecoder.canvasSource())
        lv_obj_set_pos(c, 0, 0)
        lv_obj_add_flag(c, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(c, LV_OBJ_FLAG_GESTURE_BUBBLE)
        for code in [LV_EVENT_PRESSED, LV_EVENT_PRESSING, LV_EVENT_RELEASED, LV_EVENT_PRESS_LOST] {
            lv_obj_add_event_cb(c, { e in paintUI?.touch(lv_event_get_code(e)) }, code, nil)
        }
        canvas = c

        // Tools down the right edge
        let tools: [(String?, Tool?, (PaintUI) -> Void)] = [
            (LV_SYMBOL_EDIT, .pencil, { $0.select(.pencil) }),
            (nil, .brush, { $0.select(.brush) }),
            (nil, .fill, { $0.select(.fill) }),
            (nil, nil, { $0.undoLast() }),
            (LV_SYMBOL_SAVE, nil, { $0.saveToGallery() }),
            (LV_SYMBOL_DIRECTORY, nil, { $0.showGallery() }),
        ]
        let top = (screenH - Int32(tools.count) * (buttonSize + 10) + 10) / 2
        for (i, t) in tools.enumerated() {
            let b = button(screen, t.0 ?? "", w: buttonSize, h: buttonSize, color: darkButton, action: t.2)
            lv_obj_set_pos(b, toolbarX, top + Int32(i) * (buttonSize + 10))
            lv_obj_set_style_shadow_width(b, 8, partMain)
            lv_obj_set_style_shadow_opa(b, 80, partMain)
            if t.0 == nil {
                // Drawn: brush, fill, undo
                lv_obj_add_event_cb(b, { e in
                    guard let ui = paintUI, let obj = lv_event_get_current_target_obj(e) else { return }
                    ui.drawIcon(obj, e)
                }, LV_EVENT_DRAW_MAIN, UnsafeMutableRawPointer(bitPattern: i + 1))
            }
            if let tool = t.1 { toolButtons.append((tool, b)) }
        }

        // The palette's tab on the left edge
        let tb = lvPlainObject(screen)
        lv_obj_set_size(tb, 34, 70)
        lv_obj_set_style_radius(tb, 12, partMain)
        lv_obj_set_style_bg_color(tb, lvColor(darkButton), partMain)
        lv_obj_set_style_bg_opa(tb, 255, partMain)
        lv_obj_set_style_shadow_width(tb, 8, partMain)
        lv_obj_set_style_shadow_opa(tb, 80, partMain)
        lv_obj_add_flag(tb, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_add_event_cb(tb, { _ in paintUI?.togglePalette() }, LV_EVENT_CLICKED, nil)
        lv_obj_add_event_cb(tb, { e in
            guard let ui = paintUI, let obj = lv_event_get_current_target_obj(e) else { return }
            ui.drawTab(obj, e)
        }, LV_EVENT_DRAW_MAIN, nil)
        tab = tb
        placeTab()
        refreshTools()
    }

    /// Before the app's objects go: what is drawn is saved, the memory freed
    func stop() {
        if let saveTimer { lv_timer_delete(saveTimer) }
        saveTimer = nil
        if let toastTimer { lv_timer_delete(toastTimer) }
        toastTimer = nil
        saveCurrent()
        undo.removeAll()
        PaintDecoder.image = nil
        PaintDecoder.releaseThumbnails()
    }

    // MARK: Buttons

    private func button(_ parent: LVObj, _ text: String, w: Int32, h: Int32 = 56, color: FaceColor,
                        textColor: lv_color_t = lv_color_white(), action: @escaping (PaintUI) -> Void) -> LVObj {
        let b = lvPlainObject(parent)
        lv_obj_set_size(b, w, h)
        lv_obj_set_style_radius(b, h / 2, partMain)
        lv_obj_set_style_bg_color(b, lvColor(color), partMain)
        lv_obj_set_style_bg_opa(b, 255, partMain)
        lv_obj_set_style_bg_color(b, lv_color_make(120, 120, 124), partMain | lv_style_selector_t(LV_STATE_PRESSED.rawValue))
        lv_obj_add_flag(b, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE)
        if !text.isEmpty {
            let l = lv_label_create(b)!
            lv_obj_set_style_text_font(l, wf_builtin_font(22), partMain)
            lv_obj_set_style_text_color(l, textColor, partMain)
            lvSetText(l, text)
            lv_obj_center(l)
        }
        actions.append(action)
        lv_obj_add_event_cb(b, { e in
            guard let ui = paintUI else { return }
            let i = Int(bitPattern: lv_event_get_user_data(e)) - 1
            if i >= 0 && i < ui.actions.count { ui.actions[i](ui) }
        }, LV_EVENT_CLICKED, UnsafeMutableRawPointer(bitPattern: actions.count))
        return b
    }

    private func select(_ t: Tool) {
        tool = t
        refreshTools()
    }

    private func refreshTools() {
        for (t, b) in toolButtons {
            lv_obj_set_style_bg_color(b, lvColor(t == tool ? orange : darkButton), partMain)
        }
    }

    /// Brush (a dot), fill (a bucket with a drop) and undo (a curved arrow), in the button's colour scheme
    private func drawIcon(_ obj: LVObj, _ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var a = lv_area_t()
        lv_obj_get_coords(obj, &a)
        let cx = (a.x1 + a.x2) / 2, cy = (a.y1 + a.y2) / 2
        let index = toolButtons.firstIndex { $0.1 == obj }
        let white = lv_color_white()
        func line(_ x1: Int32, _ y1: Int32, _ x2: Int32, _ y2: Int32, _ w: Int32 = 4) {
            var d = lv_draw_line_dsc_t()
            lv_draw_line_dsc_init(&d)
            d.p1 = wf_point(cx + x1, cy + y1)
            d.p2 = wf_point(cx + x2, cy + y2)
            d.width = w
            d.color = white
            d.round_start = 1
            d.round_end = 1
            lv_draw_line(layer, &d)
        }
        func disc(_ x: Int32, _ y: Int32, _ r: Int32, _ color: lv_color_t) {
            var d = lv_draw_rect_dsc_t()
            lv_draw_rect_dsc_init(&d)
            d.bg_color = color
            d.radius = wf_radius_circle()
            var area = lv_area_t(x1: cx + x - r, y1: cy + y - r, x2: cx + x + r, y2: cy + y + r)
            lv_draw_rect(layer, &d, &area)
        }
        if let index, toolButtons[index].0 == .brush {
            // A brush: handle and a round tip
            line(9, -11, -1, 3, 4)
            disc(-5, 7, 6, white)
        } else if let index, toolButtons[index].0 == .fill {
            // A bucket and a drop
            line(-11, -6, -7, 10)
            line(-7, 10, 5, 10)
            line(5, 10, 9, -6)
            line(-11, -6, 9, -6)
            disc(12, 4, 4, white)
        } else {
            // Undo: an arc with an arrowhead at its left end
            var d = lv_draw_arc_dsc_t()
            lv_draw_arc_dsc_init(&d)
            d.color = white
            d.width = 4
            d.center = lv_point_t(x: cx + 2, y: cy + 4)
            d.radius = 11
            d.start_angle = 180
            d.end_angle = 360 + 60
            d.rounded = 1
            lv_draw_arc(layer, &d)
            line(-9, 4, -15, -3)
            line(-9, 4, -2, -1)
        }
    }

    // MARK: Palette

    private func placeTab() {
        guard let tab else { return }
        lv_obj_set_pos(tab, palette == nil ? -10 : paletteW - 10, (screenH - 70) / 2)
        lv_obj_move_foreground(tab)
        lv_obj_invalidate(tab)
    }

    /// The current colour, and an arrow out (closed) or in (open)
    private func drawTab(_ obj: LVObj, _ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var a = lv_area_t()
        lv_obj_get_coords(obj, &a)
        let cx = (a.x1 + a.x2) / 2 + 5, cy = (a.y1 + a.y2) / 2
        var d = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&d)
        d.bg_color = lvColor(PaintPalette.colors[Int(color)])
        d.radius = wf_radius_circle()
        d.border_color = lv_color_white()
        d.border_width = 2
        var dot = lv_area_t(x1: cx - 9, y1: cy - 26, x2: cx + 9, y2: cy - 8)
        lv_draw_rect(layer, &d, &dot)
        var l = lv_draw_line_dsc_t()
        lv_draw_line_dsc_init(&l)
        l.color = lv_color_white()
        l.width = 4
        l.round_start = 1
        l.round_end = 1
        let dir: Int32 = palette == nil ? 1 : -1
        l.p1 = wf_point(cx - 4 * dir, cy + 4)
        l.p2 = wf_point(cx + 4 * dir, cy + 12)
        lv_draw_line(layer, &l)
        l.p1 = wf_point(cx + 4 * dir, cy + 12)
        l.p2 = wf_point(cx - 4 * dir, cy + 20)
        lv_draw_line(layer, &l)
    }

    private func togglePalette() {
        if let palette {
            lv_obj_delete_async(palette)
            self.palette = nil
            placeTab()
            return
        }
        let p = lvPlainObject(screen)
        lv_obj_set_pos(p, 0, 30)
        lv_obj_set_size(p, paletteW, screenH - 60)
        lv_obj_set_style_bg_color(p, lvColor(darkButton), partMain)
        lv_obj_set_style_bg_opa(p, 255, partMain)
        lv_obj_set_style_radius(p, 18, partMain)
        lv_obj_set_style_shadow_width(p, 12, partMain)
        lv_obj_set_style_shadow_opa(p, 90, partMain)
        lv_obj_add_flag(p, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(p, LV_OBJ_FLAG_GESTURE_BUBBLE)
        let swatch: Int32 = 40, step: Int32 = 50
        let top = (screenH - 60 - 8 * step + (step - swatch)) / 2
        for i in 0..<PaintPalette.colors.count {
            let s = lvPlainObject(p)
            lv_obj_set_size(s, swatch, swatch)
            lv_obj_set_pos(s, 14 + Int32(i % 2) * step, top + Int32(i / 2) * step)
            lv_obj_set_style_radius(s, wf_radius_circle(), partMain)
            lv_obj_set_style_bg_color(s, lvColor(PaintPalette.colors[i]), partMain)
            lv_obj_set_style_bg_opa(s, 255, partMain)
            lv_obj_set_style_border_color(s, lv_color_white(), partMain)
            lv_obj_set_style_border_width(s, UInt8(i) == color ? 4 : (i == 1 ? 1 : 0), partMain)
            lv_obj_add_flag(s, LV_OBJ_FLAG_CLICKABLE)
            lv_obj_add_event_cb(s, { e in
                guard let ui = paintUI else { return }
                ui.pick(UInt8(Int(bitPattern: lv_event_get_user_data(e)) - 1))
            }, LV_EVENT_CLICKED, UnsafeMutableRawPointer(bitPattern: i + 1))
        }
        palette = p
        placeTab()
    }

    private func pick(_ c: UInt8) {
        color = c
        togglePalette()
    }

    // MARK: Drawing

    private func touch(_ code: lv_event_code_t) {
        var p = lv_point_t()
        lv_indev_get_point(lv_indev_active(), &p)
        let x = Int(p.x) / scale, y = Int(p.y) / scale
        switch code {
        case LV_EVENT_PRESSED:
            if palette != nil {
                togglePalette()     // A tap beside the open palette closes it (and draws nothing)
                last = nil
                return
            }
            pushUndo()
            switch tool {
            case .fill:
                invalidate(image.fill(x, y, color))
                last = nil
            case .pencil, .brush:
                invalidate(image.dot(x, y, radius: radius, color))
                last = (x, y)
            }
        case LV_EVENT_PRESSING:
            guard let (lx, ly) = last, lx != x || ly != y else { return }
            invalidate(image.line(lx, ly, x, y, radius: radius, color))
            last = (x, y)
        default:
            if last != nil || tool == .fill { scheduleSave() }
            last = nil
        }
    }

    private var radius: Int { tool == .brush ? 4 : 1 }

    private func invalidate(_ r: PaintRect) {
        guard !r.isEmpty, let canvas else { return }
        var area = lv_area_t(x1: Int32(r.x0 * scale), y1: Int32(r.y0 * scale), x2: Int32(r.x1 * scale + scale - 1),
                             y2: Int32(r.y1 * scale + scale - 1))
        lv_obj_invalidate_area(canvas, &area)
    }

    private func invalidateAll() {
        if let canvas { lv_obj_invalidate(canvas) }
    }

    // MARK: Undo

    /// A copy for undo: measured first, and only if there's room for it (running out of memory would stop the
    /// watch; the oldest copies go first, and without room this step can't be undone)
    private func pushUndo() {
        let size = image.snapshotSize
        var total = undo.reduce(0) { $0 + $1.count }
        while !undo.isEmpty && (total + size > undoBudget || !hasRoom(for: size)) {
            total -= undo[0].count
            undo.removeFirst()
        }
        guard hasRoom(for: size) else { return }
        undo.append(image.snapshot())
    }

    /// Room for `bytes` in one piece, with some to spare for LVGL
    private func hasRoom(for bytes: Int) -> Bool {
        Int(heap_caps_get_largest_free_block(UInt32(MALLOC_CAP_INTERNAL))) >= bytes + 6 * 1024
    }

    private func undoLast() {
        guard let previous = undo.popLast(), image.restore(previous) else { return }
        invalidateAll()
        scheduleSave()
    }

    // MARK: Files

    private func scheduleSave() {
        if let saveTimer {
            lv_timer_reset(saveTimer)
            return
        }
        saveTimer = lv_timer_create({ _ in
            guard let ui = paintUI else { return }
            if let t = ui.saveTimer { lv_timer_delete(t) }
            ui.saveTimer = nil
            ui.saveCurrent()
        }, 1500, nil)
    }

    private func saveCurrent() {
        _ = paintDir.withCString { mkdir($0, 0o775) }
        _ = writeStreaming(currentPath) { image.write($0) }
    }

    /// A file written a piece at a time (via a temporary file and a rename, like writeFile)
    private func writeStreaming(_ path: String, _ body: (([UInt8]) -> Bool) -> Bool) -> Bool {
        let tmp = path + ".tmp"
        guard let f = tmp.withCString({ fopen($0, "wb") }) else { return false }
        let ok = body { chunk in fwrite(chunk, 1, chunk.count, f) == chunk.count }
        fclose(f)
        guard ok else {
            _ = tmp.withCString { unlink($0) }
            return false
        }
        _ = path.withCString { unlink($0) }
        return tmp.withCString { t in path.withCString { rename(t, $0) } } == 0
    }

    private func saveToGallery() {
        _ = paintDir.withCString { mkdir($0, 0o775) }
        // Named by time: newest last when sorted
        var id = "t\(time(nil))"
        while fileExists(paintDir + "/" + id + ".wpn") { id += "b" }
        let ok = writeStreaming(paintDir + "/" + id + ".wpn") { image.write($0) }
            && writeStreaming(paintDir + "/" + id + ".wpt") { image.writeThumbnail($0) }
        showToast(ok ? "Gemt" : "Kunne ikke gemme")
    }

    private func showToast(_ text: String) {
        if let toast { lv_obj_delete(toast) }
        let t = lvPlainObject(screen)
        lv_obj_set_style_bg_color(t, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(t, 200, partMain)
        lv_obj_set_style_radius(t, 20, partMain)
        lv_obj_set_style_pad_hor(t, 22, partMain)
        lv_obj_set_style_pad_ver(t, 10, partMain)
        lv_obj_set_size(t, wf_size_content(), wf_size_content())
        let l = lv_label_create(t)!
        lv_obj_set_style_text_font(l, wf_builtin_font(22), partMain)
        lv_obj_set_style_text_color(l, lv_color_white(), partMain)
        lvSetText(l, text)
        lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 30)
        toast = t
        if let toastTimer { lv_timer_delete(toastTimer) }
        toastTimer = lv_timer_create({ _ in
            guard let ui = paintUI else { return }
            if let t = ui.toast { lv_obj_delete(t) }
            ui.toast = nil
            if let t = ui.toastTimer { lv_timer_delete(t) }
            ui.toastTimer = nil
        }, 1500, nil)
    }

    // MARK: Gallery

    private func savedIDs() -> [String] {
        guard let dir = paintDir.withCString({ opendir($0) }) else { return [] }
        var ids: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard name.utf8.starts(with: "t".utf8), name.utf8.reversed().starts(with: "npw.".utf8) else { continue }
            ids.append(String(decoding: name.utf8.dropLast(4), as: UTF8.self))
        }
        closedir(dir)
        // Newest first ("t" + seconds: same length for a long while, so text order is time order)
        return ids.sorted { !$0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private func closeGallery() {
        closeSheet()
        if let gallery { lv_obj_delete_async(gallery) }
        gallery = nil
        PaintDecoder.releaseThumbnails()
    }

    private func showGallery() {
        if palette != nil { togglePalette() }
        closeGallery()
        let g = lvPlainObject(screen)
        lv_obj_set_size(g, screenW, screenH)
        lv_obj_set_style_bg_color(g, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(g, 255, partMain)
        lv_obj_add_flag(g, LV_OBJ_FLAG_CLICKABLE)
        gallery = g

        let title = lv_label_create(g)!
        lv_obj_set_style_text_font(title, wf_builtin_font(28), partMain)
        lv_obj_set_style_text_color(title, lv_color_white(), partMain)
        lvSetText(title, "Tegninger")
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 22)

        let new = button(g, "Ny tegning", w: 170, h: 48, color: orange, textColor: lv_color_black()) { ui in
            ui.newDrawing()
        }
        lv_obj_align(new, LV_ALIGN_TOP_LEFT, 34, 66)
        let back = button(g, "Luk", w: 110, h: 48, color: darkButton) { ui in ui.closeGallery() }
        lv_obj_align(back, LV_ALIGN_TOP_RIGHT, -34, 66)

        galleryIDs = savedIDs()
        let tw = (PaintImage.canvasWidth + 1) / 2, th = (PaintImage.canvasHeight + 1) / 2
        if galleryIDs.isEmpty {
            let empty = lv_label_create(g)!
            lv_obj_set_style_text_font(empty, wf_builtin_font(20), partMain)
            lv_obj_set_style_text_color(empty, lv_color_make(150, 150, 150), partMain)
            lv_obj_set_width(empty, 300)
            lv_label_set_long_mode(empty, LV_LABEL_LONG_MODE_WRAP)
            lv_obj_set_style_text_align(empty, LV_TEXT_ALIGN_CENTER, partMain)
            lvSetText(empty, "Ingen gemte tegninger endnu. Gem med \(LV_SYMBOL_SAVE)-knappen.")
            lv_obj_center(empty)
            return
        }
        let list = lvPlainObject(g)
        lv_obj_set_pos(list, 20, 128)
        lv_obj_set_size(list, screenW - 40, screenH - 128 - 16)
        lv_obj_add_flag(list, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_set_scroll_dir(list, LV_DIR_VER)
        lv_obj_set_flex_flow(list, LV_FLEX_FLOW_ROW_WRAP)
        lv_obj_set_flex_align(list, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START)
        lv_obj_set_style_pad_row(list, 12, partMain)
        lv_obj_set_style_pad_column(list, 12, partMain)
        lv_obj_set_style_pad_bottom(list, 30, partMain)
        for (i, id) in galleryIDs.enumerated() {
            let dsc = PaintDecoder.makeDsc(width: tw, height: th)
            PaintDecoder.thumbnails.append(.init(dsc: dsc, path: paintDir + "/" + id + ".wpt", width: tw, height: th))
            let img = lv_image_create(list)!
            lv_image_set_src(img, dsc)
            lv_obj_set_style_radius(img, 8, partMain)
            lv_obj_set_style_clip_corner(img, true, partMain)
            lv_obj_add_flag(img, LV_OBJ_FLAG_CLICKABLE)
            lv_obj_add_event_cb(img, { e in
                paintUI?.showSheet(Int(bitPattern: lv_event_get_user_data(e)) - 1)
            }, LV_EVENT_SHORT_CLICKED, UnsafeMutableRawPointer(bitPattern: i + 1))
        }
    }

    private func closeSheet() {
        if let sheet { lv_obj_delete_async(sheet) }
        sheet = nil
    }

    /// Open or delete a saved drawing
    private func showSheet(_ index: Int) {
        guard let gallery, index >= 0, index < galleryIDs.count else { return }
        closeSheet()
        let id = galleryIDs[index]
        let s = lvPlainObject(gallery)
        lv_obj_set_size(s, screenW, screenH)
        lv_obj_set_style_bg_color(s, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(s, 220, partMain)
        lv_obj_add_flag(s, LV_OBJ_FLAG_CLICKABLE)
        sheet = s
        let w: Int32 = 240
        let open = button(s, "Åbn", w: w, color: orange, textColor: lv_color_black()) { ui in ui.open(id) }
        lv_obj_align(open, LV_ALIGN_CENTER, 0, -70)
        let delete = button(s, "Slet", w: w, color: FaceColor(r: 192, g: 57, b: 43)) { ui in ui.delete(id) }
        lv_obj_align(delete, LV_ALIGN_CENTER, 0, 0)
        let cancel = button(s, "Annuller", w: w, color: darkButton) { ui in ui.closeSheet() }
        lv_obj_align(cancel, LV_ALIGN_CENTER, 0, 70)
    }

    private func open(_ id: String) {
        guard let bytes = readFile(paintDir + "/" + id + ".wpn", maxSize: 64 * 1024) else {
            showToast("Kunne ikke åbne")
            return
        }
        pushUndo()  // The drawing replaced can be had back with undo
        do throws(PaintFileError) {
            try image.load(bytes)
        } catch {
            if let previous = undo.popLast() { _ = image.restore(previous) }
            invalidateAll()
            showToast("Kunne ikke åbne")
            return
        }
        closeGallery()
        invalidateAll()
        saveCurrent()
    }

    private func delete(_ id: String) {
        _ = (paintDir + "/" + id + ".wpn").withCString { unlink($0) }
        _ = (paintDir + "/" + id + ".wpt").withCString { unlink($0) }
        showGallery()
    }

    private func newDrawing() {
        pushUndo()
        image.clear()
        closeGallery()
        invalidateAll()
        saveCurrent()
    }
}

nonisolated(unsafe) private var paintUI: PaintUI?

@_cdecl("paint_app_show")
public func paint_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    // ~26 KB for the drawing in one piece (undo copies are small, and loading works in place)
    let largest = heap_caps_get_largest_free_block(UInt32(MALLOC_CAP_INTERNAL))
    print("paint: free heap \(heap_caps_get_free_size(UInt32(MALLOC_CAP_INTERNAL)) / 1024) KB, largest block " +
          "\(largest / 1024) KB")
    guard largest >= 28 * 1024 else {
        let l = lv_label_create(screen)!
        lv_obj_set_width(l, 300)
        lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_WRAP)
        lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, partMain)
        lv_obj_set_style_text_font(l, wf_builtin_font(22), partMain)
        lvSetText(l, "Der er ikke hukommelse nok lige nu. Prøv igen, når uret ikke lader og Synk er lukket.")
        lv_obj_center(l)
        return
    }
    let image = PaintImage()
    if let bytes = readFile(currentPath, maxSize: 64 * 1024) {
        do throws(PaintFileError) {
            try image.load(bytes)
        } catch {}
    }
    paintUI = PaintUI(screen: screen, image: image)
}

@_cdecl("paint_app_hide")
public func paint_app_hide() {
    // Saved and freed now; the objects are deleted by the app framework after this
    paintUI?.stop()
    paintUI = nil
}
