// Encoding and decoding of WatchFace in the face file format; the tag numbers are the format, see
// docs/watch-face-format.md. Rules for changing it:
//   - never reuse or renumber a tag, never change the type of an existing tag
//   - new fields get new tags and a default that matches the old behaviour (decoders start from the defaults)
//   - new element/background kinds get new variant tags; old readers skip them (or keep them as .unknown)

public enum FaceFile {
    public static let magic: [UInt8] = [0x57, 0x46, 0x43, 0x45] // "WFCE"
    public static let version: UInt8 = 1
    public static let maxElements = 32
    public static let maxHands = 4
    public static let maxStops = 8
}

extension WatchFace {
    public func encoded() -> [UInt8] {
        var w = TLVWriter()
        w.appendRaw(FaceFile.magic)
        w.appendRaw([FaceFile.version])
        w.string(1, id)
        w.string(2, name)
        w.nested(3) { background.encode(into: &$0) }
        for element in elements {
            w.nested(4) { element.encode(into: &$0) }
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws(FaceDecodingError) {
        guard bytes.count >= 5, Array(bytes[0..<4]) == FaceFile.magic else { throw .badMagic }
        guard bytes[4] == FaceFile.version else { throw .unsupportedVersion(bytes[4]) }
        self.init(id: "", name: "")
        var r = TLVReader(bytes[5...])
        while let (tag, v) = try r.next() {
            switch tag {
            case 1: id = try v.string()
            case 2: name = try v.string()
            case 3: background = try Background(decoding: v)
            case 4:
                guard elements.count < FaceFile.maxElements else { throw .invalid }
                elements.append(try Element(decoding: v))
            default: break
            }
        }
        guard FaceID.isValid(id) else { throw .invalid }
    }
}

public enum FaceID {
    /// Same rule as file ids on the watch: 1-31 characters from A-Z a-z 0-9 _ -
    public static func isValid(_ id: String) -> Bool {
        let utf8 = id.utf8
        guard (1...31).contains(utf8.count) else { return false }
        for c in utf8 {
            let ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
                || c == 0x2D
            if !ok { return false }
        }
        return true
    }
}

// MARK: - Shared pieces

extension Placement {
    func encode(into w: inout TLVWriter) {
        w.sint(1, x)
        w.sint(2, y)
        w.uint(3, Int(anchor.rawValue))
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self.init(x: 0, y: 0)
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: x = try f.sint()
            case 2: y = try f.sint()
            case 3: anchor = PlacementAnchor(rawValue: UInt8(clamping: try f.uint())) ?? .center
            default: break
            }
        }
    }
}

extension FontRef {
    func encode(into w: inout TLVWriter) {
        switch self {
        case .builtin(let size): w.uint(1, size)
        case .asset(let id): w.string(2, id)
        }
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self = .builtin(size: 20)
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: self = .builtin(size: try f.uint())
            case 2: self = .asset(id: try f.string())
            default: break
            }
        }
    }
}

extension TextStyle {
    func encode(into w: inout TLVWriter) {
        w.nested(1) { font.encode(into: &$0) }
        w.color(2, color)
        w.sint(3, letterSpacing)
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self.init()
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: font = try FontRef(decoding: f)
            case 2: color = try f.color()
            case 3: letterSpacing = try f.sint()
            default: break
            }
        }
    }
}

extension GradientStop {
    func encode(into w: inout TLVWriter) {
        w.color(1, color)
        w.uint(2, location)
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self.init(color: .black, location: 0)
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: color = try f.color()
            case 2: location = min(255, try f.uint())
            default: break
            }
        }
    }
}

private func decodeStop(_ f: TLVValue, into stops: inout [GradientStop]) throws(FaceDecodingError) {
    guard stops.count < FaceFile.maxStops else { throw .invalid }
    stops.append(try GradientStop(decoding: f))
}

// MARK: - Background

