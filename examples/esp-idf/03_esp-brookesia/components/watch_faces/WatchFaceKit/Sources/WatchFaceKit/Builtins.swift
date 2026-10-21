// Faces built into the firmware. They need no assets (builtin fonts only). The phone can hide and reorder them,
// and use them as templates; uploading a face with the same id replaces a builtin on that watch.

extension WatchFace {
    public static let builtins: [WatchFace] = [classic, digital, mixed]

    public static let classic = WatchFace(
        id: "klassisk", name: "Klassisk",
        background: .radialGradient(RadialGradient(stops: [
            GradientStop(color: FaceColor(rgb: 0x1C2A3A), location: 0),
            GradientStop(color: FaceColor(rgb: 0x000000), location: 255),
        ], radius: 260)),
        elements: [
            .date(DateText(placement: Placement(x: WatchScreen.width / 2, y: 330),
                           style: TextStyle(font: .builtin(size: 20), color: FaceColor(rgb: 0xB0B8C0)))),
            .analogClock(AnalogClock(
                radius: 195,
                ticks: Ticks(mode: .hoursAndMinutes,
                             major: TickStyle(length: 16, width: 5, color: .white),
                             minor: TickStyle(length: 7, width: 2, color: FaceColor(rgb: 0x707880))),
                numerals: Numerals(mode: .everyThird, style: TextStyle(font: .builtin(size: 32)), inset: 45),
                hands: [
                    Hand(kind: .hour, shape: .tapered, length: 105, tail: 16, width: 12),
                    Hand(kind: .minute, shape: .tapered, length: 160, tail: 16, width: 9),
                    Hand(kind: .second, shape: .line, length: 175, tail: 35, width: 3,
                         color: FaceColor(rgb: 0xFF8A00), smooth: true),
                ],
                capRadius: 8, capColor: FaceColor(rgb: 0xFF8A00))),
        ])

    public static let digital = WatchFace(
        id: "digital", name: "Digital",
        background: .linearGradient(LinearGradient(stops: [
            GradientStop(color: FaceColor(rgb: 0x0B1F3A), location: 0),
            GradientStop(color: FaceColor(rgb: 0x000000), location: 255),
        ], angle: 180)),
        elements: [
            .digitalTime(DigitalTime(placement: Placement(x: WatchScreen.width / 2, y: 190),
                                     style: TextStyle(font: .builtin(size: 66), color: .white, letterSpacing: 2))),
            .date(DateText(placement: Placement(x: WatchScreen.width / 2, y: 260),
                           style: TextStyle(font: .builtin(size: 24), color: FaceColor(rgb: 0x8FB3E0)),
                           format: .weekdayDayMonth)),
            .steps(Steps(placement: Placement(x: WatchScreen.width / 2, y: 390), style: .ring,
                         text: TextStyle(font: .builtin(size: 18)), radius: 50, ringWidth: 8)),
        ])

    public static let mixed = WatchFace(
        id: "blandet", name: "Blandet",
        background: .pattern(Pattern(kind: .dots, foreground: FaceColor(rgb: 0x1A1A1A), background: .black,
                                     spacing: 14, size: 3)),
        elements: [
            .digitalTime(DigitalTime(placement: Placement(x: WatchScreen.width / 2, y: 150),
                                     style: TextStyle(font: .builtin(size: 28), color: FaceColor(rgb: 0xA0A0A0)))),
            .steps(Steps(placement: Placement(x: WatchScreen.width / 2, y: 345), style: .text,
                         text: TextStyle(font: .builtin(size: 20), color: FaceColor(rgb: 0x2ECC71)))),
            .analogClock(AnalogClock(
                radius: 190,
                dial: Dial(borderColor: FaceColor(rgb: 0x404040), borderWidth: 2),
                ticks: Ticks(mode: .hours, major: TickStyle(length: 10, width: 3, color: FaceColor(rgb: 0x909090))),
                numerals: Numerals(mode: .all, style: TextStyle(font: .builtin(size: 26)), inset: 36),
                hands: [
                    Hand(kind: .hour, shape: .sword, length: 100, width: 14, color: FaceColor(rgb: 0xE0E0E0)),
                    Hand(kind: .minute, shape: .sword, length: 150, width: 11, color: FaceColor(rgb: 0xE0E0E0)),
                    Hand(kind: .second, shape: .lollipop, length: 165, tail: 25, width: 4,
                         color: FaceColor(rgb: 0xE74C3C)),
                ],
                capRadius: 6, capColor: FaceColor(rgb: 0xE74C3C))),
        ])
}

/// What a face uses, by name; the watch lists what it can draw in DEVICE_INFO ("face"), and the phone warns
/// before uploading a face that uses something the watch doesn't know.
public enum FaceFeature {
    public static let all: [String] = [
        "bg.color", "bg.linearGradient", "bg.radialGradient", "bg.pattern", "bg.image",
        "digitalTime", "date", "analogClock", "steps", "battery", "text",
        "font.asset",
    ]

    public static func required(by face: WatchFace) -> [String] {
        var features: [String] = []
        func add(_ f: String) {
            if !features.contains(f) { features.append(f) }
        }
        func addFont(_ style: TextStyle) {
            if case .asset = style.font { add("font.asset") }
        }
        switch face.background {
        case .color: add("bg.color")
        case .linearGradient: add("bg.linearGradient")
        case .radialGradient: add("bg.radialGradient")
        case .pattern: add("bg.pattern")
        case .image: add("bg.image")
        case .unknown(let tag, _): add("bg.\(tag)")
        }
        for element in face.elements {
            switch element {
            case .digitalTime(let e): add("digitalTime"); addFont(e.style)
            case .date(let e): add("date"); addFont(e.style)
            case .analogClock(let e): add("analogClock"); addFont(e.numerals.style)
            case .steps(let e): add("steps"); addFont(e.text)
            case .battery(let e): add("battery"); addFont(e.text)
            case .text(let e): add("text"); addFont(e.style)
            case .unknown(let tag, _): add("element.\(tag)")
            }
        }
        return features
    }

    /// Asset ids a face refers to (fonts and background image), each once
    public static func assets(of face: WatchFace) -> [String] {
        var ids: [String] = []
        func add(_ style: TextStyle) {
            if case .asset(let id) = style.font, !ids.contains(id) { ids.append(id) }
        }
        if case .image(let image) = face.background { ids.append(image.assetID) }
        for element in face.elements {
            switch element {
            case .digitalTime(let e): add(e.style)
            case .date(let e): add(e.style)
            case .analogClock(let e): add(e.numerals.style)
            case .steps(let e): add(e.text)
            case .battery(let e): add(e.text)
            case .text(let e): add(e.style)
            case .unknown: break
            }
        }
        return ids
    }
}
