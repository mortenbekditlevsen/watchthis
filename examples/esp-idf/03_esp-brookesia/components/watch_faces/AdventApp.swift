// Julekalender (brookesia_app_advent): 24 doors in a 4 x 6 grid, numbers mixed up as on a paper calendar. Tapping a
// door that may be opened shows it big; it wiggles, swings open on its hinge with glitter streaming out, and the
// day's picture (WatchFaceKit's AdventScene) is behind it. "Luk lågen" swings it shut again, to open it once more;
// "Låger" (or a swipe right, or the power key) goes back to the doors. No home indicator: the app has no system
// navigation gestures.
// From 1 to 24 December the app opens on today's door if it's still closed. Open doors show a little of their
// picture in the grid. Which doors are open is kept in /store/advent/state (AdventState).
//
// Testing outside December: a long press on the title steps through a pretend date (1 to 24 December, 26 December,
// then the real date again; hold to keep stepping). The pretend calendar is kept in memory only.

private let stateDir = "/store/advent"
private let statePath = stateDir + "/state"

private enum Look {
    static let background = FaceColor(rgb: 0x0B1430)
    static let gold = FaceColor(rgb: 0xF2C14E)
    static let cream = FaceColor(rgb: 0xFFF3D6)
    static let doorColors = [FaceColor(rgb: 0xA3162B), FaceColor(rgb: 0x1E5A34), FaceColor(rgb: 0xEFE2C4)]

    static func doorColor(_ door: Int) -> FaceColor {
        door == 24 ? FaceColor(rgb: 0xB8862B) : doorColors[(door * 7) % 3]
    }

    static func numberColor(_ door: Int) -> FaceColor {
        doorColor(door).rgb == doorColors[2].rgb ? FaceColor(rgb: 0xA3162B) : gold
    }
}

// The grid: 4 x 6 doors under the title
private let columns = 4
private let cellW: Int32 = 88
private let cellH: Int32 = 60
private let gapX: Int32 = 8
private let gapY: Int32 = 6
private let gridTop: Int32 = 80
private let gridLeft: Int32 = (Int32(WatchScreen.width) - 4 * cellW - 3 * gapX) / 2

// The open door page: the picture in a gold frame, the date and title under it
private let sceneScale: Float = 3.0
private let sceneW = Int32(AdventScene.width * sceneScale)
private let sceneH = Int32(AdventScene.height * sceneScale)
private let sceneX = (Int32(WatchScreen.width) - sceneW) / 2
private let sceneY: Int32 = 22

/// Glitter redraw: the screen in tiles; only tiles with glitter in them (now or last frame) are redrawn
private let tileW: Int32 = 41
private let tileH: Int32 = 42
private let tileColumns = 10
private let tileRows = 12

private enum Phase {
    /// The door is shut; tap to open
    case closed
    /// Shut, opening by itself in a moment (today's door when the app starts)
    case waiting
    case wiggling
    case opening
    case open
    case closing
}

private final class AdventUI {
    let screen: LVObj
    var state: AdventState
    var seasonStarted = false
    /// The pretend date (index into `testDates`), nil = the real one
    var testIndex: Int?
    var realState: AdventState?

    // Grid
    var gridPage: LVObj!
    var titleLabel: LVObj!
    var statusLabel: LVObj!
    var cells: [LVObj] = []
    var numberLabels: [LVObj] = []
    var toast: LVObj?
    var toastTimer: OpaquePointer?
    var gridTimer: OpaquePointer?
    var shakeCell: Int?
    var shakeStart: UInt32 = 0

    // Door page
    var doorPage: LVObj?
    var sceneObj: LVObj?
    var overlay: LVObj?
    var doorNumber: LVObj?
    var dateLabel: LVObj?
    var closeButton: LVObj?
    var door = 0
    var phase = Phase.closed
    var angle: Float = 0
    var phaseTime: Float = 0
    /// How long `.waiting` lasts
    var waitTime: Float = 0
    /// Frames during the swing (logged: how smooth it was)
    var swingFrames = 0
    var sparkles = Sparkles(seed: 1)
    var sprinkleTime: Float = 0
    var animTimer: OpaquePointer?
    var lastTick: UInt32 = 0
    var lastDoorArea: lv_area_t?
    var lastTiles = [UInt16](repeating: 0, count: tileRows)

    init(screen: LVObj) {
        self.screen = screen
        state = AdventState(season: 0)
        loadState()
        buildGrid()
        refreshGrid()
        let now = self.now()
        if let today = AdventCalendar.today(at: now), !state.isOpen(today) {
            showDoor(today, autoOpen: true, delay: 0.8)
        }
    }

    // MARK: Date and state

    static let testDates: [Int] = Array(1...24) + [26]

    func now() -> WallTime {
        if let testIndex {
            let day = AdventUI.testDates[testIndex]
            let year = max(2026, currentWallTime().year)
            return WallTime(year: year, month: 12, day: day, weekday: AdventCalendar.weekday(year: year, month: 12, day: day),
                            hour: 18, minute: 0, second: 0)
        }
        return currentWallTime()
    }

