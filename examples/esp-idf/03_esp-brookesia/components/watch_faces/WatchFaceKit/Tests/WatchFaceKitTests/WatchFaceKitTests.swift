import Testing
@testable import WatchFaceKit

@Suite struct CodecTests {
    @Test(arguments: WatchFace.builtins.map(\.id))
    func builtinsRoundTrip(id: String) throws {
        let face = try #require(WatchFace.builtins.first { $0.id == id })
        let decoded = try WatchFace(decoding: face.encoded())
        #expect(decoded == face)
    }

    @Test func everyElementAndBackgroundRoundTrips() throws {
        let style = TextStyle(font: .asset(id: "font_1"), color: FaceColor(rgb: 0x123456, a: 200), letterSpacing: -3)
        let backgrounds: [Background] = [
            .color(FaceColor(rgb: 0xABCDEF)),
            .linearGradient(LinearGradient(stops: [GradientStop(color: .white, location: 10)], angle: 45)),
            .radialGradient(RadialGradient(stops: [GradientStop(color: .black, location: 255)], centerX: -5,
                                           centerY: 600, radius: 10)),
            .pattern(Pattern(kind: .checker, foreground: .white, background: .black, spacing: 20, size: 7)),
            .image(ImageBackground(assetID: "bg_1", fallback: FaceColor(rgb: 0x112233))),
            .image(ImageBackground(assetID: "bg_2", fallback: .black, dim: 40)),
            .unknown(tag: 99, payload: [1, 2, 3]),
        ]
        for background in backgrounds {
            let face = WatchFace(id: "all", name: "Alt – æøå", background: background, elements: [
                .digitalTime(DigitalTime(placement: Placement(x: -10, y: 20, anchor: .bottomTrailing), style: style,
                                         hourFormat: .h12, showSeconds: true, leadingZero: false)),
                .date(DateText(placement: Placement(x: 1, y: 2), style: style, format: .numeric, uppercase: true)),
                .analogClock(AnalogClock(
                    centerX: 100, centerY: 120, radius: 90,
                    dial: Dial(fill: FaceColor(rgb: 0x010203), borderColor: FaceColor(rgb: 0x040506), borderWidth: 3),
                    ticks: Ticks(mode: .hours, major: TickStyle(length: 9, width: 3), minor: TickStyle(length: 2, width: 1),
                                 inset: 7),
                    numerals: Numerals(mode: .custom(mask: 0b1001_0010_0101), style: style, inset: 12, roman: true),
                    hands: HandShape.allCases.prefix(3).enumerated().map { i, shape in
                        Hand(kind: HandKind(rawValue: UInt8(i))!, shape: shape, length: 50 + i, tail: i, width: 3 + i,
                             color: FaceColor(rgb: UInt32(i)), smooth: i == 2)
                    },
                    capRadius: 5, capColor: FaceColor(rgb: 0xFF0000))),
                .steps(Steps(placement: Placement(x: 5, y: 6), style: .ring, text: style, goal: 10000, radius: 33,
                             ringWidth: 4, ringColor: .white, trackColor: .black)),
                .battery(Battery(placement: Placement(x: 7, y: 8, anchor: .topLeading), style: .bar, text: style)),
                .text(StaticText(placement: Placement(x: 9, y: 10), style: style, text: "Hej")),
                .unknown(tag: 77, payload: [9, 8, 7]),
            ])
            #expect(try WatchFace(decoding: face.encoded()) == face)
        }
    }

    @Test func unknownTagsInsideKnownRecordsAreSkipped() throws {
        var w = TLVWriter()
        w.appendRaw(FaceFile.magic)
        w.appendRaw([FaceFile.version])
        w.string(1, "f1")
        w.string(500, "a field from the future")
        w.nested(4) { w in
            w.nested(1) { w in
                w.uint(3, 1)
                w.nested(42) { $0.uint(1, 7) }
            }
        }
        let face = try WatchFace(decoding: w.bytes)
        #expect(face.id == "f1")
        guard case .digitalTime(let time) = face.elements.first else {
            Issue.record("expected digital time")
            return
        }
        #expect(time.hourFormat == .h12)
    }

