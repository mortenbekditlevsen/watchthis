// Background drawing helpers shared by the watch and the phone preview.

extension LinearGradient {
    /// Start and end of the gradient line over a box, CSS style: the line goes through the center at `angle`, long
    /// enough that the corners get the first and last colors
    public func endpoints(width: Int, height: Int) -> (from: Point, to: Point) {
        let a = Float(angle) * FaceMath.pi / 180
        let dx = FaceMath.sin(a)
        let dy = -FaceMath.cos(a)
        let half = (abs(Float(width) * dx) + abs(Float(height) * dy)) / 2
        let cx = Float(width) / 2
        let cy = Float(height) / 2
        return (Point(x: cx - dx * half, y: cy - dy * half), Point(x: cx + dx * half, y: cy + dy * half))
    }
}

extension Pattern {
    /// One repeat of the pattern as RGB565 pixels (row by row); tiled over the background. Anti-aliased dots.
    public func tile() -> (width: Int, height: Int, pixels: [UInt16]) {
        let s = max(2, spacing)
        let size = max(1, min(size, s))
        let w = kind == .checker ? 2 * s : s
        let h = w
        var pixels = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var coverage: Float = 0
                switch kind {
                case .stripes:
                    coverage = y < size ? 1 : 0
                case .diagonalStripes:
                    coverage = (x + y) % s < size ? 1 : 0
                case .grid:
                    coverage = (x < size || y < size) ? 1 : 0
                case .checker:
                    coverage = (x < s) != (y < s) ? 1 : 0
                case .dots:
                    let c = Float(s) / 2
                    let dx = Float(x) + 0.5 - c
                    let dy = Float(y) + 0.5 - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    coverage = max(0, min(1, Float(size) / 2 - d + 0.5))
                }
                let a = coverage * Float(foreground.a) / 255
                func mix(_ f: UInt8, _ b: UInt8) -> UInt8 {
                    UInt8((Float(f) * a + Float(b) * (1 - a)).rounded())
                }
                pixels[y * w + x] = RGB565.pack(mix(foreground.r, background.r), mix(foreground.g, background.g),
                                                mix(foreground.b, background.b))
            }
        }
        return (w, h, pixels)
    }
}

/// Draws a gradient background as RGB565 rows, once, into a file the watch then shows like a photo (LVGL would
/// otherwise compute radial and angled gradients pixel by pixel on every redraw). Ordered (4 x 4 Bayer) dithering
/// hides RGB565's banding.
public struct GradientRaster: Sendable {
    enum Shape: Sendable {
        case linear(fromX: Float, fromY: Float, dx: Float, dy: Float, lengthSquared: Float)
        case radial(centerX: Float, centerY: Float, radius: Float)
    }

    let shape: Shape
    let stops: [GradientStop]
    /// Same gradient, same key: names the cache file
    public let cacheKey: String
    public let width = WatchScreen.width
    public let height = WatchScreen.height

