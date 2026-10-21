// Streaming PNG decoding to RGB565 rows, for face background images on the watch (no PSRAM: it can't hold a
// decoded image, so rows are written out as they come). Inflating the zlib stream is left to the caller (the
// firmware uses the ESP32 ROM's tinfl):
//
//   file bytes -> PNGChunkParser (IDAT payloads go to `idat`) -> caller inflates -> PNGRowDecoder -> `row`
//
// Supported: non-interlaced, 8 bits per sample, greyscale / RGB / palette / grey+alpha / RGBA. Alpha is blended
// over `matte`. The phone always writes this profile.

public enum PNGError: Error, Equatable {
    case notPNG
    case unsupported
    case corrupt
}

public struct PNGInfo: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var colorType: UInt8
}

/// What the chunks before the image data said; everything a PNGRowDecoder needs
public struct PNGHeader: Sendable {
    public var info: PNGInfo
    public var palette: [UInt8] // RGB triplets
    public var paletteAlpha: [UInt8]
}

/// Splits a PNG file into chunks; passes the zlib stream (IDAT payloads) on, with the header
public struct PNGChunkParser {
    public private(set) var header: PNGHeader?
    public private(set) var finished = false

    private var palette: [UInt8] = []
    private var paletteAlpha: [UInt8] = []
    private var pending: [UInt8] = [] // the 8 signature bytes, then each 8-byte chunk header
    private var signatureDone = false
    private var chunkType: UInt32 = 0
    private var chunkRemaining = 0 // payload bytes left in the current chunk
    private var crcRemaining = 0
    private var chunkData: [UInt8] = [] // payload of the small chunks needed whole (IHDR, PLTE, tRNS)

    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let IHDR: UInt32 = 0x4948_4452
    static let PLTE: UInt32 = 0x504C_5445
    static let tRNS: UInt32 = 0x7452_4E53
    static let IDAT: UInt32 = 0x4944_4154
    static let IEND: UInt32 = 0x4945_4E44

    public init() {}

    /// Feed the next bytes of the file. IDAT payload bytes (the zlib stream) are passed to `idat` in order.
    public mutating func feed(_ bytes: UnsafeBufferPointer<UInt8>,
                              idat: (UnsafeBufferPointer<UInt8>, PNGHeader) throws(PNGError) -> Void)
        throws(PNGError) {
        var i = 0
        while i < bytes.count {
            if !signatureDone {
                pending.append(bytes[i])
                i += 1
                if pending.count == 8 {
                    guard pending == PNGChunkParser.signature else { throw .notPNG }
                    signatureDone = true
                    pending.removeAll()
                }
                continue
            }
            if crcRemaining > 0 {
                let n = min(crcRemaining, bytes.count - i)
                crcRemaining -= n
                i += n
                continue
            }
            if chunkRemaining > 0 {
                let n = min(chunkRemaining, bytes.count - i)
                let slice = UnsafeBufferPointer(rebasing: bytes[i..<i + n])
                if chunkType == PNGChunkParser.IDAT {
                    guard var h = header else { throw .corrupt }
                    if h.palette.isEmpty && !palette.isEmpty {
                        h.palette = palette
                        h.paletteAlpha = paletteAlpha
                        header = h
                    }
                    try idat(slice, h)
                } else if chunkType == PNGChunkParser.IHDR || chunkType == PNGChunkParser.PLTE
                            || chunkType == PNGChunkParser.tRNS {
                    chunkData.append(contentsOf: slice)
                }
                chunkRemaining -= n
                i += n
                if chunkRemaining == 0 { try endChunk() }
                continue
            }
            // Chunk header: length(4, big endian) type(4)
            pending.append(bytes[i])
            i += 1
            if pending.count == 8 {
                let length = Int(be32(pending, 0))
                chunkType = be32(pending, 4)
                pending.removeAll()
                chunkData.removeAll()
                guard length < 0x1000_0000 else { throw .corrupt }
                chunkRemaining = length
                if length == 0 { try endChunk() }
            }
        }
    }

    private mutating func endChunk() throws(PNGError) {
        crcRemaining = 4 // not checked: the upload as a whole was CRC-checked
        switch chunkType {
        case PNGChunkParser.IHDR:
            guard chunkData.count == 13 else { throw .corrupt }
            let width = Int(be32(chunkData, 0))
            let height = Int(be32(chunkData, 4))
            let bitDepth = chunkData[8]
            let colorType = chunkData[9]
            let interlace = chunkData[12]
            guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw .corrupt }
            guard bitDepth == 8, interlace == 0, [0, 2, 3, 4, 6].contains(colorType) else { throw .unsupported }
            header = PNGHeader(info: PNGInfo(width: width, height: height, colorType: colorType), palette: [],
                               paletteAlpha: [])
        case PNGChunkParser.PLTE:
            palette = chunkData
        case PNGChunkParser.tRNS:
            paletteAlpha = chunkData
        case PNGChunkParser.IEND:
            finished = true
        default:
            break
        }
    }
}

/// Turns the inflated image data into rows of little-endian RGB565
public struct PNGRowDecoder {
    public let header: PNGHeader
    /// Rows delivered so far
    public private(set) var rowsDone = 0