    func loadState() {
        let now = currentWallTime()
        let season = AdventCalendar.season(at: now)
        if let bytes = readFile(statePath, maxSize: 16), let saved = AdventState(decoding: bytes), saved.season == season {
            state = saved
            seasonStarted = true
        } else {
            state = AdventState(season: season)
            seasonStarted = false
            // December: this season's calendar has begun (after Christmas it stays open until next December)
            if now.isValid && now.month == 12 {
                seasonStarted = true
                save()
            }
        }
    }

    func save() {
        guard testIndex == nil else { return }
        _ = stateDir.withCString { mkdir($0, 0o775) }
        if !writeFile(statePath, state.encoded()) {
            print("advent: could not save")
        }
    }

    func availability(_ door: Int) -> AdventAvailability {
        AdventCalendar.availability(door: door, at: now(), seasonStarted: seasonStarted || testIndex != nil)
    }

    /// Long press on the title: the next pretend date
    func stepTestDate() {
        closeDoorPage()
        if testIndex == nil {
            realState = state
            state = AdventState(season: now().year)
            testIndex = 0
        } else if let i = testIndex, i + 1 < AdventUI.testDates.count {
            testIndex = i + 1
        } else {
            testIndex = nil
            if let realState { state = realState }
            realState = nil
        }
        refreshGrid()
    }

    // MARK: Grid

