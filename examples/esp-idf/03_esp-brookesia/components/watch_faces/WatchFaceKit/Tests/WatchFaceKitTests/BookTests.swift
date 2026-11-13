import Testing
@testable import WatchFaceKit

struct BookTests {
    @Test func fileRoundTrips() throws {
        let text = Array("Første kapitel.\nAnden linje.\nKapitel 2\nSlut.".utf8)
        let chapters = [BookChapter(offset: 0, title: "Kapitel 1 – Begyndelsen"), BookChapter(offset: 30, title: "Kapitel 2")]
        let file = BookFile.encode(text: text, chapters: chapters)
        let header = try BookFile.header(Array(file.prefix(BookFile.headerSize)))
        #expect(header.chapters == 2)
        #expect(header.textLength == text.count)
        let table = Array(file[BookFile.headerSize..<header.textOffset])
        #expect(try BookFile.chapters(table, count: header.chapters) == chapters)
        #expect(Array(file[header.textOffset...]) == text)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: BookDecodingError.notABook) { try BookFile.header(Array("WFCE00000000000".utf8)) }
        #expect(throws: BookDecodingError.truncated) { try BookFile.header(Array("WBK1".utf8)) }
    }

    @Test func longTitlesAreCutAtACharacter() throws {
        let title = String(repeating: "ø", count: 200)  // 400 bytes
        let file = BookFile.encode(text: [], chapters: [BookChapter(offset: 0, title: title)])
        let header = try BookFile.header(file)
        let chapters = try BookFile.chapters(Array(file[BookFile.headerSize..<header.textOffset]), count: 1)
        #expect(chapters[0].title == String(repeating: "ø", count: 127))
    }

    /// Every character 10 px wide
    private func layout(_ text: String, start: Int = 0, isEnd: Bool = true, width: Int = 100, lines: Int = 10)
        -> (BookLayout.Page, [String]) {
        let bytes = Array(text.utf8)
        let page = BookLayout.page(bytes, start: start, isEnd: isEnd, lineWidth: width, lines: lines) { _, _ in 10 }
        return (page, page.lines.map { String(decoding: bytes[$0], as: UTF8.self) })
    }

    @Test func wrapsAtSpaces() {
        let (page, lines) = layout("Det var en mørk og stormfuld nat.")
        #expect(lines == ["Det var en", "mørk og", "stormfuld", "nat."])
        #expect(page.end == "Det var en mørk og stormfuld nat.".utf8.count)
    }

    @Test func paragraphsAndLongWords() {
        let (_, lines) = layout("Kort.\nSuperkalifragilistisk ord")
        #expect(lines == ["Kort.", "Superkalif", "ragilistis", "k ord"])
    }

    @Test func pageEndsAfterItsLines() {
        let text = "en to tre fire fem seks syv otte ni ti"
        let (page, lines) = layout(text, width: 70, lines: 2)
        #expect(lines == ["en to", "tre"])
        let rest = String(decoding: Array(text.utf8)[page.end...], as: UTF8.self)
        #expect(rest.hasPrefix("fire"))
    }

    @Test func aLineRunningIntoTheWindowsEndWaits() {
        // Not the end of the text: the last line might continue past the window
        let (page, lines) = layout("en to tre fire fem", isEnd: false, width: 70, lines: 10)
        #expect(lines == ["en to", "tre", "fire"])
        #expect(page.end == "en to tre fire ".utf8.count)
    }

    @Test func pagesStartAtCharacters() {
        let text = Array("æøå æøå æøå æøå æøå".utf8)
        var start = 0
        while start < text.count {
            let page = BookLayout.page(text, start: start, isEnd: true, lineWidth: 35, lines: 1) { _, _ in 10 }
            #expect(page.end > start)
            #expect(page.end == text.count || text[page.end] & 0xC0 != 0x80)
            start = page.end
        }
    }

    @Test func paragraphAndCharacterStarts() {
        let b = Array("abc\nøde\nxyz".utf8)
        #expect(BookLayout.paragraphStart(b, before: 6) == 4)
        #expect(BookLayout.paragraphStart(b, before: 2) == 0)
        #expect(BookLayout.characterStart(b, 5) == 4)   // Inside the ø
        #expect(BookLayout.decode(b, 4) == (0xF8, 2))
    }
}
