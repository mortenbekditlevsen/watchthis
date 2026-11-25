import Testing
@testable import WatchFaceKit

struct AdventTests {
    func day(_ year: Int, _ month: Int, _ day: Int) -> WallTime {
        WallTime(year: year, month: month, day: day, weekday: AdventCalendar.weekday(year: year, month: month, day: day),
                 hour: 12, minute: 0, second: 0)
    }

    @Test func decemberOpensDoorsUpToToday() {
        let t = day(2026, 12, 7)
        #expect(AdventCalendar.today(at: t) == 7)
        #expect(AdventCalendar.availability(door: 1, at: t, seasonStarted: true) == .available)
        #expect(AdventCalendar.availability(door: 7, at: t, seasonStarted: true) == .available)
        #expect(AdventCalendar.availability(door: 8, at: t, seasonStarted: true) == .locked(daysLeft: 1))
        #expect(AdventCalendar.availability(door: 24, at: t, seasonStarted: false) == .locked(daysLeft: 17))
    }

    @Test func afterChristmasEverythingStaysOpenUntilNextDecember() {
        #expect(AdventCalendar.today(at: day(2026, 12, 26)) == nil)
        #expect(AdventCalendar.availability(door: 24, at: day(2026, 12, 26), seasonStarted: true) == .available)
        #expect(AdventCalendar.season(at: day(2027, 3, 1)) == 2026)
        #expect(AdventCalendar.availability(door: 24, at: day(2027, 3, 1), seasonStarted: true) == .available)
        #expect(AdventCalendar.season(at: day(2027, 12, 1)) == 2027)
        #expect(AdventCalendar.availability(door: 2, at: day(2027, 12, 1), seasonStarted: true) == .locked(daysLeft: 1))
    }

    @Test func beforeTheFirstDecemberItWaits() {
        let t = day(2026, 11, 25)
        #expect(AdventCalendar.daysUntilDecember(t) == 6)
        #expect(AdventCalendar.availability(door: 1, at: t, seasonStarted: false) == .locked(daysLeft: 6))
        #expect(AdventCalendar.availability(door: 3, at: t, seasonStarted: false) == .locked(daysLeft: 8))
        #expect(AdventCalendar.daysUntilDecember(day(2028, 2, 28)) == 277) // A leap year
    }

    @Test func clockNotSet() {
        let t = WallTime(year: 1970, month: 1, day: 1, weekday: 4, hour: 0, minute: 0, second: 0)
        #expect(AdventCalendar.availability(door: 1, at: t, seasonStarted: true) == .unknownTime)
        #expect(AdventCalendar.today(at: t) == nil)
    }

    @Test func weekdays() {
        #expect(AdventCalendar.weekday(year: 1970, month: 1, day: 1) == 4)
        #expect(AdventCalendar.weekday(year: 2026, month: 12, day: 24) == 4) // Torsdag
        #expect(AdventCalendar.weekday(year: 2026, month: 11, day: 25) == 3)
    }

    @Test func stateRoundTrips() {
        var s = AdventState(season: 2026)
        s.setOpen(1, true)
        s.setOpen(24, true)
        s.setOpen(13, true)
        s.setOpen(13, false)
        s.setOpen(25, true) // Ignored
        #expect(s.isOpen(1) && s.isOpen(24) && !s.isOpen(13) && !s.isOpen(25))
        #expect(AdventState(decoding: s.encoded()) == s)
        #expect(AdventState(decoding: [1, 2, 3]) == nil)
        #expect(AdventState(decoding: [0, 0, 0, 0, 0, 0]) == nil) // No season
    }

    @Test func layoutHasEveryDoorOnce() {
        #expect(AdventCalendar.layout.sorted() == Array(1...24))
    }

    @Test func doorSwingsOpen() {
        let closed = AdventDoor.quad(x: 10, y: 20, w: 100, h: 200, angle: 0)
        #expect(abs(closed[1].x - 110) < 0.01 && abs(closed[1].y - 20) < 0.01 && abs(closed[2].y - 220) < 0.01)
        let open = AdventDoor.quad(x: 10, y: 20, w: 100, h: 200, angle: AdventDoor.openAngle)
        #expect(open[1].x < 10) // Past the hinge: out of the way of the picture
        #expect(AdventDoor.showsBack(AdventDoor.openAngle) && !AdventDoor.showsBack(0.5))
        #expect(AdventDoor.ease(0) == 0 && AdventDoor.ease(1) == 1)
    }

    @Test func everyPictureHasShapesAndATitle() {
        for door in 1...24 {
            let shapes = AdventScene.shapes(door)
            #expect(shapes.count > 20 && shapes.count < 320, "door \(door): \(shapes.count) shapes")
            #expect(!AdventScene.title(door).isEmpty)
        }
    }

    @Test func sparklesFadeAway() {
        var s = Sparkles(seed: 7)
        s.burst(x: 100, top: 0, bottom: 300, count: 40)
        s.sprinkle(x: 0, y: 0, w: 300, h: 300, count: 500)
        #expect(s.particles.count == Sparkles.maxParticles)
        for _ in 0..<200 { s.step(0.02) }
        #expect(s.isEmpty)
    }
}