    private let matte: FaceColor
    private let bytesPerPixel: Int
    private let rowBytes: Int
    private var current: [UInt8] // index 0 is the filter type byte; pixels start at 1
    private var previous: [UInt8]
    private var filled = 0 // bytes of `current` filled, including the filter byte
    private var output: [UInt8]

    public init(header: PNGHeader, matte: FaceColor = .black) {
        self.header = header
        self.matte = matte
        switch header.info.colorType {
        case 0, 3: bytesPerPixel = 1
        case 2: bytesPerPixel = 3
        case 4: bytesPerPixel = 2
        default: bytesPerPixel = 4
        }
        rowBytes = header.info.width * bytesPerPixel
        current = [UInt8](repeating: 0, count: rowBytes + 1)
        previous = [UInt8](repeating: 0, count: rowBytes + 1)
        output = [UInt8](repeating: 0, count: header.info.width * 2)
    }

    public var isComplete: Bool { rowsDone == header.info.height }

    /// Feed inflated (decompressed) image data; each completed row is passed to `row`
    public mutating func feed(_ bytes: UnsafeBufferPointer<UInt8>,
                              row: (UnsafeBufferPointer<UInt8>) -> Void) throws(PNGError) {
        var i = 0
        while i < bytes.count {
            guard rowsDone < header.info.height else { return } // trailing data
            let n = min(rowBytes + 1 - filled, bytes.count - i)
            for k in 0..<n {
                current[filled + k] = bytes[i + k]
            }
            filled += n
            i += n
            if filled == rowBytes + 1 {
                try unfilter()
                convertRow()
                output.withUnsafeBufferPointer { row($0) }
                swap(&current, &previous)
                filled = 0
                rowsDone += 1
            }
        }
    }

    private mutating func unfilter() throws(PNGError) {
        let bpp = bytesPerPixel
        switch current[0] {
        case 0:
            break
        case 1: // Sub
            for x in (1 + bpp)..<(rowBytes + 1) {
                current[x] = current[x] &+ current[x - bpp]
            }
        case 2: // Up
            for x in 1..<(rowBytes + 1) {
                current[x] = current[x] &+ previous[x]
            }
        case 3: // Average
            for x in 1..<(rowBytes + 1) {
                let left = x > bpp ? Int(current[x - bpp]) : 0
                current[x] = current[x] &+ UInt8((left + Int(previous[x])) / 2)
            }
        case 4: // Paeth
            for x in 1..<(rowBytes + 1) {
                let a = x > bpp ? Int(current[x - bpp]) : 0
                let b = Int(previous[x])
                let c = x > bpp ? Int(previous[x - bpp]) : 0
                let p = a + b - c
                let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                let predictor = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                current[x] = current[x] &+ UInt8(predictor)
            }
        default:
            throw .corrupt
        }
    }

    private mutating func convertRow() {
        let palette = header.palette
        let paletteAlpha = header.paletteAlpha
        for x in 0..<header.info.width {
            let p = 1 + x * bytesPerPixel
            var r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255
            switch header.info.colorType {
            case 0:
                r = current[p]; g = r; b = r
            case 2:
                r = current[p]; g = current[p + 1]; b = current[p + 2]
            case 3:
                let index = Int(current[p])
                if index * 3 + 2 < palette.count {
                    r = palette[index * 3]; g = palette[index * 3 + 1]; b = palette[index * 3 + 2]
                } else {
                    r = 0; g = 0; b = 0
                }
                if index < paletteAlpha.count { a = paletteAlpha[index] }
            case 4:
                r = current[p]; g = r; b = r; a = current[p + 1]
            default: // 6
                r = current[p]; g = current[p + 1]; b = current[p + 2]; a = current[p + 3]
            }
            if a != 255 {
                r = blend(r, matte.r, a)
                g = blend(g, matte.g, a)
                b = blend(b, matte.b, a)
            }
            let v = RGB565.pack(r, g, b)
            output[x * 2] = UInt8(truncatingIfNeeded: v)
            output[x * 2 + 1] = UInt8(truncatingIfNeeded: v >> 8)
        }
    }
}

private func blend(_ fg: UInt8, _ bg: UInt8, _ a: UInt8) -> UInt8 {
    UInt8((Int(fg) * Int(a) + Int(bg) * (255 - Int(a)) + 127) / 255)
}

private func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
}

public enum RGB565 {
    public static func pack(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt16 {
        UInt16(r >> 3) << 11 | UInt16(g >> 2) << 5 | UInt16(b >> 3)
    }

    public static func pack(_ c: FaceColor) -> UInt16 {
        pack(c.r, c.g, c.b)
    }

    /// The 12-byte header of an LVGL 9 image file (lv_image_header_t) for an RGB565 image without padding
    public static func lvglImageHeader(width: Int, height: Int) -> [UInt8] {
        let magic: UInt8 = 0x19 // LV_IMAGE_HEADER_MAGIC
        let colorFormat: UInt8 = 0x12 // LV_COLOR_FORMAT_RGB565
        let stride = width * 2
        return [magic, colorFormat, 0, 0,
                UInt8(truncatingIfNeeded: width), UInt8(truncatingIfNeeded: width >> 8),
                UInt8(truncatingIfNeeded: height), UInt8(truncatingIfNeeded: height >> 8),
                UInt8(truncatingIfNeeded: stride), UInt8(truncatingIfNeeded: stride >> 8),
                0, 0]
    }
}
