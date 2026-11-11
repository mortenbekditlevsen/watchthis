// Lommeregner: a calculator in the Apple Watch calculator's colours (black, dark grey digits, light grey functions,
// orange operators; the chosen operator white with orange). Multiplication and division before addition and
// subtraction (2 + 3 × 4 = 14), up to 9 digits, Danish number format (1.234,5). Numbers are Doubles shown rounded to 9
// significant digits (so 0,1 + 0,2 shows 0,3); formatted here without Foundation.

private let orange = FaceColor(r: 255, g: 159, b: 10)
private let darkGrey = FaceColor(r: 51, g: 51, b: 51)
private let lightGrey = FaceColor(r: 165, g: 165, b: 165)
private let pressedDark = FaceColor(r: 115, g: 115, b: 115)
private let pressedLight = FaceColor(r: 217, g: 217, b: 217)
private let pressedOrange = FaceColor(r: 252, g: 199, b: 140)

private let maxDigits = 9

// MARK: - Danish number formatting
// On ASCII bytes: String's Character operations (prefix, dropFirst, removeLast...) would pull Unicode's grapheme and
// normalization tables into the firmware.

private let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
private let commaByte = UInt8(ascii: ","), minusByte = UInt8(ascii: "-"), pointByte = UInt8(ascii: ".")

enum CalculatorFormat {
    static func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// 1234567 as "1.234.567" (`digits`: the integer part's)
    static func grouped<S: Collection>(_ digits: S) -> [UInt8] where S.Element == UInt8 {
        var out: [UInt8] = []
        let n = digits.count
        for (i, c) in digits.enumerated() {
            if i > 0 && (n - i) % 3 == 0 { out.append(pointByte) }
            out.append(c)
        }
        return out
    }

    private static func trimmingZeros(_ bytes: [UInt8]) -> [UInt8] {
        var b = bytes
        while b.last == zero { b.removeLast() }
        return b
    }

    /// `v` rounded to 9 significant digits: "1.234,5", "-0,001", "1,5e12" (too big or small for 9 digits)
    static func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "Fejl" }
        if v == 0 { return "0" }
        let negative = v < 0
        // |v| = scaled × 10^e with 1 <= scaled < 10
        var scaled = negative ? -v : v
        var e = 0
        while scaled >= 10 { scaled /= 10; e += 1 }
        while scaled < 1 { scaled *= 10; e -= 1 }
        var significant = Int64((scaled * 100_000_000).rounded())
        if significant >= 1_000_000_000 {
            significant /= 10
            e += 1
        }
        let digits = Array(String(significant).utf8)   // 9 of them
        var out: [UInt8] = negative ? [minusByte] : []
        if e >= maxDigits || e < -(maxDigits - 1) {
            // Scientific: d,dddd e±N
            out.append(digits[0])
            let fraction = trimmingZeros(Array(digits[1...]))
            if !fraction.isEmpty { out += [commaByte] + fraction }
            return text(out) + "e\(e)"
        }
        let fraction: [UInt8]
        if e >= 0 {
            out += grouped(digits[0...e])
            fraction = trimmingZeros(Array(digits[(e + 1)...]))
        } else {
            out.append(zero)
            fraction = trimmingZeros([UInt8](repeating: zero, count: -e - 1) + digits)
        }
        if !fraction.isEmpty { out += [commaByte] + fraction }
        return text(out)
    }
}

// MARK: - Arithmetic

enum CalculatorOperator {
    case add, subtract, multiply, divide

    var isMultiplicative: Bool { self == .multiply || self == .divide }

    func apply(_ a: Double, _ b: Double) -> Double {
        switch self {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide: return b == 0 ? Double.nan : a / b
        }
    }
}

/// The calculator's state, without any UI (WatchFaceKit-style: testable on its own)
struct Calculator {
    /// What is being typed (ASCII): digits and at most one comma, maybe a sign first; nil when showing a result
    private(set) var entry: [UInt8]? = [zero]
    private(set) var value: Double = 0
    /// Waiting for the right-hand side: a + or − (and a × or ÷, which binds tighter)
    private var additive: (left: Double, op: CalculatorOperator)?
    private var multiplicative: (left: Double, op: CalculatorOperator)?
    /// The operator just pressed (shown highlighted; pressing another one replaces it)
    private(set) var selected: CalculatorOperator?
    private(set) var failed = false

    /// AC (all clear) or C (clear the entry)
    var clearsAll: Bool { entry.map { Calculator.isZero($0) } ?? true }

