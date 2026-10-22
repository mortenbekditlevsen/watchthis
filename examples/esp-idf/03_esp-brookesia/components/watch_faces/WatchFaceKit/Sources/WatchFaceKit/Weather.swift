// Weather for the watch's Vejr app (and later face elements): the phone fetches a forecast and uploads it as a small
// file (file_store kind FILE_STORE_WEATHER, docs/watch-ble-protocol.md §13). Same TLV records as face files, magic
// "WWTR". Temperatures in tenths of °C, wind in tenths of m/s.

public enum WeatherCondition: UInt8, CaseIterable, Sendable {
    case clear = 0, partlyCloudy, cloudy, fog, drizzle, rain, showers, sleet, snow, thunder

    /// WMO weather interpretation codes (as Open-Meteo reports them)
    public init(wmo code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .sleet
        case 61, 63, 65: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 80, 81, 82: self = .showers
        case 95, 96, 99: self = .thunder
        default: self = .cloudy
        }
    }

    public func text(isDay: Bool = true) -> String {
        switch self {
        case .clear: isDay ? "Sol" : "Klart"
        case .partlyCloudy: "Delvis skyet"
        case .cloudy: "Overskyet"
        case .fog: "Tåge"
        case .drizzle: "Støvregn"
        case .rain: "Regn"
        case .showers: "Byger"
        case .sleet: "Slud"
        case .snow: "Sne"
        case .thunder: "Torden"
        }
    }
}

public struct WeatherNow: Equatable, Sendable {
    public var condition: WeatherCondition
    public var isDay: Bool
    /// Tenths of °C
    public var temperature: Int
    public var feelsLike: Int
    /// Tenths of m/s
    public var wind: Int
    public var gusts: Int

    public init(condition: WeatherCondition, isDay: Bool = true, temperature: Int, feelsLike: Int, wind: Int = 0,
                gusts: Int = 0) {
        self.condition = condition
        self.isDay = isDay
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.wind = wind
        self.gusts = gusts
    }
}

public struct WeatherDay: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var condition: WeatherCondition
    /// Tenths of °C
    public var high: Int
    public var low: Int
    /// Tenths of mm
    public var precipitation: Int
    /// 0...100
    public var precipitationProbability: Int
    /// Strongest wind of the day, tenths of m/s
    public var windMax: Int

    public init(year: Int, month: Int, day: Int, condition: WeatherCondition, high: Int, low: Int,
                precipitation: Int = 0, precipitationProbability: Int = 0, windMax: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.condition = condition
        self.high = high
        self.low = low
        self.precipitation = precipitation
        self.precipitationProbability = precipitationProbability
        self.windMax = windMax
    }

    public func isSameDate(_ t: WallTime) -> Bool {
        year == t.year && month == t.month && day == t.day
    }

    /// 0 = Sunday
    public var weekday: Int {
        // Sakamoto's method
        let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = month < 3 ? year - 1 : year
        return (y + y / 4 - y / 100 + y / 400 + offsets[(month - 1) % 12] + day) % 7
    }
}

public struct WeatherReport: Equatable, Sendable {
    public var location: String
    /// When the forecast was fetched (Unix seconds)
    public var updated: Int64
    public var now: WeatherNow
    /// From today on
    public var days: [WeatherDay]

    public static let maxDays = 10
    /// "Windy" from here (a strong breeze, 10.8 m/s)
    public static let windyFrom = 108

    public init(location: String, updated: Int64, now: WeatherNow, days: [WeatherDay]) {
        self.location = location
        self.updated = updated
        self.now = now
        self.days = days
    }

    /// The forecast for the date `t`, if the report has it
    public func day(for t: WallTime) -> WeatherDay? {
        days.first { $0.isSameDate(t) }
    }

    /// The days from `t`'s date on (an older report still has the days that haven't passed)
    public func days(from t: WallTime) -> [WeatherDay] {
        let today = t.year * 10_000 + t.month * 100 + t.day
        return days.filter { $0.year * 10_000 + $0.month * 100 + $0.day >= today }
    }
}

// MARK: - Texts

public enum WeatherText {
    /// "12°", "-3°" (never "-0°")
    public static func temperature(_ tenths: Int) -> String {
        let rounded = tenths >= 0 ? (tenths + 5) / 10 : -((-tenths + 5) / 10)
        return "\(rounded)°"
    }

    /// "6 m/s"
    public static func wind(_ tenths: Int) -> String {
        "\((tenths + 5) / 10) m/s"
    }

    /// "I dag", "I morgen", then "Fre 24."
    public static func dayName(_ day: WeatherDay, today t: WallTime) -> String {
        if day.isSameDate(t) { return "I dag" }
        if isNextDay(day, after: t) { return "I morgen" }
        let short = ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"]
        return "\(short[day.weekday]) \(day.day)."
    }

