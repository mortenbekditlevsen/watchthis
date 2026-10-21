// Tag-length-value records, the building block of the face file format (docs/watch-face-format.md):
//
//   record = tag(varint) length(varint) payload(length bytes)
//
// Varints are unsigned LEB128; signed values are zigzag encoded. A payload is a scalar or a sequence of nested
// records. Readers skip tags they don't know, which is what lets the format grow.

public enum FaceDecodingError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt8)
    case truncated
    case invalid
}

public struct TLVWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func appendRaw(_ raw: [UInt8]) {
        bytes.append(contentsOf: raw)
    }

    public mutating func appendVarint(_ value: UInt32) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: v) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    private mutating func record(_ tag: UInt32, _ payload: [UInt8]) {
        appendVarint(tag)
        appendVarint(UInt32(payload.count))
        bytes.append(contentsOf: payload)
    }

    public mutating func uint(_ tag: UInt32, _ value: Int) {
        var w = TLVWriter()
        w.appendVarint(UInt32(clamping: max(0, value)))
        record(tag, w.bytes)
    }

    public mutating func sint(_ tag: UInt32, _ value: Int) {
        let v = Int32(clamping: value)
        let zigzag = UInt32(bitPattern: (v << 1) ^ (v >> 31))
        var w = TLVWriter()
        w.appendVarint(zigzag)
        record(tag, w.bytes)
    }

    public mutating func bool(_ tag: UInt32, _ value: Bool) {
        uint(tag, value ? 1 : 0)
    }

    public mutating func color(_ tag: UInt32, _ value: FaceColor) {
        record(tag, [value.r, value.g, value.b, value.a])
    }

    public mutating func string(_ tag: UInt32, _ value: String) {
        record(tag, Array(value.utf8))
    }

    public mutating func raw(_ tag: UInt32, _ payload: [UInt8]) {
        record(tag, payload)
    }

    public mutating func nested(_ tag: UInt32, _ body: (inout TLVWriter) -> Void) {
        var w = TLVWriter()
        body(&w)
        record(tag, w.bytes)
    }
}

public struct TLVValue {
    public let payload: ArraySlice<UInt8>

    public func uint() throws(FaceDecodingError) -> Int {
        var r = TLVReader(payload)
        let v = try r.readVarint()
        return Int(clamping: v)
    }

    public func sint() throws(FaceDecodingError) -> Int {
        var r = TLVReader(payload)
        let z = try r.readVarint()
        return Int(Int32(bitPattern: (z >> 1) ^ (0 &- (z & 1))))
    }

    public func bool() throws(FaceDecodingError) -> Bool {
        try uint() != 0
    }

    public func color() throws(FaceDecodingError) -> FaceColor {
        guard payload.count >= 4 else { throw .truncated }
        let i = payload.startIndex
        return FaceColor(r: payload[i], g: payload[i + 1], b: payload[i + 2], a: payload[i + 3])
    }

    public func string() throws(FaceDecodingError) -> String {
        String(decoding: payload, as: UTF8.self)
    }

    public var bytes: [UInt8] { Array(payload) }

    public var records: TLVReader { TLVReader(payload) }
}

public struct TLVReader {
    private let data: ArraySlice<UInt8>
    private var position: Int

    public init(_ data: ArraySlice<UInt8>) {
        self.data = data
        self.position = data.startIndex
    }

    public init(_ data: [UInt8]) {
        self.init(data[...])
    }

    public var isAtEnd: Bool { position >= data.endIndex }

    public mutating func readByte() throws(FaceDecodingError) -> UInt8 {
        guard position < data.endIndex else { throw .truncated }
        defer { position += 1 }
        return data[position]
    }

    public mutating func readVarint() throws(FaceDecodingError) -> UInt32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while true {
            let byte = try readByte()
            guard shift < 32 else { throw .invalid }
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    /// The next record, or nil at the end
    public mutating func next() throws(FaceDecodingError) -> (tag: UInt32, value: TLVValue)? {
        guard !isAtEnd else { return nil }
        let tag = try readVarint()
        let length = Int(try readVarint())
        guard length <= data.endIndex - position else { throw .truncated }
        let payload = data[position..<position + length]
        position += length
        return (tag, TLVValue(payload: payload))
    }
}
