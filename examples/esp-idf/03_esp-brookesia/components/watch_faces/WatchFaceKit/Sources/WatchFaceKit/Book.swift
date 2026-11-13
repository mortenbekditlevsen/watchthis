// Books for the watch's Bøger app (file_store kind FILE_STORE_BOOK, docs/watch-ble-protocol.md §14). The phone turns
// TXT and EPUB into this: UTF-8 text with paragraphs separated by "\n" (characters limited to what the watch's reading
// font has, see BookText in the app) and a table of chapters. The watch reads the header and the table, then the text
// a window at a time (a book doesn't fit in its RAM) and lays out a page at a time (BookLayout).
//
//   "WBK1" | version u8 | chapterCount u16 | textOffset u32 | textLength u32       (little endian)
//   chapterCount x { textByteOffset u32 | titleLength u8 | title (UTF-8) }
//   text (at textOffset, textLength bytes)

public struct BookChapter: Equatable, Sendable {
    /// Where it starts in the text (a byte offset)
    public var offset: Int
    public var title: String

    public init(offset: Int, title: String) {
        self.offset = offset
        self.title = title
    }
}

public enum BookDecodingError: Error, Equatable {
    case notABook, truncated
}

public enum BookFile {
    public static let magic: [UInt8] = Array("WBK1".utf8)
    public static let version: UInt8 = 1
    /// The fixed part of the header
    public static let headerSize = 15

    /// The whole file. Titles are cut to 255 bytes (at a character boundary).
    public static func encode(text: [UInt8], chapters: [BookChapter]) -> [UInt8] {
        var table: [UInt8] = []
        for chapter in chapters.prefix(Int(UInt16.max)) {
            table += le32(chapter.offset)
            var title = Array(chapter.title.utf8)
            if title.count > 255 {
                var n = 255
                while n > 0 && title[n] & 0xC0 == 0x80 { n -= 1 }
                title = Array(title[0..<n])
            }
            table.append(UInt8(title.count))
            table += title
        }
        let textOffset = headerSize + table.count
        return magic + [version] + le16(min(chapters.count, Int(UInt16.max))) + le32(textOffset) + le32(text.count)
            + table + text
    }

    /// The header's fixed part: the chapter count, and where the text is
    public static func header(_ bytes: [UInt8]) throws(BookDecodingError) -> (chapters: Int, textOffset: Int,
                                                                               textLength: Int) {
        guard bytes.count >= headerSize else { throw .truncated }
        guard bytes.prefix(4).elementsEqual(magic) else { throw .notABook }
        let chapters = Int(bytes[5]) | Int(bytes[6]) << 8
        let textOffset = u32(bytes, 7), textLength = u32(bytes, 11)
        guard textOffset >= headerSize else { throw .notABook }
        return (chapters, textOffset, textLength)
    }

    /// The chapter table: the bytes from `headerSize` up to the text
    public static func chapters(_ table: [UInt8], count: Int) throws(BookDecodingError) -> [BookChapter] {
        var result: [BookChapter] = []
        var i = 0
        for _ in 0..<count {
            guard i + 5 <= table.count else { throw .truncated }
            let offset = u32(table, i)
            let length = Int(table[i + 4])
            i += 5
            guard i + length <= table.count else { throw .truncated }
            result.append(BookChapter(offset: offset, title: String(decoding: table[i..<(i + length)], as: UTF8.self)))
            i += length
        }
        return result
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    private static func le32(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)]
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
    }
}

/// Line breaking for one page, on UTF-8 bytes: words wrap at spaces, a word wider than a line is broken where it has
/// to, "\n" ends a paragraph. `width(codepoint, next)` is the advance in pixels (the watch asks its font).
public enum BookLayout {
    public struct Page: Equatable, Sendable {
        /// Each line's bytes (relative to the window), without the space or newline it broke at
        public var lines: [Range<Int>]
        /// Where the next page starts (relative to the window); the window's end if it ran out
        public var end: Int
    }

    /// The page starting at `start` in `window`. `isEnd`: the window reaches the end of the text (else a line that
    /// runs into the window's end isn't taken, so the window must hold more than a page).
    public static func page(_ window: [UInt8], start: Int, isEnd: Bool, lineWidth: Int, lines maxLines: Int,
                            width: (UInt32, UInt32) -> Int) -> Page {
        var lines: [Range<Int>] = []
        var i = start
        while lines.count < maxLines && i < window.count {
            guard let line = nextLine(window, from: i, lineWidth: lineWidth, width: width) else { break }
            if !isEnd && line.next == window.count && !line.endsParagraph {
                break   // Ran into the window's end: it might go on past it
            }
            lines.append(line.range)
            i = line.next
        }
        return Page(lines: lines, end: i)
    }

    /// The line from `i`: its bytes, where the next one starts, and whether it ended a paragraph
    static func nextLine(_ w: [UInt8], from start: Int, lineWidth: Int,
                         width: (UInt32, UInt32) -> Int) -> (range: Range<Int>, next: Int, endsParagraph: Bool)? {
        guard start < w.count else { return nil }
        var x = 0
        var i = start
        var lastSpace: Int?    // Where the last space was (a break there)
        while i < w.count {
            let (cp, n) = decode(w, i)
            if cp == 0x0A {
                return (start..<i, i + 1, true)
            }
            let next = i + n < w.count ? decode(w, i + n).0 : 0
            let advance = width(cp, next)
            if cp == 0x20 {
                lastSpace = i
            } else if x + advance > lineWidth && i > start {
                if let space = lastSpace, space > start {
                    return (start..<space, space + 1, false)
                }
                return (start..<i, i, false)    // One long word: broken where it must
            }
            x += advance
            i += n
        }
        return (start..<i, i, false)
    }

    /// The codepoint at `i` and its byte count (a stray continuation byte counts as one replacement character)
    public static func decode(_ b: [UInt8], _ i: Int) -> (UInt32, Int) {
        let c = b[i]
        if c < 0x80 { return (UInt32(c), 1) }
        let n = c >= 0xF0 ? 4 : (c >= 0xE0 ? 3 : (c >= 0xC0 ? 2 : 1))
        if n == 1 || i + n > b.count { return (0xFFFD, 1) }
        var v = UInt32(c) & (0xFF >> UInt32(n + 1))
        for k in 1..<n {
            let cc = b[i + k]
            guard cc & 0xC0 == 0x80 else { return (0xFFFD, 1) }
            v = v << 6 | UInt32(cc & 0x3F)
        }
        return (v, n)
    }

    /// The start of the paragraph `offset` is in (just after the "\n" before it), searching back to `limit`
    public static func paragraphStart(_ window: [UInt8], before offset: Int, limit: Int = 0) -> Int {
        var i = min(offset, window.count)
        while i > limit && window[i - 1] != 0x0A { i -= 1 }
        return i
    }

    /// `offset` moved back to the start of the character it is in
    public static func characterStart(_ window: [UInt8], _ offset: Int) -> Int {
        var i = min(offset, window.count)
        while i > 0 && i < window.count && window[i] & 0xC0 == 0x80 { i -= 1 }
        return i
    }
}
