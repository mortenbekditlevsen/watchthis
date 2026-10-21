// LVGL's binary font format ("binfont", what lv_font_conv --format bin writes and lv_binfont_create() loads), for
// face fonts the phone rasterizes. Written as LVGL 9's loader (src/font/binfont_loader) reads it:
//
//   head: length "head" font_header_bin_t (40 bytes)
//   cmap: length "cmap" count(4) { data_offset(4) range_start(4) range_length(2) glyph_id_start(2) entries(2)
//                                  format(1) pad(1) }* data
//   loca: length "loca" count(4) offset(4)*            (offsets from the start of glyf)
//   glyf: length "glyf" glyph*                          (bit streams, MSB first; glyph 0 is unused)
//
// Every table starts with its length (including the 8-byte label) as UInt32 LE. Glyphs: advance (16 bits, 1/16 px),
// x/y offset (12 bits signed each), width/height (12 bits each), then the bitmap: 4 bits per pixel, rows packed
// back to back. One sparse "tiny" cmap (glyph ids follow the sorted code points); no kerning.

public struct BinFontGlyph: Equatable, Sendable {
    public var codepoint: UInt32
    /// Pixels (fractional)
    public var advance: Float
    /// Left edge of the bitmap relative to the pen position
    public var offsetX: Int
    /// Bottom edge of the bitmap above the baseline (negative: below)
    public var offsetY: Int
    public var width: Int
    public var height: Int
    /// width * height coverage values (0-255), top row first
    public var alpha: [UInt8]

    public init(codepoint: UInt32, advance: Float, offsetX: Int, offsetY: Int, width: Int, height: Int,
                alpha: [UInt8]) {
        self.codepoint = codepoint
        self.advance = advance
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.height = height
        self.alpha = alpha
    }
}

public struct BinFont: Equatable, Sendable {
    /// Pixels
    public var size: Int
    /// Above the baseline (positive)
    public var ascent: Int
    /// Below the baseline (positive)
    public var descent: Int
    public var glyphs: [BinFontGlyph]

    public init(size: Int, ascent: Int, descent: Int, glyphs: [BinFontGlyph]) {
        self.size = size
        self.ascent = ascent
        self.descent = descent
        self.glyphs = glyphs
    }

    static let xyBits = 12
    static let whBits = 12
    static let advanceBits = 16
    static let bitsPerPixel = 4

    public func encoded() -> [UInt8] {
        var sorted: [BinFontGlyph] = []
        for g in glyphs.sorted(by: { $0.codepoint < $1.codepoint }) where g.codepoint <= 0xFFFF {
            if sorted.last?.codepoint != g.codepoint { sorted.append(g) }
        }

        // head
        var head = ByteWriter()
        head.u32(1) // version
        head.u16(3) // tables (head, cmap, loca, glyf; the loader only checks for >= 4 = kerning)
        head.u16(size)
        head.u16(ascent)
        head.i16(-descent)
        head.u16(ascent) // typo ascent
        head.i16(-descent)
        head.u16(0) // typo line gap
        head.i16(sorted.map { $0.offsetY }.min() ?? 0)
        head.i16(sorted.map { $0.offsetY + $0.height }.max() ?? 0)
        head.u16(0) // default advance width: per glyph
        head.u16(0) // kerning scale
        head.bytes([1, 0, 1, UInt8(BinFont.bitsPerPixel), UInt8(BinFont.xyBits), UInt8(BinFont.whBits),
                    UInt8(BinFont.advanceBits), 0, 0, 0])
        // index to loc: 32 bit; glyph ids: 1 byte (only for kerning); advance: 1/16 px; bpp; field widths;
        // compression: none; subpixel: none; padding
        head.i16(-max(1, size / 10)) // underline position
        head.u16(max(1, size / 20)) // underline thickness

        // cmap
        var cmap = ByteWriter()
        let rangeStart = sorted.first?.codepoint ?? 0
        let rangeLength = sorted.isEmpty ? 0 : Int(sorted.last!.codepoint - rangeStart) + 1
        cmap.u32(1)
        cmap.u32(8 + 4 + 16) // data offset, from the start of the cmap table
        cmap.u32(rangeStart)
        cmap.u16(rangeLength)
        cmap.u16(1) // first glyph id
        cmap.u16(sorted.count)
        cmap.bytes([3, 0]) // LV_FONT_FMT_TXT_CMAP_SPARSE_TINY
        for g in sorted {
            cmap.u16(Int(g.codepoint - rangeStart))
        }

        // glyf (and loca with the offsets into it)
        var glyf: [UInt8] = []
        var offsets: [UInt32] = []
        let empty = BinFontGlyph(codepoint: 0, advance: 0, offsetX: 0, offsetY: 0, width: 0, height: 0, alpha: [])
        for g in [empty] + sorted {
            offsets.append(UInt32(8 + glyf.count))
            var bits = BitWriter()
            bits.write(UInt32(max(0, min(0xFFFF, Int((g.advance * 16).rounded())))), BinFont.advanceBits)
            bits.write(UInt32(bitPattern: Int32(g.offsetX)), BinFont.xyBits)
            bits.write(UInt32(bitPattern: Int32(g.offsetY)), BinFont.xyBits)
            bits.write(UInt32(g.width), BinFont.whBits)
            bits.write(UInt32(g.height), BinFont.whBits)
            for a in g.alpha.prefix(g.width * g.height) {
                bits.write(UInt32((Int(a) * 15 + 127) / 255), BinFont.bitsPerPixel)
            }
            glyf += bits.bytes
        }
        var loca = ByteWriter()
        loca.u32(offsets.count)
        for o in offsets { loca.u32(Int(o)) }

        var out: [UInt8] = []
        for (label, body) in [("head", head.data), ("cmap", cmap.data), ("loca", loca.data), ("glyf", glyf)] {
            var b = body
            while b.count % 4 != 0 { b.append(0) } // keep tables 4-byte aligned
            var w = ByteWriter()
            w.u32(8 + b.count)
            w.bytes(Array(label.utf8))
            out += w.data + b
        }
        return out
    }

