// The faces screen: shows one face. A swipe up goes home (anywhere on the face: brookesia's own gesture only counts
// from the bottom edge). A long press opens the switcher: half-size pictures of the faces, swipe left/right between
// them, tap to choose. Only the face on screen exists; the switcher shows files (Baker).

private let toastDuration: UInt32 = 1200
/// After the finger lifts, keep the face still this long (brookesia's home gesture, the switcher opening)
private let touchQuietTime: UInt32 = 400
/// Frames slower than this are logged (rendering and touch input share the LVGL task)
private let slowFrameMs: UInt32 = 60
/// A smooth second hand needs frames faster than this; slower, it ticks once a second (on the second marks) rather
/// than in fast-looking steps. Back to smooth below `smoothRecoverMs`.
private let smoothLimitMs: UInt32 = 60
private let smoothRecoverMs: UInt32 = 40
private let bakeStepMs: UInt32 = 50

final class Carousel {
    let screen: LVObj
    private var ids: [String]
    private var index: Int
    private var current: RenderedFace?
    private var timer: OpaquePointer?
    private var bakeTimer: OpaquePointer?
    private let toast: LVObj
    private var toastShownAt: UInt32 = 0
    private var touchedAt: UInt32?
    /// Recent frame time (ms, smoothed)
    private var frameMs: UInt32 = 0
    private var appliedPeriod: UInt32 = 0
    private var ticking = false // a smooth second hand ticking once a second (frames too slow)
    private let birthday: BirthdayDecoration
    private let baker = Baker()
    private var switcher: Switcher?

    init() {
        screen = lv_obj_create(nil)!
        lv_obj_remove_style_all(screen)
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
        // The power manager's "idle sleep allowed here" flag (main/power_manager.hpp)
        lv_obj_add_flag(screen, LV_OBJ_FLAG_USER_1)

        toast = lv_label_create(screen)!
        lv_obj_set_style_text_font(toast, wf_builtin_font(20), partMain)
        lv_obj_set_style_text_color(toast, lv_color_white(), partMain)
        lv_obj_set_style_bg_color(toast, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(toast, 180, partMain)
        lv_obj_set_style_radius(toast, 12, partMain)
        lv_obj_set_style_pad_hor(toast, 14, partMain)
        lv_obj_set_style_pad_ver(toast, 6, partMain)
        lv_obj_align(toast, LV_ALIGN_TOP_MID, 0, 84) // below the birthday flag
        lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN)
        birthday = BirthdayDecoration(screen: screen)

        let visible = FaceStore.visible()
        ids = visible.ids
        index = visible.active
        wf_atomic_store(&facesChanged, 0)

        lv_obj_add_event_cb(screen, { _ in carousel?.onGesture() }, LV_EVENT_GESTURE, nil)
        lv_obj_add_event_cb(screen, { _ in carousel?.openSwitcher() }, LV_EVENT_LONG_PRESSED, nil)
        baker.onFinished = { face, product in carousel?.baked(face, product) }

        showCurrent()
        birthday.update(currentWallTime())
        lv_display_add_event_cb(lv_display_get_default(), refreshCallback, LV_EVENT_REFR_START, nil)
        lv_display_add_event_cb(lv_display_get_default(), refreshCallback, LV_EVENT_REFR_READY, nil)
        timer = lv_timer_create({ _ in carousel?.tick() }, current?.updatePeriod ?? 1000, nil)
        bakeTimer = lv_timer_create({ _ in carousel?.bakeTick() }, bakeStepMs, nil)
        adjustPeriod()
    }

    func stop() {
        // Both registrations (start and ready) use the same function and user data
        while lv_display_remove_event_cb_with_user_data(lv_display_get_default(), refreshCallback, nil) > 0 {}
        birthday.stop()
        baker.cancelAll()
        if let timer { lv_timer_delete(timer) }
        timer = nil
        if let bakeTimer { lv_timer_delete(bakeTimer) }
        bakeTimer = nil
    }

    private var isOnScreen: Bool { lv_screen_active() == screen }