    @Test func rejectsBadInput() {
        #expect(throws: FaceDecodingError.badMagic) { try WatchFace(decoding: [1, 2, 3, 4, 5]) }
        #expect(throws: FaceDecodingError.unsupportedVersion(9)) { try WatchFace(decoding: FaceFile.magic + [9]) }
        var face = WatchFace.classic.encoded()
        face.removeLast(3)
        #expect(throws: FaceDecodingError.truncated) { try WatchFace(decoding: face) }
        #expect(throws: FaceDecodingError.invalid) {
            try WatchFace(decoding: WatchFace(id: "not valid!", name: "").encoded())
        }
    }

    @Test func varints() throws {
        for value: Int in [0, 1, 127, 128, 300, 16384, Int(Int32.max)] {
            var w = TLVWriter()
            w.uint(1, value)
            var r = TLVReader(w.bytes)
            #expect(try r.next()?.value.uint() == value)
        }
        for value: Int in [0, -1, 1, -64, 64, -100_000, Int(Int32.min)] {
            var w = TLVWriter()
            w.sint(1, value)
            var r = TLVReader(w.bytes)
            #expect(try r.next()?.value.sint() == value)
        }
    }

    /// The exact bytes of a small face; if this changes, the format changed (and old files may no longer decode)
    @Test func goldenBytes() {
        let face = WatchFace(id: "a", name: "B", background: .color(FaceColor(rgb: 0x010203)), elements: [
            .text(StaticText(placement: Placement(x: -1, y: 2), text: "x"))
        ])
        let hex = face.encoded().map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        #expect(hex == "5746434501" // magic, version
            + "010161" + "020142" // id "a", name "B"
            + "0306" + "0104010203ff" // background: color
            + "0420" + "061e" // element: text
            + "0109" + "010101" + "020104" + "030104" // placement x -1, y 2, anchor center
            + "020e" + "0103" + "010114" + "0204ffffffff" + "030100" // style: builtin 20, white, spacing 0
            + "030178") // text "x"
    }
}

@Suite struct GeometryTests {
    @Test func sineMatchesKnownValues() {
        let cases: [(Float, Float)] = [(0, 0), (FaceMath.pi / 6, 0.5), (FaceMath.pi / 2, 1), (FaceMath.pi, 0),
                                       (-FaceMath.pi / 2, -1), (7 * FaceMath.pi / 2, -1), (100, -0.50636564)]
        for (x, expected) in cases {
            #expect(abs(FaceMath.sin(x) - expected) < 1e-5)
        }
    }

    @Test func handAngles() {
        let t = WallTime(year: 2026, month: 10, day: 20, weekday: 2, hour: 15, minute: 30, second: 45,
                         millisecond: 500)
        #expect(Hand(kind: .hour, length: 1, width: 1).angleTenths(at: t) == 3 * 300 + 150)
        #expect(Hand(kind: .minute, length: 1, width: 1).angleTenths(at: t) == 30 * 60 + 45)
        #expect(Hand(kind: .second, length: 1, width: 1).angleTenths(at: t) == 45 * 60)
        #expect(Hand(kind: .second, length: 1, width: 1, smooth: true).angleTenths(at: t) == 45 * 60 + 30)
    }

    @Test(arguments: HandShape.allCases)
    func handMaskCoversTheHand(shape: HandShape) {
        let hand = Hand(kind: .minute, shape: shape, length: 100, tail: 20, width: 10)
        let mask = HandMask(hand: hand)
        #expect(mask.alpha.count == mask.width * mask.height)
        // The pivot and a point halfway up the shaft are inside; the corners are empty
        #expect(mask.alpha[mask.pivotY * mask.width + mask.pivotX] == 255)
        #expect(mask.alpha[(mask.pivotY - 50) * mask.width + mask.pivotX] == 255)
        #expect(mask.alpha[0] == 0)
        #expect(mask.alpha[mask.alpha.count - 1] == 0)
        #expect(mask.height >= 120 && mask.height <= 125)
    }

    @Test func ticksAndNumerals() {
        var clock = AnalogClock(centerX: 200, centerY: 250, radius: 100)
        clock.ticks.mode = .hours
        #expect(clock.tickSegments().count == 12)
        clock.ticks.mode = .hoursAndMinutes
        #expect(clock.tickSegments().count == 60)

        clock.numerals = Numerals(mode: .everyThird, inset: 20)
        let labels = clock.numeralLabels()
        #expect(labels.map(\.text) == ["3", "6", "9", "12"])
        let twelve = labels[3].center
        #expect(abs(twelve.x - 200) < 0.01 && abs(twelve.y - 170) < 0.01)
        let three = labels[0].center
        #expect(abs(three.x - 280) < 0.01 && abs(three.y - 250) < 0.01)
    }
}

