import Testing
import WatchToolsKit

@Suite struct StopwatchTests {
    @Test func startStopResumeReset() {
        var watch = Stopwatch()
        #expect(!watch.canReset && !watch.isRunning)
        watch.toggle(at: 1_000_000)
        #expect(watch.isRunning && !watch.canReset) // "Nulstil" is disabled while running
        #expect(watch.elapsed(at: 3_500_000) == 2_500_000)
        watch.toggle(at: 4_000_000)
        #expect(!watch.isRunning && watch.canReset)
        #expect(watch.elapsed(at: 99_000_000) == 3_000_000) // stopped: doesn't move
        watch.toggle(at: 10_000_000)
        watch.toggle(at: 11_000_000)
        #expect(watch.elapsed(at: 50_000_000) == 4_000_000) // runs add up
        watch.reset()
        #expect(watch.elapsed(at: 50_000_000) == 0 && !watch.canReset)
    }

    @Test func resetIsIgnoredWhileRunning() {
        var watch = Stopwatch()
        watch.toggle(at: 0)
        watch.reset()
        #expect(watch.elapsed(at: 5) == 5)
    }

    @Test func texts() {
        #expect(TimeText.stopwatch(0) == "00:00,00")
        #expect(TimeText.stopwatch(65_432_100) == "01:05,43")
        #expect(TimeText.stopwatch(3_725_000_000) == "1:02:05")
        #expect(TimeText.countdown(299_000_001) == "5:00") // rounds up
        #expect(TimeText.countdown(0) == "0:00")
        #expect(TimeText.countdown(3_600_000_000) == "1:00:00")
        #expect(TimeText.duration(seconds: 120) == "2 min")
        #expect(TimeText.duration(seconds: 90) == "1 min 30 sek")
        #expect(TimeText.duration(seconds: 45) == "45 sek")
        #expect(TimeText.duration(seconds: 5400) == "1 t 30 min")
        #expect(TimeText.duration(seconds: 3605) == "1 t 0 min 5 sek")
        #expect(TimeText.duration(seconds: 7200) == "2 t")
    }
}

@Suite struct CountdownTests {
    @Test func runsPausesAndRings() {
        var timer = Countdown()
        timer.start(seconds: 10, at: 0)
        #expect(timer.wakeAt == 10_000_000)
        #expect(timer.tick(at: 4_000_000) == .none)
        timer.pause(at: 4_000_000)
        #expect(timer.wakeAt == nil)
        #expect(timer.remaining(at: 100_000_000) == 6_000_000)
        timer.resume(at: 100_000_000)
        #expect(timer.progress(at: 103_000_000) == 0.7)
        #expect(timer.tick(at: 106_000_000) == .startRinging)
        #expect(timer.state == .ringing(since: 106_000_000))
        #expect(timer.tick(at: 106_000_000 + Countdown.ringDuration) == .stopRinging)
        #expect(timer.state == .idle)
    }

    @Test func cancelStopsTheAlarm() {
        var timer = Countdown()
        timer.start(seconds: 1, at: 0)
        _ = timer.tick(at: 2_000_000)
        timer.cancel()
        #expect(timer.state == .idle && timer.tick(at: 99_000_000) == .none)
    }

    @Test func recentTimers() {
        var choices = TimerChoices()
        for s in [90, 300, 45, 90, 1200, 3600, 7] { choices.remember(s) }
        #expect(choices.recent == [7, 3600, 1200, 90]) // newest first, no duplicates, no presets, four at most
        #expect(choices.all == [120, 180, 300, 600, 7, 3600, 1200, 90])
        #expect(TimerChoices(decoding: choices.encoded) == choices)
        #expect(TimerChoices(decoding: [1, 2]).recent.isEmpty)
    }
}
