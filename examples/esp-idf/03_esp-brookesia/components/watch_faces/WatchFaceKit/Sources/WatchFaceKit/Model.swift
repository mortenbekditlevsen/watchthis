// The watch face model. Coordinates are screen pixels on the watch (WatchScreen.width x WatchScreen.height, origin top left).
// Plain structs and enums only (no `any`, no Foundation) so this compiles for Embedded Swift.

public enum WatchScreen {
    public static let width = 410
    public static let height = 502
}

public struct WatchFace: Equatable, Sendable {
    /// 1-31 characters from A-Z a-z 0-9 _ - (the file id on the watch)
    public var id: String
    /// Display name (UTF-8, up to 63 bytes)
    public var name: String
    public var background: Background
    /// Drawn in order: later elements are on top
    public var elements: [Element]

    public init(id: String, name: String, background: Background = .color(.black), elements: [Element] = []) {
        self.id = id
        self.name = name
        self.background = background
        self.elements = elements
    }
}

public struct FaceColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 0xRRGGBB
    public init(rgb: UInt32, a: UInt8 = 255) {
        self.init(r: UInt8(truncatingIfNeeded: rgb >> 16), g: UInt8(truncatingIfNeeded: rgb >> 8),
                  b: UInt8(truncatingIfNeeded: rgb), a: a)
    }

    public var rgb: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

    public static let black = FaceColor(rgb: 0x000000)
    public static let white = FaceColor(rgb: 0xFFFFFF)
}

/// Which point of an element's bounding box `Placement.x/y` refers to. Text is also aligned this way.
public enum PlacementAnchor: UInt8, CaseIterable, Sendable {
    case topLeading = 0, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing

    /// 0 = leading/top, 1 = center, 2 = trailing/bottom
    public var horizontal: Int { Int(rawValue) % 3 }
    public var vertical: Int { Int(rawValue) / 3 }
}

public struct Placement: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var anchor: PlacementAnchor

    public init(x: Int, y: Int, anchor: PlacementAnchor = .center) {
        self.x = x
        self.y = y
        self.anchor = anchor
    }
}

public enum FontRef: Equatable, Sendable {
    /// A font built into the firmware: Montserrat in even sizes 8...44, and 66 = a condensed light oblique font
    /// (ASCII only). Other sizes use the nearest one.
    case builtin(size: Int)
    /// A font file uploaded with the face (LVGL binfont, rasterized by the phone)
    case asset(id: String)

    public static let builtinSizes = Array(stride(from: 8, through: 44, by: 2)) + [66]

    /// The builtin size the watch uses for `size`
    public static func nearestBuiltinSize(_ size: Int) -> Int {
        var best = builtinSizes[0]
        for s in builtinSizes where abs(s - size) < abs(best - size) {
            best = s
        }
        return best
    }
}

public struct TextStyle: Equatable, Sendable {
    public var font: FontRef
    public var color: FaceColor
    public var letterSpacing: Int

    public init(font: FontRef = .builtin(size: 20), color: FaceColor = .white, letterSpacing: Int = 0) {
        self.font = font
        self.color = color
        self.letterSpacing = letterSpacing
    }
}

// MARK: - Background

public enum Background: Equatable, Sendable {
    case color(FaceColor)
    case linearGradient(LinearGradient)
    case radialGradient(RadialGradient)
    case pattern(Pattern)
    case image(ImageBackground)
    /// A background kind this version does not know; kept so that editing a face does not drop it
    case unknown(tag: UInt32, payload: [UInt8])
}

public struct GradientStop: Equatable, Sendable {
    public var color: FaceColor
    /// 0 (start) ... 255 (end)
    public var location: Int

    public init(color: FaceColor, location: Int) {
        self.color = color
        self.location = location
    }
}

public struct LinearGradient: Equatable, Sendable {
    public var stops: [GradientStop]
    /// CSS convention: 180 = top to bottom, 90 = left to right
    public var angle: Int

    public init(stops: [GradientStop], angle: Int = 180) {
        self.stops = stops
        self.angle = angle
    }
}

public struct RadialGradient: Equatable, Sendable {
    public var stops: [GradientStop]
    public var centerX: Int
    public var centerY: Int
    public var radius: Int

    public init(stops: [GradientStop], centerX: Int = WatchScreen.width / 2, centerY: Int = WatchScreen.height / 2,
                radius: Int = WatchScreen.height / 2) {
        self.stops = stops
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
    }
}

public enum PatternKind: UInt8, CaseIterable, Sendable {
    case stripes = 0, diagonalStripes, dots, checker, grid
}