@Suite struct TextTests {
    let t = WallTime(year: 2026, month: 10, day: 20, weekday: 2, hour: 7, minute: 5, second: 9)

    @Test func time() {
        #expect(FaceText.time(DigitalTime(placement: Placement(x: 0, y: 0)), t) == "07:05")
        #expect(FaceText.time(DigitalTime(placement: Placement(x: 0, y: 0), leadingZero: false), t) == "7:05")
        #expect(FaceText.time(DigitalTime(placement: Placement(x: 0, y: 0), showSeconds: true), t) == "07:05:09")
        var pm = t
        pm.hour = 0
        #expect(FaceText.time(DigitalTime(placement: Placement(x: 0, y: 0), hourFormat: .h12), pm) == "12:05")
        var unset = t
        unset.year = 1970
        #expect(FaceText.time(DigitalTime(placement: Placement(x: 0, y: 0)), unset) == "--:--")
    }

    @Test func date() {
        let p = Placement(x: 0, y: 0)
        #expect(FaceText.date(DateText(placement: p), t) == "Tir 20. okt.")
        #expect(FaceText.date(DateText(placement: p, format: .weekday, uppercase: true), t) == "TIRSDAG")
        #expect(FaceText.date(DateText(placement: p, format: .numeric), t) == "20/10")
    }

    @Test func glyphsCoverTheText() {
        let e = DateText(placement: Placement(x: 0, y: 0), format: .weekdayDayMonth)
        let glyphs = FaceText.glyphs(for: .date(e))
        for weekday in 0..<7 {
            var day = t
            day.weekday = weekday
            for c in FaceText.date(e, day) {
                #expect(glyphs.contains(c))
            }
        }
    }
}

@Suite struct PNGTests {
    /// Builds a PNG whose IDAT holds the raw (not deflated) scanlines; feedInflated is then fed those directly
    func png(width: Int, height: Int, colorType: UInt8, rows: [[UInt8]], palette: [UInt8] = []) -> ([UInt8], [UInt8]) {
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let n = UInt32(data.count)
            return [UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8),
                    UInt8(truncatingIfNeeded: n)] + Array(type.utf8) + data + [0, 0, 0, 0]
        }
        let ihdr: [UInt8] = [0, 0, 0, UInt8(width), 0, 0, 0, UInt8(height), 8, colorType, 0, 0, 0]
        let raw = rows.flatMap { $0 }
        var file = PNGChunkParser.signature + chunk("IHDR", ihdr)
        if !palette.isEmpty { file += chunk("PLTE", palette) }
        file += chunk("IDAT", raw) + chunk("IEND", [])
        return (file, raw)
    }

    func decode(_ file: [UInt8], matte: FaceColor = .black) throws -> (PNGChunkParser, PNGRowDecoder?, [UInt16]) {
        var parser = PNGChunkParser()
        var rows: PNGRowDecoder?
        var pixels: [UInt16] = []
        // Feed in small pieces to exercise the chunk state machine
        var i = 0
        while i < file.count {
            let piece = Array(file[i..<min(file.count, i + 5)])
            try piece.withUnsafeBufferPointer { b throws(PNGError) in
                try parser.feed(b) { idat, header throws(PNGError) in
                    if rows == nil { rows = PNGRowDecoder(header: header, matte: matte) }
                    try rows!.feed(idat) { row in
                        for x in stride(from: 0, to: row.count, by: 2) {
                            pixels.append(UInt16(row[x]) | UInt16(row[x + 1]) << 8)
                        }
                    }
                }
            }
            i += 5
        }
        return (parser, rows, pixels)
    }

    @Test func rgbWithAllFilters() throws {
        // 2x5 RGB; row y uses filter y. The decoded pixels are all (8y, 16x+8, 4) in each row.
        let width = 2
        var rows: [[UInt8]] = []
        var previous = [UInt8](repeating: 0, count: width * 3)
        for filter in 0..<5 {
            var raw: [UInt8] = []
            for x in 0..<width { raw += [UInt8(8 * filter), UInt8(16 * x + 8), 4] }
            var filtered = [UInt8(filter)]
            for i in 0..<raw.count {
                let a = i >= 3 ? Int(raw[i - 3]) : 0
                let b = Int(previous[i])
                let c = i >= 3 ? Int(previous[i - 3]) : 0
                let predictor: Int
                switch filter {
                case 1: predictor = a
                case 2: predictor = b
                case 3: predictor = (a + b) / 2
                case 4:
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    predictor = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                default: predictor = 0
                }
                filtered.append(raw[i] &- UInt8(predictor))
            }
            rows.append(filtered)
            previous = raw
        }
        let (file, _) = png(width: width, height: 5, colorType: 2, rows: rows)
        let (parser, decoder, pixels) = try decode(file)
        #expect(parser.finished && decoder?.isComplete == true)
        #expect(parser.header?.info == PNGInfo(width: 2, height: 5, colorType: 2))
        var expected: [UInt16] = []
        for y in 0..<5 {
            for x in 0..<width { expected.append(RGB565.pack(UInt8(8 * y), UInt8(16 * x + 8), 4)) }
        }
        #expect(pixels == expected)
    }

    @Test func paletteAndAlpha() throws {
        let (file, _) = png(width: 2, height: 1, colorType: 3, rows: [[0, 0, 1]], palette: [255, 0, 0, 0, 0, 255])
        #expect(try decode(file).2 == [RGB565.pack(255, 0, 0), RGB565.pack(0, 0, 255)])

        let (rgba, _) = png(width: 1, height: 1, colorType: 6, rows: [[0, 255, 255, 255, 0]])
        #expect(try decode(rgba, matte: FaceColor(rgb: 0x00FF00)).2 == [RGB565.pack(0, 255, 0)])
    }

    @Test func rejectsWhatItCannotDecode() {
        #expect(throws: PNGError.notPNG) { try decode([1, 2, 3, 4, 5, 6, 7, 8, 9]) }
        var (file, _) = png(width: 1, height: 1, colorType: 2, rows: [[0, 1, 2, 3]])
        file[8 + 8 + 12] = 1 // interlaced
        #expect(throws: PNGError.unsupported) { try decode(file) }
    }

    @Test func lvglHeader() {
        #expect(RGB565.lvglImageHeader(width: 410, height: 502) == [0x19, 0x12, 0, 0, 0x9A, 0x01, 0xF6, 0x01, 0x34, 0x03, 0, 0])
    }
}