    private func showCurrent() {
        if let current { lv_obj_delete(current.root) }
        let face = FaceStore.load(ids[index]) ?? WatchFace.classic
        let start = lv_tick_get()
        let rendered = RenderedFace(face: face, parent: screen)
        lv_obj_move_background(rendered.root) // under the toast and the birthday flag
        print("watch_faces: \(face.id) built in \(lv_tick_elaps(start)) ms, free heap " +
              "\(heap_caps_get_free_size(UInt32(MALLOC_CAP_INTERNAL)) / 1024) KB")
        current = rendered
        if rendered.needsBake { baker.bakeSlot(face) }
        baker.enqueueThumbnail(face)
        adjustPeriod()
    }

    private func baked(_ face: WatchFace, _ product: Baker.Product) {
        switch product {
        case .slot:
            if let current, BakeKeys.hash(current.face).utf8.elementsEqual(BakeKeys.hash(face).utf8) {
                current.useSlot()
            }
        case .thumbnail:
            switcher?.refresh()
        }
    }

    /// Called after every display refresh with how long it took
    func noteFrame(_ ms: UInt32) {
        frameMs = (frameMs * 3 + ms) / 4
        adjustPeriod()
    }

    private func adjustPeriod() {
        guard let timer, let current else { return }
        if current.hasSmoothSecondHand {
            if !ticking && frameMs > smoothLimitMs { ticking = true }
            if ticking && frameMs < smoothRecoverMs { ticking = false }
        }
        let period = ticking ? max(current.updatePeriod, 1000) : current.updatePeriod
        if period != appliedPeriod {
            appliedPeriod = period
            lv_timer_set_period(timer, period)
        }
    }

    private func tick() {
        if wf_atomic_load(&facesChanged) != 0 {
            wf_atomic_store(&facesChanged, 0)
            ImageWorker.failedAssets.removeAll()
            if wf_atomic_load(&assetsChanged) != 0 {
                // A replaced font or image: the baked layers may contain the old one
                wf_atomic_store(&assetsChanged, 0)
                baker.cancelAll()
                if let current { lv_obj_delete(current.root) }
                current = nil
                ImageWorker.removeBaked()
                StaticSlot.invalidate()
            }
            let previousID = ids[index]
            let visible = FaceStore.visible()
            ids = visible.ids
            index = ids.firstIndex { $0.utf8.elementsEqual(previousID.utf8) } ?? visible.active
            if let switcher {
                switcher.remove()
                self.switcher = nil
            }
            showCurrent()
            return
        }
        guard isOnScreen, switcher == nil else { return } // paused at home, or the switcher shows
        // Touch input and drawing share the LVGL task: while a finger is on the screen (and just after), don't redraw
        // the face, so gestures are read promptly. The hands catch up afterwards (everything comes from the clock).
        if isTouching() {
            touchedAt = lv_tick_get()
            return
        }
        if let touchedAt, lv_tick_elaps(touchedAt) < touchQuietTime {
            return
        }
        touchedAt = nil
        var now = currentWallTime()
        if ticking { now.millisecond = 0 } // on the second marks
        current?.update(now)
        birthday.update(now)
        if !lv_obj_has_flag(toast, LV_OBJ_FLAG_HIDDEN) && lv_tick_elaps(toastShownAt) > toastDuration {
            lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN)
        }
    }

    private func bakeTick() {
        guard isOnScreen, !isTouching(), !baker.isIdle else { return }
        if let touchedAt, lv_tick_elaps(touchedAt) < touchQuietTime { return }
        baker.step()
    }

    /// What's showing, for the slow-frame log
    var describe: String {
        if switcher != nil { return "switcher" + (baker.isIdle ? "" : ", baking") }
        guard let current else { return "no face" }
        return current.face.id + (current.needsBake ? " (live)" : " (baked)") + (baker.isIdle ? "" : ", baking")
    }

    private func isTouching() -> Bool {
        var indev = lv_indev_get_next(nil)
        while let device = indev {
            if lv_indev_get_type(device) == LV_INDEV_TYPE_POINTER && lv_indev_get_state(device) == LV_INDEV_STATE_PRESSED {
                return true
            }
            indev = lv_indev_get_next(device)
        }
        return false
    }

    private func showToast(_ text: String) {
        lvSetText(toast, text)
        lv_obj_remove_flag(toast, LV_OBJ_FLAG_HIDDEN)
        lv_obj_move_foreground(toast)
        toastShownAt = lv_tick_get()
    }

    // MARK: - Gestures

    fileprivate func onGesture() {
        let dir = lv_indev_get_gesture_dir(lv_indev_active())
        if let switcher {
            switcher.onGesture(dir)
        } else if dir == LV_DIR_TOP {
            // Not from inside this event (the navigation pauses the app and changes the screen)
            lv_async_call({ _ in homeHandler?() }, nil)
        }
    }

    // MARK: - Switcher

    fileprivate func openSwitcher() {
        guard switcher == nil, isOnScreen else { return }
        // Free the face while the switcher shows (and let the baker use the time for missing pictures)
        if let current { lv_obj_delete(current.root) }
        current = nil
        let faces = ids.map { FaceStore.load($0) ?? WatchFace.classic }
        for i in 0..<faces.count {
            baker.enqueueThumbnail(faces[(index + i) % faces.count]) // the current one and the next ones first
        }
        switcher = Switcher(parent: screen, faces: faces, index: index)
        birthday.bringToFront()
    }

    fileprivate func closeSwitcher(choosing chosen: Int? = nil) {
        guard let switcher else { return }
        switcher.remove()
        self.switcher = nil
        if let chosen, chosen != index {
            index = chosen
            FaceStore.saveActive(index, ids: ids)
        }
        showCurrent()
        birthday.bringToFront()
        if chosen != nil, let current { showToast(current.face.name) }
    }

    fileprivate func switcherTapped(_ tag: Int) {
        switcher?.tapped(tag)
    }

    fileprivate var switcherChoice: Int? { switcher?.chosen }
}