    /// "0" or "-0"
    static func isZero(_ e: [UInt8]) -> Bool {
        e == [zero] || e == [minusByte, zero]
    }

    var display: String {
        if failed { return "Fejl" }
        guard let entry else { return CalculatorFormat.format(value) }
        let negative = entry.first == minusByte
        let body = negative ? Array(entry[1...]) : entry
        // The integer part grouped, the rest (comma and decimals as typed) as is
        let wholeCount = body.prefix { $0 != commaByte }.count
        var out: [UInt8] = negative ? [minusByte] : []
        out += CalculatorFormat.grouped(body[0..<wholeCount])
        out += body[wholeCount...]
        return CalculatorFormat.text(out)
    }

    private var current: Double {
        guard let entry else { return value }
        var whole: Double = 0, fraction: Double = 0, scale: Double = 1
        var afterComma = false
        for c in entry {
            if c == commaByte {
                afterComma = true
            } else if c >= zero && c <= nine {
                let d = Double(Int(c) - 48)
                if afterComma {
                    scale /= 10
                    fraction += d * scale
                } else {
                    whole = whole * 10 + d
                }
            }
        }
        let v = whole + fraction
        return entry.first == minusByte ? -v : v
    }

    mutating func digit(_ d: Int) {
        if failed { clear() }
        selected = nil
        var e = entry ?? [zero]
        let digitCount = e.filter { $0 >= zero && $0 <= nine }.count
        let digit = zero + UInt8(d)
        if Calculator.isZero(e) {
            e[e.count - 1] = digit
        } else if digitCount < maxDigits {
            e.append(digit)
        }
        entry = e
    }

    mutating func comma() {
        if failed { clear() }
        selected = nil
        var e = entry ?? [zero]
        if !e.contains(commaByte) { e.append(commaByte) }
        entry = e
    }

    mutating func toggleSign() {
        if failed { return }
        if selected != nil {
            // Right after an operator: the next number starts negative
            entry = [minusByte, zero]
            selected = nil
        } else if let e = entry {
            entry = e.first == minusByte ? Array(e[1...]) : [minusByte] + e
        } else {
            value = -value  // A result
        }
    }

    mutating func percent() {
        if failed { return }
        value = current / 100
        entry = nil
        selected = nil
    }

    mutating func operation(_ op: CalculatorOperator) {
        if failed { return }
        if selected != nil {
            // Another operator instead of the one just pressed (its left-hand side is the number shown)
            if let m = multiplicative {
                if op.isMultiplicative {
                    multiplicative = (m.left, op)
                } else {
                    // 2 + 3 × then −: 2 + 3 = 5, then −
                    multiplicative = nil
                    resolveAdditive(m.left, op)
                }
            } else if let a = additive {
                if op.isMultiplicative {
                    // 2 + then ×: 2 ×
                    additive = nil
                    multiplicative = (a.left, op)
                } else {
                    additive = (a.left, op)
                }
            }
            selected = op
            return
        }
        var v = current
        if let m = multiplicative {
            v = m.op.apply(m.left, v)
            multiplicative = nil
        }
        if op.isMultiplicative {
            multiplicative = (v, op)
            value = v
        } else {
            resolveAdditive(v, op)
        }
        entry = nil
        selected = op
        failed = value.isNaN || value.isInfinite
    }

    private mutating func resolveAdditive(_ v: Double, _ op: CalculatorOperator) {
        var v = v
        if let a = additive { v = a.op.apply(a.left, v) }
        additive = (v, op)
        value = v
    }

    mutating func equals() {
        if failed { return }
        var v = current
        if let m = multiplicative { v = m.op.apply(m.left, v) }
        if let a = additive { v = a.op.apply(a.left, v) }
        multiplicative = nil
        additive = nil
        value = v
        entry = nil
        selected = nil
        failed = v.isNaN || v.isInfinite
    }

    mutating func clear() {
        if clearsAll || failed {
            self = Calculator()
        } else {
            entry = [zero]
        }
    }
}

// MARK: - UI

private enum KeyKind {
    case digit(Int), comma, clear, sign, percent, op(CalculatorOperator), equals
}

private final class Key {
    let kind: KeyKind
    let obj: LVObj
    let label: LVObj?

    init(kind: KeyKind, obj: LVObj, label: LVObj?) {
        self.kind = kind
        self.obj = obj
        self.label = label
    }

    var isOperator: Bool {
        switch kind {
        case .op, .equals: return true
        default: return false
        }
    }
}

