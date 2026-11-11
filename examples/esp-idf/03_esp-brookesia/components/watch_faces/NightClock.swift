// The night clock: the time in big red digits with the date underneath, for a watch lying on its side (the
// power manager decides when; main/power_manager.cpp). The watch lies sideways, so everything is drawn turned 90°:
// "view" coordinates (u to the right, v down, as the viewer sees them; VW x VH) map to the screen's.
//
// The digits are seven-segment bars: plain rectangles, still rectangles once turned. The date is text: LVGL turns
// letters one by one but clips each by its unturned box (bits go missing when the screen is drawn in strips), so the
// date is drawn upright into a buffer once a day and turned here, then shown as an A8 image (coloured by its recolor).
//
// Its own screen: the face underneath isn't redrawn meanwhile (its timers only invalidate a screen not shown). The
// shell's overlays (the home indicator bar, on the system layer above every screen) are hidden meanwhile.

private let viewW = Int32(WatchScreen.height)  // The watch on its side: the screen's height is the width seen
private let viewH = Int32(WatchScreen.width)

private let digitW: Int32 = 92
private let digitH: Int32 = 200
private let stroke: Int32 = 26
private let segmentGap: Int32 = 3
private let pairGap: Int32 = 20     // Between the two digits of the hours (and of the minutes)
private let colonW: Int32 = 52      // The colon's column, with its space either side
private let timeTop: Int32 = 46
private let dateTop: Int32 = 290
private let dateHeight: Int32 = 40

private let red = FaceColor(r: 235, g: 20, b: 20)
private let dateRed = FaceColor(r: 200, g: 20, b: 20)

/// How long a finger must stay down to end the clock (a tap, or brushing against it in the night, doesn't)
private let longPressMs: UInt32 = 1000

private let monthsFull = ["januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september",
                          "oktober", "november", "december"]

/// Segments a...g (bit 0 = a: top, b: top right, c: bottom right, d: bottom, e: bottom left, f: top left, g: middle)
private let digitSegments: [UInt8] = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

private final class NightClock {
    /// +1: left side down, -1: right side down
    let side: Int32
    let screen: LVObj
    private let previous: LVObj?
    private var timer: OpaquePointer?
    private var shownMinute = -1
    private var shownDay = -1
    private var dateImage: LVObj?
    private var datePixels: UnsafeMutablePointer<UInt8>?
    private var dateDsc: UnsafeMutablePointer<lv_image_dsc_t>?
    /// What was visible on the system layer (hidden while the clock shows)
    private var hiddenSystemObjects: [LVObj] = []
    private var pressedSince: UInt32?