extension Background {
    func encode(into w: inout TLVWriter) {
        switch self {
        case .color(let c):
            w.color(1, c)
        case .linearGradient(let g):
            w.nested(2) { w in
                for s in g.stops { w.nested(1) { s.encode(into: &$0) } }
                w.uint(2, g.angle)
            }
        case .radialGradient(let g):
            w.nested(3) { w in
                for s in g.stops { w.nested(1) { s.encode(into: &$0) } }
                w.sint(2, g.centerX)
                w.sint(3, g.centerY)
                w.uint(4, g.radius)
            }
        case .pattern(let p):
            w.nested(4) { w in
                w.uint(1, Int(p.kind.rawValue))
                w.color(2, p.foreground)
                w.color(3, p.background)
                w.uint(4, p.spacing)
                w.uint(5, p.size)
            }
        case .image(let i):
            w.nested(5) { w in
                w.string(1, i.assetID)
                w.color(2, i.fallback)
                if i.dim > 0 { w.uint(3, i.dim) }
            }
        case .unknown(let tag, let payload):
            w.raw(tag, payload)
        }
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self = .color(.black)
        var r = v.records
        guard let (tag, f) = try r.next() else { return }
        var fields = f.records
        switch tag {
        case 1:
            self = .color(try f.color())
        case 2:
            var g = LinearGradient(stops: [])
            while let (t, x) = try fields.next() {
                switch t {
                case 1: try decodeStop(x, into: &g.stops)
                case 2: g.angle = try x.uint() % 360
                default: break
                }
            }
            self = .linearGradient(g)
        case 3:
            var g = RadialGradient(stops: [])
            while let (t, x) = try fields.next() {
                switch t {
                case 1: try decodeStop(x, into: &g.stops)
                case 2: g.centerX = try x.sint()
                case 3: g.centerY = try x.sint()
                case 4: g.radius = try x.uint()
                default: break
                }
            }
            self = .radialGradient(g)
        case 4:
            var p = Pattern(kind: .stripes, foreground: .white, background: .black)
            while let (t, x) = try fields.next() {
                switch t {
                case 1: p.kind = PatternKind(rawValue: UInt8(clamping: try x.uint())) ?? .stripes
                case 2: p.foreground = try x.color()
                case 3: p.background = try x.color()
                case 4: p.spacing = min(64, max(4, try x.uint()))
                case 5: p.size = min(64, max(1, try x.uint()))
                default: break
                }
            }
            self = .pattern(p)
        case 5:
            var i = ImageBackground(assetID: "")
            while let (t, x) = try fields.next() {
                switch t {
                case 1: i.assetID = try x.string()
                case 2: i.fallback = try x.color()
                case 3: i.dim = min(100, try x.uint())
                default: break
                }
            }
            self = .image(i)
        default:
            self = .unknown(tag: tag, payload: f.bytes)
        }
    }
}

// MARK: - Elements