/// The face switcher: the chosen face's picture in the middle, its neighbours peeking in at the sides
private final class Switcher {
    let container: LVObj
    let faces: [WatchFace]
    var index: Int
    var left: LVObj!
    var center: LVObj!
    var right: LVObj!
    var name: LVObj!
    var dots: LVObj!

    // Quarter-size thumbnails shown at twice their size
    static let thumbW = Int32(BakeKeys.thumbnailWidth * 2)
    static let thumbH = Int32(BakeKeys.thumbnailHeight * 2)
    static let gap: Int32 = 20
    static let topY: Int32 = 70

    init(parent: LVObj, faces: [WatchFace], index: Int) {
        self.faces = faces
        self.index = index
        container = lvPlainObject(parent)
        lv_obj_set_size(container, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_color(container, lv_color_hex(0x101010), partMain)
        lv_obj_set_style_bg_opa(container, 255, partMain)
        lv_obj_add_flag(container, LV_OBJ_FLAG_GESTURE_BUBBLE)

        let x0 = (Int32(WatchScreen.width) - Switcher.thumbW) / 2
        left = slot(x0 - Switcher.thumbW - Switcher.gap, 1)
        center = slot(x0, 2)
        right = slot(x0 + Switcher.thumbW + Switcher.gap, 3)
        lv_obj_set_style_border_width(center, 3, partMain)
        lv_obj_set_style_border_color(center, lv_color_white(), partMain)
        lv_obj_set_style_border_post(center, true, partMain)

        name = lv_label_create(container)!
        lv_obj_set_style_text_font(name, wf_builtin_font(28), partMain)
        lv_obj_set_style_text_color(name, lv_color_white(), partMain)
        lv_obj_align(name, LV_ALIGN_TOP_MID, 0, Switcher.topY + Switcher.thumbH + 18)

        dots = lv_label_create(container)!
        lv_obj_set_style_text_font(dots, wf_builtin_font(20), partMain)
        lv_obj_set_style_text_color(dots, lv_color_hex(0x9A9A9A), partMain)
        lv_obj_align(dots, LV_ALIGN_TOP_MID, 0, Switcher.topY + Switcher.thumbH + 62)

        let hint = lv_label_create(container)!
        lv_obj_set_style_text_font(hint, wf_builtin_font(20), partMain)
        lv_obj_set_style_text_color(hint, lv_color_hex(0x707070), partMain)
        lvSetText(hint, "Tryk for at vælge")
        lv_obj_align(hint, LV_ALIGN_BOTTOM_MID, 0, -36)
        refresh()
    }

    /// A thumbnail frame; `tag` says which (1 left, 2 center, 3 right) when tapped
    private func slot(_ x: Int32, _ tag: Int) -> LVObj {
        let frame = lvPlainObject(container)
        lv_obj_set_size(frame, Switcher.thumbW, Switcher.thumbH)
        lv_obj_set_pos(frame, x, Switcher.topY)
        lv_obj_set_style_bg_color(frame, lv_color_hex(0x262626), partMain)
        lv_obj_set_style_bg_opa(frame, 255, partMain)
        lv_obj_add_flag(frame, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_add_flag(frame, LV_OBJ_FLAG_GESTURE_BUBBLE)
        lv_obj_add_event_cb(frame, { _ in Switcher.pressed() }, LV_EVENT_PRESSED, nil)
        lv_obj_add_event_cb(frame, { e in
            // Only a real tap: a short swipe (under LVGL's gesture distance) is a click too
            guard Switcher.wasTap() else { return }
            carousel?.switcherTapped(Int(bitPattern: lv_event_get_user_data(e)))
        }, LV_EVENT_CLICKED, UnsafeMutableRawPointer(bitPattern: tag))
        let image = lv_image_create(frame)!
        lv_obj_add_flag(image, LV_OBJ_FLAG_GESTURE_BUBBLE)
        // The decoder presents the quarter-size picture at twice its size (StoreImageDecoder)
        let label = lv_label_create(frame)!
        lv_obj_set_style_text_font(label, wf_builtin_font(20), partMain)
        lv_obj_set_style_text_color(label, lv_color_hex(0x9A9A9A), partMain)
        lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, partMain)
        lv_obj_center(label)
        return frame
    }

    func remove() {
        lv_obj_delete(container)
    }

    // Tap detection: where and when the finger went down
    nonisolated(unsafe) private static var pressPoint = lv_point_t()
    nonisolated(unsafe) private static var pressTick: UInt32 = 0

    static func pressed() {
        lv_indev_get_point(lv_indev_active(), &pressPoint)
        pressTick = lv_tick_get()
    }

    /// The finger moved less than 15 px and lifted within half a second
    static func wasTap() -> Bool {
        var p = lv_point_t()
        lv_indev_get_point(lv_indev_active(), &p)
        let dx = Int(p.x) - Int(pressPoint.x), dy = Int(p.y) - Int(pressPoint.y)
        return dx * dx + dy * dy < 15 * 15 && lv_tick_elaps(pressTick) < 500
    }

    private func show(_ face: WatchFace?, in frame: LVObj) {
        guard let face else {
            lv_obj_add_flag(frame, LV_OBJ_FLAG_HIDDEN)
            return
        }
        lv_obj_remove_flag(frame, LV_OBJ_FLAG_HIDDEN)
        let image = lv_obj_get_child(frame, 0)!
        let label = lv_obj_get_child(frame, 1)!
        let path = RenderedFace.thumbnailPath(face)
        if fileExists(path) {
            ("S:" + path).withCString { lv_image_set_src(image, $0) }
            lv_obj_remove_flag(image, LV_OBJ_FLAG_HIDDEN)
            lv_obj_add_flag(label, LV_OBJ_FLAG_HIDDEN)
        } else {
            // Not drawn yet (the baker is on it)
            lv_obj_add_flag(image, LV_OBJ_FLAG_HIDDEN)
            lv_obj_remove_flag(label, LV_OBJ_FLAG_HIDDEN)
            lvSetText(label, face.name + "\n...")
        }
    }

    func refresh() {
        let n = faces.count
        show(n > 1 ? faces[(index + n - 1) % n] : nil, in: left)
        show(faces[index], in: center)
        show(n > 2 ? faces[(index + 1) % n] : nil, in: right)
        lvSetText(name, faces[index].name)
        lvSetText(dots, "\(index + 1) / \(n)")
    }

    func onGesture(_ dir: lv_dir_t) {
        let n = faces.count
        if dir == LV_DIR_LEFT && n > 1 {
            index = (index + 1) % n
            refresh()
        } else if dir == LV_DIR_RIGHT && n > 1 {
            index = (index + n - 1) % n
            refresh()
        } else if dir == LV_DIR_TOP {
            lv_async_call({ _ in carousel?.closeSwitcher() }, nil) // back to the face it came from
        }
    }

    /// 1 left, 2 center, 3 right
    func tapped(_ tag: Int) {
        let n = faces.count
        switch tag {
        case 1: index = (index + n - 1) % n; refresh()
        case 3: index = (index + 1) % n; refresh()
        default:
            chosen = index
            // Not from inside the click event: closing deletes the object that was clicked
            lv_async_call({ _ in carousel?.closeSwitcherChoosing() }, nil)
        }
    }

    var chosen: Int?
}

extension Carousel {
    fileprivate func closeSwitcherChoosing() {
        closeSwitcher(choosing: switcherChoice)
    }
}

nonisolated(unsafe) private var carousel: Carousel?
nonisolated(unsafe) private var homeHandler: (@convention(c) () -> Void)?
nonisolated(unsafe) private var refreshStarted: UInt32 = 0
nonisolated(unsafe) private var refreshAreas: UInt32 = 0
nonisolated(unsafe) private var refreshPixels: UInt32 = 0
nonisolated(unsafe) private var lastSlowLog: UInt32 = 0

/// One function for adding and removing (a closure literal per call would be a different function each time)
private let refreshCallback: lv_event_cb_t = { e in onRefresh(e) }

/// Display refresh start/end while the faces show: logs slow frames (at most every 2 s)
private func onRefresh(_ e: OpaquePointer?) {
    if lv_event_get_code(e) == LV_EVENT_REFR_START {
        refreshStarted = lv_tick_get()
        let disp = lv_display_get_default()
        refreshAreas = wf_display_invalid_areas(disp)
        refreshPixels = wf_display_invalid_pixels(disp)
        StoreImageDecoder.readMicros = 0
        StoreImageDecoder.rowsRead = 0
        return
    }
    let took = lv_tick_elaps(refreshStarted)
    carousel?.noteFrame(took)
    if took > slowFrameMs && lv_tick_elaps(lastSlowLog) > 2000 {
        lastSlowLog = lv_tick_get()
        print("watch_faces: slow frame, \(took) ms: \(refreshAreas) areas, \(refreshPixels / 1000)k px, reading " +
              "\(StoreImageDecoder.readMicros / 1000) ms (\(StoreImageDecoder.rowsRead) rows); " +
              (carousel?.describe ?? ""))
    }
}

@_cdecl("watch_faces_show")
public func watch_faces_show() {
    if carousel != nil { watch_faces_hide() }
    StoreImageDecoder.register()
    let c = Carousel()
    carousel = c
    lv_screen_load(c.screen)
}

@_cdecl("watch_faces_hide")
public func watch_faces_hide() {
    carousel?.stop()
    carousel = nil
    StoreImageDecoder.release() // the open file and its rows (~7 KB) while other apps run
}

@_cdecl("watch_faces_set_battery_source")
public func watch_faces_set_battery_source(_ source: (@convention(c) () -> Int32)?) {
    batterySource = source
}

@_cdecl("watch_faces_set_home_handler")
public func watch_faces_set_home_handler(_ handler: (@convention(c) () -> Void)?) {
    homeHandler = handler
}
