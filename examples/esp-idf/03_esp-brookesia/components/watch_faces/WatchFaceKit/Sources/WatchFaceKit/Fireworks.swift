// Birthday fireworks: rockets rise from the bottom and burst into sparks that fall and fade. A plain simulation
// (positions in screen pixels, time in seconds); the watch draws `sparks` as small dots.

public struct Spark: Sendable {
    public var x: Float
    public var y: Float
    var vx: Float
    var vy: Float
    /// Seconds left; it fades over the last part
    var life: Float
    let lifetime: Float
    public let color: FaceColor
    /// A rocket on its way up (bursts when it slows down)
    let isRocket: Bool

    /// 0...255
    public var opacity: UInt8 {
        UInt8(max(0, min(255, life / lifetime * 2 * 255)))
    }

    public var size: Int { isRocket ? 4 : 3 }
}

public struct Fireworks: Sendable {
    public private(set) var sparks: [Spark] = []
    public private(set) var elapsed: Float = 0
    /// New rockets are launched until then; the show ends when the last spark is gone
    public let launchDuration: Float
    private var nextLaunch: Float = 0
    private var random: UInt32

    public static let maxSparks = 300
    static let gravity: Float = 160
    static let colors: [FaceColor] = [
        FaceColor(rgb: 0xC8102E), FaceColor(rgb: 0xFFFFFF), FaceColor(rgb: 0xFFD23F), FaceColor(rgb: 0x3FA7FF),
        FaceColor(rgb: 0x5CFF7A), FaceColor(rgb: 0xFF6FD8), FaceColor(rgb: 0xFF8A00),
    ]

    public init(seed: UInt32, launchDuration: Float = 4) {
        random = seed | 1
        self.launchDuration = launchDuration
    }

    public var isFinished: Bool { elapsed > launchDuration && sparks.isEmpty }

    private mutating func next() -> Float {
        // xorshift32: 0..<1
        random ^= random << 13
        random ^= random >> 17
        random ^= random << 5
        return Float(random >> 8) / Float(1 << 24)
    }

    private mutating func between(_ a: Float, _ b: Float) -> Float {
        a + (b - a) * next()
    }

    public mutating func step(_ dt: Float) {
        elapsed += dt
        if elapsed < launchDuration && elapsed >= nextLaunch {
            nextLaunch = elapsed + between(0.25, 0.6)
            let color = Fireworks.colors[Int(next() * Float(Fireworks.colors.count)) % Fireworks.colors.count]
            sparks.append(Spark(x: between(80, Float(WatchScreen.width) - 80), y: Float(WatchScreen.height),
                                vx: between(-30, 30), vy: between(-380, -300), life: 3, lifetime: 3, color: color,
                                isRocket: true))
        }
        var bursts: [(Float, Float, FaceColor)] = []
        var i = 0
        while i < sparks.count {
            var s = sparks[i]
            s.vy += Fireworks.gravity * dt
            if !s.isRocket {
                s.vx *= 1 - 1.2 * dt // air drag
                s.vy *= 1 - 1.2 * dt
            }
            s.x += s.vx * dt
            s.y += s.vy * dt
            s.life -= dt
            if s.isRocket && s.vy > -60 {
                bursts.append((s.x, s.y, s.color))
                s.life = 0
            }
            if s.life <= 0 || s.y > Float(WatchScreen.height) + 10 {
                sparks.remove(at: i)
            } else {
                sparks[i] = s
                i += 1
            }
        }
        for (x, y, color) in bursts {
            let count = min(48, Fireworks.maxSparks - sparks.count)
            for k in 0..<max(0, count) {
                let angle = Float(k) / Float(count) * 2 * FaceMath.pi + between(-0.1, 0.1)
                let speed = between(90, 200)
                let life = between(1.0, 1.6)
                // Mostly the burst's color, a few white glitters
                let sparkColor = next() < 0.15 ? FaceColor.white : color
                sparks.append(Spark(x: x, y: y, vx: speed * FaceMath.cos(angle), vy: speed * FaceMath.sin(angle),
                                    life: life, lifetime: life, color: sparkColor, isRocket: false))
            }
        }
    }
}

/// The Danish flag (Dannebrog) in proportions 37:28, the cross 4 units wide, its vertical bar 12 units from the
/// hoist: the rectangles to draw, in flag coordinates
public enum Dannebrog {
    public static let red = FaceColor(rgb: 0xC8102E)

    /// (x, y, width, height) of the two white bars, for a flag `width` wide
    public static func whiteBars(width: Int) -> (vertical: (Int, Int, Int, Int), horizontal: (Int, Int, Int, Int)) {
        let unit = Float(width) / 37
        let h = Int((unit * 28).rounded())
        let bar = Int((unit * 4).rounded())
        let x = Int((unit * 12).rounded())
        let y = Int((unit * 12).rounded())
        return ((x, 0, bar, h), (0, y, width, bar))
    }

    public static func height(width: Int) -> Int {
        Int((Float(width) * 28 / 37).rounded())
    }
}

public struct BirthdayDate: Equatable, Sendable {
    /// 1...12
    public var month: Int
    /// 1...31
    public var day: Int

    public init?(month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.month = month
        self.day = day
    }

    public func isToday(_ t: WallTime) -> Bool {
        guard t.isValid else { return false }
        // Born on 29 February: celebrate on 28 February in other years
        if month == 2 && day == 29 && !Self.isLeapYear(t.year) {
            return t.month == 2 && t.day == 28
        }
        return t.month == month && t.day == day
    }

    static func isLeapYear(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }
}