    static func isNextDay(_ day: WeatherDay, after t: WallTime) -> Bool {
        let daysInMonth = [31, (t.year % 4 == 0 && t.year % 100 != 0) || t.year % 400 == 0 ? 29 : 28, 31, 30, 31, 30,
                           31, 31, 30, 31, 30, 31]
        var (y, m, d) = (t.year, t.month, t.day + 1)
        if d > daysInMonth[(m - 1) % 12] { d = 1; m += 1 }
        if m > 12 { m = 1; y += 1 }
        return day.year == y && day.month == m && day.day == d
    }

    /// The condition, and "blæsende" when it's windy
    public static func description(_ now: WeatherNow) -> String {
        let text = now.condition.text(isDay: now.isDay)
        return now.wind >= WeatherReport.windyFrom || now.gusts >= 2 * WeatherReport.windyFrom
            ? text + ", blæsende" : text
    }
}

// MARK: - Encoding

public enum WeatherFile {
    public static let magic: [UInt8] = [0x57, 0x57, 0x54, 0x52] // "WWTR"
    public static let version: UInt8 = 1
}

extension WeatherReport {
    public func encoded() -> [UInt8] {
        var w = TLVWriter()
        w.appendRaw(WeatherFile.magic)
        w.appendRaw([WeatherFile.version])
        w.string(1, location)
        w.sint(2, Int(clamping: updated))
        w.nested(3) { w in
            w.uint(1, Int(now.condition.rawValue))
            w.bool(2, now.isDay)
            w.sint(3, now.temperature)
            w.sint(4, now.feelsLike)
            w.uint(5, now.wind)
            w.uint(6, now.gusts)
        }
        for day in days.prefix(WeatherReport.maxDays) {
            w.nested(4) { w in
                w.uint(1, day.year * 10_000 + day.month * 100 + day.day)
                w.uint(2, Int(day.condition.rawValue))
                w.sint(3, day.high)
                w.sint(4, day.low)
                w.uint(5, day.precipitation)
                w.uint(6, day.precipitationProbability)
                w.uint(7, day.windMax)
            }
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws(FaceDecodingError) {
        guard bytes.count >= 5, Array(bytes[0..<4]) == WeatherFile.magic else { throw .badMagic }
        guard bytes[4] == WeatherFile.version else { throw .unsupportedVersion(bytes[4]) }
        self.init(location: "", updated: 0, now: WeatherNow(condition: .cloudy, temperature: 0, feelsLike: 0), days: [])
        var r = TLVReader(bytes[5...])
        while let (tag, v) = try r.next() {
            var fields = v.records
            switch tag {
            case 1: location = try v.string()
            case 2: updated = Int64(try v.sint())
            case 3:
                while let (t, x) = try fields.next() {
                    switch t {
                    case 1: now.condition = WeatherCondition(rawValue: UInt8(clamping: try x.uint())) ?? .cloudy
                    case 2: now.isDay = try x.bool()
                    case 3: now.temperature = try x.sint()
                    case 4: now.feelsLike = try x.sint()
                    case 5: now.wind = try x.uint()
                    case 6: now.gusts = try x.uint()
                    default: break
                    }
                }
            case 4:
                guard days.count < WeatherReport.maxDays else { throw .invalid }
                var day = WeatherDay(year: 2000, month: 1, day: 1, condition: .cloudy, high: 0, low: 0)
                while let (t, x) = try fields.next() {
                    switch t {
                    case 1:
                        let date = try x.uint()
                        (day.year, day.month, day.day) = (date / 10_000, date / 100 % 100, date % 100)
                    case 2: day.condition = WeatherCondition(rawValue: UInt8(clamping: try x.uint())) ?? .cloudy
                    case 3: day.high = try x.sint()
                    case 4: day.low = try x.sint()
                    case 5: day.precipitation = try x.uint()
                    case 6: day.precipitationProbability = min(100, try x.uint())
                    case 7: day.windMax = try x.uint()
                    default: break
                    }
                }
                guard (1...12).contains(day.month), (1...31).contains(day.day) else { throw .invalid }
                days.append(day)
            default:
                break
            }
        }
    }
}

// MARK: - Icons

/// One piece of a weather icon, in a 100 x 100 box (y down)
public enum IconShape: Equatable, Sendable {
    case circle(x: Float, y: Float, r: Float, color: FaceColor)
    case roundRect(x: Float, y: Float, w: Float, h: Float, r: Float, color: FaceColor)
    case line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float, color: FaceColor)
    case triangle(x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float, color: FaceColor)
}

public enum WeatherIcon {
    static let sun = FaceColor(rgb: 0xFFC83D)
    static let moon = FaceColor(rgb: 0xF2E9C9)
    static let cloudLight = FaceColor(rgb: 0xE8EDF2)
    static let cloudDark = FaceColor(rgb: 0x9AA4B0)
    static let rain = FaceColor(rgb: 0x4AA8FF)
    static let snow = FaceColor(rgb: 0xFFFFFF)
    static let bolt = FaceColor(rgb: 0xFFD23F)
    static let wind = FaceColor(rgb: 0xB8E0FF)