extension Element {
    func encode(into w: inout TLVWriter) {
        switch self {
        case .digitalTime(let e):
            w.nested(1) { w in
                w.nested(1) { e.placement.encode(into: &$0) }
                w.nested(2) { e.style.encode(into: &$0) }
                w.uint(3, Int(e.hourFormat.rawValue))
                w.bool(4, e.showSeconds)
                w.bool(5, e.leadingZero)
            }
        case .date(let e):
            w.nested(2) { w in
                w.nested(1) { e.placement.encode(into: &$0) }
                w.nested(2) { e.style.encode(into: &$0) }
                w.uint(3, Int(e.format.rawValue))
                w.bool(4, e.uppercase)
            }
        case .analogClock(let e):
            w.nested(3) { e.encode(into: &$0) }
        case .steps(let e):
            w.nested(4) { w in
                w.nested(1) { e.placement.encode(into: &$0) }
                w.uint(2, Int(e.style.rawValue))
                w.nested(3) { e.text.encode(into: &$0) }
                w.uint(4, e.goal)
                w.uint(5, e.radius)
                w.uint(6, e.ringWidth)
                w.color(7, e.ringColor)
                w.color(8, e.trackColor)
            }
        case .battery(let e):
            w.nested(5) { w in
                w.nested(1) { e.placement.encode(into: &$0) }
                w.uint(2, Int(e.style.rawValue))
                w.nested(3) { e.text.encode(into: &$0) }
            }
        case .text(let e):
            w.nested(6) { w in
                w.nested(1) { e.placement.encode(into: &$0) }
                w.nested(2) { e.style.encode(into: &$0) }
                w.string(3, e.text)
            }
        case .unknown(let tag, let payload):
            w.raw(tag, payload)
        }
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        var r = v.records
        guard let (tag, f) = try r.next() else { throw .invalid }
        var fields = f.records
        switch tag {
        case 1:
            var e = DigitalTime(placement: Placement(x: 0, y: 0))
            while let (t, x) = try fields.next() {
                switch t {
                case 1: e.placement = try Placement(decoding: x)
                case 2: e.style = try TextStyle(decoding: x)
                case 3: e.hourFormat = HourFormat(rawValue: UInt8(clamping: try x.uint())) ?? .h24
                case 4: e.showSeconds = try x.bool()
                case 5: e.leadingZero = try x.bool()
                default: break
                }
            }
            self = .digitalTime(e)
        case 2:
            var e = DateText(placement: Placement(x: 0, y: 0))
            while let (t, x) = try fields.next() {
                switch t {
                case 1: e.placement = try Placement(decoding: x)
                case 2: e.style = try TextStyle(decoding: x)
                case 3: e.format = DateFormat(rawValue: UInt8(clamping: try x.uint())) ?? .weekdayDayMonth
                case 4: e.uppercase = try x.bool()
                default: break
                }
            }
            self = .date(e)
        case 3:
            self = .analogClock(try AnalogClock(decoding: f))
        case 4:
            var e = Steps(placement: Placement(x: 0, y: 0))
            while let (t, x) = try fields.next() {
                switch t {
                case 1: e.placement = try Placement(decoding: x)
                case 2: e.style = StepsStyle(rawValue: UInt8(clamping: try x.uint())) ?? .text
                case 3: e.text = try TextStyle(decoding: x)
                case 4: e.goal = max(1, try x.uint())
                case 5: e.radius = try x.uint()
                case 6: e.ringWidth = try x.uint()
                case 7: e.ringColor = try x.color()
                case 8: e.trackColor = try x.color()
                default: break
                }
            }
            self = .steps(e)
        case 5:
            var e = Battery(placement: Placement(x: 0, y: 0))
            while let (t, x) = try fields.next() {
                switch t {
                case 1: e.placement = try Placement(decoding: x)
                case 2: e.style = BatteryStyle(rawValue: UInt8(clamping: try x.uint())) ?? .text
                case 3: e.text = try TextStyle(decoding: x)
                default: break
                }
            }
            self = .battery(e)
        case 6:
            var e = StaticText(placement: Placement(x: 0, y: 0), text: "")
            while let (t, x) = try fields.next() {
                switch t {
                case 1: e.placement = try Placement(decoding: x)
                case 2: e.style = try TextStyle(decoding: x)
                case 3: e.text = try x.string()
                default: break
                }
            }
            self = .text(e)
        default:
            self = .unknown(tag: tag, payload: f.bytes)
        }
    }
}

extension TickStyle {
    func encode(into w: inout TLVWriter) {
        w.uint(1, length)
        w.uint(2, width)
        w.color(3, color)
    }

    init(decoding v: TLVValue, default d: TickStyle) throws(FaceDecodingError) {
        self = d
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: length = try f.uint()
            case 2: width = try f.uint()
            case 3: color = try f.color()
            default: break
            }
        }
    }
}

