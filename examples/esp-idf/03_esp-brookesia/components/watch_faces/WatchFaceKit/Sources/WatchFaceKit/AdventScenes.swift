// The Julekalender's 24 pictures: Danish Christmas, one for each door. Drawn from simple shapes (IconShape, as the
// weather icons) in a 100 x 120 box (y down), scaled to wherever they're shown: the open door and the little
// picture behind a door in the calendar. The shapes go straight to a sink as they're made (the watch draws each one
// at once: no list of hundreds of shapes in memory).

/// Where a picture's shapes go, in drawing order
public protocol IconShapeSink {
    mutating func add(_ shape: IconShape)
}

/// Collects the shapes (previews, tests)
public struct IconShapeList: IconShapeSink {
    public var shapes: [IconShape] = []

    public init() {}

    public mutating func add(_ shape: IconShape) {
        shapes.append(shape)
    }
}

public enum AdventScene {
    /// The box the shapes are in
    public static let width: Float = 100
    public static let height: Float = 120

    public static func title(_ door: Int) -> String {
        switch door {
        case 1: return "Kravlenissen"
        case 2: return "Et flettet julehjerte"
        case 3: return "Kalenderlyset"
        case 4: return "Pebernødder"
        case 5: return "Flag på juletræet"
        case 6: return "Risengrød med smørhul"
        case 7: return "Nissen på loftet"
        case 8: return "Æbleskiver"
        case 9: return "Kræmmerhuset"
        case 10: return "Brunkager og klejner"
        case 11: return "Marcipangrisen"
        case 12: return "Juleneg til fuglene"
        case 13: return "Santa Lucia"
        case 14: return "Snemanden"
        case 15: return "Landsbykirken"
        case 16: return "Gløgg"
        case 17: return "Adventskransen"
        case 18: return "Julestjernen"
        case 19: return "Juleklokker"
        case 20: return "Dørkransen"
        case 21: return "Vintersolhverv"
        case 22: return "Pakkerne er klar"
        case 23: return "Risalamande"
        default: return "Glædelig jul!"
        }
    }

    public static func shapes(_ door: Int) -> [IconShape] {
        var list = IconShapeList()
        draw(door, into: &list)
        return list.shapes
    }

    public static func draw<Sink: IconShapeSink>(_ door: Int, into sink: inout Sink) {
        var b = SceneBuilder(sink: sink)
        switch door {
        case 1: b.kravlenisse()
        case 2: b.julehjerte()
        case 3: b.kalenderlys()
        case 4: b.pebernodder()
        case 5: b.flagTree()
        case 6: b.risengrod()
        case 7: b.nisseLoft()
        case 8: b.aebleskiver()
        case 9: b.kraemmerhus()
        case 10: b.brunkager()
        case 11: b.marcipangris()
        case 12: b.juleneg()
        case 13: b.lucia()
        case 14: b.snowman()
        case 15: b.church()
        case 16: b.glogg()
        case 17: b.adventskrans()
        case 18: b.julestjerne()
        case 19: b.bells()
        case 20: b.doorWreath()
        case 21: b.solstice()
        case 22: b.presents()
        case 23: b.risalamande()
        default: b.juleaften()
        }
        sink = b.sink
    }
}

// MARK: - Colours

private enum C {
    static let night = FaceColor(rgb: 0x0E1838)
    static let nightLight = FaceColor(rgb: 0x1D2C5C)
    static let snow = FaceColor(rgb: 0xF4F7FB)
    static let snowShade = FaceColor(rgb: 0xD5DEEA)
    static let red = FaceColor(rgb: 0xC8102E)
    static let darkRed = FaceColor(rgb: 0x8C0C20)
    static let green = FaceColor(rgb: 0x1F7A3E)
    static let darkGreen = FaceColor(rgb: 0x12502A)
    static let lightGreen = FaceColor(rgb: 0x3E9E57)
    static let gold = FaceColor(rgb: 0xF2C14E)
    static let darkGold = FaceColor(rgb: 0xC8922A)
    static let skin = FaceColor(rgb: 0xF6D2B5)
    static let cheek = FaceColor(rgb: 0xEE9A92)
    static let brown = FaceColor(rgb: 0x7A4A2A)
    static let darkBrown = FaceColor(rgb: 0x4A2C18)
    static let wood = FaceColor(rgb: 0xA26E3F)
    static let lightWood = FaceColor(rgb: 0xC4935E)
    static let cream = FaceColor(rgb: 0xFFF3D6)
    static let white = FaceColor.white
    static let black = FaceColor(rgb: 0x1A1A1A)
    static let grey = FaceColor(rgb: 0x8A8F98)
    static let flame = FaceColor(rgb: 0xFFB830)
    static let flameCore = FaceColor(rgb: 0xFFF2A8)
    static let blue = FaceColor(rgb: 0x1F4FA8)
    static let wall = FaceColor(rgb: 0x6E2430)
    static let wallDark = FaceColor(rgb: 0x561B25)

    static func alpha(_ c: FaceColor, _ a: UInt8) -> FaceColor {
        FaceColor(r: c.r, g: c.g, b: c.b, a: a)
    }
}

// MARK: - Building blocks

struct SceneBuilder<Sink: IconShapeSink> {
    var sink: Sink
    private var random: UInt32 = 0x2545F491

    init(sink: Sink) {
        self.sink = sink
    }

