// The text that face elements show, in Danish like the rest of the watch. Shared so the phone preview matches the
// watch, and so the phone knows which glyphs a rasterized font needs (FaceText.glyphs).
// Upper case variants are spelled out: String.uppercased() would pull Unicode tables into the firmware.

public enum FaceText {
    static let weekdaysShort = ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"]
    static let weekdaysShortUpper = ["SØN", "MAN", "TIR", "ONS", "TOR", "FRE", "LØR"]
    static let weekdays = ["Søndag", "Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag"]
    static let weekdaysUpper = ["SØNDAG", "MANDAG", "TIRSDAG", "ONSDAG", "TORSDAG", "FREDAG", "LØRDAG"]
    // "maj" is the full word, so it has no period
    static let months = ["jan.", "feb.", "mar.", "apr.", "maj", "jun.", "jul.", "aug.", "sep.", "okt.", "nov.", "dec."]
    static let monthsUpper = ["JAN.", "FEB.", "MAR.", "APR.", "MAJ", "JUN.", "JUL.", "AUG.", "SEP.", "OKT.", "NOV.",
                              "DEC."]
    static let romanNumerals = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]

    public static func roman(_ hour: Int) -> String {
        romanNumerals[hour % 12]
    }

    static func twoDigits(_ v: Int) -> String {
        v < 10 ? "0\(v)" : "\(v)"
    }

    public static func time(_ e: DigitalTime, _ t: WallTime) -> String {
        guard t.isValid else { return e.showSeconds ? "--:--:--" : "--:--" }
        var hour = t.hour
        if e.hourFormat == .h12 {
            hour = hour % 12
            if hour == 0 { hour = 12 }
        }
        var s = e.leadingZero ? twoDigits(hour) : "\(hour)"
        s += ":" + twoDigits(t.minute)
        if e.showSeconds { s += ":" + twoDigits(t.second) }
        return s
    }

    public static func date(_ e: DateText, _ t: WallTime) -> String {
        guard t.isValid else { return "" }
        let wd = max(0, min(6, t.weekday))
        let mo = max(0, min(11, t.month - 1))
        let up = e.uppercase
        switch e.format {
        case .weekdayDayMonth:
            return "\(up ? weekdaysShortUpper[wd] : weekdaysShort[wd]) \(t.day). \(up ? monthsUpper[mo] : months[mo])"
        case .dayMonth:
            return "\(t.day). \(up ? monthsUpper[mo] : months[mo])"
        case .weekday:
            return up ? weekdaysUpper[wd] : weekdays[wd]
        case .numeric:
            return "\(t.day)/\(t.month)"
        case .weekdayDay:
            return "\(up ? weekdaysShortUpper[wd] : weekdaysShort[wd]) \(t.day)"
        }
    }

    public static func steps(_ count: Int) -> String {
        "\(count)"
    }

    public static func battery(_ percent: Int) -> String {
        percent < 0 ? "--%" : "\(percent)%"
    }

    /// Every character an element can show in this font style, for rasterizing a font subset on the phone
    public static func glyphs(for element: Element) -> String {
        let digits = "0123456789"
        switch element {
        case .digitalTime: return digits + ":-"
        case .date(let e):
            var s = digits + " ./"
            switch e.format {
            case .weekdayDayMonth, .weekdayDay:
                s += (e.uppercase ? weekdaysShortUpper : weekdaysShort).joined()
            case .weekday:
                s += (e.uppercase ? weekdaysUpper : weekdays).joined()
            case .dayMonth, .numeric:
                break
            }
            if e.format == .weekdayDayMonth || e.format == .dayMonth {
                s += (e.uppercase ? monthsUpper : months).joined()
            }
            return s
        case .analogClock(let e): return e.numerals.roman ? "IVX" : digits
        case .steps: return digits
        case .battery: return digits + "%-"
        case .text(let e): return e.text
        case .unknown: return ""
        }
    }
}