public struct Pattern: Equatable, Sendable {
    public var kind: PatternKind
    public var foreground: FaceColor
    public var background: FaceColor
    /// Distance between repeats in pixels (4...64)
    public var spacing: Int
    /// Line width / dot diameter / square size in pixels
    public var size: Int

    public init(kind: PatternKind, foreground: FaceColor, background: FaceColor, spacing: Int = 16, size: Int = 2) {
        self.kind = kind
        self.foreground = foreground
        self.background = background
        self.spacing = spacing
        self.size = size
    }
}

public struct ImageBackground: Equatable, Sendable {
    /// Face asset id of a WatchScreen.width x WatchScreen.height PNG or baseline JPEG
    public var assetID: String
    /// Shown while the watch prepares the image, or if it is missing
    public var fallback: FaceColor
    /// Darkens the image (a black layer over it), 0 (none) ... 100 % (black), to make the time easier to read
    public var dim: Int

    public init(assetID: String, fallback: FaceColor = .black, dim: Int = 0) {
        self.assetID = assetID
        self.fallback = fallback
        self.dim = dim
    }

    /// The black layer's opacity, 0...255
    public var dimOpacity: UInt8 { UInt8(max(0, min(100, dim)) * 255 / 100) }
}

// MARK: - Elements

public enum Element: Equatable, Sendable {
    case digitalTime(DigitalTime)
    case date(DateText)
    case analogClock(AnalogClock)
    case steps(Steps)
    case battery(Battery)
    case text(StaticText)
    /// An element kind this version does not know (a newer app or firmware); skipped when drawing, kept when editing
    case unknown(tag: UInt32, payload: [UInt8])
}

public enum HourFormat: UInt8, Sendable {
    case h24 = 0, h12
}

public struct DigitalTime: Equatable, Sendable {
    public var placement: Placement
    public var style: TextStyle
    public var hourFormat: HourFormat
    public var showSeconds: Bool
    /// "07:05" rather than "7:05"
    public var leadingZero: Bool

    public init(placement: Placement, style: TextStyle = TextStyle(font: .builtin(size: 44)),
                hourFormat: HourFormat = .h24, showSeconds: Bool = false, leadingZero: Bool = true) {
        self.placement = placement
        self.style = style
        self.hourFormat = hourFormat
        self.showSeconds = showSeconds
        self.leadingZero = leadingZero
    }
}

public enum DateFormat: UInt8, CaseIterable, Sendable {
    /// "Tir 20. okt."
    case weekdayDayMonth = 0
    /// "20. okt."
    case dayMonth
    /// "Tirsdag"
    case weekday
    /// "20/10"
    case numeric
    /// "Tir 20"
    case weekdayDay
}

public struct DateText: Equatable, Sendable {
    public var placement: Placement
    public var style: TextStyle
    public var format: DateFormat
    public var uppercase: Bool

    public init(placement: Placement, style: TextStyle = TextStyle(), format: DateFormat = .weekdayDayMonth,
                uppercase: Bool = false) {
        self.placement = placement
        self.style = style
        self.format = format
        self.uppercase = uppercase
    }
}

public enum HandKind: UInt8, CaseIterable, Sendable {
    case hour = 0, minute, second
}

public enum HandShape: UInt8, CaseIterable, Sendable {
    /// Rectangle with square ends
    case line = 0
    /// Rectangle with round ends
    case rounded
    /// Narrows towards the tip
    case tapered
    /// Widens, then comes to a point
    case sword
    /// Thin shaft with a triangular head
    case arrow
    /// Thin shaft with a disc near the tip
    case lollipop
}

public struct Hand: Equatable, Sendable {
    public var kind: HandKind
    public var shape: HandShape
    /// From the center to the tip
    public var length: Int
    /// Extends past the center on the other side
    public var tail: Int
    public var width: Int
    public var color: FaceColor
    /// Moves continuously instead of in steps (second hand: 10 updates per second)
    public var smooth: Bool

    public init(kind: HandKind, shape: HandShape = .rounded, length: Int, tail: Int = 0, width: Int,
                color: FaceColor = .white, smooth: Bool = false) {
        self.kind = kind
        self.shape = shape
        self.length = length
        self.tail = tail
        self.width = width
        self.color = color
        self.smooth = smooth
    }
}

public enum NumeralMode: Equatable, Sendable {
    case hidden
    case all
    /// 12, 3, 6 and 9
    case everyThird
    /// Bit n set: show hour n (bit 0 = 12)
    case custom(mask: UInt16)