    /// Reads a font written by `encoded()` (the subset of the format it uses), the way LVGL's loader does
    public init(decoding data: [UInt8]) throws(FaceDecodingError) {
        var r = ByteReader(data)
        func table(_ label: String) throws(FaceDecodingError) -> (start: Int, length: Int) {
            let start = r.position
            let length = Int(try r.u32())
            guard Array(try r.bytes(4)) == Array(label.utf8), length >= 8 else { throw .invalid }
            return (start, length)
        }
        let headTable = try table("head")
        _ = try r.u32() // version
        _ = try r.u16() // tables
        size = Int(try r.u16())
        ascent = Int(try r.u16())
        descent = -Int(try r.i16())
        _ = try r.bytes(14)
        let formats = Array(try r.bytes(10))
        guard formats[0] == 1, formats[2] == 1, formats[3] == 4, formats[7] == 0 else { throw .invalid }
        let xyBits = Int(formats[4]), whBits = Int(formats[5]), advanceBits = Int(formats[6])

        r.position = headTable.start + headTable.length
        let cmapTable = try table("cmap")
        guard try r.u32() == 1 else { throw .invalid }
        let dataOffset = Int(try r.u32())
        let rangeStart = try r.u32()
        _ = try r.u16()
        _ = try r.u16()
        let entries = Int(try r.u16())
        guard try r.bytes(2).first == 3 else { throw .invalid }
        r.position = cmapTable.start + dataOffset
        var codepoints: [UInt32] = []
        for _ in 0..<entries { codepoints.append(rangeStart + UInt32(try r.u16())) }

        r.position = cmapTable.start + cmapTable.length
        let locaTable = try table("loca")
        let count = Int(try r.u32())
        var offsets: [Int] = []
        for _ in 0..<count { offsets.append(Int(try r.u32())) }
        r.position = locaTable.start + locaTable.length
        let glyfStart = r.position
        _ = try table("glyf")

        glyphs = []
        for i in 1..<count {
            var bits = BitReader(data, byteOffset: glyfStart + offsets[i])
            let advance = Float(try bits.read(advanceBits)) / 16
            let ox = try bits.readSigned(xyBits), oy = try bits.readSigned(xyBits)
            let w = Int(try bits.read(whBits)), h = Int(try bits.read(whBits))
            var alpha: [UInt8] = []
            for _ in 0..<(w * h) { alpha.append(UInt8(try bits.read(4) * 17)) }
            guard i - 1 < codepoints.count else { throw .invalid }
            glyphs.append(BinFontGlyph(codepoint: codepoints[i - 1], advance: advance, offsetX: ox, offsetY: oy,
                                       width: w, height: h, alpha: alpha))
        }
    }
}

struct ByteWriter {
    var data: [UInt8] = []
    mutating func bytes(_ b: [UInt8]) { data += b }
    mutating func u16(_ v: Int) {
        data.append(UInt8(truncatingIfNeeded: v))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
    }
    mutating func i16(_ v: Int) { u16(Int(UInt16(bitPattern: Int16(clamping: v)))) }
    mutating func u32(_ v: Int) { u32(UInt32(truncatingIfNeeded: v)) }
    mutating func u32(_ v: UInt32) {
        for i in 0..<4 { data.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) }
    }
}

struct ByteReader {
    let data: [UInt8]
    var position = 0
    init(_ data: [UInt8]) { self.data = data }
    mutating func bytes(_ n: Int) throws(FaceDecodingError) -> ArraySlice<UInt8> {
        guard position + n <= data.count else { throw .truncated }
        defer { position += n }
        return data[position..<position + n]
    }
    mutating func u16() throws(FaceDecodingError) -> UInt16 {
        let b = try bytes(2)
        return UInt16(b[b.startIndex]) | UInt16(b[b.startIndex + 1]) << 8
    }
    mutating func i16() throws(FaceDecodingError) -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u32() throws(FaceDecodingError) -> UInt32 {
        let b = try bytes(4)
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(b[b.startIndex + i]) << (8 * UInt32(i)) }
        return v
    }
}

struct BitWriter {
    var bytes: [UInt8] = []
    private var used = 8 // bits used in the last byte

    /// The low `count` bits of `value`, most significant first
    mutating func write(_ value: UInt32, _ count: Int) {
        for i in stride(from: count - 1, through: 0, by: -1) {
            if used == 8 {
                bytes.append(0)
                used = 0
            }
            if (value >> UInt32(i)) & 1 != 0 {
                bytes[bytes.count - 1] |= 0x80 >> UInt8(used)
            }
            used += 1
        }
    }
}

struct BitReader {
    let data: [UInt8]
    var bit: Int

    init(_ data: [UInt8], byteOffset: Int) {
        self.data = data
        bit = byteOffset * 8
    }

    mutating func read(_ count: Int) throws(FaceDecodingError) -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<count {
            guard bit / 8 < data.count else { throw .truncated }
            v = v << 1 | UInt32((data[bit / 8] >> UInt8(7 - bit % 8)) & 1)
            bit += 1
        }
        return v
    }

    mutating func readSigned(_ count: Int) throws(FaceDecodingError) -> Int {
        let v = try read(count)
        return v & (1 << UInt32(count - 1)) != 0 ? Int(v) - (1 << count) : Int(v)
    }
}
