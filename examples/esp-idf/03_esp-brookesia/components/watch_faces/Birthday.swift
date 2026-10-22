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

    private func startFireworks() {
        fireworks = Fireworks(seed: lv_tick_get())
        lastTick = lv_tick_get()
        if overlay == nil {
            let overlay = lvPlainObject(screen)
            lv_obj_set_size(overlay, Int32(WatchScreen.width), Int32(WatchScreen.height))
            lv_obj_add_event_cb(overlay, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                Unmanaged<BirthdayDecoration>.fromOpaque(ud).takeUnretainedValue().draw(e)
            }, LV_EVENT_DRAW_POST, Unmanaged.passUnretained(self).toOpaque())
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

    private func tick() {
        let now = lv_tick_get()
        // Clamp: after a slow frame (or light sleep), don't jump
        fireworks.step(min(0.1, Float(now &- lastTick) / 1000))
        lastTick = now
        if fireworks.isFinished {
            stopFireworks()
        } else if let overlay {
            lv_obj_invalidate(overlay)
        }
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
