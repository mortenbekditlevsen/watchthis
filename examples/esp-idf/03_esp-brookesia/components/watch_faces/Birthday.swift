// The wearer's birthday (set by the phone, SetBirthday): on that day the faces get a Danish flag in the top left
// corner, and tapping it sets off fireworks. Kept in /store/faces/birthday as month(1) day(1).

enum Birthday {
    static let path = "/store/faces/birthday"

    /// month * 32 + day, 0 = none; written by the BLE task, read by the LVGL task
    nonisolated(unsafe) static var packed: Int32 = 0

    static var date: BirthdayDate? {
        let p = Int(wf_atomic_load(&packed))
        return BirthdayDate(month: p / 32, day: p % 32)
    }

    static func load() {
        guard let bytes = readFile(path, maxSize: 2), bytes.count == 2,
              BirthdayDate(month: Int(bytes[0]), day: Int(bytes[1])) != nil else { return }
        wf_atomic_store(&packed, Int32(bytes[0]) * 32 + Int32(bytes[1]))
    }
}

/// month 0 / day 0 = no birthday. Returns a Result status (0 = OK, 1 = failed, 2 = invalid).
@_cdecl("watch_faces_set_birthday")
public func watch_faces_set_birthday(_ month: UInt8, _ day: UInt8) -> UInt8 {
    if month == 0 && day == 0 {
        _ = Birthday.path.withCString { unlink($0) }
        wf_atomic_store(&Birthday.packed, 0)
        return 0
    }
    guard BirthdayDate(month: Int(month), day: Int(day)) != nil else { return 2 }
    guard writeFile(Birthday.path, [month, day]) else { return 1 }
    wf_atomic_store(&Birthday.packed, Int32(month) * 32 + Int32(day))
    return 0
}

/// The flag (top left, on top of every face) and the fireworks it sets off
final class BirthdayDecoration {
    private let screen: LVObj
    private var flag: LVObj?
    private var overlay: LVObj?
    private var timer: OpaquePointer?
    private var fireworks = Fireworks(seed: 1)
    private var lastTick: UInt32 = 0

    init(screen: LVObj) {
        self.screen = screen
    }

    /// Show or hide the flag for today; from the carousel's timer
    func update(_ t: WallTime) {
        let today = Birthday.date?.isToday(t) ?? false
        if today && flag == nil {
            flag = makeFlag()
        } else if !today, let flag {
            stopFireworks()
            lv_obj_delete(flag)
            self.flag = nil
        }
    }

    /// Keep the flag (and fireworks) above a newly built face
    func bringToFront() {
        if let flag { lv_obj_move_foreground(flag) }
        if let overlay { lv_obj_move_foreground(overlay) }
    }

    /// Before the decoration goes away: its objects' callbacks point at it
    func stop() {
        stopFireworks()
        if let flag { lv_obj_delete(flag) }
        flag = nil
    }

    private func makeFlag() -> LVObj {
        let width: Int32 = 60
        let height = Int32(Dannebrog.height(width: Int(width)))
        let flag = lvPlainObject(screen)
        lv_obj_set_size(flag, width, height)
        lv_obj_set_pos(flag, 26, 22)
        lv_obj_set_style_bg_color(flag, lvColor(Dannebrog.red), partMain)
        lv_obj_set_style_bg_opa(flag, 255, partMain)
        lv_obj_set_style_radius(flag, 3, partMain)
        lv_obj_set_style_clip_corner(flag, true, partMain)
        let bars = Dannebrog.whiteBars(width: Int(width))
        for (x, y, w, h) in [bars.vertical, bars.horizontal] {
            let bar = lvPlainObject(flag)
            lv_obj_set_pos(bar, Int32(x), Int32(y))
            lv_obj_set_size(bar, Int32(w), Int32(h))
            lv_obj_set_style_bg_color(bar, lv_color_white(), partMain)
            lv_obj_set_style_bg_opa(bar, 255, partMain)
        }
        // Tappable (with some slack around it); swipes that start on it still change the face
        lv_obj_add_flag(flag, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_add_flag(flag, LV_OBJ_FLAG_GESTURE_BUBBLE)
        lv_obj_set_ext_click_area(flag, 16)
        lv_obj_add_event_cb(flag, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            Unmanaged<BirthdayDecoration>.fromOpaque(ud).takeUnretainedValue().startFireworks()
        }, LV_EVENT_CLICKED, Unmanaged.passUnretained(self).toOpaque())
        return flag
    }

    // MARK: - Fireworks