    func buildGrid() {
        lv_obj_set_style_bg_color(screen, lvColor(Look.background), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)

        let page = lvPlainObject(screen)
        lv_obj_set_size(page, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_add_flag(page, LV_OBJ_FLAG_EVENT_BUBBLE)
        lv_obj_add_flag(page, LV_OBJ_FLAG_GESTURE_BUBBLE)
        gridPage = page
        // A little snow in the background
        lv_obj_add_event_cb(page, { e in adventUI?.drawSnow(e) }, LV_EVENT_DRAW_MAIN, nil)

        let title = lv_label_create(page)!
        lv_obj_set_style_text_font(title, wf_builtin_font(30), partMain)
        lv_obj_set_style_text_color(title, lvColor(Look.gold), partMain)
        lvSetText(title, "Julekalender")
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 10)
        lv_obj_add_flag(title, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_set_ext_click_area(title, 12)
        for code in [LV_EVENT_LONG_PRESSED, LV_EVENT_LONG_PRESSED_REPEAT] {
            lv_obj_add_event_cb(title, { _ in adventUI?.stepTestDate() }, code, nil)
        }
        titleLabel = title

        let status = lv_label_create(page)!
        lv_obj_set_style_text_font(status, wf_builtin_font(16), partMain)
        lv_obj_set_style_text_color(status, lvColor(Look.cream), partMain)
        lv_obj_align(status, LV_ALIGN_TOP_MID, 0, 50)
        statusLabel = status

        for (i, door) in AdventCalendar.layout.enumerated() {
            let cell = lvPlainObject(page)
            lv_obj_set_size(cell, cellW, cellH)
            lv_obj_set_pos(cell, gridLeft + Int32(i % columns) * (cellW + gapX), gridTop + Int32(i / columns) * (cellH + gapY))
            lv_obj_set_style_radius(cell, 6, partMain)
            lv_obj_set_style_bg_color(cell, lvColor(Look.doorColor(door)), partMain)
            lv_obj_set_style_bg_opa(cell, 255, partMain)
            lv_obj_set_style_border_color(cell, lvColor(Look.gold), partMain)
            lv_obj_set_style_border_width(cell, 2, partMain)
            lv_obj_set_style_border_post(cell, true, partMain) // Over the little picture
            lv_obj_add_flag(cell, LV_OBJ_FLAG_CLICKABLE)
            lv_obj_add_flag(cell, LV_OBJ_FLAG_GESTURE_BUBBLE)
            let ud = UnsafeMutableRawPointer(bitPattern: i + 1)
            lv_obj_add_event_cb(cell, { e in
                adventUI?.tapped(Int(bitPattern: lv_event_get_user_data(e)) - 1)
            }, LV_EVENT_CLICKED, ud)
            lv_obj_add_event_cb(cell, { e in
                adventUI?.drawCell(e, Int(bitPattern: lv_event_get_user_data(e)) - 1)
            }, LV_EVENT_DRAW_MAIN, ud)

            let number = lv_label_create(cell)!
            numberLabels.append(number)
            lvSetText(number, "\(door)")
            cells.append(cell)
        }

        // The grid's timer: today's door glows, a tapped locked door shakes
        gridTimer = lv_timer_create({ _ in adventUI?.gridTick() }, 40, nil)
    }

    /// Doors and the status line for the (possibly pretend) date and what's open
    func refreshGrid() {
        let now = self.now()
        let today = AdventCalendar.today(at: now)
        for (i, door) in AdventCalendar.layout.enumerated() {
            let number = numberLabels[i]
            let cell = cells[i]
            if state.isOpen(door) {
                // A small number in the corner over the picture
                lv_obj_set_style_text_font(number, wf_builtin_font(14), partMain)
                lv_obj_set_style_text_color(number, lv_color_white(), partMain)
                lv_obj_set_style_bg_color(number, lv_color_black(), partMain)
                lv_obj_set_style_bg_opa(number, 150, partMain)
                lv_obj_set_style_radius(number, 4, partMain)
                lv_obj_set_style_pad_hor(number, 4, partMain)
                lv_obj_align(number, LV_ALIGN_BOTTOM_RIGHT, -3, -3)
            } else {
                lv_obj_set_style_text_font(number, wf_builtin_font(28), partMain)
                lv_obj_set_style_text_color(number, lvColor(Look.numberColor(door)), partMain)
                lv_obj_set_style_bg_opa(number, 0, partMain)
                lv_obj_set_style_pad_hor(number, 0, partMain)
                lv_obj_center(number)
            }
            let locked: Bool
            if case .available = availability(door) { locked = false } else { locked = true }
            lv_obj_set_style_opa(number, locked && !state.isOpen(door) ? 150 : 255, partMain)
            if door != today || state.isOpen(door) {
                lv_obj_set_style_border_color(cell, lvColor(Look.gold), partMain)
                lv_obj_set_style_border_width(cell, 2, partMain)
            }
            lv_obj_invalidate(cell)
        }
        lvSetText(statusLabel, statusText(now))
    }

    func statusText(_ t: WallTime) -> String {
        let prefix = testIndex != nil ? "Test: " : ""
        guard t.isValid else { return "Uret er ikke stillet endnu" }
        if t.month == 12 && t.day <= 24 {
            return prefix + FaceText.weekdays[t.weekday] + " \(t.day). december"
        }
        if t.month == 12 { return prefix + "Glædelig jul!" }
        if seasonStarted { return "Alle låger kan åbnes" }
        let days = AdventCalendar.daysUntilDecember(t)
        return days == 1 ? "1 dag til 1. december" : "\(days) dage til 1. december"
    }

    func tapped(_ index: Int) {
        guard index >= 0 && index < cells.count else { return }
        let door = AdventCalendar.layout[index]
        switch availability(door) {
        case .available:
            showDoor(door, autoOpen: !state.isOpen(door), delay: 0.15)
        case .locked(let daysLeft):
            shake(index)
            showToast(daysLeft == 1 ? "Låge \(door) åbner i morgen" : "Låge \(door) åbner om \(daysLeft) dage")
        case .unknownTime:
            shake(index)
            showToast("Uret er ikke stillet endnu")
        }
    }

    func shake(_ index: Int) {
        if let shakeCell { lv_obj_set_style_translate_x(cells[shakeCell], 0, partMain) }
        shakeCell = index
        shakeStart = lv_tick_get()
    }

    func gridTick() {
        guard doorPage == nil else { return }
        let t = lv_tick_get()
        if let index = shakeCell {
            let s = Float(t &- shakeStart) / 1000
            if s >= 0.35 {
                lv_obj_set_style_translate_x(cells[index], 0, partMain)
                shakeCell = nil
            } else {
                let dx = 7 * FaceMath.sin(s * 45) * (1 - s / 0.35)
                lv_obj_set_style_translate_x(cells[index], Int32(dx.rounded()), partMain)
            }
        }
        // Today's door, while closed, glows
        if let today = AdventCalendar.today(at: now()), !state.isOpen(today),
           let index = AdventCalendar.layout.firstIndex(of: today) {
            let k = 0.5 + 0.5 * FaceMath.sin(Float(t % 100_000) / 1000 * 3.5)
            let cell = cells[index]
            lv_obj_set_style_border_width(cell, 2 + Int32((k * 2).rounded()), partMain)
            lv_obj_set_style_border_color(cell, lv_color_mix(lv_color_white(), lvColor(Look.gold), UInt8(k * 200)),
                                          partMain)
        }
    }

    func showToast(_ text: String) {
        if toast == nil {
            let l = lv_label_create(gridPage)!
            lv_obj_set_style_text_font(l, wf_builtin_font(20), partMain)
            lv_obj_set_style_text_color(l, lv_color_white(), partMain)
            lv_obj_set_style_bg_color(l, lv_color_make(30, 30, 40), partMain)
            lv_obj_set_style_bg_opa(l, 235, partMain)
            lv_obj_set_style_radius(l, 20, partMain)
            lv_obj_set_style_pad_hor(l, 18, partMain)
            lv_obj_set_style_pad_ver(l, 10, partMain)
            lv_obj_set_style_border_color(l, lvColor(Look.gold), partMain)
            lv_obj_set_style_border_width(l, 1, partMain)
            toast = l
        }
        guard let toast else { return }
        lvSetText(toast, text)
        lv_obj_align(toast, LV_ALIGN_BOTTOM_MID, 0, -40)
        lv_obj_remove_flag(toast, LV_OBJ_FLAG_HIDDEN)
        if let toastTimer { lv_timer_delete(toastTimer) }
        toastTimer = lv_timer_create({ _ in adventUI?.hideToast() }, 2200, nil)
    }

    func hideToast() {
        if let toastTimer { lv_timer_delete(toastTimer) }
        toastTimer = nil
        if let toast { lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN) }
    }

