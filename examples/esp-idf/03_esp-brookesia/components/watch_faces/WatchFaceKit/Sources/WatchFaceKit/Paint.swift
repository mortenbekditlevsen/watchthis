// Drawings for the watch's Tegn app: 16 colours (PaintPalette), 4 bits a pixel, at half the screen's resolution
// (205 x 251; shown at twice that). A whole screen of RGB565 wouldn't fit in the watch's RAM; this is ~26 KB, kept in
// bands of 16 rows (~1.6 KB each): the watch's free memory is fragmented, and 26 KB in one piece often isn't there.
// Saved run-length encoded (mostly one colour, so a drawing takes a few KB):
//
//   "WPN1" | width u16 | height u16 | runs: { count u8 (1...255) | byte (two pixels: high nibble first) }
//
// Thumbnails are a quarter of the pixels (half each way), stored unencoded so the watch can read them a row at a time:
//
//   "WPT1" | width u16 | height u16 | rows of (width + 1) / 2 bytes

public enum PaintPalette {
    /// White (the paper) first, then black, greys, colours
    public static let colors: [FaceColor] = [
        FaceColor(rgb: 0xFFFFFF), FaceColor(rgb: 0x000000), FaceColor(rgb: 0x8E8E93), FaceColor(rgb: 0xD1D1D6),
        FaceColor(rgb: 0xFF3B30), FaceColor(rgb: 0xFF9500), FaceColor(rgb: 0xFFCC00), FaceColor(rgb: 0xA4E063),
        FaceColor(rgb: 0x34C759), FaceColor(rgb: 0x30B0C7), FaceColor(rgb: 0x007AFF), FaceColor(rgb: 0x1C2E8C),
        FaceColor(rgb: 0xAF52DE), FaceColor(rgb: 0xFF7EB6), FaceColor(rgb: 0x8B5A2B), FaceColor(rgb: 0xF5D6B4),
    ]
}

/// An area of a drawing, inclusive (empty when x1 < x0)
public struct PaintRect: Equatable, Sendable {
    public var x0, y0, x1, y1: Int

    public static let empty = PaintRect(x0: 0, y0: 0, x1: -1, y1: -1)

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public var isEmpty: Bool { x1 < x0 || y1 < y0 }

    public func union(_ o: PaintRect) -> PaintRect {
        if isEmpty { return o }
        if o.isEmpty { return self }
        return PaintRect(x0: min(x0, o.x0), y0: min(y0, o.y0), x1: max(x1, o.x1), y1: max(y1, o.y1))
    }
}

public enum PaintFileError: Error, Equatable {
    case notADrawing, corrupt
}

/// A drawing being edited (a class: the pixels are changed in place, never copied)
public final class PaintImage {
    public static let canvasWidth = 205
    public static let canvasHeight = 251
    public static let magic: [UInt8] = Array("WPN1".utf8)
    public static let thumbnailMagic: [UInt8] = Array("WPT1".utf8)

    public let width: Int
    public let height: Int
    public let stride: Int
    /// Rows a band holds
    public static let bandRows = 16
    /// Two pixels a byte, the left one in the high nibble; `bandRows` rows a band
    private var bands: [[UInt8]] = []
    private let bandBytes: Int
    /// All the pixels' bytes
    public let byteCount: Int

    public init(width: Int = canvasWidth, height: Int = canvasHeight, color: UInt8 = 0) {
        self.width = width
        self.height = height
        stride = (width + 1) / 2
        bandBytes = stride * Self.bandRows
        byteCount = stride * height
        let fill = color & 0xF | (color & 0xF) << 4
        var y = 0
        while y < height {
            bands.append([UInt8](repeating: fill, count: stride * min(Self.bandRows, height - y)))
            y += Self.bandRows
        }
    }

    /// All the pixels' bytes in one array (a copy: for tests and small images)
    public var pixels: [UInt8] {
        var all: [UInt8] = []
        for band in bands { all += band }
        return all
    }

    /// Byte `i` of all the pixels (row by row)
    @inline(__always)
    public func byte(_ i: Int) -> UInt8 { bands[i / bandBytes][i % bandBytes] }

    @inline(__always)
    private func setByte(_ i: Int, _ b: UInt8) { bands[i / bandBytes][i % bandBytes] = b }

    public func pixel(_ x: Int, _ y: Int) -> UInt8 {
        let b = byte(y * stride + x / 2)
        return x & 1 == 0 ? b >> 4 : b & 0xF
    }