    @inline(never) mutating func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: FaceColor, r: Float = 0) {
        sink.add(.roundRect(x: x, y: y, w: w, h: h, r: r, color: color))
    }

    @inline(never) mutating func circle(_ x: Float, _ y: Float, _ r: Float, _ color: FaceColor) {
        sink.add(.circle(x: x, y: y, r: r, color: color))
    }

    @inline(never) mutating func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ w: Float, _ color: FaceColor) {
        sink.add(.line(x1: x1, y1: y1, x2: x2, y2: y2, width: w, color: color))
    }

    @inline(never) mutating func tri(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ color: FaceColor) {
        sink.add(.triangle(x1: x1, y1: y1, x2: x2, y2: y2, x3: x3, y3: y3, color: color))
    }

    /// A convex polygon, as a fan of triangles. Each is grown a little (away from its middle) so the edges they
    /// share overlap: anti-aliased, they'd otherwise leave a faint seam.
    @inline(never) mutating func poly(_ p: [(Float, Float)], _ color: FaceColor) {
        guard p.count >= 3 else { return }
        if p.count == 3 {
            tri(p[0].0, p[0].1, p[1].0, p[1].1, p[2].0, p[2].1, color)
            return
        }
        for i in 1..<(p.count - 1) {
            let mx = (p[0].0 + p[i].0 + p[i + 1].0) / 3, my = (p[0].1 + p[i].1 + p[i + 1].1) / 3
            func grow(_ q: (Float, Float)) -> (Float, Float) {
                let dx = q.0 - mx, dy = q.1 - my
                let len = max(0.01, (dx * dx + dy * dy).squareRoot())
                return (q.0 + dx / len * 0.6, q.1 + dy / len * 0.6)
            }
            let a = grow(p[0]), b = grow(p[i]), c = grow(p[i + 1])
            tri(a.0, a.1, b.0, b.1, c.0, c.1, color)
        }
    }

    @inline(never) mutating func ellipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ color: FaceColor) {
        if abs(rx - ry) < 0.3 {
            circle(cx, cy, rx, color)
            return
        }
        // Small ones need fewer corners
        let size = max(rx, ry)
        let segments = size < 4 ? 8 : (size < 12 ? 10 : 14)
        var p: [(Float, Float)] = []
        for i in 0..<segments {
            let a = Float(i) * 2 * FaceMath.pi / Float(segments)
            p.append((cx + rx * FaceMath.cos(a), cy + ry * FaceMath.sin(a)))
        }
        poly(p, color)
    }

    /// The lower half of an ellipse (a bowl), flat side up at cy
    @inline(never) mutating func halfEllipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ color: FaceColor) {
        var p: [(Float, Float)] = []
        for i in 0...8 {
            let a = Float(i) * FaceMath.pi / 8
            p.append((cx + rx * FaceMath.cos(a), cy + ry * FaceMath.sin(a)))
        }
        poly(p, color)
    }

    /// A star with `points` tips, the first pointing up
    @inline(never) mutating func star(_ cx: Float, _ cy: Float, _ r: Float, _ color: FaceColor, points: Int = 5, inner: Float = 0.45) {
        let n = points * 2
        var p: [(Float, Float)] = []
        for i in 0..<n {
            let a = Float(i) * FaceMath.pi / Float(points) - FaceMath.pi / 2
            let radius = i % 2 == 0 ? r : r * inner
            p.append((cx + radius * FaceMath.cos(a), cy + radius * FaceMath.sin(a)))
        }
        for i in 0..<n {
            let q = p[(i + 1) % n]
            tri(cx, cy, p[i].0, p[i].1, q.0, q.1, color)
        }
    }

    /// An arc of a circle as short lines; angles in radians, 0 = right, clockwise (y is down)
    @inline(never) mutating func arc(_ cx: Float, _ cy: Float, _ r: Float, from a0: Float, to a1: Float, _ w: Float, _ color: FaceColor,
                      segments: Int = 8) {
        var last = (cx + r * FaceMath.cos(a0), cy + r * FaceMath.sin(a0))
        for i in 1...segments {
            let a = a0 + (a1 - a0) * Float(i) / Float(segments)
            let p = (cx + r * FaceMath.cos(a), cy + r * FaceMath.sin(a))
            line(last.0, last.1, p.0, p.1, w, color)
            last = p
        }
    }

    @inline(never) mutating func next() -> Float {
        random ^= random << 13
        random ^= random >> 17
        random ^= random << 5
        return Float(random >> 8) / Float(1 << 24)
    }

    /// The whole picture's background: bands from `top` to `bottom`
    @inline(never) mutating func sky(_ top: FaceColor, _ bottom: FaceColor, bands: Int = 6) {
        for i in 0..<bands {
            let t = Float(i) / Float(bands - 1)
            let c = FaceColor(r: UInt8(Float(top.r) + (Float(bottom.r) - Float(top.r)) * t),
                              g: UInt8(Float(top.g) + (Float(bottom.g) - Float(top.g)) * t),
                              b: UInt8(Float(top.b) + (Float(bottom.b) - Float(top.b)) * t))
            let h = AdventScene.height / Float(bands)
            rect(0, Float(i) * h, AdventScene.width, h + 0.6, c)
        }
    }

    @inline(never) mutating func snowfall(_ count: Int, top: Float = 0, bottom: Float = 120, color: FaceColor = C.alpha(C.white, 200)) {
        for _ in 0..<count {
            circle(next() * 100, top + next() * (bottom - top), 0.5 + next() * 0.9, color)
        }
    }

    @inline(never) mutating func stars(_ count: Int, bottom: Float) {
        for _ in 0..<count {
            let x = next() * 100, y = next() * bottom, big = next() < 0.2
            if big {
                star(x, y, 2.2, C.alpha(C.flameCore, 230), points: 4, inner: 0.3)
            } else {
                circle(x, y, 0.5 + next() * 0.4, C.alpha(C.white, 210))
            }
        }
    }

    /// Rolling snow from y to the bottom
    @inline(never) mutating func snowGround(_ y: Float) {
        ellipse(20, y + 6, 45, 10, C.snowShade)
        ellipse(80, y + 4, 40, 9, C.snowShade)
        rect(0, y + 6, 100, 120 - y - 6, C.snow)
        ellipse(25, y + 8, 40, 7, C.snow)
        ellipse(78, y + 7, 36, 6, C.snow)
    }

    @inline(never) mutating func candle(_ x: Float, _ top: Float, _ w: Float, _ h: Float, _ color: FaceColor, lit: Bool = true) {
        if lit {
            circle(x + w / 2, top - 4, w * 1.4, C.alpha(C.flame, 45))
        }
        rect(x, top, w, h, color, r: w * 0.15)
        rect(x + w * 0.62, top + 1, w * 0.18, h - 2, C.alpha(C.white, 70), r: w * 0.09)
        line(x + w / 2, top, x + w / 2, top - 1.6, 0.7, C.black)
        if lit {
            flame(x + w / 2, top - 1.4, max(1.6, w * 0.38))
        }
    }

    @inline(never) mutating func flame(_ x: Float, _ base: Float, _ r: Float) {
        circle(x, base - r, r, C.flame)
        tri(x - r * 0.9, base - r * 1.3, x + r * 0.9, base - r * 1.3, x, base - r * 3.4, C.flame)
        circle(x, base - r * 0.9, r * 0.55, C.flameCore)
    }

    /// A Danish flag `w` wide, its top left corner at (x, y)
    @inline(never) mutating func flag(_ x: Float, _ y: Float, _ w: Float) {
        let h = w * 28 / 37
        rect(x, y, w, h, C.red)
        rect(x + w * 12 / 37, y, w * 4 / 37, h, C.white)
        rect(x, y + w * 12 / 37, w, w * 4 / 37, C.white)
    }

    /// A fir tree: three tiers from `top` to `bottom`, `w` wide at the bottom, centred on cx
    @inline(never) mutating func tree(_ cx: Float, top: Float, bottom: Float, w: Float, trunk: Bool = true) {
        let h = bottom - top
        if trunk {
            rect(cx - w * 0.07, bottom - h * 0.02, w * 0.14, h * 0.1, C.darkBrown)
        }
        let tiers: [(Float, Float, Float)] = [(0.0, 0.42, 0.55), (0.25, 0.7, 0.78), (0.5, 1.0, 1.0)]
        for (i, (t0, t1, wk)) in tiers.enumerated() {
            let y0 = top + h * t0, y1 = top + h * t1, half = w * wk / 2
            tri(cx, y0, cx - half, y1, cx + half, y1, i % 2 == 0 ? C.green : C.darkGreen)
            tri(cx, y0, cx + half * 0.15, y1, cx + half, y1, C.alpha(C.darkGreen, 150))
        }
    }

    /// A pointed nisse cap (red, white brim and bobble) over a head at (cx, cy) with radius r
    @inline(never) mutating func nisseHead(_ cx: Float, _ cy: Float, _ r: Float, droop: Float = 1) {
        // The cap: from the brim up to a tip that droops to the side
        tri(cx - r * 1.05, cy - r * 0.35, cx + r * 1.05, cy - r * 0.35, cx + r * 0.9 * droop, cy - r * 2.6, C.red)
        tri(cx + r * 0.2, cy - r * 0.35, cx + r * 1.05, cy - r * 0.35, cx + r * 0.9 * droop, cy - r * 2.6, C.darkRed)
        circle(cx + r * 0.95 * droop, cy - r * 2.6, r * 0.32, C.white)
        circle(cx, cy + r * 0.1, r, C.skin)
        // Beard and moustache
        ellipse(cx, cy + r * 0.85, r * 0.95, r * 0.8, C.white)
        ellipse(cx - r * 0.3, cy + r * 0.35, r * 0.42, r * 0.22, C.white)
        ellipse(cx + r * 0.3, cy + r * 0.35, r * 0.42, r * 0.22, C.white)
        circle(cx, cy + r * 0.2, r * 0.2, C.cheek)
        circle(cx - r * 0.35, cy - r * 0.12, r * 0.11, C.black)
        circle(cx + r * 0.35, cy - r * 0.12, r * 0.11, C.black)
        rect(cx - r * 1.1, cy - r * 0.55, r * 2.2, r * 0.42, C.white, r: r * 0.2)
    }

    /// A Danish woven paper heart (two lobes, a chequered middle), its centre at (cx, cy)
    @inline(never) mutating func wovenHeart(_ cx: Float, _ cy: Float, _ d: Float, _ a: FaceColor = C.red, _ b: FaceColor = C.white) {
        // A diamond pointing down; the lobes sit on its two upper edges
        let left = (cx - d, cy), top = (cx, cy - d), right = (cx + d, cy), bottom = (cx, cy + d)
        let lobe = d * 0.7071
        circle((left.0 + top.0) / 2, (left.1 + top.1) / 2, lobe, a)
        circle((right.0 + top.0) / 2, (right.1 + top.1) / 2, lobe, b)
        // P(u, v) = bottom + u (left - bottom) + v (right - bottom)
        func p(_ u: Float, _ v: Float) -> (Float, Float) {
            (bottom.0 + u * (left.0 - bottom.0) + v * (right.0 - bottom.0),
             bottom.1 + u * (left.1 - bottom.1) + v * (right.1 - bottom.1))
        }
        let n = 3
        for i in 0..<n {
            for j in 0..<n {
                let u0 = Float(i) / Float(n), u1 = Float(i + 1) / Float(n)
                let v0 = Float(j) / Float(n), v1 = Float(j + 1) / Float(n)
                let c = (i + j) % 2 == 0 ? a : b
                let p00 = p(u0, v0), p10 = p(u1, v0), p11 = p(u1, v1), p01 = p(u0, v1)
                poly([p00, p10, p11, p01], c)
            }
        }
    }

    /// A little bird (a sparrow), facing right, at (x, y)
    @inline(never) mutating func bird(_ x: Float, _ y: Float, _ s: Float) {
        ellipse(x, y, s * 1.3, s, C.brown)
        circle(x + s * 1.0, y - s * 0.6, s * 0.65, C.brown)
        ellipse(x - s * 0.1, y + s * 0.3, s * 0.9, s * 0.5, C.lightWood)
        tri(x - s * 1.1, y - s * 0.2, x - s * 2.3, y - s * 0.8, x - s * 2.1, y + s * 0.2, C.darkBrown)
        tri(x + s * 1.5, y - s * 0.75, x + s * 2.2, y - s * 0.5, x + s * 1.5, y - s * 0.35, C.darkGold)
        circle(x + s * 1.15, y - s * 0.75, s * 0.14, C.black)
    }

    /// A present: box, ribbon both ways and a bow
    @inline(never) mutating func present(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ box: FaceColor, _ ribbon: FaceColor) {
        rect(x, y, w, h, box, r: 0.8)
        rect(x + w * 0.62, y, w * 0.38, h, C.alpha(C.black, 40), r: 0.8)
        rect(x + w / 2 - w * 0.07, y, w * 0.14, h, ribbon)
        rect(x, y + h * 0.4, w, h * 0.13, ribbon)
        let s = min(w, h) * 0.28
        tri(x + w / 2, y, x + w / 2 - s * 1.4, y - s, x + w / 2 - s * 1.2, y + s * 0.3, ribbon)
        tri(x + w / 2, y, x + w / 2 + s * 1.4, y - s, x + w / 2 + s * 1.2, y + s * 0.3, ribbon)
        circle(x + w / 2, y, s * 0.35, ribbon)
    }

    /// A string of little Danish flags along a sagging line (the "flagranke" on a tree)
    @inline(never) mutating func flagString(from a: (Float, Float), to b: (Float, Float), sag: Float, count: Int, size: Float) {
        var last = a
        let steps = count * 2
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            let x = a.0 + (b.0 - a.0) * t
            let y = a.1 + (b.1 - a.1) * t + sag * 4 * t * (1 - t)
            line(last.0, last.1, x, y, 0.5, C.cream)
            last = (x, y)
        }
        for i in 0..<count {
            let t = (Float(i) + 0.5) / Float(count)
            let x = a.0 + (b.0 - a.0) * t
            let y = a.1 + (b.1 - a.1) * t + sag * 4 * t * (1 - t)
            flag(x - size / 2, y, size)
        }
    }

    @inline(never) mutating func pinecone(_ x: Float, _ y: Float, _ s: Float) {
        ellipse(x, y, s * 0.7, s, C.brown)
        for i in 0..<3 {
            let yy = y - s * 0.5 + Float(i) * s * 0.45
            line(x - s * 0.5, yy, x + s * 0.5, yy + s * 0.2, s * 0.14, C.darkBrown)
        }
    }

    /// A sprig of fir from (x1, y1) to (x2, y2)
    @inline(never) mutating func sprig(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ w: Float = 1.2) {
        line(x1, y1, x2, y2, w * 0.8, C.darkBrown)
        let n = 7
        let dx = x2 - x1, dy = y2 - y1
        let len = max(0.01, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / len, ny = dx / len
        for i in 1...n {
            let t = Float(i) / Float(n + 1)
            let x = x1 + dx * t, y = y1 + dy * t
            let l: Float = 4.5 * (1.1 - t * 0.5)
            line(x, y, x + (nx + dx / len * 0.6) * l, y + (ny + dy / len * 0.6) * l, w, C.green)
            line(x, y, x + (-nx + dx / len * 0.6) * l, y + (-ny + dy / len * 0.6) * l, w, C.lightGreen)
        }
    }

    // MARK: - The pictures

    /// 1: The climbing nisse sits on the bookshelf, legs dangling
    @inline(never) mutating func kravlenisse() {
        sky(C.wall, C.wallDark)
        // Wallpaper stripes
        for i in 0..<6 { rect(Float(i) * 18 + 6, 0, 5, 120, C.alpha(C.white, 14)) }
        // A framed picture on the wall
        rect(62, 12, 26, 20, C.lightWood, r: 1)
        rect(64.5, 14.5, 21, 15, C.nightLight)
        tree(75, top: 16, bottom: 28, w: 12, trunk: false)
        // The shelf with books and a candle
        rect(4, 66, 92, 5, C.wood, r: 1)
        rect(4, 70, 92, 2, C.darkBrown)
        let books: [(Float, Float, FaceColor)] = [(8, 22, C.green), (14, 26, C.blue), (20, 20, C.gold), (25, 24, C.darkRed),
                                                  (73, 20, C.darkGreen), (79, 25, C.red), (85, 22, C.cream)]
        for (x, h, c) in books { rect(x, 66 - h, 5.2, h, c, r: 0.6) }
        candle(66, 52, 4, 14, C.cream)
        // The nisse on the edge: long thin legs over the side, hands on the shelf
        let cx: Float = 46
        line(cx - 3, 70, cx - 7, 86, 2.4, C.red)
        line(cx - 7, 86, cx - 4, 101, 2.4, C.red)
        line(cx + 3, 70, cx + 8, 84, 2.4, C.red)
        line(cx + 8, 84, cx + 7, 100, 2.4, C.red)
        ellipse(cx - 5, 102, 3.4, 1.9, C.black)
        ellipse(cx + 9, 101, 3.4, 1.9, C.black)
        rect(cx - 6, 54, 12, 14, C.red, r: 3)
        rect(cx - 6, 63, 12, 2.4, C.black)
        rect(cx - 1.4, 62.8, 2.8, 2.8, C.gold, r: 0.4)
        line(cx - 5, 57, cx - 13, 66, 2.2, C.red)
        line(cx + 5, 57, cx + 13, 66, 2.2, C.red)
        circle(cx - 13, 66.3, 1.8, C.skin)
        circle(cx + 13, 66.3, 1.8, C.skin)
        nisseHead(cx, 47, 7, droop: -1)
        // The floor
        rect(0, 108, 100, 12, C.darkBrown)
        for i in 0..<5 { line(Float(i) * 22 + 4, 108, Float(i) * 22 + 4, 120, 0.6, C.black) }
    }

    /// 2: A red and white woven heart hanging from a fir branch
    @inline(never) mutating func julehjerte() {
        sky(C.darkGreen, FaceColor(rgb: 0x0A2E19))
        snowfall(28)
        sprig(-4, 14, 104, 8, 1.8)
        line(50, 12, 50, 30, 0.8, C.cream)
        // Handle: a strip over the top of the heart
        arc(50, 36, 9, from: FaceMath.pi * 1.05, to: FaceMath.pi * 1.95, 2.4, C.red)
        wovenHeart(50, 62, 24)
        // Two small hearts lower down, gold and green
        line(20, 12, 20, 82, 0.6, C.cream)
        wovenHeart(20, 92, 8, C.gold, C.white)
        line(82, 10, 82, 88, 0.6, C.cream)
        wovenHeart(82, 98, 7, C.green, C.white)
    }

    /// 3: The calendar candle, burnt down to the 3rd
    @inline(never) mutating func kalenderlys() {
        sky(FaceColor(rgb: 0x241A2E), FaceColor(rgb: 0x3A2430))
        // Window with snow outside
        rect(10, 8, 34, 42, C.cream, r: 1)
        rect(12, 10, 30, 38, C.nightLight)
        snowfallIn(x: 12, y: 10, w: 30, h: 38, count: 14)
        rect(26, 10, 2, 38, C.cream)
        rect(12, 28, 30, 2, C.cream)
        // The table
        rect(0, 98, 100, 22, C.wood)
        rect(0, 98, 100, 2, C.lightWood)
        // The candle: 24 marks from the top; three have burnt
        let top: Float = 30, bottom: Float = 96, w: Float = 16, x: Float = 50 - 16 / 2
        let markSpace: Float = 2.5
        let burnt = 3
        let candleTop = top + Float(burnt) * markSpace
        circle(50, candleTop - 6, 18, C.alpha(C.flame, 35))
        circle(50, candleTop - 6, 10, C.alpha(C.flame, 45))
        rect(x, candleTop, w, bottom - candleTop, C.white, r: 2)
        rect(x + w * 0.65, candleTop + 1, 3, bottom - candleTop - 2, C.alpha(C.snowShade, 200), r: 1)
        for i in burnt..<24 {
            let y = top + Float(i) * markSpace + 1.2
            line(x + 3, y, x + (i % 2 == 1 ? 9 : 6), y, 0.6, C.red)
        }
        // Red hearts and a fir sprig painted on it
        for (yy, s) in [(Float(60), Float(2.2)), (Float(76), Float(2.6))] {
            circle(x + 10.5, yy, s * 0.55, C.red)
            circle(x + 12.5, yy, s * 0.55, C.red)
            tri(x + 9.4, yy + 0.3, x + 13.6, yy + 0.3, x + 11.5, yy + s * 1.4, C.red)
        }
        line(50, candleTop, 50, candleTop - 2.2, 0.8, C.black)
        flame(50, candleTop - 1.8, 2.6)
        // The holder with fir, berries and a cone
        ellipse(50, 97, 22, 4, C.darkGold)
        ellipse(50, 96, 20, 3, C.gold)
        sprig(28, 96, 46, 92, 1.3)
        sprig(72, 96, 55, 92, 1.3)
        circle(40, 93, 1.6, C.red)
        circle(43, 94.5, 1.6, C.red)
        circle(62, 94, 1.6, C.red)
        pinecone(68, 93, 3)
    }

    @inline(never) mutating func snowfallIn(x: Float, y: Float, w: Float, h: Float, count: Int) {
        for _ in 0..<count {
            circle(x + 1 + next() * (w - 2), y + 1 + next() * (h - 2), 0.4 + next() * 0.5, C.alpha(C.white, 220))
        }
    }

    /// Red and white chequered tablecloth
    @inline(never) mutating func gingham(_ y: Float) {
        rect(0, y, 100, 120 - y, C.red)
        var x: Float = 0
        while x < 100 {
            rect(x, y, 5, 120 - y, C.alpha(C.white, 90))
            x += 10
        }
        var yy = y
        while yy < 120 {
            rect(0, yy, 100, 5, C.alpha(C.white, 90))
            yy += 10
        }
    }

    /// 4: A bowl of pebernødder on a chequered cloth
    @inline(never) mutating func pebernodder() {
        sky(C.wall, C.wallDark)
        gingham(62)
        // Some on the cloth
        for (x, y) in [(Float(14), Float(98)), (20, 104), (84, 100), (78, 108), (88, 92), (12, 110)] {
            pebernod(x, y, 3.2)
        }
        // The bowl
        ellipse(50, 70, 36, 8, C.darkBrown)
        // The heap
        var r: UInt32 = 7
        for row in 0..<4 {
            let y = 68 - Float(row) * 4.2
            let n = 9 - row * 2
            for i in 0..<n {
                r = r &* 1103515245 &+ 12345
                let jitter = Float(r >> 16 & 0xFF) / 255 * 2 - 1
                let x = 50 + (Float(i) - Float(n - 1) / 2) * 7.2 + jitter
                pebernod(x, y + jitter * 0.8, 3.6)
            }
        }
        // The bowl's front over the heap
        halfEllipse(50, 70, 36, 22, C.blue)
        halfEllipse(50, 70, 33, 19, FaceColor(rgb: 0x2A62C4))
        for i in 0..<7 {
            let x = 26 + Float(i) * 8
            circle(x, 80, 1.6, C.white)
        }
        rect(14, 69, 72, 2.5, C.white, r: 1.2)
        ellipse(50, 93, 12, 2.5, C.alpha(C.black, 60))
    }

    @inline(never) mutating func pebernod(_ x: Float, _ y: Float, _ r: Float) {
        circle(x, y, r, C.brown)
        circle(x - r * 0.3, y - r * 0.35, r * 0.45, C.lightWood)
        line(x - r * 0.4, y + r * 0.3, x + r * 0.4, y + r * 0.1, r * 0.25, C.darkBrown)
    }

    /// 5: A Christmas tree with strings of Danish flags
    @inline(never) mutating func flagTree() {
        sky(C.night, C.nightLight)
        stars(14, bottom: 50)
        snowGround(98)
        tree(50, top: 14, bottom: 104, w: 76)
        flagString(from: (36, 38), to: (64, 36), sag: 6, count: 3, size: 5)
        flagString(from: (26, 62), to: (76, 60), sag: 8, count: 5, size: 5.5)
        flagString(from: (17, 88), to: (84, 86), sag: 9, count: 7, size: 6)
        star(50, 13, 7, C.gold)
        star(50, 13, 3.5, C.flameCore)
        present(18, 100, 14, 12, C.red, C.gold)
        present(66, 102, 16, 10, C.green, C.red)
        present(36, 104, 10, 8, C.gold, C.red)
    }

    /// 6: Rice porridge with a pool of butter and cinnamon in a blue fluted bowl
    @inline(never) mutating func risengrod() {
        sky(FaceColor(rgb: 0x3A2A20), FaceColor(rgb: 0x5A3E2A))
        rect(0, 70, 100, 50, C.wood)
        for i in 0..<5 { rect(0, 72 + Float(i) * 10, 100, 0.8, C.alpha(C.darkBrown, 120)) }
        // Steam
        for x in [Float(38), 50, 62] {
            line(x, 36, x - 3, 26, 1.4, C.alpha(C.white, 70))
            line(x - 3, 26, x + 1, 16, 1.4, C.alpha(C.white, 50))
        }
        // Bowl
        ellipse(50, 98, 38, 8, C.alpha(C.black, 70))
        halfEllipse(50, 62, 40, 32, C.white)
        for i in 0..<9 {
            let x = 18 + Float(i) * 8
            line(x, 66, 50 + (x - 50) * 0.6, 90, 2, C.alpha(C.blue, 170))
        }
        ellipse(50, 62, 40, 10, C.white)
        ellipse(50, 62, 36, 8, FaceColor(rgb: 0xF7EDD8))
        ellipse(52, 61, 14, 4.5, FaceColor(rgb: 0xF4C430))
        ellipse(52, 60.5, 10, 3, FaceColor(rgb: 0xFFE27A))
        for _ in 0..<16 {
            circle(24 + next() * 52, 57 + next() * 9, 0.5 + next() * 0.4, C.brown)
        }
        // A spoon
        line(72, 58, 94, 40, 3, C.grey)
        ellipse(70, 61, 5, 2.6, FaceColor(rgb: 0xB8BCC4))
    }

    /// 7: The nisse in the attic with his porridge and the cat
    @inline(never) mutating func nisseLoft() {
        sky(FaceColor(rgb: 0x2B1B12), FaceColor(rgb: 0x3D2818))
        // Roof beams
        tri(-10, 46, 50, 0, 110, 46, FaceColor(rgb: 0x352216))
        line(-6, 44, 50, 2, 3, C.darkBrown)
        line(106, 44, 50, 2, 3, C.darkBrown)
        line(50, 2, 50, 70, 3, C.darkBrown)
        line(10, 70, 90, 70, 2.5, C.darkBrown)
        // A round window with the moon
        circle(50, 30, 10, C.darkBrown)
        circle(50, 30, 8.5, C.nightLight)
        circle(53, 27, 3, FaceColor(rgb: 0xF2E9C9))
        line(41.5, 30, 58.5, 30, 1, C.darkBrown)
        line(50, 21.5, 50, 38.5, 1, C.darkBrown)
        // Hay on the floor
        rect(0, 92, 100, 28, FaceColor(rgb: 0x5A3D22))
        for i in 0..<26 {
            let x = Float(i) * 4 + next() * 3
            line(x, 92 + next() * 4, x + next() * 6 - 3, 84 + next() * 5, 0.8, C.gold)
        }
        // The nisse
        let cx: Float = 36
        rect(cx - 10, 72, 20, 22, FaceColor(rgb: 0x6B7A8F), r: 5)
        rect(cx - 10, 88, 20, 6, FaceColor(rgb: 0x4F5B6B), r: 2)
        nisseHead(cx, 64, 8)
        // The bowl in his lap and a spoon
        halfEllipse(cx + 2, 82, 9, 6, C.cream)
        ellipse(cx + 2, 82, 9, 2.2, FaceColor(rgb: 0xF7EDD8))
        circle(cx + 3, 81.8, 1.6, FaceColor(rgb: 0xF4C430))
        line(cx + 6, 81, cx + 12, 74, 1.2, C.grey)
        line(cx - 8, 78, cx - 3, 83, 2.4, FaceColor(rgb: 0x6B7A8F))
        // The cat, curled up
        ellipse(74, 88, 13, 7, C.grey)
        circle(84, 82, 5.5, C.grey)
        tri(80, 79, 81.5, 73.5, 84, 77.5, C.grey)
        tri(85, 77.5, 88, 74, 88.5, 79.5, C.grey)
        circle(82.5, 81.5, 0.8, C.flameCore)
        circle(86, 81.5, 0.8, C.flameCore)
        line(62, 90, 58, 82, 2.4, C.grey)
        for i in 0..<3 { line(66 + Float(i) * 5, 83, 67 + Float(i) * 5, 93, 0.8, C.alpha(C.black, 60)) }
    }

    /// 8: Æbleskiver in the pan, jam and icing sugar
    @inline(never) mutating func aebleskiver() {
        sky(FaceColor(rgb: 0xDDE8F0), FaceColor(rgb: 0xC5D5E2))
        // Tiles
        for i in 0..<6 { line(Float(i) * 20, 0, Float(i) * 20, 60, 0.6, C.alpha(C.grey, 120)) }
        for i in 0..<3 { line(0, Float(i) * 20, 100, Float(i) * 20, 0.6, C.alpha(C.grey, 120)) }
        rect(0, 58, 100, 62, C.wood)
        rect(0, 58, 100, 2, C.lightWood)
        // The pan with seven holes
        line(80, 72, 104, 54, 6, C.black)
        circle(48, 84, 32, FaceColor(rgb: 0x2A2A2E))
        circle(48, 84, 29, FaceColor(rgb: 0x3A3A40))
        let holes: [(Float, Float)] = [(48, 84), (48, 65), (48, 103), (31, 74.5), (65, 74.5), (31, 93.5), (65, 93.5)]
        for (x, y) in holes {
            circle(x, y, 8.6, FaceColor(rgb: 0x1F1F22))
            circle(x, y, 7.6, FaceColor(rgb: 0xC98A3D))
            circle(x - 2.2, y - 2.2, 3.4, FaceColor(rgb: 0xE6B060))
            circle(x + 2.5, y + 2.8, 1.8, C.alpha(C.darkBrown, 90))
        }
        // Icing sugar
        for _ in 0..<30 { circle(18 + next() * 60, 54 + next() * 60, 0.5, C.alpha(C.white, 200)) }
        // Jam
        ellipse(86, 104, 10, 4, C.white)
        ellipse(86, 103.5, 8, 2.8, FaceColor(rgb: 0xA31F34))
    }

    /// 9: A woven paper cone on a branch, filled with sweets
    @inline(never) mutating func kraemmerhus() {
        sky(FaceColor(rgb: 0x2A1420), FaceColor(rgb: 0x4A1F2C))
        snowfall(14)
        sprig(-4, 18, 104, 12, 2)
        // The handle from the branch
        line(36, 32, 50, 16, 1.4, C.red)
        line(64, 32, 50, 16, 1.4, C.red)
        // The sweets on top
        for (x, y, c) in [(Float(40), Float(31), C.green), (47, 28, C.gold), (55, 29, C.red), (61, 31, C.white),
                          (51, 25, FaceColor(rgb: 0xFF77AA))] {
            circle(x, y, 3.6, c)
        }
        line(45, 27, 41, 18, 1.4, C.white)
        line(41, 18, 43, 16, 1.4, C.red)
        // The cone: stripes in red and white
        let top: Float = 32, tip: (Float, Float) = (50, 98)
        let left: Float = 32, right: Float = 68
        let n = 6
        for i in 0..<n {
            let x0 = left + (right - left) * Float(i) / Float(n)
            let x1 = left + (right - left) * Float(i + 1) / Float(n)
            tri(x0, top, x1, top, tip.0, tip.1, i % 2 == 0 ? C.red : C.white)
        }
        rect(left - 1, top - 1.5, right - left + 2, 4, C.gold, r: 1.5)
        tri(50, top + 2.5, right, top + 2.5, tip.0, tip.1, C.alpha(C.black, 40))
        // A tassel
        line(50, 98, 50, 104, 1.2, C.gold)
        circle(50, 106, 2, C.gold)
    }

    /// 10: Brunkager with almonds and klejner on a plate
    @inline(never) mutating func brunkager() {
        sky(C.darkGreen, FaceColor(rgb: 0x0A3A1F))
        for i in 0..<8 { star(Float(i) * 14 + 4, 10 + Float(i % 2) * 8, 1.4, C.alpha(C.gold, 140), points: 4) }
        rect(0, 50, 100, 70, C.wood)
        // The plate
        ellipse(50, 84, 46, 26, C.alpha(C.black, 60))
        ellipse(50, 82, 46, 26, C.white)
        ellipse(50, 82, 38, 20, FaceColor(rgb: 0xEEF2F6))
        ellipse(50, 82, 38, 20, C.alpha(C.blue, 30))
        // Brunkager: thin, round, half an almond each
        for (x, y) in [(Float(30), Float(76)), (42, 70), (36, 88), (52, 80), (48, 93)] {
            ellipse(x, y, 8, 5.5, FaceColor(rgb: 0x8A4B22))
            ellipse(x, y - 0.4, 7, 4.6, FaceColor(rgb: 0xA35E2C))
            ellipse(x + 0.5, y - 0.3, 2.4, 1.3, C.cream)
        }
        // Klejner: twisted diamonds with a slit
        for (x, y) in [(Float(68), Float(72)), (74, 86), (62, 92), (66, 80)] {
            poly([(x - 7, y), (x - 1, y - 4.5), (x + 7, y), (x + 1, y + 4.5)], FaceColor(rgb: 0xD9A35F))
            line(x - 2.5, y + 1, x + 2.5, y - 1, 1.2, FaceColor(rgb: 0x9C6A32))
            for _ in 0..<3 { circle(x - 3 + next() * 6, y - 2 + next() * 4, 0.4, C.alpha(C.white, 200)) }
        }
    }

    /// 11: A pink marzipan pig with a red bow (the almond present)
    @inline(never) mutating func marcipangris() {
        sky(C.green, C.darkGreen)
        snowfall(16, bottom: 60)
        rect(0, 86, 100, 34, C.cream)
        rect(0, 86, 100, 2, C.alpha(C.black, 40))
        ellipse(52, 98, 34, 6, C.alpha(C.black, 50))
        let pink = FaceColor(rgb: 0xF5A3B5), darkPink = FaceColor(rgb: 0xE07C93)
        // Legs, body, head
        for x in [Float(30), 40, 60, 70] { rect(x - 3, 86, 6, 10, darkPink, r: 2) }
        line(20, 70, 14, 64, 1.4, darkPink)
        arc(12, 66, 3, from: 0, to: FaceMath.pi * 1.6, 1.4, darkPink)
        ellipse(48, 76, 28, 17, pink)
        circle(72, 66, 13, pink)
        tri(64, 58, 64, 46, 72, 54, darkPink)
        tri(76, 54, 84, 46, 82, 58, darkPink)
        ellipse(82, 70, 5, 4, darkPink)
        circle(80.5, 70, 1, FaceColor(rgb: 0x9C3F55))
        circle(83.5, 70, 1, FaceColor(rgb: 0x9C3F55))
        circle(71, 62, 1.4, C.black)
        circle(78, 61, 1.4, C.black)
        ellipse(42, 70, 10, 6, C.alpha(C.white, 60))
        // A red bow at its neck
        tri(61.5, 62, 52, 56, 53, 67, C.red)
        tri(61.5, 62, 71, 54, 70, 65, C.darkRed)
        circle(61.5, 62, 2, C.darkRed)
    }

    /// 12: The sheaf of grain on its pole for the birds, in the snow
    @inline(never) mutating func juleneg() {
        sky(FaceColor(rgb: 0xA9C8E8), FaceColor(rgb: 0xE4EEF7))
        circle(80, 22, 8, C.alpha(FaceColor(rgb: 0xFFE9A8), 180))
        snowGround(88)
        tree(12, top: 52, bottom: 96, w: 22)
        tree(90, top: 58, bottom: 98, w: 18)
        // The pole
        rect(48.5, 52, 3, 50, C.brown)
        // The sheaf: stalks fanning out, ears at the top, a red ribbon
        for i in 0..<15 {
            let t = Float(i) / 14
            let x = 34 + t * 32
            line(50, 56, x, 24 + abs(t - 0.5) * 12, 1, C.darkGold)
            ellipse(x, 22 + abs(t - 0.5) * 12, 1.6, 3.6, C.gold)
        }
        for i in 0..<6 {
            let x = 44 + Float(i) * 2.4
            line(50, 56, x, 64, 1, C.darkGold)
        }
        rect(44, 52, 12, 4, C.red, r: 1)
        tri(50, 54, 44, 62, 48, 62, C.red)
        tri(50, 54, 56, 62, 52, 62, C.darkRed)
        // Birds: on the sheaf, on the ground, flying
        bird(40, 24, 3.2)
        bird(62, 26, 3)
        bird(30, 98, 3.4)
        bird(70, 100, 3.2)
        line(72, 40, 76, 37, 1, C.darkBrown)
        line(76, 37, 80, 40, 1, C.darkBrown)
        line(16, 34, 19, 32, 1, C.darkBrown)
        line(19, 32, 22, 34, 1, C.darkBrown)
    }

    /// 13: Lucia with the crown of candles, singing in the dark
    @inline(never) mutating func lucia() {
        sky(FaceColor(rgb: 0x0A0E24), FaceColor(rgb: 0x1A1E3C))
        circle(50, 30, 34, C.alpha(C.flame, 25))
        circle(50, 30, 22, C.alpha(C.flame, 30))
        // Long fair hair, behind her shoulders
        let hair = FaceColor(rgb: 0xE8C26A)
        ellipse(50, 44, 12.5, 12, hair)
        poly([(38, 44), (62, 44), (65, 66), (35, 66)], hair)
        // The white gown and the red sash
        poly([(38, 60), (62, 60), (78, 120), (22, 120)], C.white)
        poly([(62, 60), (78, 120), (60, 120)], C.alpha(C.snowShade, 200))
        rect(36, 74, 28, 5, C.red, r: 1)
        tri(52, 77, 48, 98, 56, 96, C.red)
        // Hands holding a candle
        circle(46, 90, 2.8, C.skin)
        circle(54, 90, 2.8, C.skin)
        candle(48, 74, 4, 15, C.white)
        // The face, the fringe
        circle(50, 45, 9.5, C.skin)
        ellipse(50, 37, 9.5, 3.4, hair)
        circle(46, 46, 0.9, C.black)
        circle(54, 46, 0.9, C.black)
        ellipse(50, 50.5, 1.8, 1.4, FaceColor(rgb: 0xC0504D))
        circle(44, 49, 1.5, C.alpha(C.cheek, 160))
        circle(56, 49, 1.5, C.alpha(C.cheek, 160))
        // The crown: a lingonberry wreath and four candles
        ellipse(50, 35, 14, 3.4, C.darkGreen)
        for i in 0..<7 { circle(38 + Float(i) * 4, 35 + (i % 2 == 0 ? 0.8 : -0.6), 1, C.red) }
        for x in [Float(39), 46, 54, 61] {
            candle(x - 1.6, x == 46 || x == 54 ? 23 : 26, 3.2, x == 46 || x == 54 ? 11 : 8, C.white)
        }
        snowfall(10)
    }

    /// 14: A snowman in the garden with a red scarf and a broom
    @inline(never) mutating func snowman() {
        sky(C.night, C.nightLight)
        stars(12, bottom: 50)
        snowGround(84)
        // A fence
        for i in 0..<9 {
            let x = Float(i) * 12 + 2
            rect(x, 76, 4, 22, C.wood, r: 0.8)
            tri(x, 76, x + 4, 76, x + 2, 73, C.wood)
        }
        rect(0, 81, 100, 2.5, C.wood)
        rect(0, 90, 100, 2.5, C.wood)
        snowfall(30)
        // The broom behind
        line(70, 40, 82, 104, 1.8, C.brown)
        poly([(79, 96), (86, 94), (92, 112), (80, 114)], C.gold)
        // The snowman
        circle(50, 96, 20, C.snow)
        circle(50, 66, 14, C.snow)
        circle(50, 42, 10, C.snow)
        ellipse(56, 99, 12, 14, C.alpha(C.snowShade, 140))
        // Hat, eyes, carrot, buttons
        rect(38, 31, 24, 3, C.black, r: 1)
        rect(42, 18, 16, 14, C.black, r: 1)
        rect(42, 28, 16, 2.5, C.red)
        circle(46, 40, 1.3, C.black)
        circle(54, 40, 1.3, C.black)
        tri(50, 43, 50, 46, 62, 45.5, FaceColor(rgb: 0xFF8A1E))
        for i in 0..<5 { circle(42 + Float(i) * 4, 48 + abs(Float(i) - 2) * -0.8, 0.8, C.black) }
        for y in [Float(60), 68, 88, 98] { circle(50, y, 1.6, C.black) }
        // The scarf
        rect(39, 52, 22, 5, C.red, r: 2)
        rect(52, 54, 6, 16, C.red, r: 1.5)
        rect(39, 53.5, 22, 1, C.white)
        // Twig arms
        line(37, 64, 22, 54, 1.3, C.darkBrown)
        line(26, 57, 22, 60, 1, C.darkBrown)
        line(63, 64, 72, 58, 1.3, C.darkBrown)
    }

    /// 15: A whitewashed village church with a stepped gable in the snow
    @inline(never) mutating func church() {
        sky(C.night, C.nightLight)
        stars(20, bottom: 60)
        circle(84, 16, 6, FaceColor(rgb: 0xF2E9C9))
        circle(86.5, 14, 5, C.night)
        let wall = FaceColor(rgb: 0xF5F2EA), shade = FaceColor(rgb: 0xD8D2C4), tile = FaceColor(rgb: 0xA8442E)
        // The nave: a long red roof
        rect(40, 62, 54, 32, wall)
        poly([(36, 64), (44, 48), (98, 48), (98, 64)], tile)
        poly([(36, 64), (44, 48), (98, 48), (98, 52), (46, 52), (40, 64)], C.alpha(C.snow, 230))
        // The tower with the stepped gable
        rect(14, 36, 28, 58, wall)
        rect(36, 36, 6, 58, shade)
        let steps: [(Float, Float)] = [(14, 36), (17, 32), (20, 28), (23, 24), (26, 20)]
        for (i, (x, y)) in steps.enumerated() {
            let w = 28 - Float(i) * 6
            rect(x, y, w, 4.2, wall)
        }
        rect(26, 14, 4, 8, wall)
        line(28, 4, 28, 14, 1.2, C.gold)
        line(25, 8, 31, 8, 1.2, C.gold)
        // Windows and the door
        for x in [Float(50), 62, 74, 86] {
            rect(x, 68, 5, 10, FaceColor(rgb: 0xFFD36B), r: 2.5)
            circle(x + 2.5, 70, 6, C.alpha(C.flame, 30))
        }
        rect(24, 72, 8, 22, C.darkBrown, r: 4)
        rect(25, 42, 6, 9, C.night, r: 3)
        // Snow on the ground, trees, a path
        snowGround(92)
        poly([(24, 94), (32, 94), (44, 120), (14, 120)], C.snowShade)
        tree(6, top: 70, bottom: 100, w: 16)
        tree(94, top: 74, bottom: 102, w: 14)
        snowfall(20)
    }

    /// 16: A glass of mulled wine with raisins and almonds
    @inline(never) mutating func glogg() {
        sky(FaceColor(rgb: 0x2E1418), FaceColor(rgb: 0x4A1E22))
        rect(0, 92, 100, 28, C.wood)
        rect(0, 92, 100, 2, C.lightWood)
        // Steam
        for x in [Float(42), 52, 60] {
            line(x, 34, x + 3, 24, 1.4, C.alpha(C.white, 60))
            line(x + 3, 24, x - 1, 14, 1.4, C.alpha(C.white, 40))
        }
        // The glass with a handle
        arc(70, 64, 10, from: -FaceMath.pi * 0.5, to: FaceMath.pi * 0.5, 3, C.alpha(C.white, 140))
        poly([(28, 38), (72, 38), (68, 96), (32, 96)], C.alpha(C.white, 70))
        poly([(30, 46), (70, 46), (67, 94), (33, 94)], FaceColor(rgb: 0x8E1426))
        poly([(30, 46), (70, 46), (69, 52), (31, 52)], FaceColor(rgb: 0xB3263A))
        rect(28, 36.5, 44, 2.5, C.alpha(C.white, 160), r: 1)
        rect(36, 50, 3, 40, C.alpha(C.white, 50), r: 1.5)
        // Raisins and almonds floating
        for (x, y) in [(Float(40), Float(48)), (56, 49), (48, 50)] { ellipse(x, y, 2.4, 1.6, FaceColor(rgb: 0x3A1410)) }
        for (x, y) in [(Float(44), Float(47.5)), (62, 48.5)] { ellipse(x, y, 3, 1.3, C.cream) }
        // A slice of orange and a cinnamon stick
        circle(70, 40, 9, FaceColor(rgb: 0xF28C1E))
        circle(70, 40, 7.5, FaceColor(rgb: 0xFFB54D))
        for i in 0..<6 {
            let a = Float(i) * FaceMath.pi / 3
            line(70, 40, 70 + 6.5 * FaceMath.cos(a), 40 + 6.5 * FaceMath.sin(a), 0.6, C.cream)
        }
        line(52, 44, 62, 18, 3.4, C.brown)
        line(52.5, 44, 62.5, 18, 1, FaceColor(rgb: 0x9C6A3F))
        // Star anise and almonds on the table
        star(16, 104, 5, C.darkBrown, points: 8, inner: 0.5)
        ellipse(84, 104, 3.4, 1.8, C.cream)
        ellipse(90, 108, 3.4, 1.8, C.cream)
    }

    /// 17: The Advent wreath with four candles, three of them lit
    @inline(never) mutating func adventskrans() {
        sky(FaceColor(rgb: 0x1C1A2C), FaceColor(rgb: 0x2C2238))
        rect(0, 80, 100, 40, C.wood)
        rect(0, 80, 100, 2, C.lightWood)
        // The wreath: a ring of fir in perspective
        ellipse(50, 88, 42, 14, C.alpha(C.black, 60))
        for i in 0..<28 {
            let a = Float(i) * 2 * FaceMath.pi / 28
            let x = 50 + 36 * FaceMath.cos(a), y = 84 + 11 * FaceMath.sin(a)
            circle(x, y, 6.5, i % 2 == 0 ? C.green : C.darkGreen)
        }
        // Berries, cones, ribbons
        for i in 0..<10 {
            let a = Float(i) * 2 * FaceMath.pi / 10 + 0.3
            circle(50 + 38 * FaceMath.cos(a), 84 + 12 * FaceMath.sin(a), 1.6, C.red)
        }
        pinecone(22, 88, 3)
        pinecone(78, 90, 3)
        // Four candles in a row on the wreath, back ones higher
        let candles: [(Float, Float, Bool)] = [(20, 64, true), (40, 58, true), (60, 58, true), (80, 64, false)]
        for (x, y, lit) in candles {
            candle(x - 4, y, 8, 22, C.red, lit: lit)
        }
        // The front of the wreath over the candles' feet
        for i in 0..<12 {
            let a = FaceMath.pi * (0.1 + 0.8 * Float(i) / 11)
            circle(50 + 36 * FaceMath.cos(a), 84 + 11 * FaceMath.sin(a), 6, i % 2 == 0 ? C.green : C.lightGreen)
        }
        for i in 0..<5 {
            let a = FaceMath.pi * (0.2 + 0.6 * Float(i) / 4)
            circle(50 + 37 * FaceMath.cos(a), 85 + 12 * FaceMath.sin(a), 1.6, C.red)
        }
        // A red bow at the front
        tri(50, 95, 40, 90, 41, 100, C.red)
        tri(50, 95, 60, 90, 59, 100, C.red)
        circle(50, 95, 2, C.darkRed)
    }

    /// 18: A poinsettia in a pot
    @inline(never) mutating func julestjerne() {
        sky(C.cream, FaceColor(rgb: 0xF0DFC0))
        rect(0, 96, 100, 24, C.wood)
        // Green leaves underneath, then the red bracts
        for i in 0..<6 {
            let a = Float(i) * FaceMath.pi / 3 + 0.5
            leaf(50, 56, 34, a, C.darkGreen)
        }
        for i in 0..<7 {
            let a = Float(i) * 2 * FaceMath.pi / 7
            leaf(50, 56, 28, a, C.red)
        }
        for i in 0..<6 {
            let a = Float(i) * FaceMath.pi / 3 + 0.25
            leaf(50, 56, 16, a, FaceColor(rgb: 0xE0283E))
        }
        for i in 0..<6 {
            let a = Float(i) * FaceMath.pi / 3
            circle(50 + 3 * FaceMath.cos(a), 56 + 3 * FaceMath.sin(a), 1.6, FaceColor(rgb: 0xD4C21F))
        }
        circle(50, 56, 1.8, C.lightGreen)
        // The pot with a gold band
        poly([(32, 80), (68, 80), (64, 106), (36, 106)], FaceColor(rgb: 0xC8102E))
        rect(30, 78, 40, 6, C.darkRed, r: 1)
        rect(30, 82, 40, 2, C.gold)
        ellipse(50, 106, 16, 2, C.alpha(C.black, 60))
    }

    /// A pointed leaf from (cx, cy), `len` long in direction `a`
    @inline(never) mutating func leaf(_ cx: Float, _ cy: Float, _ len: Float, _ a: Float, _ color: FaceColor) {
        let c = FaceMath.cos(a), s = FaceMath.sin(a)
        let w = len * 0.28
        let mid = (cx + c * len * 0.5, cy + s * len * 0.5)
        let tip = (cx + c * len, cy + s * len)
        poly([(cx, cy), (mid.0 - s * w, mid.1 + c * w), tip, (mid.0 + s * w, mid.1 - c * w)], color)
        line(cx, cy, tip.0 - c * 2, tip.1 - s * 2, 0.5, C.alpha(C.black, 60))
    }

    /// 19: Two golden bells with a red bow and holly
    @inline(never) mutating func bells() {
        sky(C.darkRed, FaceColor(rgb: 0x5A0814))
        snowfall(22)
        for _ in 0..<10 { star(next() * 100, 30 + next() * 90, 1.5, C.alpha(C.gold, 110), points: 4, inner: 0.3) }
        // A fir branch across the top; the ribbons hang from a bow on it
        sprig(-6, 16, 106, 12, 1.8)
        line(50, 20, 31, 48, 2.2, C.red)
        line(50, 20, 69, 48, 2.2, C.red)
        // The bells, swinging out to the sides
        bell(31, 48, 0.22, size: 0.95)
        bell(69, 48, -0.22, size: 0.95)
        // Holly and the bow
        leaf(50, 18, 15, FaceMath.pi * 1.1, C.green)
        leaf(50, 18, 15, FaceMath.pi * 1.9, C.darkGreen)
        tri(50, 20, 38, 13, 39, 26, C.red)
        tri(50, 20, 62, 13, 61, 26, C.red)
        tri(50, 20, 40, 17, 41, 23, C.darkRed)
        tri(50, 20, 60, 17, 59, 23, C.darkRed)
        circle(50, 20, 2.8, C.darkRed)
        for (x, y) in [(Float(46), Float(15)), (49.5, 13.5), (53, 15)] { circle(x, y, 1.7, FaceColor(rgb: 0xE0283E)) }
    }

    /// A bell hanging from its loop at (x, y), swung by `tilt` (radians; positive swings its mouth to the left)
    @inline(never) mutating func bell(_ x: Float, _ y: Float, _ tilt: Float, size k: Float = 1) {
        let c = FaceMath.cos(tilt), s = FaceMath.sin(tilt)
        func p(_ dx: Float, _ dy: Float) -> (Float, Float) {
            (x + (dx * c - dy * s) * k, y + (dx * s + dy * c) * k)
        }
        // The loop, the clapper peeking out under the mouth
        let loop = p(0, 1.5)
        circle(loop.0, loop.1, 2.6 * k, C.darkGold)
        let clapper = p(0, 41)
        circle(clapper.0, clapper.1, 3.6 * k, C.darkGold)
        // The crown (a dome), then the flaring body in bands (each band a convex piece), right side in shade
        let crown = p(0, 11)
        circle(crown.0, crown.1, 8.5 * k, C.gold)
        let rows: [(Float, Float)] = [(11, 8.5), (20, 9.6), (27, 11.6), (32, 14.6), (36, 18.5)]
        for i in 0..<(rows.count - 1) {
            let (y0, w0) = rows[i], (y1, w1) = rows[i + 1]
            poly([p(-w0, y0), p(w0, y0), p(w1, y1), p(-w1, y1)], C.gold)
            poly([p(w0 * 0.4, y0), p(w0, y0), p(w1, y1), p(w1 * 0.45, y1)], FaceColor(rgb: 0xDCA63C))
        }
        // The rim: a band across the mouth
        var rim: [(Float, Float)] = []
        for i in 0...10 {
            let a = Float(i) * FaceMath.pi / 10
            rim.append(p(-19.5 * FaceMath.cos(a), 36 + 3.4 * FaceMath.sin(a)))
        }
        rim.append(p(19.5, 34))
        rim.append(p(-19.5, 34))
        poly(rim, C.darkGold)
        let rimL = p(-18.5, 34.5), rimR = p(18.5, 34.5)
        line(rimL.0, rimL.1, rimR.0, rimR.1, 1.2 * k, C.alpha(FaceColor(rgb: 0xFFE08A), 220))
        // A shine on the left
        let a = p(-5.5, 13), b = p(-7.5, 30)
        line(a.0, a.1, b.0, b.1, 2.2 * k, C.alpha(C.white, 140))
    }

    /// 20: A wreath with cones and a red bow on a wooden front door
    @inline(never) mutating func doorWreath() {
        sky(FaceColor(rgb: 0xF0EBE0), FaceColor(rgb: 0xD8D0C0))
        // The door
        rect(14, 6, 72, 114, FaceColor(rgb: 0x1F4A33), r: 2)
        rect(20, 12, 60, 44, FaceColor(rgb: 0x245A3E), r: 1)
        rect(20, 62, 60, 52, FaceColor(rgb: 0x245A3E), r: 1)
        circle(76, 74, 2.4, C.gold)
        // The wreath
        for i in 0..<22 {
            let a = Float(i) * 2 * FaceMath.pi / 22
            circle(50 + 20 * FaceMath.cos(a), 46 + 20 * FaceMath.sin(a), 7, i % 2 == 0 ? C.green : C.lightGreen)
        }
        for i in 0..<22 {
            let a = Float(i) * 2 * FaceMath.pi / 22 + 0.15
            line(50 + 15 * FaceMath.cos(a), 46 + 15 * FaceMath.sin(a), 50 + 27 * FaceMath.cos(a + 0.2),
                 46 + 27 * FaceMath.sin(a + 0.2), 1, C.darkGreen)
        }
        for i in 0..<5 {
            let a = Float(i) * 2 * FaceMath.pi / 5 - 0.6
            pinecone(50 + 21 * FaceMath.cos(a), 46 + 21 * FaceMath.sin(a), 3.4)
        }
        for i in 0..<8 {
            let a = Float(i) * 2 * FaceMath.pi / 8 + 0.2
            circle(50 + 24 * FaceMath.cos(a), 46 + 24 * FaceMath.sin(a), 1.8, C.red)
        }
        // The ribbon it hangs from, and the bow at the top
        rect(48, 0, 4, 26, C.red)
        tri(50, 26, 38, 20, 40, 32, C.red)
        tri(50, 26, 62, 20, 60, 32, C.red)
        tri(50, 26, 44, 40, 48, 40, C.darkRed)
        tri(50, 26, 56, 40, 52, 40, C.darkRed)
        circle(50, 26, 2.6, C.darkRed)
        // Snow on the step
        rect(0, 112, 100, 8, C.snow)
    }

    /// 21: The longest night: moon and stars over a snowy landscape
    @inline(never) mutating func solstice() {
        sky(FaceColor(rgb: 0x060A1E), FaceColor(rgb: 0x1A2A58), bands: 8)
        stars(40, bottom: 80)
        // The moon with a halo
        circle(68, 30, 18, C.alpha(FaceColor(rgb: 0xF2E9C9), 25))
        circle(68, 30, 12, C.alpha(FaceColor(rgb: 0xF2E9C9), 40))
        circle(68, 30, 9, FaceColor(rgb: 0xF2E9C9))
        circle(65, 28, 2, C.alpha(C.grey, 70))
        circle(71, 33, 1.4, C.alpha(C.grey, 70))
        // Hills
        ellipse(20, 98, 50, 18, FaceColor(rgb: 0xC5D2E8))
        ellipse(84, 100, 44, 16, FaceColor(rgb: 0xB0C0DC))
        rect(0, 100, 100, 20, C.snow)
        ellipse(50, 104, 60, 8, C.snow)
        // A little farm with a lit window
        rect(56, 82, 20, 14, FaceColor(rgb: 0xB0362A))
        tri(53, 83, 66, 72, 79, 83, C.snow)
        rect(60, 86, 5, 5, FaceColor(rgb: 0xFFD36B))
        circle(62.5, 88.5, 6, C.alpha(C.flame, 40))
        rect(70, 87, 4, 9, C.darkBrown)
        tree(16, top: 70, bottom: 100, w: 16)
        tree(28, top: 76, bottom: 102, w: 12)
        tree(90, top: 74, bottom: 100, w: 14)
    }

    /// 22: A pile of presents, wrapped and ready
    @inline(never) mutating func presents() {
        sky(C.wall, C.wallDark)
        for i in 0..<10 { star(Float(i % 5) * 22 + 6, Float(i / 5) * 24 + 10, 2, C.alpha(C.gold, 70), points: 4) }
        rect(0, 100, 100, 20, C.darkBrown)
        // A corner of the tree
        tree(92, top: 10, bottom: 104, w: 56)
        present(6, 74, 30, 28, C.red, C.gold)
        present(40, 80, 24, 22, C.gold, C.red)
        present(62, 88, 22, 14, FaceColor(rgb: 0x2A62C4), C.white)
        present(14, 52, 18, 20, C.green, C.red)
        present(44, 60, 14, 18, C.white, C.red)
        // Name tags
        rect(26, 86, 7, 5, C.cream, r: 0.8)
        line(26, 86, 22, 82, 0.5, C.cream)
        wovenHeart(52, 92, 3.4)
    }

    /// 23: Risalamande with warm cherry sauce, and the almond
    @inline(never) mutating func risalamande() {
        sky(FaceColor(rgb: 0x1E1A2A), FaceColor(rgb: 0x2E2638))
        rect(0, 80, 100, 40, FaceColor(rgb: 0xF2EEE6))
        rect(0, 80, 100, 3, C.red)
        // The glass bowl on its foot
        rect(44, 92, 12, 10, C.alpha(C.white, 140), r: 1)
        ellipse(50, 103, 16, 3, C.alpha(C.white, 160))
        halfEllipse(50, 56, 34, 36, C.alpha(C.white, 80))
        halfEllipse(50, 58, 31, 32, FaceColor(rgb: 0xFAF5EA))
        // Whipped rice and almonds in it
        for _ in 0..<16 { ellipse(24 + next() * 52, 64 + next() * 18, 1.6, 0.8, C.alpha(C.cream, 255)) }
        ellipse(50, 56, 34, 8, C.alpha(C.white, 120))
        ellipse(50, 57, 31, 7, FaceColor(rgb: 0xFBF7EE))
        // The cherry sauce running over the top
        ellipse(52, 55, 18, 4.5, FaceColor(rgb: 0x8E0E22))
        for (x, l) in [(Float(38), Float(10)), (48, 16), (60, 12), (66, 8)] {
            line(x, 56, x, 56 + l, 2.6, FaceColor(rgb: 0x8E0E22))
            circle(x, 56 + l, 1.8, FaceColor(rgb: 0x8E0E22))
        }
        for (x, y) in [(Float(48), Float(53)), (56, 55), (44, 56)] { circle(x, y, 2.4, FaceColor(rgb: 0x6A0818)) }
        // The whole almond peeking out (with a sparkle)
        ellipse(66, 54, 3.6, 2, FaceColor(rgb: 0xE9D7B0))
        star(70, 50, 4, C.flameCore, points: 4, inner: 0.25)
        // A spoon
        line(80, 88, 96, 74, 2.6, C.grey)
        ellipse(78, 90, 4, 2.2, FaceColor(rgb: 0xB8BCC4))
    }

    /// 24: Christmas Eve: the tree with flags, live candles and hearts, presents underneath
    @inline(never) mutating func juleaften() {
        sky(FaceColor(rgb: 0x3A1820), FaceColor(rgb: 0x5A2228))
        circle(50, 56, 50, C.alpha(C.flame, 25))
        rect(0, 106, 100, 14, C.darkBrown)
        tree(50, top: 12, bottom: 108, w: 84)
        flagString(from: (36, 40), to: (64, 38), sag: 6, count: 3, size: 4.6)
        flagString(from: (22, 70), to: (78, 68), sag: 8, count: 5, size: 5)
        // Hearts and candles on the branches
        for (x, y) in [(Float(44), Float(32)), (30, 60), (68, 58), (22, 92), (78, 94), (50, 84)] {
            line(x, y - 4, x, y - 1.5, 0.4, C.cream)
            wovenHeart(x, y + 1.4, 2.6)
        }
        for (x, y) in [(Float(57), Float(30)), (40, 52), (60, 50), (32, 80), (68, 80), (18, 102), (84, 102), (50, 98)] {
            candle(x - 1.1, y, 2.2, 5, C.white)
        }
        star(50, 11, 7.5, C.gold)
        star(50, 11, 3.8, C.flameCore)
        present(4, 100, 18, 16, C.red, C.gold)
        present(76, 102, 20, 14, C.green, C.red)
        present(26, 106, 14, 10, C.gold, C.red)
        present(60, 108, 12, 8, FaceColor(rgb: 0x2A62C4), C.white)
    }
}