    static let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }

    /// nil for backgrounds that aren't worth it: no gradient, or one LVGL draws cheaply (see `isCheap`)
    public init?(_ background: Background) {
        switch background {
        case .linearGradient(let g) where !GradientRaster.isCheap(g) && !g.stops.isEmpty:
            let (from, to) = g.endpoints(width: WatchScreen.width, height: WatchScreen.height)
            let dx = to.x - from.x, dy = to.y - from.y
            shape = .linear(fromX: from.x, fromY: from.y, dx: dx, dy: dy, lengthSquared: max(1, dx * dx + dy * dy))
            stops = g.stops.sorted { $0.location < $1.location }
        case .radialGradient(let g) where !g.stops.isEmpty:
            shape = .radial(centerX: Float(g.centerX), centerY: Float(g.centerY), radius: Float(max(1, g.radius)))
            stops = g.stops.sorted { $0.location < $1.location }
        default:
            return nil
        }
        var w = TLVWriter()
        background.encode(into: &w)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in w.bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let hex = Array("0123456789abcdef".utf8)
        var key = Array("grad_".utf8)
        for i in stride(from: 60, through: 0, by: -4) {
            key.append(hex[Int((hash >> UInt64(i)) & 0xF)])
        }
        cacheKey = String(decoding: key, as: UTF8.self)
    }

    /// Top-to-bottom and left-to-right gradients (and reversed): LVGL fills those row by row, which is cheap
    public static func isCheap(_ g: LinearGradient) -> Bool {
        g.angle % 90 == 0
    }

    /// 0...1 at a pixel
    func position(x: Float, y: Float) -> Float {
        switch shape {
        case .linear(let fx, let fy, let dx, let dy, let lengthSquared):
            return ((x - fx) * dx + (y - fy) * dy) / lengthSquared
        case .radial(let cx, let cy, let r):
            let ddx = x - cx, ddy = y - cy
            return (ddx * ddx + ddy * ddy).squareRoot() / r
        }
    }

    /// The color at 0...1 (red, green, blue as 0...255 floats)
    func color(at t: Float) -> (Float, Float, Float) {
        let p = max(0, min(1, t)) * 255
        let first = stops[0], last = stops[stops.count - 1]
        if p <= Float(first.location) { return (Float(first.color.r), Float(first.color.g), Float(first.color.b)) }
        if p >= Float(last.location) { return (Float(last.color.r), Float(last.color.g), Float(last.color.b)) }
        var i = 1
        while i < stops.count - 1 && Float(stops[i].location) < p { i += 1 }
        let a = stops[i - 1], b = stops[i]
        let span = Float(max(1, b.location - a.location))
        let f = (p - Float(a.location)) / span
        func mix(_ u: UInt8, _ v: UInt8) -> Float { Float(u) + (Float(v) - Float(u)) * f }
        return (mix(a.color.r, b.color.r), mix(a.color.g, b.color.g), mix(a.color.b, b.color.b))
    }

    /// Row `y` as little-endian RGB565 (width * 2 bytes)
    public func row(_ y: Int, into out: inout [UInt8]) {
        if out.count != width * 2 { out = [UInt8](repeating: 0, count: width * 2) }
        for x in 0..<width {
            let (r, g, b) = color(at: position(x: Float(x) + 0.5, y: Float(y) + 0.5))
            let d = GradientRaster.bayer[(y & 3) * 4 + (x & 3)]
            func q(_ v: Float, _ step: Float, _ maxValue: Float) -> UInt16 {
                UInt16(max(0, min(maxValue, (v / step + d).rounded(.down))))
            }
            let v = q(r, 255.0 / 31.0, 31) << 11 | q(g, 255.0 / 63.0, 63) << 5 | q(b, 255.0 / 31.0, 31)
            out[x * 2] = UInt8(truncatingIfNeeded: v)
            out[x * 2 + 1] = UInt8(truncatingIfNeeded: v >> 8)
        }
    }
}

/// Names for what the watch draws once per face: its static layer (background, dial, ticks, numerals, fixed text;
/// kept in the memory-mapped slot) and a quarter-size thumbnail for the face switcher (a file, shown at twice its
/// size). Any change to the face gives new names.
public enum BakeKeys {
    public static func hash(_ face: WatchFace) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in face.encoded() {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let hex = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        for i in stride(from: 60, through: 0, by: -4) {
            out.append(hex[Int((hash >> UInt64(i)) & 0xF)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func staticKey(_ face: WatchFace) -> String { "st_" + hash(face) }
    public static func thumbnailKey(_ face: WatchFace) -> String { "tq_" + hash(face) }

    public static let thumbnailScale = 4
    public static let thumbnailWidth = WatchScreen.width / thumbnailScale
    public static let thumbnailHeight = WatchScreen.height / thumbnailScale
}

/// Pieces of a hand bitmap of at most `rows` rows each, overlapping by `overlap` rows, so each piece's rotated
/// bounding box is small: moving a long hand then redraws narrow areas along it, not one big square
public enum HandSlices {
    public static func ranges(height: Int, rows: Int = 32, overlap: Int = 2) -> [(start: Int, count: Int)] {
        var result: [(start: Int, count: Int)] = []
        var start = 0
        while start < height {
            let count = min(rows, height - start)
            result.append((start, count))
            if start + count >= height { break }
            start += count - overlap
        }
        return result
    }
}