    public func shows(hour: Int) -> Bool {
        let h = hour % 12
        switch self {
        case .hidden: return false
        case .all: return true
        case .everyThird: return h % 3 == 0
        case .custom(let mask): return mask & (1 << UInt16(h)) != 0
        }
    }
}

public struct Numerals: Equatable, Sendable {
    public var mode: NumeralMode
    public var style: TextStyle
    /// Distance from the dial edge to the numeral centers
    public var inset: Int
    public var roman: Bool

    public init(mode: NumeralMode = .hidden, style: TextStyle = TextStyle(font: .builtin(size: 24)), inset: Int = 30,
                roman: Bool = false) {
        self.mode = mode
        self.style = style
        self.inset = inset
        self.roman = roman
    }
}

public enum TickMode: UInt8, CaseIterable, Sendable {
    case hidden = 0, hours, hoursAndMinutes
}

public struct TickStyle: Equatable, Sendable {
    public var length: Int
    public var width: Int
    public var color: FaceColor

    public init(length: Int, width: Int, color: FaceColor = .white) {
        self.length = length
        self.width = width
        self.color = color
    }
}

public struct Ticks: Equatable, Sendable {
    public var mode: TickMode
    public var major: TickStyle
    public var minor: TickStyle
    /// Distance from the dial edge to the outer end of the ticks
    public var inset: Int

    public init(mode: TickMode = .hidden, major: TickStyle = TickStyle(length: 12, width: 4),
                minor: TickStyle = TickStyle(length: 6, width: 2, color: FaceColor(rgb: 0x808080)), inset: Int = 4) {
        self.mode = mode
        self.major = major
        self.minor = minor
        self.inset = inset
    }
}

public struct Dial: Equatable, Sendable {
    public var fill: FaceColor
    public var borderColor: FaceColor
    public var borderWidth: Int

    public init(fill: FaceColor = FaceColor(rgb: 0, a: 0), borderColor: FaceColor = .white, borderWidth: Int = 0) {
        self.fill = fill
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

public struct AnalogClock: Equatable, Sendable {
    public var centerX: Int
    public var centerY: Int
    public var radius: Int
    public var dial: Dial
    public var ticks: Ticks
    public var numerals: Numerals
    /// Drawn in order (normally hour, minute, second)
    public var hands: [Hand]
    /// Disc over the hands' pivot; radius 0 = none
    public var capRadius: Int
    public var capColor: FaceColor

    public init(centerX: Int = WatchScreen.width / 2, centerY: Int = WatchScreen.height / 2, radius: Int = 190,
                dial: Dial = Dial(), ticks: Ticks = Ticks(), numerals: Numerals = Numerals(), hands: [Hand] = [],
                capRadius: Int = 0, capColor: FaceColor = .white) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.dial = dial
        self.ticks = ticks
        self.numerals = numerals
        self.hands = hands
        self.capRadius = capRadius
        self.capColor = capColor
    }
}

public enum StepsStyle: UInt8, CaseIterable, Sendable {
    /// "4321"
    case text = 0
    /// A ring that fills towards the goal, with the count inside
    case ring
}

public struct Steps: Equatable, Sendable {
    public var placement: Placement
    public var style: StepsStyle
    public var text: TextStyle
    public var goal: Int
    /// Ring only
    public var radius: Int
    public var ringWidth: Int
    public var ringColor: FaceColor
    public var trackColor: FaceColor

    public init(placement: Placement, style: StepsStyle = .text, text: TextStyle = TextStyle(), goal: Int = 6000,
                radius: Int = 40, ringWidth: Int = 6, ringColor: FaceColor = FaceColor(rgb: 0x2ECC71),
                trackColor: FaceColor = FaceColor(rgb: 0x303030)) {
        self.placement = placement
        self.style = style
        self.text = text
        self.goal = goal
        self.radius = radius
        self.ringWidth = ringWidth
        self.ringColor = ringColor
        self.trackColor = trackColor
    }
}

public enum BatteryStyle: UInt8, CaseIterable, Sendable {
    /// "87%"
    case text = 0
    /// A small battery outline that fills
    case bar
}

public struct Battery: Equatable, Sendable {
    public var placement: Placement
    public var style: BatteryStyle
    public var text: TextStyle

    public init(placement: Placement, style: BatteryStyle = .text, text: TextStyle = TextStyle()) {
        self.placement = placement
        self.style = style
        self.text = text
    }
}

public struct StaticText: Equatable, Sendable {
    public var placement: Placement
    public var style: TextStyle
    public var text: String

    public init(placement: Placement, style: TextStyle = TextStyle(), text: String) {
        self.placement = placement
        self.style = style
        self.text = text
    }
}