    /// The fireworks get a page of their own: black, with the greeting in the middle. Being opaque, the face
    /// underneath isn't redrawn on every frame.
    private func startFireworks() {
        fireworks = Fireworks(seed: lv_tick_get(), launchDuration: 6)
        lastTick = lv_tick_get()
        lastSparkArea = nil
        if overlay == nil {
            let overlay = lvPlainObject(screen)
            lv_obj_set_size(overlay, Int32(WatchScreen.width), Int32(WatchScreen.height))
            lv_obj_set_style_bg_color(overlay, lv_color_black(), partMain)
            lv_obj_set_style_bg_opa(overlay, 255, partMain)
            // Sparks in DRAW_MAIN (after the background, before the children): the greeting stays on top
            lv_obj_add_event_cb(overlay, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                Unmanaged<BirthdayDecoration>.fromOpaque(ud).takeUnretainedValue().draw(e)
            }, LV_EVENT_DRAW_MAIN, Unmanaged.passUnretained(self).toOpaque())
            // A tap ends the show early
            lv_obj_add_flag(overlay, LV_OBJ_FLAG_CLICKABLE)
            lv_obj_add_event_cb(overlay, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                Unmanaged<BirthdayDecoration>.fromOpaque(ud).takeUnretainedValue().stopFireworks()
            }, LV_EVENT_CLICKED, Unmanaged.passUnretained(self).toOpaque())

            let greeting = lv_label_create(overlay)!
            lv_obj_set_width(greeting, Int32(WatchScreen.width) - 40)
            lv_obj_set_style_text_font(greeting, wf_builtin_font(28), partMain)
            lv_obj_set_style_text_color(greeting, lv_color_white(), partMain)
            lv_obj_set_style_text_align(greeting, LV_TEXT_ALIGN_CENTER, partMain)
            lv_obj_set_style_text_line_space(greeting, 6, partMain)
            lvSetText(greeting, "Tillykke med\nfødselsdagen!")
            lv_obj_center(greeting)
            self.overlay = overlay
        }
        if timer == nil {
            timer = lv_timer_create({ t in
                guard let ud = lv_timer_get_user_data(t) else { return }
                Unmanaged<BirthdayDecoration>.fromOpaque(ud).takeUnretainedValue().tick()
            }, 33, Unmanaged.passUnretained(self).toOpaque())
        }
        bringToFront()
    }

    private func stopFireworks() {
        if let timer { lv_timer_delete(timer) }
        timer = nil
        if let overlay { lv_obj_delete(overlay) }
        overlay = nil
    }

    /// Where the sparks were drawn last frame (it must be redrawn to erase them)
    private var lastSparkArea: lv_area_t?

    private func tick() {
        let now = lv_tick_get()
        // Clamp: after a slow frame (or light sleep), don't jump
        fireworks.step(min(0.1, Float(now &- lastTick) / 1000))
        lastTick = now
        // Watching counts as activity: the idle sleep (10 s, power manager) starts counting when the show ends
        lv_display_trigger_activity(nil)
        guard !fireworks.isFinished else {
            stopFireworks()
            return
        }
        guard let overlay else { return }
        // Redraw only the box around the sparks (now and last frame), not the whole screen
        var area = sparkArea()
        if let last = lastSparkArea {
            if let current = area {
                area = lv_area_t(x1: min(current.x1, last.x1), y1: min(current.y1, last.y1),
                                 x2: max(current.x2, last.x2), y2: max(current.y2, last.y2))
            } else {
                area = last
            }
        }
        lastSparkArea = sparkArea()
        if var area {
            lv_obj_invalidate_area(overlay, &area)
        }
    }

    private func sparkArea() -> lv_area_t? {
        guard let first = fireworks.sparks.first else { return nil }
        var area = lv_area_t(x1: Int32(first.x), y1: Int32(first.y), x2: Int32(first.x), y2: Int32(first.y))
        for spark in fireworks.sparks {
            area.x1 = min(area.x1, Int32(spark.x))
            area.y1 = min(area.y1, Int32(spark.y))
            area.x2 = max(area.x2, Int32(spark.x))
            area.y2 = max(area.y2, Int32(spark.y))
        }
        let margin: Int32 = 4 // the dots' size
        area.x1 = max(0, area.x1 - margin)
        area.y1 = max(0, area.y1 - margin)
        area.x2 = min(Int32(WatchScreen.width) - 1, area.x2 + margin)
        area.y2 = min(Int32(WatchScreen.height) - 1, area.y2 + margin)
        return area.x1 <= area.x2 && area.y1 <= area.y2 ? area : nil
    }

    private func draw(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var dsc = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&dsc)
        dsc.radius = wf_radius_circle()
        for spark in fireworks.sparks {
            dsc.bg_color = lvColor(spark.color)
            dsc.bg_opa = spark.opacity
            let x = Int32(spark.x), y = Int32(spark.y), r = Int32(spark.size / 2)
            var area = lv_area_t(x1: x - r, y1: y - r, x2: x - r + Int32(spark.size) - 1, y2: y - r + Int32(spark.size) - 1)
            lv_draw_rect(layer, &dsc, &area)
        }
    }
}
