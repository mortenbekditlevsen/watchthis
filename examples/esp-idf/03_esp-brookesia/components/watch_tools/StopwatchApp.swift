// Stopur: the time, and two buttons. Start (Stop while running), and Nulstil, which only works when stopped with a
// measured time. The stopwatch keeps running when the app closes or the watch sleeps.

nonisolated(unsafe) private var stopwatch = Stopwatch()
nonisolated(unsafe) private var ui: StopwatchUI?

private final class StopwatchUI {
    let screen: LVObj
    let time: LVObj
    let startButton: LVObj
    let startLabel: LVObj
    let resetButton: LVObj
    var timer: OpaquePointer?

    init(screen: LVObj) {
        self.screen = screen
        prepareScreen(screen)

        let title = label(screen, "Stopur", size: 28, color: Palette.dimText)
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 40)

        time = label(screen, "", size: 66)
        lv_obj_align(time, LV_ALIGN_CENTER, 0, -50)

        let diameter: Int32 = 150
        let reset = button(screen, "Nulstil", color: Palette.grey, width: diameter, height: diameter, round: true) { _ in
            stopwatch.reset()
            ui?.refresh()
        }
        lv_obj_align(reset.button, LV_ALIGN_BOTTOM_LEFT, 35, -50)
        resetButton = reset.button

        let start = button(screen, "Start", color: Palette.green, width: diameter, height: diameter, round: true) { _ in
            stopwatch.toggle(at: now())
            ui?.refresh()
        }
        lv_obj_align(start.button, LV_ALIGN_BOTTOM_RIGHT, -35, -50)
        startButton = start.button
        startLabel = start.label

        refresh()
        timer = lv_timer_create({ _ in ui?.tick() }, 33, nil)
    }

    func stop() {
        if let timer { lv_timer_delete(timer) }
        timer = nil
    }

    func tick() {
        if stopwatch.isRunning {
            setText(time, TimeText.stopwatch(stopwatch.elapsed(at: now())))
        }
    }

    func refresh() {
        setText(time, TimeText.stopwatch(stopwatch.elapsed(at: now())))
        setText(startLabel, stopwatch.isRunning ? "Stop" : "Start")
        setButtonColor(startButton, stopwatch.isRunning ? Palette.red : Palette.green)
        setEnabled(resetButton, stopwatch.canReset)
    }
}

@_cdecl("stopwatch_app_show")
public func stopwatch_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    ui?.stop()
    ui = StopwatchUI(screen: screen)
}

@_cdecl("stopwatch_app_hide")
public func stopwatch_app_hide() {
    ui?.stop()
    ui = nil
}