    public func setPixel(_ x: Int, _ y: Int, _ c: UInt8) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = y * stride + x / 2
        let b = byte(i)
        setByte(i, x & 1 == 0 ? (b & 0x0F) | c << 4 : (b & 0xF0) | c)
    }

    public func clear(_ c: UInt8 = 0) {
        let b = c & 0xF | (c & 0xF) << 4
        for i in 0..<byteCount { setByte(i, b) }
    }

    /// A round dot of radius `r` (0: one pixel)
    @discardableResult
    public func dot(_ cx: Int, _ cy: Int, radius r: Int, _ c: UInt8) -> PaintRect {
        for dy in -r...r {
            for dx in -r...r where dx * dx + dy * dy <= r * r + r {
                setPixel(cx + dx, cy + dy, c)
            }
        }
        return PaintRect(x0: max(0, cx - r), y0: max(0, cy - r), x1: min(width - 1, cx + r), y1: min(height - 1, cy + r))
    }

    /// A line of dots from (x0, y0) to (x1, y1)
    @discardableResult
    public func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, radius r: Int, _ c: UInt8) -> PaintRect {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var area = PaintRect.empty
        while true {
            area = area.union(dot(x, y, radius: r, c))
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x += sx
            }
            if e2 <= dx {
                err += dx
                y += sy
            }
        }
        return area
    }

    /// Fills the area of (x, y)'s colour around it (4-connected) with `c`: what changed
    @discardableResult
    public func fill(_ x: Int, _ y: Int, _ c: UInt8) -> PaintRect {
        guard x >= 0, y >= 0, x < width, y < height else { return .empty }
        let old = pixel(x, y)
        guard old != c else { return .empty }
        var area = PaintRect.empty
        // Scanline fill: a stack of seeds, each filled to the left and right, seeding the rows above and below
        var stack: [(Int, Int)] = [(x, y)]
        while let (sx, sy) = stack.popLast() {
            guard pixel(sx, sy) == old else { continue }
            var l = sx, r = sx
            while l > 0 && pixel(l - 1, sy) == old { l -= 1 }
            while r < width - 1 && pixel(r + 1, sy) == old { r += 1 }
            for i in l...r { setPixel(i, sy, c) }
            area = area.union(PaintRect(x0: l, y0: sy, x1: r, y1: sy))
            for ny in [sy - 1, sy + 1] where ny >= 0 && ny < height {
                var i = l
                while i <= r {
                    if pixel(i, ny) == old {
                        stack.append((i, ny))
                        while i <= r && pixel(i, ny) == old { i += 1 }
                    }
                    i += 1
                }
            }
        }
        return area
    }

    // MARK: Files

    public func encoded() -> [UInt8] {
        var out: [UInt8] = []
        _ = write { out += $0; return true }
        return out
    }

    /// The drawing file, handed to `sink` a piece at a time (the watch has no room for a copy of it): false if the
    /// sink failed
    public func write(_ sink: ([UInt8]) -> Bool) -> Bool {
        guard sink(Self.magic + Self.le16(width) + Self.le16(height)) else { return false }
        var chunk: [UInt8] = []
        chunk.reserveCapacity(256)
        let ok = forEachRun { n, b in
            chunk.append(UInt8(n))
            chunk.append(b)
            guard chunk.count >= 254 else { return true }
            defer { chunk.removeAll(keepingCapacity: true) }
            return sink(chunk)
        }
        return ok && (chunk.isEmpty || sink(chunk))
    }

    /// The runs of equal bytes (at most 255 long), in order; stops when `body` returns false
    private func forEachRun(_ body: (Int, UInt8) -> Bool) -> Bool {
        var i = 0
        while i < byteCount {
            let b = byte(i)
            var n = 1
            while n < 255 && i + n < byteCount && byte(i + n) == b { n += 1 }
            guard body(n, b) else { return false }
            i += n
        }
        return true
    }

    /// The runs in `bytes` from `start` into the pixels, if they make exactly the pixels' bytes (else unchanged)
    private func decodeRuns(_ bytes: [UInt8], from start: Int) -> Bool {
        guard PaintRLE.decodedCount(bytes, from: start) == byteCount else { return false }
        var o = 0
        var i = start
        while i + 1 < bytes.count && o < byteCount {
            let n = Int(bytes[i])
            guard n > 0 else { return false }
            for k in 0..<n { setByte(o + k, bytes[i + 1]) }
            o += n
            i += 2
        }
        return o == byteCount
    }

    public convenience init(decoding bytes: [UInt8]) throws(PaintFileError) {
        guard bytes.count >= 8, bytes.prefix(4).elementsEqual(Self.magic) else { throw .notADrawing }
        let w = Int(bytes[4]) | Int(bytes[5]) << 8, h = Int(bytes[6]) | Int(bytes[7]) << 8
        guard w > 0, h > 0, w <= 1024, h <= 1024 else { throw .corrupt }
        self.init(width: w, height: h)
        guard decodeRuns(bytes, from: 8) else { throw .corrupt }
    }

    /// Loads a drawing file of this size into these pixels (no second copy: the watch has room for one).
    /// On failure the pixels are unchanged.
    public func load(_ bytes: [UInt8]) throws(PaintFileError) {
        guard bytes.count >= 8, bytes.prefix(4).elementsEqual(Self.magic) else { throw .notADrawing }
        let w = Int(bytes[4]) | Int(bytes[5]) << 8, h = Int(bytes[6]) | Int(bytes[7]) << 8
        guard w == width, h == height else { throw .corrupt }
        guard decodeRuns(bytes, from: 8) else { throw .corrupt }
    }

    /// Restores pixels saved with `snapshot()`, in place
    public func restore(_ snapshot: [UInt8]) -> Bool {
        decodeRuns(snapshot, from: 0)
    }

    /// The pixels run-length encoded (for undo): one allocation of the right size (growing an array would briefly
    /// need twice the memory)
    public func snapshot() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(snapshotSize)
        _ = forEachRun { n, b in
            out.append(UInt8(n))
            out.append(b)
            return true
        }
        return out
    }

    /// How big `snapshot()` would be
    public var snapshotSize: Int {
        var size = 0
        _ = forEachRun { _, _ in
            size += 2
            return true
        }
        return size
    }

    /// Half the size each way: of each 2 x 2, the first pixel that isn't the paper (so thin lines stay)
    public func thumbnail() -> PaintImage {
        let t = PaintImage(width: (width + 1) / 2, height: (height + 1) / 2)
        for ty in 0..<t.height {
            for tx in 0..<t.width {
                t.setPixel(tx, ty, thumbnailPixel(tx, ty))
            }
        }
        return t
    }

    private func thumbnailPixel(_ tx: Int, _ ty: Int) -> UInt8 {
        let c = pixel(min(2 * tx, width - 1), min(2 * ty, height - 1))
        guard c == 0 else { return c }
        for (dx, dy) in [(1, 0), (0, 1), (1, 1)] {
            let x = 2 * tx + dx, y = 2 * ty + dy
            if x < width && y < height && pixel(x, y) != 0 { return pixel(x, y) }
        }
        return 0
    }

    /// This drawing's thumbnail file (`thumbnail()` as a file), a row at a time
    public func writeThumbnail(_ sink: ([UInt8]) -> Bool) -> Bool {
        let tw = (width + 1) / 2, th = (height + 1) / 2
        guard sink(Self.thumbnailMagic + Self.le16(tw) + Self.le16(th)) else { return false }
        var row = [UInt8](repeating: 0, count: (tw + 1) / 2)
        for ty in 0..<th {
            for tx in Swift.stride(from: 0, to: tw, by: 2) {
                let hi = thumbnailPixel(tx, ty)
                let lo = tx + 1 < tw ? thumbnailPixel(tx + 1, ty) : 0
                row[tx / 2] = hi << 4 | lo
            }
            guard sink(row) else { return false }
        }
        return true
    }

    /// As a thumbnail file (of a thumbnail image)
    public func thumbnailFile() -> [UInt8] {
        Self.thumbnailMagic + Self.le16(width) + Self.le16(height) + pixels
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
}

public enum PaintRLE {
    /// One allocation of the right size (on the watch, growing an array would briefly need twice the memory)
    public static func encode(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(encodedSize(bytes))
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            var n = 1
            while n < 255 && i + n < bytes.count && bytes[i + n] == b { n += 1 }
            out.append(UInt8(n))
            out.append(b)
            i += n
        }
        return out
    }

    public static func encodedSize(_ bytes: [UInt8]) -> Int {
        var size = 0
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            var n = 1
            while n < 255 && i + n < bytes.count && bytes[i + n] == b { n += 1 }
            size += 2
            i += n
        }
        return size
    }

    /// How many bytes the runs make
    public static func decodedCount(_ bytes: [UInt8], from start: Int) -> Int {
        var n = 0
        var i = start
        while i + 1 < bytes.count {
            n += Int(bytes[i])
            i += 2
        }
        return n
    }
}