    init(side: Int32) {
        self.side = side
        previous = lv_screen_active()
        screen = lv_obj_create(nil)!
        lv_obj_remove_style_all(screen)
        lv_obj_set_size(screen, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_add_flag(screen, LV_OBJ_FLAG_CLICKABLE)
        let me = Unmanaged.passUnretained(self).toOpaque()
        lv_obj_add_event_cb(screen, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            Unmanaged<NightClock>.fromOpaque(ud).takeUnretainedValue().draw(e)
        }, LV_EVENT_DRAW_MAIN, me)
        // A long press ends it (the power manager decides what then)
        for code in [LV_EVENT_PRESSED, LV_EVENT_PRESSING, LV_EVENT_RELEASED, LV_EVENT_PRESS_LOST] {
            lv_obj_add_event_cb(screen, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                Unmanaged<NightClock>.fromOpaque(ud).takeUnretainedValue().touch(lv_event_get_code(e))
            }, code, me)
        }
        timer = lv_timer_create({ t in
            guard let ud = lv_timer_get_user_data(t) else { return }
            Unmanaged<NightClock>.fromOpaque(ud).takeUnretainedValue().tick()
        }, 1000, me)
        tick()
        lv_screen_load(screen)
        if let layer = lv_layer_sys() {
            for i in 0..<lv_obj_get_child_count(layer) {
                guard let child = lv_obj_get_child(layer, Int32(i)), !lv_obj_has_flag(child, LV_OBJ_FLAG_HIDDEN) else {
                    continue
                }
                lv_obj_add_flag(child, LV_OBJ_FLAG_HIDDEN)
                hiddenSystemObjects.append(child)
            }
        }
    }

    func close() {
        if let timer { lv_timer_delete(timer) }
        timer = nil
        for obj in hiddenSystemObjects where lv_obj_is_valid(obj) {
            lv_obj_remove_flag(obj, LV_OBJ_FLAG_HIDDEN)
        }
        hiddenSystemObjects.removeAll()
        if let previous, lv_obj_is_valid(previous) { lv_screen_load(previous) }
        lv_obj_delete(screen)
        freeDate()
    }

    private func touch(_ code: lv_event_code_t) {
        let now = lv_tick_get()
        switch code {
        case LV_EVENT_PRESSED:
            pressedSince = now
        case LV_EVENT_PRESSING:
            if let since = pressedSince, now &- since >= longPressMs {
                pressedSince = nil  // Once
                nightClockTapHandler?()
            }
        default:
            pressedSince = nil
        }
    }

    private func tick() {
        let t = currentWallTime()
        if t.day != shownDay {
            shownDay = t.day
            makeDate(t)
        }
        if t.minute != shownMinute {
            shownMinute = t.minute
            lv_obj_invalidate(screen)
        }
    }

    // MARK: - Turning view coordinates into the screen's

    /// The screen area of the view rectangle u1...u2, v1...v2 (inclusive)
    private func screenArea(_ u1: Int32, _ v1: Int32, _ u2: Int32, _ v2: Int32) -> lv_area_t {
        if side > 0 {
            // Left side down: the view's top is the screen's right edge, its left the screen's top
            return lv_area_t(x1: viewH - 1 - v2, y1: u1, x2: viewH - 1 - v1, y2: u2)
        }
        return lv_area_t(x1: v1, y1: viewW - 1 - u2, x2: v2, y2: viewW - 1 - u1)
    }

    // MARK: - Time

    private func draw(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        let t = currentWallTime()
        let total = 4 * digitW + 2 * pairGap + colonW
        var u = (viewW - total) / 2
        let digits = [t.hour / 10, t.hour % 10, t.minute / 10, t.minute % 10]
        for (i, d) in digits.enumerated() {
            // No leading zero in the hours
            if !(i == 0 && d == 0) { drawDigit(layer, d, u: u, v: timeTop) }
            u += digitW
            if i == 0 || i == 2 { u += pairGap }
            if i == 1 {
                let x = u + (colonW - stroke) / 2
                fill(layer, x, timeTop + digitH * 3 / 10 - stroke / 2, x + stroke - 1, timeTop + digitH * 3 / 10 + stroke / 2)
                fill(layer, x, timeTop + digitH * 7 / 10 - stroke / 2, x + stroke - 1, timeTop + digitH * 7 / 10 + stroke / 2)
                u += colonW
            }
        }
    }

    private func drawDigit(_ layer: UnsafeMutablePointer<lv_layer_t>, _ digit: Int, u: Int32, v: Int32) {
        let bits = digitSegments[digit]
        let g = segmentGap, s = stroke, w = digitW, h = digitH, mid = digitH / 2
        // Horizontal bars between the vertical ones, vertical ones the full half height (gaps at the joints)
        let segments: [(Int32, Int32, Int32, Int32)] = [
            (s + g, 0, w - s - g - 1, s - 1),                       // a
            (w - s, g, w - 1, mid - g),                             // b
            (w - s, mid + g, w - 1, h - g - 1),                     // c
            (s + g, h - s, w - s - g - 1, h - 1),                   // d
            (0, mid + g, s - 1, h - g - 1),                         // e
            (0, g, s - 1, mid - g),                                 // f
            (s + g, mid - s / 2, w - s - g - 1, mid + s / 2 - 1),   // g
        ]
        for (i, seg) in segments.enumerated() where bits & (1 << i) != 0 {
            fill(layer, u + seg.0, v + seg.1, u + seg.2, v + seg.3)
        }
    }

    private func fill(_ layer: UnsafeMutablePointer<lv_layer_t>, _ u1: Int32, _ v1: Int32, _ u2: Int32, _ v2: Int32) {
        var dsc = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&dsc)
        dsc.bg_color = lvColor(red)
        dsc.bg_opa = 255
        dsc.radius = 5
        var area = screenArea(u1, v1, u2, v2)
        lv_draw_rect(layer, &dsc, &area)
    }

    // MARK: - Date

    private func freeDate() {
        if let dateImage, lv_obj_is_valid(dateImage) { lv_obj_delete(dateImage) }
        dateImage = nil
        datePixels?.deallocate()
        datePixels = nil
        dateDsc?.deallocate()
        dateDsc = nil
    }

    private func makeDate(_ t: WallTime) {
        freeDate()
        let text = "\(FaceText.weekdays[max(0, min(6, t.weekday))]) \(t.day). \(monthsFull[max(0, min(11, t.month - 1))])"
        let font = wf_builtin_font(28)
        let textW = min(viewW - 20, text.withCString { wf_text_width($0, font) } + 8)
        let textH = dateHeight
        // Upright first (L8, white on black), then turned into the image (A8: the same values as coverage)
        let uprightStride = Int32(wf_l8_stride(textW))
        guard textW > 0, let upright = malloc(Int(uprightStride * textH))?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        defer { free(upright) }
        text.withCString { wf_render_text_l8(screen, upright, textW, textH, $0, font) }
        // Turned: the image is textH wide and textW high
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(textW * textH))
        for j in 0..<textH {
            for i in 0..<textW {
                let value = upright[Int(j * uprightStride + i)]
                let (sx, sy) = side > 0 ? (textH - 1 - j, i) : (j, textW - 1 - i)
                pixels[Int(sy * textH + sx)] = value
            }
        }
        let dsc = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
        dsc.initialize(to: lv_image_dsc_t())
        wf_image_dsc_init(dsc, LV_COLOR_FORMAT_A8, UInt32(textH), UInt32(textW), UInt32(textH), pixels,
                          UInt32(textW * textH))
        let image = lv_image_create(screen)!
        lv_image_set_src(image, UnsafeRawPointer(dsc))
        lv_obj_set_style_image_recolor(image, lvColor(dateRed), partMain)
        lv_obj_set_style_image_recolor_opa(image, 255, partMain)
        let u1 = (viewW - textW) / 2
        let area = screenArea(u1, dateTop, u1 + textW - 1, dateTop + textH - 1)
        lv_obj_set_pos(image, area.x1, area.y1)
        datePixels = pixels
        dateDsc = dsc
        dateImage = image
    }
}

nonisolated(unsafe) private var nightClock: NightClock?
nonisolated(unsafe) private var nightClockTapHandler: (@convention(c) () -> Void)?

/// `side`: 1 = lying on its left side, -1 = on its right side. With the LVGL lock held.
@_cdecl("night_clock_show")
public func night_clock_show(_ side: Int32) {
    if let clock = nightClock {
        if clock.side == side { return }
        clock.close()
    }
    nightClock = NightClock(side: side >= 0 ? 1 : -1)
}

@_cdecl("night_clock_hide")
public func night_clock_hide() {
    nightClock?.close()
    nightClock = nil
}

/// Called (on the LVGL task) when the night clock is long pressed
@_cdecl("night_clock_set_tap_handler")
public func night_clock_set_tap_handler(_ handler: (@convention(c) () -> Void)?) {
    nightClockTapHandler = handler
}