extension Hand {
    func encode(into w: inout TLVWriter) {
        w.uint(1, Int(kind.rawValue))
        w.uint(2, Int(shape.rawValue))
        w.uint(3, length)
        w.uint(4, tail)
        w.uint(5, width)
        w.color(6, color)
        w.bool(7, smooth)
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self.init(kind: .hour, length: 100, width: 6)
        var r = v.records
        while let (tag, f) = try r.next() {
            switch tag {
            case 1: kind = HandKind(rawValue: UInt8(clamping: try f.uint())) ?? .hour
            case 2: shape = HandShape(rawValue: UInt8(clamping: try f.uint())) ?? .rounded
            case 3: length = min(WatchScreen.height, try f.uint())
            case 4: tail = min(WatchScreen.height, try f.uint())
            case 5: width = min(64, max(1, try f.uint()))
            case 6: color = try f.color()
            case 7: smooth = try f.bool()
            default: break
            }
        }
    }
}

extension AnalogClock {
    func encode(into w: inout TLVWriter) {
        w.sint(1, centerX)
        w.sint(2, centerY)
        w.uint(3, radius)
        w.nested(4) { w in
            w.color(1, dial.fill)
            w.color(2, dial.borderColor)
            w.uint(3, dial.borderWidth)
        }
        w.nested(5) { w in
            w.uint(1, Int(ticks.mode.rawValue))
            w.nested(2) { ticks.major.encode(into: &$0) }
            w.nested(3) { ticks.minor.encode(into: &$0) }
            w.uint(4, ticks.inset)
        }
        w.nested(6) { w in
            switch numerals.mode {
            case .hidden: w.uint(1, 0)
            case .all: w.uint(1, 1)
            case .everyThird: w.uint(1, 2)
            case .custom(let mask):
                w.uint(1, 3)
                w.uint(2, Int(mask))
            }
            w.nested(3) { numerals.style.encode(into: &$0) }
            w.uint(4, numerals.inset)
            w.bool(5, numerals.roman)
        }
        for hand in hands {
            w.nested(7) { hand.encode(into: &$0) }
        }
        w.uint(8, capRadius)
        w.color(9, capColor)
    }

    init(decoding v: TLVValue) throws(FaceDecodingError) {
        self.init()
        var r = v.records
        while let (tag, f) = try r.next() {
            var fields = f.records
            switch tag {
            case 1: centerX = try f.sint()
            case 2: centerY = try f.sint()
            case 3: radius = min(WatchScreen.height, try f.uint())
            case 4:
                while let (t, x) = try fields.next() {
                    switch t {
                    case 1: dial.fill = try x.color()
                    case 2: dial.borderColor = try x.color()
                    case 3: dial.borderWidth = min(64, try x.uint())
                    default: break
                    }
                }
            case 5:
                while let (t, x) = try fields.next() {
                    switch t {
                    case 1: ticks.mode = TickMode(rawValue: UInt8(clamping: try x.uint())) ?? .hidden
                    case 2: ticks.major = try TickStyle(decoding: x, default: ticks.major)
                    case 3: ticks.minor = try TickStyle(decoding: x, default: ticks.minor)
                    case 4: ticks.inset = try x.uint()
                    default: break
                    }
                }
            case 6:
                var mode = 0
                var mask: UInt16 = 0
                while let (t, x) = try fields.next() {
                    switch t {
                    case 1: mode = try x.uint()
                    case 2: mask = UInt16(truncatingIfNeeded: try x.uint())
                    case 3: numerals.style = try TextStyle(decoding: x)
                    case 4: numerals.inset = try x.uint()
                    case 5: numerals.roman = try x.bool()
                    default: break
                    }
                }
                switch mode {
                case 1: numerals.mode = .all
                case 2: numerals.mode = .everyThird
                case 3: numerals.mode = .custom(mask: mask)
                default: numerals.mode = .hidden
                }
            case 7:
                guard hands.count < FaceFile.maxHands else { throw .invalid }
                hands.append(try Hand(decoding: f))
            case 8: capRadius = min(64, try f.uint())
            case 9: capColor = try f.color()
            default: break
            }
        }
    }
}