private final class CalculatorUI {
    private var calc = Calculator()
    private var keys: [Key] = []
    private let display: LVObj
    private var clearLabel: LVObj?

    init(screen: LVObj) {
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)

        // Clear of the screen's rounded corners at the bottom (at 18 the bottom row was cut off)
        let side: Int32 = 20, gap: Int32 = 10, bottom: Int32 = 32
        let width = Int32(WatchScreen.width), height = Int32(WatchScreen.height)
        let keyW = (width - 2 * side - 3 * gap) / 4
        let keyH: Int32 = 64
        let top = height - bottom - 5 * keyH - 4 * gap

        display = lv_label_create(screen)!
        lv_obj_set_width(display, width - 2 * side - 10)
        lv_obj_set_style_text_align(display, LV_TEXT_ALIGN_RIGHT, partMain)
        lv_obj_set_style_text_color(display, lv_color_white(), partMain)
        lv_label_set_long_mode(display, LV_LABEL_LONG_MODE_CLIP)
        lv_obj_set_pos(display, side, top - 64)

        let rows: [[KeyKind]] = [
            [.clear, .sign, .percent, .op(.divide)],
            [.digit(7), .digit(8), .digit(9), .op(.multiply)],
            [.digit(4), .digit(5), .digit(6), .op(.subtract)],
            [.digit(1), .digit(2), .digit(3), .op(.add)],
            [.digit(0), .comma, .equals],
        ]
        for (r, row) in rows.enumerated() {
            var x = side
            for kind in row {
                // 0 takes two columns, as on the Apple Watch
                var w = keyW
                if case .digit(0) = kind { w = 2 * keyW + gap }
                addKey(screen, kind, x: x, y: top + Int32(r) * (keyH + gap), w: w, h: keyH)
                x += w + gap
            }
        }
        refresh()
    }

    private func addKey(_ screen: LVObj, _ kind: KeyKind, x: Int32, y: Int32, w: Int32, h: Int32) {
        let obj = lvPlainObject(screen)
        lv_obj_set_pos(obj, x, y)
        lv_obj_set_size(obj, w, h)
        lv_obj_set_style_radius(obj, h / 2, partMain)
        lv_obj_set_style_bg_opa(obj, 255, partMain)
        lv_obj_add_flag(obj, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(obj, LV_OBJ_FLAG_GESTURE_BUBBLE)
        let pressed = partMain | lv_style_selector_t(LV_STATE_PRESSED.rawValue)
        var text: String?
        var textColor = lv_color_white()
        switch kind {
        case .digit(let d):
            text = "\(d)"
            lv_obj_set_style_bg_color(obj, lvColor(darkGrey), partMain)
            lv_obj_set_style_bg_color(obj, lvColor(pressedDark), pressed)
        case .comma:
            text = ","
            lv_obj_set_style_bg_color(obj, lvColor(darkGrey), partMain)
            lv_obj_set_style_bg_color(obj, lvColor(pressedDark), pressed)
        case .clear, .percent:
            text = { if case .clear = kind { return "AC" } else { return "%" } }()
            textColor = lv_color_black()
            lv_obj_set_style_bg_color(obj, lvColor(lightGrey), partMain)
            lv_obj_set_style_bg_color(obj, lvColor(pressedLight), pressed)
        case .sign:
            textColor = lv_color_black()
            lv_obj_set_style_bg_color(obj, lvColor(lightGrey), partMain)
            lv_obj_set_style_bg_color(obj, lvColor(pressedLight), pressed)
        case .op, .equals:
            lv_obj_set_style_bg_color(obj, lvColor(orange), partMain)
            lv_obj_set_style_bg_color(obj, lvColor(pressedOrange), pressed)
        }
        var label: LVObj?
        if let text {
            let l = lv_label_create(obj)!
            lv_obj_set_style_text_font(l, wf_builtin_font(text.utf8.count > 1 ? 30 : 36), partMain)
            lv_obj_set_style_text_color(l, textColor, partMain)
            lvSetText(l, text)
            // The 0 key's digit sits where the other digits do (left), as on the Apple Watch
            if case .digit(0) = kind {
                lv_obj_align(l, LV_ALIGN_LEFT_MID, (h - 20) / 2 + 2, 0)
            } else {
                lv_obj_center(l)
            }
            label = l
        }
        let key = Key(kind: kind, obj: obj, label: label)
        keys.append(key)
        if case .clear = kind { clearLabel = label }
        let ud = Unmanaged.passUnretained(key).toOpaque()
        lv_obj_add_event_cb(obj, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            let key = Unmanaged<Key>.fromOpaque(ud).takeUnretainedValue()
            calculatorUI?.pressed(key)
        }, LV_EVENT_CLICKED, ud)
        if text == nil {
            lv_obj_add_event_cb(obj, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                let key = Unmanaged<Key>.fromOpaque(ud).takeUnretainedValue()
                calculatorUI?.drawSymbol(key, e)
            }, LV_EVENT_DRAW_MAIN, ud)
        }
    }

    func pressed(_ key: Key) {
        switch key.kind {
        case .digit(let d): calc.digit(d)
        case .comma: calc.comma()
        case .clear: calc.clear()
        case .sign: calc.toggleSign()
        case .percent: calc.percent()
        case .op(let op): calc.operation(op)
        case .equals: calc.equals()
        }
        refresh()
    }

    private func refresh() {
        let text = calc.display
        let length = text.utf8.count
        lv_obj_set_style_text_font(display, wf_builtin_font(length <= 8 ? 44 : (length <= 10 ? 36 : 30)), partMain)
        lvSetText(display, text)
        if let clearLabel { lvSetText(clearLabel, calc.clearsAll ? "AC" : "C") }
        // The chosen operator: white, its symbol orange
        for key in keys {
            guard case .op(let op) = key.kind else { continue }
            let chosen = calc.selected == op
            lv_obj_set_style_bg_color(key.obj, chosen ? lv_color_white() : lvColor(orange), partMain)
            lv_obj_invalidate(key.obj)
        }
    }

    // MARK: Symbols (Montserrat has no × ÷ − ±): drawn as lines

    func drawSymbol(_ key: Key, _ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var area = lv_area_t()
        lv_obj_get_coords(key.obj, &area)
        let cx = (area.x1 + area.x2) / 2, cy = (area.y1 + area.y2) / 2
        var color = lv_color_white()
        switch key.kind {
        case .op(let op): if calc.selected == op { color = lvColor(orange) }
        case .sign: color = lv_color_black()
        default: break
        }
        let s: Int32 = 13   // Half the symbol's size
        let w: Int32 = 5
        func line(_ x1: Int32, _ y1: Int32, _ x2: Int32, _ y2: Int32, width: Int32 = w) {
            var dsc = lv_draw_line_dsc_t()
            lv_draw_line_dsc_init(&dsc)
            dsc.p1 = wf_point(cx + x1, cy + y1)
            dsc.p2 = wf_point(cx + x2, cy + y2)
            dsc.width = width
            dsc.color = color
            dsc.opa = 255
            dsc.round_start = 1
            dsc.round_end = 1
            lv_draw_line(layer, &dsc)
        }
        func dot(_ x: Int32, _ y: Int32) {
            var dsc = lv_draw_rect_dsc_t()
            lv_draw_rect_dsc_init(&dsc)
            dsc.bg_color = color
            dsc.bg_opa = 255
            dsc.radius = wf_radius_circle()
            var a = lv_area_t(x1: cx + x - 3, y1: cy + y - 3, x2: cx + x + 3, y2: cy + y + 3)
            lv_draw_rect(layer, &dsc, &a)
        }
        switch key.kind {
        case .op(.add):
            line(-s, 0, s, 0)
            line(0, -s, 0, s)
        case .op(.subtract):
            line(-s, 0, s, 0)
        case .op(.multiply):
            let d = s * 3 / 4
            line(-d, -d, d, d)
            line(-d, d, d, -d)
        case .op(.divide):
            line(-s, 0, s, 0)
            dot(0, -s + 2)
            dot(0, s - 2)
        case .equals:
            line(-s, -6, s, -6)
            line(-s, 6, s, 6)
        case .sign:
            // A small + up left, a slash, a small − down right
            line(-14, -8, -4, -8, width: 4)
            line(-9, -13, -9, -3, width: 4)
            line(-3, 12, 5, -12, width: 3)
            line(4, 9, 14, 9, width: 4)
        default:
            break
        }
    }
}

nonisolated(unsafe) private var calculatorUI: CalculatorUI?

@_cdecl("calculator_app_show")
public func calculator_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    calculatorUI = CalculatorUI(screen: screen)
}

@_cdecl("calculator_app_hide")
public func calculator_app_hide() {
    // The objects are deleted by the app framework after this; their callbacks point at the keys, so the UI is kept
    // until the next show
}
