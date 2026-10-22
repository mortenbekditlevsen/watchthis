// Timer: pick a preset (2, 3, 5, 10 min) or one of the last four the user made, or make a new one with three
// rollers (hours, minutes, seconds). The countdown keeps going when the app closes or the watch sleeps; when it's
// done the watch wakes up (power manager, watch_tools_wake_at_us), the Timer app opens and the alarm sounds until
// stopped (or for a minute).

private let recentPath = "/store/timers.bin"

nonisolated(unsafe) private var countdown = Countdown()
nonisolated(unsafe) private var choices = TimerChoices()
nonisolated(unsafe) private var openTimerApp: (@convention(c) () -> Void)?
nonisolated(unsafe) private var ui: TimerUI?
/// When the power manager must wake the watch (esp_timer microseconds), 0 = never; atomic (power task reads it)
nonisolated(unsafe) private var wakeAt: Int64 = 0

/// After every change to `countdown`: tells the power manager when to wake up
private func countdownChanged() {
    wt_atomic_store64(&wakeAt, countdown.wakeAt ?? 0)
}

/// Every 250 ms, whether the app is open or not (also right after waking up)
private func backgroundTick() {
    switch countdown.tick(at: now()) {
    case .startRinging:
        countdownChanged()
        music_player_alarm_start()
        if ui == nil {
            openTimerApp?()
        }
    case .stopRinging:
        music_player_alarm_stop()
    case .none:
        break
    }
    ui?.tick()
}

private func startTimer(seconds: Int) {
    countdown.start(seconds: seconds, at: now())
    countdownChanged()
}

private final class TimerUI {
    enum View: Equatable {
        case choices, picker, running, ringing
    }

    let screen: LVObj
    var view: View?
    var showPicker = false

    // Running view
    var arc: LVObj?
    var remaining: LVObj?
    var pauseLabel: LVObj?
    // Picker view
    var rollers: [LVObj] = []
    var pickerStart: LVObj?
    // Ringing view
    var flashOn = false
    var lastFlash: UInt32 = 0

    init(screen: LVObj) {
        self.screen = screen
        tick()
    }

    var wantedView: View {
        switch countdown.state {
        case .ringing: .ringing
        case .running, .paused: .running
        case .idle: showPicker ? .picker : .choices
        }
    }

    func tick() {
        let wanted = wantedView
        if wanted != view {
            build(wanted)
        }
        switch wanted {
        case .running:
            let t = now()
            if let remaining { setText(remaining, TimeText.countdown(countdown.remaining(at: t))) }
            if let arc { lv_arc_set_value(arc, Int32(1000 - countdown.progress(at: t) * 1000)) }
        case .ringing:
            if lv_tick_elaps(lastFlash) >= 500 {
                lastFlash = lv_tick_get()
                flashOn.toggle()
                lv_obj_set_style_bg_color(screen, flashOn ? lv_color_hex(Palette.orange) : lv_color_black(), partMain)
            }
        case .choices, .picker:
            break
        }
    }

    private func build(_ view: View) {
        self.view = view
        prepareScreen(screen)
        arc = nil
        remaining = nil
        pauseLabel = nil
        rollers = []
        pickerStart = nil
        // Idle sleep is fine while counting down (the timer wakes the watch); otherwise stay on as other apps do
        if view == .running {
            lv_obj_add_flag(screen, LV_OBJ_FLAG_USER_1)
        } else {
            lv_obj_remove_flag(screen, LV_OBJ_FLAG_USER_1)
        }
        switch view {
        case .choices: buildChoices()
        case .picker: buildPicker()
        case .running: buildRunning()
        case .ringing: buildRinging()
        }
    }

    // MARK: Choices

    private func buildChoices() {
        let title = label(screen, "Timer", size: 28, color: Palette.dimText)
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 30)