    /// Snowflakes in the background (fixed places)
    func drawSnow(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var dsc = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&dsc)
        dsc.radius = wf_radius_circle()
        dsc.bg_color = lv_color_white()
        var r: UInt32 = 12345
        for _ in 0..<40 {
            r = r &* 1103515245 &+ 12345
            let x = Int32((r >> 8) % UInt32(WatchScreen.width))
            r = r &* 1103515245 &+ 12345
            let y = Int32((r >> 8) % UInt32(WatchScreen.height))
            let s = Int32((r >> 4) & 1) + 2
            dsc.bg_opa = UInt8(60 + ((r >> 12) & 63))
            var a = lv_area_t(x1: x, y1: y, x2: x + s - 1, y2: y + s - 1)
            lv_draw_rect(layer, &dsc, &a)
        }
    }

    /// An open door's cell: its picture (the middle of it), and the door itself folded back against the left side
    func drawCell(_ e: OpaquePointer?, _ index: Int) {
        guard index >= 0 && index < cells.count, let layer = lv_event_get_layer(e) else { return }
        let door = AdventCalendar.layout[index]
        guard state.isOpen(door) else { return }
        var a = lv_area_t()
        lv_obj_get_coords(cells[index], &a)
        let k = Float(cellW) / AdventScene.width
        var sink = LayerShapeSink(layer: layer, x0: a.x1, y0: a.y1 + (cellH - Int32(AdventScene.height * k)) / 2, scale: k)
        AdventScene.draw(door, into: &sink)
        // The open door, seen from the side
        let shade = AdventDoor.shade(Look.doorColor(door), angle: 1.2)
        wf_draw_triangle(layer, a.x1, a.y1 - 1, a.x1 + 9, a.y1 - 4, a.x1 + 9, a.y2 + 4, lvColor(shade), 255)
        wf_draw_triangle(layer, a.x1, a.y1 - 1, a.x1 + 9, a.y2 + 4, a.x1, a.y2 + 1, lvColor(shade), 255)
    }

    // MARK: Door page

    /// `autoOpen`: the door opens by itself after `delay` seconds; otherwise an open door shows open, a closed one
    /// waits for a tap
    func showDoor(_ door: Int, autoOpen: Bool, delay: Float = 0) {
        closeDoorPage()
        hideToast()
        self.door = door
        let isOpen = state.isOpen(door) && !autoOpen
        phase = isOpen ? .open : (autoOpen ? .waiting : .closed)
        angle = isOpen ? AdventDoor.openAngle : 0
        phaseTime = 0
        waitTime = delay
        sparkles = Sparkles(seed: lv_tick_get() | 1)
        lastDoorArea = nil
        lastTiles = [UInt16](repeating: 0, count: tileRows)

        let page = lvPlainObject(screen)
        lv_obj_set_size(page, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_color(page, lvColor(Look.background), partMain)
        lv_obj_set_style_bg_opa(page, 255, partMain)
        doorPage = page
        lv_obj_add_flag(gridPage, LV_OBJ_FLAG_HIDDEN)

        // The gold frame and the picture in it (tap: open the door, or more glitter)
        let frame = lvPlainObject(page)
        lv_obj_set_size(frame, sceneW + 10, sceneH + 10)
        lv_obj_set_pos(frame, sceneX - 5, sceneY - 5)
        lv_obj_set_style_bg_color(frame, lvColor(Look.gold), partMain)
        lv_obj_set_style_bg_opa(frame, 255, partMain)
        lv_obj_set_style_radius(frame, 6, partMain)
        let scene = lvPlainObject(page)
        lv_obj_set_size(scene, sceneW, sceneH)
        lv_obj_set_pos(scene, sceneX, sceneY)
        lv_obj_set_style_bg_color(scene, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(scene, 255, partMain)
        lv_obj_add_flag(scene, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_add_flag(scene, LV_OBJ_FLAG_GESTURE_BUBBLE)
        lv_obj_add_event_cb(scene, { e in adventUI?.drawScene(e) }, LV_EVENT_DRAW_MAIN, nil)
        lv_obj_add_event_cb(scene, { _ in adventUI?.sceneTapped() }, LV_EVENT_CLICKED, nil)
        sceneObj = scene

        let date = lv_label_create(page)!
        lv_obj_set_style_text_font(date, wf_builtin_font(18), partMain)
        lv_obj_set_style_text_color(date, lvColor(Look.cream), partMain)
        lvSetText(date, AdventCalendar.dateText(door))
        lv_obj_align(date, LV_ALIGN_TOP_MID, 0, sceneY + sceneH + 10)
        dateLabel = date

        // Back to the doors (left), close this one again (right, once it's open)
        let back = pillButton(page, "Låger") { _ in adventUI?.closeDoorPage() }
        lv_obj_align(back, LV_ALIGN_TOP_MID, -75, sceneY + sceneH + 42)
        let close = pillButton(page, "Luk lågen") { _ in adventUI?.startClosing() }
        lv_obj_align(close, LV_ALIGN_TOP_MID, 75, sceneY + sceneH + 42)
        closeButton = close
        // No system back gesture in this app (no home indicator): a swipe right goes back to the doors too
        lv_obj_add_event_cb(page, { _ in
            if lv_indev_get_gesture_dir(lv_indev_active()) == LV_DIR_RIGHT { adventUI?.closeDoorPage() }
        }, LV_EVENT_GESTURE, nil)

        // On top of it all: the door and the glitter (not clickable: taps go through to the picture)
        let overlay = lvPlainObject(page)
        lv_obj_set_size(overlay, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_add_event_cb(overlay, { e in adventUI?.drawOverlay(e) }, LV_EVENT_DRAW_MAIN, nil)
        self.overlay = overlay
        let number = lv_label_create(overlay)!
        lv_obj_set_style_text_font(number, wf_builtin_font(66), partMain)
        lv_obj_set_style_text_color(number, lvColor(Look.numberColor(door)), partMain)
        lvSetText(number, "\(door)")
        lv_obj_align(number, LV_ALIGN_TOP_MID, 0, sceneY + sceneH / 2 - 40)
        doorNumber = number

        updateDoorTexts()
        if phase == .waiting || isOpen {
            // An open door greets with a little glitter
            if isOpen { sprinkleTime = 0.6 }
            startTimer()
        }
    }

    func pillButton(_ parent: LVObj, _ text: String, action: lv_event_cb_t) -> LVObj {
        let button = lvPlainObject(parent)
        lv_obj_set_size(button, 140, 40)
        lv_obj_set_style_radius(button, 20, partMain)
        lv_obj_set_style_bg_color(button, lv_color_make(40, 44, 70), partMain)
        lv_obj_set_style_bg_opa(button, 255, partMain)
        lv_obj_set_style_bg_color(button, lv_color_make(90, 94, 120), partMain | lv_style_selector_t(LV_STATE_PRESSED.rawValue))
        lv_obj_set_style_border_color(button, lvColor(Look.gold), partMain)
        lv_obj_set_style_border_width(button, 1, partMain)
        lv_obj_add_flag(button, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_add_flag(button, LV_OBJ_FLAG_GESTURE_BUBBLE)
        lv_obj_set_ext_click_area(button, 8)
        let label = lv_label_create(button)!
        lv_obj_set_style_text_font(label, wf_builtin_font(18), partMain)
        lv_obj_set_style_text_color(label, lvColor(Look.cream), partMain)
        lvSetText(label, text)
        lv_obj_center(label)
        lv_obj_add_event_cb(button, action, LV_EVENT_CLICKED, nil)
        return button
    }

    /// Back from the door to the grid (returns false if the grid shows: the app closes)
    @discardableResult
    func closeDoorPage() -> Bool {
        guard let page = doorPage else { return false }
        stopTimer()
        // Often from inside one of the page's own events (its button, a swipe): gone right away, deleted after
        lv_obj_add_flag(page, LV_OBJ_FLAG_HIDDEN)
        lv_obj_delete_async(page)
        doorPage = nil
        sceneObj = nil
        overlay = nil
        doorNumber = nil
        dateLabel = nil
        closeButton = nil
        sparkles = Sparkles(seed: 1)
        lv_obj_remove_flag(gridPage, LV_OBJ_FLAG_HIDDEN)
        refreshGrid()
        return true
    }

    /// "Luk lågen" only on an open door; the door's number fades as it opens
    func updateDoorTexts() {
        guard let closeButton, let doorNumber else { return }
        if phase == .open {
            lv_obj_remove_flag(closeButton, LV_OBJ_FLAG_HIDDEN)
        } else {
            lv_obj_add_flag(closeButton, LV_OBJ_FLAG_HIDDEN)
        }
        // The number fades as the door turns away
        let opa = max(0, 1 - angle / 0.7)
        lv_obj_set_style_opa(doorNumber, UInt8(opa * 255), partMain)
        lv_obj_set_style_translate_x(doorNumber, Int32(-Float(sceneW) * (1 - FaceMath.cos(angle)) / 2), partMain)
    }

    func sceneTapped() {
        switch phase {
        case .closed:
            startOpening()
        case .open:
            sparkles.sprinkle(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), count: 14,
                              festive: door == 24)
            startTimer()
        default:
            break
        }
    }

    func startOpening() {
        phase = .wiggling
        phaseTime = 0
        startTimer()
    }

    func startClosing() {
        guard phase == .open else { return }
        phase = .closing
        phaseTime = 0
        state.setOpen(door, false)
        save()
        updateDoorTexts()
        startTimer()
    }

    func startTimer() {
        guard animTimer == nil else { return }
        lastTick = lv_tick_get()
        animTimer = lv_timer_create({ _ in adventUI?.tick() }, 20, nil)
    }

    func stopTimer() {
        if let animTimer { lv_timer_delete(animTimer) }
        animTimer = nil
    }

    static let wiggleTime: Float = 0.5
    static let swingTime: Float = 1.2
    static let closeTime: Float = 0.8

    func tick() {
        let t = lv_tick_get()
        // Clamped: after a slow frame, don't jump
        let dt = min(0.05, Float(t &- lastTick) / 1000)
        lastTick = t
        phaseTime += dt
        lv_display_trigger_activity(nil)
        let festive = door == 24
        let oldAngle = angle

        switch phase {
        case .waiting:
            if phaseTime >= waitTime {
                phase = .wiggling
                phaseTime = 0
            }
        case .wiggling:
            // A little jiggle, as if stuck, then it gives
            let s = FaceMath.sin(phaseTime * 2 * FaceMath.pi * 5)
            angle = 0.07 * s * s * (phaseTime / AdventUI.wiggleTime)
            if phaseTime >= AdventUI.wiggleTime {
                phase = .opening
                phaseTime = 0
                swingFrames = 0
                state.setOpen(door, true)
                save()
                let edge = AdventDoor.quad(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), angle: angle)
                sparkles.burst(x: edge[1].x, top: Float(sceneY), bottom: Float(sceneY + sceneH), count: festive ? 60 : 40,
                               festive: festive)
            }
        case .opening:
            angle = AdventDoor.openAngle * AdventDoor.ease(phaseTime / AdventUI.swingTime)
            swingFrames += 1
            if phaseTime < AdventUI.swingTime * 0.6 {
                let edge = AdventDoor.quad(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), angle: angle)
                sparkles.burst(x: edge[1].x, top: edge[1].y, bottom: edge[2].y, count: festive ? 5 : 3, festive: festive)
            }
            if phaseTime >= AdventUI.swingTime {
                angle = AdventDoor.openAngle
                phase = .open
                print("advent: door \(door) swung open in \(swingFrames) frames (\(Int(Float(swingFrames) / phaseTime)) fps)")
                sprinkleTime = festive ? 6 : 2.5
            }
            updateDoorTexts()
        case .closing:
            angle = AdventDoor.openAngle * (1 - AdventDoor.ease(phaseTime / AdventUI.closeTime))
            if phaseTime >= AdventUI.closeTime {
                angle = 0
                phase = .closed
            }
            updateDoorTexts()
        case .open, .closed:
            break
        }

        if sprinkleTime > 0 {
            sprinkleTime -= dt
            // A few new twinkles every frame over the picture
            if Int(sprinkleTime * 50) % 3 == 0 {
                sparkles.sprinkle(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH),
                                  count: festive ? 3 : 1, festive: festive)
            }
        }
        sparkles.step(dt)

        if angle != oldAngle { invalidateDoor() }
        invalidateSparkles()

        if (phase == .open || phase == .closed) && sparkles.isEmpty && sprinkleTime <= 0 {
            stopTimer()
            invalidateDoor()
            updateDoorTexts()
        }
    }

    // MARK: Drawing the door page

    func drawScene(_ e: OpaquePointer?) {
        // Behind a shut (or only jiggling) door there's nothing to see
        let visible = phase == .open || (phase == .opening || phase == .closing) && angle > 0.01
        guard visible, let layer = lv_event_get_layer(e), let sceneObj else { return }
        var a = lv_area_t()
        lv_obj_get_coords(sceneObj, &a)
        // While the door's front still covers part of the picture, only what's right of its edge is drawn: a frame
        // of the swing then only draws the strip it uncovered (the rest under the door is drawn over anyway)
        let saved = layer.pointee._clip_area
        var edge: Int32?
        if phase != .open && !AdventDoor.showsBack(angle) {
            let q = AdventDoor.quad(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), angle: angle)
            edge = Int32(q[1].x.rounded(.down))
            layer.pointee._clip_area.x1 = max(saved.x1, edge! - 2)
            guard layer.pointee._clip_area.x1 <= layer.pointee._clip_area.x2 else {
                layer.pointee._clip_area = saved
                return
            }
        }
        var sink = LayerShapeSink(layer: layer, x0: a.x1, y0: a.y1, scale: sceneScale)
        AdventScene.draw(door, into: &sink)
        // The door's shadow on the picture, just right of its edge (stronger the more it still faces us)
        if let edge {
            var dsc = lv_draw_rect_dsc_t()
            lv_draw_rect_dsc_init(&dsc)
            dsc.bg_color = lv_color_black()
            let strength = FaceMath.cos(angle)
            for (i, opa) in [Float(110), 60, 25].enumerated() {
                dsc.bg_opa = UInt8(opa * strength)
                var r = lv_area_t(x1: edge + Int32(i) * 7, y1: a.y1, x2: edge + Int32(i) * 7 + 6, y2: a.y2)
                lv_draw_rect(layer, &dsc, &r)
            }
        }
        layer.pointee._clip_area = saved
    }

    func drawOverlay(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        drawDoor(layer)
        drawSparkles(layer)
    }

    func drawDoor(_ layer: UnsafeMutablePointer<lv_layer_t>) {
        let q = AdventDoor.quad(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), angle: angle)
        // The front in the door's colour; the back is plain card
        let back = AdventDoor.showsBack(angle)
        let base = back ? FaceColor(rgb: 0xD9CCB0) : Look.doorColor(door)
        let body = lvColor(AdventDoor.shade(base, angle: angle))
        func p(_ u: Float, _ v: Float) -> (Int32, Int32) {
            // Bilinear over the quad: u across (0 = hinge), v down
            let top = (q[0].x + (q[1].x - q[0].x) * u, q[0].y + (q[1].y - q[0].y) * u)
            let bottom = (q[3].x + (q[2].x - q[3].x) * u, q[3].y + (q[2].y - q[3].y) * u)
            return (Int32((top.0 + (bottom.0 - top.0) * v).rounded()), Int32((top.1 + (bottom.1 - top.1) * v).rounded()))
        }
        // A rectangle (a plain fill: fast) and thin wedges above and below it for the perspective (LVGL's triangles
        // are slow over big areas)
        let (ax, ay) = p(0, 0), (bx, by) = p(1, 0), (cx, cy) = p(1, 1), (dx, dy) = p(0, 1)
        var fill = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&fill)
        fill.bg_color = body
        var rect = lv_area_t(x1: min(ax, bx), y1: ay, x2: max(ax, bx), y2: dy)
        lv_draw_rect(layer, &fill, &rect)
        if by < ay - 1 {
            wf_draw_triangle(layer, ax, ay, bx, ay, bx, by, body, 255)
            wf_draw_triangle(layer, dx, dy, cx, dy, cx, cy, body, 255)
        }

        func line(_ a: (Int32, Int32), _ b: (Int32, Int32), _ w: Int32, _ c: lv_color_t, _ opa: UInt8 = 255) {
            var d = lv_draw_line_dsc_t()
            lv_draw_line_dsc_init(&d)
            d.p1 = wf_point(a.0, a.1)
            d.p2 = wf_point(b.0, b.1)
            d.width = w
            d.color = c
            d.opa = opa
            d.round_start = 1
            d.round_end = 1
            lv_draw_line(layer, &d)
        }
        // Two inset panels and the gold edge
        let dark = lvColor(AdventDoor.shade(FaceColor(r: base.r / 2, g: base.g / 2, b: base.b / 2), angle: angle))
        for (v0, v1) in [(Float(0.07), Float(0.47)), (Float(0.53), Float(0.93))] where !back {
            let corners = [p(0.12, v0), p(0.88, v0), p(0.88, v1), p(0.12, v1)]
            for i in 0..<4 { line(corners[i], corners[(i + 1) % 4], 3, dark) }
        }
        let gold = lvColor(AdventDoor.shade(Look.gold, angle: angle))
        let corners = [p(0, 0), p(1, 0), p(1, 1), p(0, 1)]
        for i in 0..<4 { line(corners[i], corners[(i + 1) % 4], 3, gold) }
        guard !back else { return }
        // The knob
        let (kx, ky) = p(0.9, 0.5)
        var knob = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&knob)
        knob.radius = wf_radius_circle()
        knob.bg_color = gold
        var ka = lv_area_t(x1: kx - 6, y1: ky - 6, x2: kx + 6, y2: ky + 6)
        lv_draw_rect(layer, &knob, &ka)
        // Light through the gap while it's stuck
        if phase == .wiggling {
            let glow = UInt8(min(255, phaseTime / AdventUI.wiggleTime * 255))
            line(p(1, 0.02), p(1, 0.98), 4, lvColor(FaceColor(rgb: 0xFFF2A8)), glow)
        }
    }

    func drawSparkles(_ layer: UnsafeMutablePointer<lv_layer_t>) {
        var dot = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&dot)
        dot.radius = wf_radius_circle()
        for s in sparkles.particles {
            let opa = s.opacity
            guard opa > 8 else { continue }
            let x = Int32(s.x), y = Int32(s.y)
            if s.isStar {
                // A four-pointed glint: two thin lines and a bright middle
                let r = Int32(s.size)
                var d = lv_draw_line_dsc_t()
                lv_draw_line_dsc_init(&d)
                d.width = 2
                d.color = lvColor(s.color)
                d.opa = opa
                d.round_start = 1
                d.round_end = 1
                d.p1 = wf_point(x - r, y)
                d.p2 = wf_point(x + r, y)
                lv_draw_line(layer, &d)
                d.p1 = wf_point(x, y - r)
                d.p2 = wf_point(x, y + r)
                lv_draw_line(layer, &d)
                dot.bg_color = lv_color_white()
                dot.bg_opa = opa
                var a = lv_area_t(x1: x - 2, y1: y - 2, x2: x + 2, y2: y + 2)
                lv_draw_rect(layer, &dot, &a)
            } else {
                let r = Int32(s.size / 2)
                dot.bg_color = lvColor(s.color)
                dot.bg_opa = opa
                var a = lv_area_t(x1: x - r, y1: y - r, x2: x + r, y2: y + r)
                lv_draw_rect(layer, &dot, &a)
            }
        }
    }

    // MARK: Redrawing only what changed

    func doorArea() -> lv_area_t {
        let q = AdventDoor.quad(x: Float(sceneX), y: Float(sceneY), w: Float(sceneW), h: Float(sceneH), angle: angle)
        let left = min(Float(sceneX), q[1].x), right = max(Float(sceneX), q[1].x)
        let top = min(q[0].y, q[1].y), bottom = max(q[3].y, q[2].y)
        // With room for the knob and the lines' width
        return lv_area_t(x1: Int32(left.rounded(.down)) - 8, y1: Int32(top.rounded(.down)) - 4,
                         x2: Int32(right.rounded(.up)) + 24, y2: Int32(bottom.rounded(.up)) + 4) // + the shadow
    }

    func invalidateDoor() {
        guard let overlay else { return }
        var area = doorArea()
        if let last = lastDoorArea {
            area = lv_area_t(x1: min(area.x1, last.x1), y1: min(area.y1, last.y1),
                             x2: max(area.x2, last.x2), y2: max(area.y2, last.y2))
        }
        lastDoorArea = doorArea()
        lv_obj_invalidate_area(overlay, &area)
        if let doorNumber { lv_obj_invalidate(doorNumber) }
    }

    /// Mark the tiles with glitter in them (now and last frame) for redrawing, a run of tiles per row at a time
    func invalidateSparkles() {
        guard let overlay else { return }
        var tiles = [UInt16](repeating: 0, count: tileRows)
        for s in sparkles.particles {
            let r = s.size + 2
            let c0 = max(0, min(tileColumns - 1, Int((s.x - r) / Float(tileW))))
            let c1 = max(0, min(tileColumns - 1, Int((s.x + r) / Float(tileW))))
            let r0 = max(0, min(tileRows - 1, Int((s.y - r) / Float(tileH))))
            let r1 = max(0, min(tileRows - 1, Int((s.y + r) / Float(tileH))))
            guard s.x + r >= 0, s.y + r >= 0 else { continue }
            for row in r0...r1 {
                for col in c0...c1 { tiles[row] |= 1 << UInt16(col) }
            }
        }
        for row in 0..<tileRows {
            let bits = tiles[row] | lastTiles[row]
            var col = 0
            while col < tileColumns {
                guard bits & (1 << UInt16(col)) != 0 else {
                    col += 1
                    continue
                }
                var end = col
                while end + 1 < tileColumns && bits & (1 << UInt16(end + 1)) != 0 { end += 1 }
                var area = lv_area_t(x1: Int32(col) * tileW, y1: Int32(row) * tileH,
                                     x2: min(Int32(WatchScreen.width), Int32(end + 1) * tileW) - 1,
                                     y2: min(Int32(WatchScreen.height), Int32(row + 1) * tileH) - 1)
                lv_obj_invalidate_area(overlay, &area)
                col = end + 1
            }
        }
        lastTiles = tiles
    }

    // MARK: Leaving

    func stop() {
        stopTimer()
        if let gridTimer { lv_timer_delete(gridTimer) }
        gridTimer = nil
        if let toastTimer { lv_timer_delete(toastTimer) }
        toastTimer = nil
    }
}

