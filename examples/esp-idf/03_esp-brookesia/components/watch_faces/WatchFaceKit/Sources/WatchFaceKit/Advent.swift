// Julekalender: 24 doors, one for each day from 1 to 24 December. A door can be opened on its day or any day after
// it (a forgotten one later), never before. After Christmas every door stays openable until the next 1 December,
// when the calendar starts over with all doors closed. Which doors are open is kept per season (the year of the
// December it belongs to). The pictures are in AdventScenes.swift.

/// Which doors are open in one season's calendar
public struct AdventState: Equatable, Sendable {
    /// The year of the calendar's December
    public var season: Int
    /// Bit d - 1 for door d
    public var opened: UInt32

    public init(season: Int, opened: UInt32 = 0) {
        self.season = season
        self.opened = opened & AdventState.allDoors
    }

    static let allDoors: UInt32 = (1 << 24) - 1

    public func isOpen(_ door: Int) -> Bool {
        (1...24).contains(door) && opened & (1 << UInt32(door - 1)) != 0
    }

    public mutating func setOpen(_ door: Int, _ open: Bool) {
        guard (1...24).contains(door) else { return }
        let bit: UInt32 = 1 << UInt32(door - 1)
        if open { opened |= bit } else { opened &= ~bit }
    }

    /// The file: season (UInt16, little endian), opened (UInt32, little endian)
    public func encoded() -> [UInt8] {
        let s = UInt16(clamping: season)
        return [UInt8(s & 0xFF), UInt8(s >> 8),
                UInt8(opened & 0xFF), UInt8((opened >> 8) & 0xFF), UInt8((opened >> 16) & 0xFF), UInt8(opened >> 24)]
    }

    public init?(decoding bytes: [UInt8]) {
        guard bytes.count == 6 else { return nil }
        let season = Int(bytes[0]) | Int(bytes[1]) << 8
        guard season >= 2024 else { return nil }
        let opened = UInt32(bytes[2]) | UInt32(bytes[3]) << 8 | UInt32(bytes[4]) << 16 | UInt32(bytes[5]) << 24
        self.init(season: season, opened: opened)
    }
}

public enum AdventAvailability: Equatable, Sendable {
    case available
    /// Opens in this many days
    case locked(daysLeft: Int)
    /// The clock hasn't been set yet: nothing can be opened
    case unknownTime
}

public enum AdventCalendar {
    public static let doors = 24

    /// The season `t` belongs to: December's year, or last year's from January to November
    public static func season(at t: WallTime) -> Int {
        t.month == 12 ? t.year : t.year - 1
    }

    /// Today's door (1 to 24 December), whose opening plays when the app starts
    public static func today(at t: WallTime) -> Int? {
        t.isValid && t.month == 12 && t.day <= 24 ? t.day : nil
    }

    /// `seasonStarted`: the calendar for `season(at: t)` has been used (opened in its December). Without that, from
    /// January to November nothing can be opened: the calendar waits for the coming December (no peeking before it).
    public static func availability(door: Int, at t: WallTime, seasonStarted: Bool) -> AdventAvailability {
        guard t.isValid else { return .unknownTime }
        if t.month == 12 {
            return t.day >= 25 || door <= t.day ? .available : .locked(daysLeft: door - t.day)
        }
        return seasonStarted ? .available : .locked(daysLeft: daysUntilDecember(t) + door - 1)
    }

    /// Days from `t` (January to November) to 1 December of the same year
    public static func daysUntilDecember(_ t: WallTime) -> Int {
        dayNumber(year: t.year, month: 12, day: 1) - dayNumber(year: t.year, month: t.month, day: t.day)
    }

    /// 0 = Sunday
    public static func weekday(year: Int, month: Int, day: Int) -> Int {
        let d = dayNumber(year: year, month: month, day: day) % 7
        return (d + 4 + 7) % 7 // 1970-01-01 was a Thursday
    }

    /// Days since 1970-01-01 (proleptic Gregorian calendar)
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The doors' numbers, row by row in a 4 x 6 grid: mixed up, as on a real calendar
    public static let layout: [Int] = [
        17, 4, 22, 9,
        1, 13, 20, 6,
        11, 24, 3, 15,
        7, 19, 2, 12,
        23, 8, 14, 18,
        5, 16, 10, 21,
    ]

    /// "1. december"
    public static func dateText(_ door: Int) -> String {
        "\(door). december"
    }
}

// MARK: - The door