@Suite struct BinFontTests {
    @Test func roundTrip() throws {
        let font = BinFont(size: 30, ascent: 28, descent: 7, glyphs: [
            BinFontGlyph(codepoint: 0x31, advance: 17.5, offsetX: 2, offsetY: -1, width: 3, height: 2,
                         alpha: [0, 17, 34, 255, 136, 0]),
            BinFontGlyph(codepoint: 0x20, advance: 8, offsetX: 0, offsetY: 0, width: 0, height: 0, alpha: []),
            BinFontGlyph(codepoint: 0xF8, advance: 16, offsetX: -3, offsetY: -5, width: 1, height: 1, alpha: [255]),
        ])
        let bytes = font.encoded()
        #expect(Array(bytes[4..<8]) == Array("head".utf8))
        #expect(bytes[0] == 48) // LVGL takes the cmap table to start right after head
        let decoded = try BinFont(decoding: bytes)
        #expect(decoded.size == 30 && decoded.ascent == 28 && decoded.descent == 7)
        #expect(decoded.glyphs.map(\.codepoint) == [0x20, 0x31, 0xF8])
        #expect(decoded.glyphs[1] == font.glyphs[0])
        #expect(decoded.glyphs[2].offsetX == -3 && decoded.glyphs[2].offsetY == -5)
    }
}

@Suite struct BirthdayTests {
    func day(_ year: Int, _ month: Int, _ day: Int) -> WallTime {
        WallTime(year: year, month: month, day: day, weekday: 0, hour: 12, minute: 0, second: 0)
    }

    @Test func isToday() throws {
        let birthday = try #require(BirthdayDate(month: 10, day: 22))
        #expect(birthday.isToday(day(2026, 10, 22)))
        #expect(!birthday.isToday(day(2026, 10, 23)))
        #expect(!birthday.isToday(day(1970, 10, 22))) // clock not set
        #expect(BirthdayDate(month: 13, day: 1) == nil)
    }