    /// The shapes, drawn in order. `background` is what the icon is drawn on (the moon's crescent is cut with it).
    public static func shapes(_ condition: WeatherCondition, isDay: Bool, windy: Bool,
                              background: FaceColor = .black) -> [IconShape] {
        var s: [IconShape] = []
        func sunOrMoon(x: Float, y: Float, r: Float) {
            if isDay {
                for i in 0..<8 {
                    let a = Float(i) * FaceMath.pi / 4
                    let (c, n) = (FaceMath.cos(a), FaceMath.sin(a))
                    s.append(.line(x1: x + c * (r + 6), y1: y + n * (r + 6), x2: x + c * (r + 14), y2: y + n * (r + 14),
                                   width: 5, color: sun))
                }
                s.append(.circle(x: x, y: y, r: r, color: sun))
            } else {
                s.append(.circle(x: x, y: y, r: r, color: moon))
                s.append(.circle(x: x + r * 0.45, y: y - r * 0.35, r: r * 0.85, color: background))
            }
        }
        func cloud(x: Float, y: Float, scale: Float, color: FaceColor) {
            // A flat bottom with three bumps; (x, y) is the bottom left corner
            s.append(.roundRect(x: x, y: y - 22 * scale, w: 64 * scale, h: 22 * scale, r: 11 * scale, color: color))
            s.append(.circle(x: x + 20 * scale, y: y - 20 * scale, r: 15 * scale, color: color))
            s.append(.circle(x: x + 40 * scale, y: y - 26 * scale, r: 20 * scale, color: color))
        }
        func drops(_ count: Int, color: FaceColor, top: Float, snowflakes: Bool = false) {
            for i in 0..<count {
                let x = 32 + Float(i) * 16
                if snowflakes {
                    s.append(.circle(x: x, y: top + 8 + Float(i % 2) * 8, r: 4.5, color: color))
                } else {
                    s.append(.line(x1: x + 4, y1: top, x2: x - 4, y2: top + 16, width: 5, color: color))
                }
            }
        }

        switch condition {
        case .clear:
            sunOrMoon(x: 50, y: 50, r: 22)
        case .partlyCloudy:
            sunOrMoon(x: 62, y: 36, r: 17)
            cloud(x: 12, y: 80, scale: 1.0, color: cloudLight)
        case .cloudy:
            cloud(x: 30, y: 62, scale: 0.85, color: cloudDark)
            cloud(x: 10, y: 82, scale: 1.05, color: cloudLight)
        case .fog:
            cloud(x: 18, y: 58, scale: 1.0, color: cloudDark)
            for (i, y) in [68, 80, 92].enumerated() {
                s.append(.line(x1: Float(14 + i * 6), y1: Float(y), x2: Float(86 - i * 4), y2: Float(y), width: 5,
                               color: cloudLight))
            }
        case .drizzle:
            cloud(x: 18, y: 66, scale: 1.0, color: cloudLight)
            drops(3, color: rain, top: 72)
        case .rain:
            cloud(x: 18, y: 66, scale: 1.0, color: cloudDark)
            drops(4, color: rain, top: 72)
        case .showers:
            sunOrMoon(x: 66, y: 30, r: 14)
            cloud(x: 14, y: 66, scale: 1.0, color: cloudLight)
            drops(3, color: rain, top: 72)
        case .sleet:
            cloud(x: 18, y: 66, scale: 1.0, color: cloudLight)
            s.append(.line(x1: 36, y1: 72, x2: 28, y2: 88, width: 5, color: rain))
            s.append(.circle(x: 50, y: 82, r: 4.5, color: snow))
            s.append(.line(x1: 68, y1: 72, x2: 60, y2: 88, width: 5, color: rain))
        case .snow:
            cloud(x: 18, y: 66, scale: 1.0, color: cloudLight)
            drops(4, color: snow, top: 70, snowflakes: true)
        case .thunder:
            cloud(x: 18, y: 62, scale: 1.0, color: cloudDark)
            s.append(.triangle(x1: 54, y1: 60, x2: 38, y2: 82, x3: 52, y3: 80, color: bolt))
            s.append(.triangle(x1: 52, y1: 76, x2: 60, y2: 76, x3: 44, y3: 98, color: bolt))
        }
        if windy {
            // Gusts across the lower right
            s.append(.line(x1: 58, y1: 86, x2: 94, y2: 86, width: 4, color: wind))
            s.append(.line(x1: 66, y1: 95, x2: 90, y2: 95, width: 4, color: wind))
        }
        return s
    }
}