/// Draws a picture's shapes as they're made
/// Shapes outside the area being redrawn are skipped: LVGL would allocate (and queue) a draw task for each anyway,
/// and a picture has up to ~300 shapes, drawn again for every strip of every frame that touches it.
private struct LayerShapeSink: IconShapeSink {
    let layer: UnsafeMutablePointer<lv_layer_t>
    let x0: Int32
    let y0: Int32
    let scale: Float
    /// The redrawn area in picture units (with a little margin for anti-aliasing and rounding)
    let minX: Float, minY: Float, maxX: Float, maxY: Float

    init(layer: UnsafeMutablePointer<lv_layer_t>, x0: Int32, y0: Int32, scale: Float) {
        self.layer = layer
        self.x0 = x0
        self.y0 = y0
        self.scale = scale
        let clip = layer.pointee._clip_area
        minX = Float(clip.x1 - x0 - 2) / scale
        minY = Float(clip.y1 - y0 - 2) / scale
        maxX = Float(clip.x2 - x0 + 2) / scale
        maxY = Float(clip.y2 - y0 + 2) / scale
    }

    mutating func add(_ shape: IconShape) {
        let (x1, y1, x2, y2): (Float, Float, Float, Float)
        switch shape {
        case .circle(let cx, let cy, let r, _):
            (x1, y1, x2, y2) = (cx - r, cy - r, cx + r, cy + r)
        case .roundRect(let x, let y, let w, let h, _, _):
            (x1, y1, x2, y2) = (x, y, x + w, y + h)
        case .line(let ax, let ay, let bx, let by, let width, _):
            let m = width / 2
            (x1, y1, x2, y2) = (min(ax, bx) - m, min(ay, by) - m, max(ax, bx) + m, max(ay, by) + m)
        case .triangle(let ax, let ay, let bx, let by, let cx, let cy, _):
            (x1, y1, x2, y2) = (min(ax, bx, cx), min(ay, by, cy), max(ax, bx, cx), max(ay, by, cy))
        }
        guard x2 >= minX && x1 <= maxX && y2 >= minY && y1 <= maxY else { return }
        WeatherIconDrawing.draw(shape, layer: layer, x0: x0, y0: y0, scale: scale)
    }
}

nonisolated(unsafe) private var adventUI: AdventUI?

@_cdecl("advent_app_show")
public func advent_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    adventUI = AdventUI(screen: screen)
}

/// The system's back gesture: from a door to the grid. False when the grid shows (the app closes).
@_cdecl("advent_app_back")
public func advent_app_back() -> Bool {
    adventUI?.closeDoorPage() ?? false
}

@_cdecl("advent_app_hide")
public func advent_app_hide() {
    // The objects are deleted by the app framework after this; their callbacks go through `adventUI`
    adventUI?.stop()
    adventUI = nil
}