    @Test func leapDay() throws {
        let birthday = try #require(BirthdayDate(month: 2, day: 29))
        #expect(birthday.isToday(day(2027, 2, 28)))
        #expect(!birthday.isToday(day(2028, 2, 28)))
        #expect(birthday.isToday(day(2028, 2, 29)))
    }

    @Test func fireworksLaunchBurstAndEnd() {
        var fireworks = Fireworks(seed: 42, launchDuration: 2)
        var most = 0
        var lowest = Float(WatchScreen.height)
        for _ in 0..<300 {
            fireworks.step(1.0 / 30)
            most = max(most, fireworks.sparks.count)
            lowest = min(lowest, fireworks.sparks.map(\.y).min() ?? lowest)
            #expect(fireworks.sparks.count <= Fireworks.maxSparks)
        }
        #expect(most > 40) // at least one burst
        #expect(lowest > 0) // bursts stay on screen
        #expect(fireworks.isFinished) // ten seconds is plenty for a two second show
    }

    @Test func flagProportions() {
        let bars = Dannebrog.whiteBars(width: 37)
        #expect(Dannebrog.height(width: 37) == 28)
        #expect(bars.vertical == (12, 0, 4, 28) && bars.horizontal == (0, 12, 37, 4))
    }
}

@Suite struct WeatherTests {
    let report = WeatherReport(
        location: "Aarhus", updated: 1_792_650_000,
        now: WeatherNow(condition: .showers, isDay: false, temperature: -4, feelsLike: -38, wind: 112, gusts: 190),
        days: [
            WeatherDay(year: 2026, month: 10, day: 31, condition: .rain, high: 121, low: 64, precipitation: 35,
                       precipitationProbability: 80, windMax: 90),
            WeatherDay(year: 2026, month: 11, day: 1, condition: .snow, high: 15, low: -22),
            WeatherDay(year: 2026, month: 11, day: 2, condition: .clear, high: 80, low: 10),
        ])

    @Test func roundTrip() throws {
        #expect(try WeatherReport(decoding: report.encoded()) == report)
        #expect(report.encoded().count < 200)
    }

    @Test func wmoCodes() {
        #expect(WeatherCondition(wmo: 0) == .clear && WeatherCondition(wmo: 3) == .cloudy)
        #expect(WeatherCondition(wmo: 63) == .rain && WeatherCondition(wmo: 81) == .showers)
        #expect(WeatherCondition(wmo: 75) == .snow && WeatherCondition(wmo: 95) == .thunder)
        #expect(WeatherCondition(wmo: 1234) == .cloudy)
    }

    @Test func texts() {
        #expect(WeatherText.temperature(-4) == "0°" && WeatherText.temperature(-5) == "-1°")
        #expect(WeatherText.temperature(125) == "13°" && WeatherText.temperature(-38) == "-4°")
        #expect(WeatherText.description(report.now) == "Byger, blæsende")
        let t = WallTime(year: 2026, month: 10, day: 31, weekday: 6, hour: 8, minute: 0, second: 0)
        #expect(report.days.map { WeatherText.dayName($0, today: t) } == ["I dag", "I morgen", "Man 2."])
        #expect(report.days(from: WallTime(year: 2026, month: 11, day: 1, weekday: 0, hour: 0, minute: 0, second: 0)).count == 2)
        #expect(report.days[0].weekday == 6) // 31 Oct 2026 is a Saturday
    }

    @Test func everyConditionHasAnIcon() {
        for condition in WeatherCondition.allCases {
            #expect(!WeatherIcon.shapes(condition, isDay: true, windy: false).isEmpty)
        }
    }
}

@Suite struct DimTests {
    @Test func dimOpacity() {
        #expect(ImageBackground(assetID: "a", dim: 0).dimOpacity == 0)
        #expect(ImageBackground(assetID: "a", dim: 50).dimOpacity == 127)
        #expect(ImageBackground(assetID: "a", dim: 100).dimOpacity == 255)
    }

    @Test func undimmedImagesEncodeAsBefore() {
        // No dim field when it's 0: files read by older firmware stay the same
        let face = WatchFace(id: "a", name: "", background: .image(ImageBackground(assetID: "x")))
        var dimmed = face
        dimmed.background = .image(ImageBackground(assetID: "x", dim: 30))
        #expect(dimmed.encoded().count == face.encoded().count + 3)
    }
}