/// The door swinging open on its left hinge, towards the viewer: its free edge moves left (cos of the angle) and,
/// coming closer, gets taller
public enum AdventDoor {
    /// The door's corners (top left, top right, bottom right, bottom left) for a frame at (x, y), `w` x `h`, opened
    /// `angle` radians (0 = closed)
    public static func quad(x: Float, y: Float, w: Float, h: Float, angle: Float) -> [Point] {
        let edge = x + w * FaceMath.cos(angle)
        let grow = h * 0.12 * FaceMath.sin(angle)
        return [Point(x: x, y: y), Point(x: edge, y: y - grow), Point(x: edge, y: y + h + grow), Point(x: x, y: y + h)]
    }

    /// The angle when the door is fully open: past square, its back showing to the left of the hinge
    public static let openAngle: Float = 1.85

    /// Past square to the frame, the door's back shows
    public static func showsBack(_ angle: Float) -> Bool {
        FaceMath.cos(angle) < 0
    }

    /// 0...1 -> 0...1, slow at both ends
    public static func ease(_ t: Float) -> Float {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    /// A door's colour gets darker as it turns away from the light (edge on: darkest)
    public static func shade(_ color: FaceColor, angle: Float) -> FaceColor {
        let k = 0.5 + 0.5 * abs(FaceMath.cos(angle))
        return FaceColor(r: UInt8(Float(color.r) * k), g: UInt8(Float(color.g) * k), b: UInt8(Float(color.b) * k),
                         a: color.a)
    }
}

// MARK: - Sparkles

/// One glitter: drifts, fades and twinkles
public struct Twinkle: Sendable {
    public var x: Float
    public var y: Float
    var vx: Float
    var vy: Float
    var age: Float = 0
    let lifetime: Float
    let phase: Float
    public let color: FaceColor
    /// Diameter in pixels; the bigger ones are drawn as little stars
    public let size: Float

    /// 0...255: fades in quickly, twinkles, fades out over its last third
    public var opacity: UInt8 {
        let fadeIn = min(1, age / 0.12)
        let fadeOut = min(1, (lifetime - age) / (lifetime / 3))
        let twinkle = 0.6 + 0.4 * FaceMath.sin(phase + age * 13)
        return UInt8(max(0, min(255, fadeIn * fadeOut * twinkle * 255)))
    }

    public var isStar: Bool { size >= 5 }
}

/// The glitter when a door opens: a burst from the opening edge, then stars twinkling over the picture
public struct Sparkles: Sendable {
    public private(set) var particles: [Twinkle] = []
    private var random: UInt32

    public static let maxParticles = 140
    static let gravity: Float = 35
    static let colors: [FaceColor] = [
        FaceColor(rgb: 0xFFD966), FaceColor(rgb: 0xFFF4C2), FaceColor(rgb: 0xFFFFFF), FaceColor(rgb: 0xF2B33D),
    ]
    /// Juleaften: some red and green too
    static let festiveColors: [FaceColor] = colors + [FaceColor(rgb: 0xFF4D5E), FaceColor(rgb: 0x7CFF9A)]

    public init(seed: UInt32) {
        random = seed | 1
    }

    public var isEmpty: Bool { particles.isEmpty }

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

    private mutating func color(festive: Bool) -> FaceColor {
        let palette = festive ? Sparkles.festiveColors : Sparkles.colors
        return palette[Int(next() * Float(palette.count)) % palette.count]
    }

    /// Glitter streaming out of the gap along the vertical edge at `x`, from `top` to `bottom`, flying right
    public mutating func burst(x: Float, top: Float, bottom: Float, count: Int, festive: Bool = false) {
        for _ in 0..<min(count, Sparkles.maxParticles - particles.count) {
            let life = between(0.7, 1.6)
            particles.append(Twinkle(x: x + between(-3, 3), y: between(top, bottom), vx: between(20, 150),
                                     vy: between(-70, 25), lifetime: life, phase: between(0, 6.28),
                                     color: color(festive: festive), size: next() < 0.25 ? between(5, 9) : between(2, 4)))
        }
    }

    /// Stars that appear in place, twinkle and go, scattered over the rect
    public mutating func sprinkle(x: Float, y: Float, w: Float, h: Float, count: Int, festive: Bool = false) {
        for _ in 0..<min(count, Sparkles.maxParticles - particles.count) {
            let life = between(0.6, 1.4)
            particles.append(Twinkle(x: between(x, x + w), y: between(y, y + h), vx: 0, vy: between(-6, 6),
                                     lifetime: life, phase: between(0, 6.28), color: color(festive: festive),
                                     size: next() < 0.5 ? between(5, 11) : between(2, 4)))
        }
    }

    public mutating func step(_ dt: Float) {
        var i = 0
        while i < particles.count {
            var p = particles[i]
            p.vy += Sparkles.gravity * dt
            p.vx *= 1 - 1.5 * dt // air drag
            p.vy *= 1 - 1.5 * dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.age += dt
            if p.age >= p.lifetime {
                particles.remove(at: i)
            } else {
                particles[i] = p
                i += 1
            }
        }
    }
}