        let grid = lv_obj_create(screen)!
        lv_obj_remove_style_all(grid)
        lv_obj_set_size(grid, screenWidth, screenHeight - 80)
        lv_obj_align(grid, LV_ALIGN_BOTTOM_MID, 0, 0)
        lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP)
        lv_obj_set_flex_align(grid, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START)
        lv_obj_set_style_pad_left(grid, 25, partMain)
        lv_obj_set_style_pad_right(grid, 25, partMain)
        lv_obj_set_style_pad_bottom(grid, 30, partMain)
        lv_obj_set_style_pad_row(grid, 16, partMain)
        lv_obj_set_style_pad_column(grid, 16, partMain)
        lv_obj_set_scroll_dir(grid, LV_DIR_VER)
        lv_obj_set_scrollbar_mode(grid, LV_SCROLLBAR_MODE_OFF)

        let all = choices.all
        for (index, seconds) in all.enumerated() {
            let isPreset = index < TimerChoices.presets.count
            _ = button(grid, TimeText.duration(seconds: seconds), color: isPreset ? Palette.blue : Palette.grey,
                       width: 172, height: 84, size: seconds % 60 == 0 ? 28 : 20, tag: index) { e in
                let all = choices.all
                let index = eventTag(e)
                guard all.indices.contains(index) else { return }
                startTimer(seconds: all[index])
                ui?.tick()
            }
        }
        _ = button(grid, "+ Ny", color: Palette.orange, width: 172, height: 84) { _ in
            ui?.showPicker = true
            ui?.tick()
        }
    }

    // MARK: Picker

    private func buildPicker() {
        let title = label(screen, "Ny timer", size: 28, color: Palette.dimText)
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 30)

        let columns: [(max: Int, unit: String, initial: Int)] = [(23, "t", 0), (59, "min", 1), (59, "sek", 0)]
        for (i, column) in columns.enumerated() {
            let roller = lv_roller_create(screen)!
            let options = (0...column.max).map { "\($0)" }.joined(separator: "\n")
            options.withCString { lv_roller_set_options(roller, $0, LV_ROLLER_MODE_NORMAL) }
            lv_roller_set_visible_row_count(roller, 3)
            lv_roller_set_selected(roller, UInt32(column.initial), false)
            lv_obj_set_width(roller, 104)
            lv_obj_set_style_text_font(roller, wt_font(44), partMain)
            lv_obj_set_style_text_font(roller, wt_font(44), partSelected)
            lv_obj_set_style_bg_color(roller, lv_color_hex(0x161616), partMain)
            lv_obj_set_style_text_color(roller, lv_color_hex(0x707070), partMain)
            lv_obj_set_style_border_width(roller, 0, partMain)
            lv_obj_set_style_bg_color(roller, lv_color_hex(Palette.blue), partSelected)
            lv_obj_set_style_text_color(roller, lv_color_white(), partSelected)
            lv_obj_align(roller, LV_ALIGN_TOP_MID, Int32(i - 1) * 124, 100)
            lv_obj_add_event_cb(roller, { _ in ui?.updatePickerStart() }, LV_EVENT_VALUE_CHANGED, nil)
            rollers.append(roller)

            let unit = label(screen, column.unit, size: 20, color: Palette.dimText)
            lv_obj_align_to(unit, roller, LV_ALIGN_OUT_BOTTOM_MID, 0, 8)
        }

        let cancel = button(screen, "Annuller", color: Palette.grey, width: 160, height: 84) { _ in
            ui?.showPicker = false
            ui?.tick()
        }
        lv_obj_align(cancel.button, LV_ALIGN_BOTTOM_LEFT, 30, -40)
        let start = button(screen, "Start", color: Palette.green, width: 160, height: 84) { _ in
            guard let seconds = ui?.pickedSeconds, seconds > 0 else { return }
            choices.remember(seconds)
            writeFile(recentPath, choices.encoded)
            ui?.showPicker = false
            startTimer(seconds: seconds)
            ui?.tick()
        }
        lv_obj_align(start.button, LV_ALIGN_BOTTOM_RIGHT, -30, -40)
        pickerStart = start.button
        updatePickerStart()
    }

    var pickedSeconds: Int {
        guard rollers.count == 3 else { return 0 }
        let v = rollers.map { Int(lv_roller_get_selected($0)) }
        return v[0] * 3600 + v[1] * 60 + v[2]
    }

    func updatePickerStart() {
        if let pickerStart { setEnabled(pickerStart, pickedSeconds > 0) }
    }

    // MARK: Running

    private func buildRunning() {
        let arc = lv_arc_create(screen)!
        lv_obj_set_size(arc, 330, 330)
        lv_obj_align(arc, LV_ALIGN_TOP_MID, 0, 30)
        lv_arc_set_rotation(arc, 270)
        lv_arc_set_bg_angles(arc, 0, 360)
        lv_arc_set_range(arc, 0, 1000)
        lv_obj_remove_style(arc, nil, partKnob)
        lv_obj_remove_flag(arc, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_set_style_arc_width(arc, 14, partMain)
        lv_obj_set_style_arc_width(arc, 14, partIndicator)
        lv_obj_set_style_arc_color(arc, lv_color_hex(0x222222), partMain)
        lv_obj_set_style_arc_color(arc, lv_color_hex(Palette.orange), partIndicator)
        self.arc = arc

        let remaining = label(screen, "", size: 66)
        lv_obj_align_to(remaining, arc, LV_ALIGN_CENTER, 0, -10)
        self.remaining = remaining
        let of = label(screen, "af " + TimeText.duration(seconds: countdown.duration), size: 20, color: Palette.dimText)
        lv_obj_align_to(of, arc, LV_ALIGN_CENTER, 0, 50)

        let cancel = button(screen, "Annuller", color: Palette.grey, width: 160, height: 84) { _ in
            countdown.cancel()
            countdownChanged()
            ui?.tick()
        }
        lv_obj_align(cancel.button, LV_ALIGN_BOTTOM_LEFT, 30, -30)
        let isPaused = { if case .paused = countdown.state { true } else { false } }()
        let pause = button(screen, isPaused ? "Fortsæt" : "Pause", color: Palette.orange, width: 160, height: 84) { _ in
            if case .paused = countdown.state {
                countdown.resume(at: now())
            } else {
                countdown.pause(at: now())
            }
            countdownChanged()
            if let label = ui?.pauseLabel {
                if case .paused = countdown.state { setText(label, "Fortsæt") } else { setText(label, "Pause") }
            }
        }
        lv_obj_align(pause.button, LV_ALIGN_BOTTOM_RIGHT, -30, -30)
        pauseLabel = pause.label
    }

    // MARK: Ringing

    private func buildRinging() {
        let text = label(screen, "Tiden er gået!", size: 28)
        lv_obj_align(text, LV_ALIGN_CENTER, 0, -110)
        let duration = label(screen, TimeText.duration(seconds: countdown.duration), size: 44)
        lv_obj_align(duration, LV_ALIGN_CENTER, 0, -50)
        let stop = button(screen, "Stop", color: Palette.red, width: 200, height: 200, round: true) { _ in
            countdown.cancel()
            countdownChanged()
            music_player_alarm_stop()
            ui?.tick()
        }
        lv_obj_align(stop.button, LV_ALIGN_BOTTOM_MID, 0, -40)
        lastFlash = 0
    }
}

// MARK: - C API

@_cdecl("watch_tools_init")
public func watch_tools_init(_ open: (@convention(c) () -> Void)?) {
    openTimerApp = open
    if let bytes = readFile(recentPath, maxSize: 4 * TimerChoices.maxRecent) {
        choices = TimerChoices(decoding: bytes)
    }
    // Never deleted: the countdown runs whether the app is open or not
    _ = lv_timer_create({ _ in backgroundTick() }, 250, nil)
}

@_cdecl("watch_tools_wake_at_us")
public func watch_tools_wake_at_us() -> Int64 {
    wt_atomic_load64(&wakeAt)
}

@_cdecl("timer_app_show")
public func timer_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    ui = TimerUI(screen: screen)
}

@_cdecl("timer_app_hide")
public func timer_app_hide() {
    ui = nil
    // Leaving the alarm (e.g. with the power key) dismisses it
    if case .ringing = countdown.state {
        countdown.cancel()
        countdownChanged()
        music_player_alarm_stop()
    }
}
