import Testing
@testable import WatchFaceKit

struct PaintTests {
    @Test func pixelsPackTwoToAByte() {
        let p = PaintImage(width: 3, height: 2)
        #expect(p.stride == 2)
        p.setPixel(0, 0, 5)
        p.setPixel(1, 0, 10)
        p.setPixel(2, 1, 15)
        #expect(p.pixels[0] == 0x5A)
        #expect(p.pixel(0, 0) == 5 && p.pixel(1, 0) == 10 && p.pixel(2, 1) == 15 && p.pixel(0, 1) == 0)
        p.setPixel(-1, 0, 3)    // Outside: ignored
        p.setPixel(3, 0, 3)
        #expect(p.pixels[0] == 0x5A)
    }

    @Test func linesAndDots() {
        let p = PaintImage(width: 20, height: 20)
        let area = p.line(2, 2, 10, 2, radius: 0, 1)
        #expect(area == PaintRect(x0: 2, y0: 2, x1: 10, y1: 2))
        #expect((2...10).allSatisfy { p.pixel($0, 2) == 1 })
        #expect(p.pixel(11, 2) == 0)
        let dot = p.dot(15, 15, radius: 2, 4)
        #expect(dot == PaintRect(x0: 13, y0: 13, x1: 17, y1: 17))
        #expect(p.pixel(15, 13) == 4 && p.pixel(13, 13) == 0)   // Round: not the corners
    }

    @Test func fillStopsAtLines() {
        let p = PaintImage(width: 10, height: 10)
        p.line(5, 0, 5, 9, radius: 0, 1)          // A wall down the middle
        let area = p.fill(1, 1, 4)
        #expect(area == PaintRect(x0: 0, y0: 0, x1: 4, y1: 9))
        #expect(p.pixel(4, 9) == 4 && p.pixel(5, 3) == 1 && p.pixel(6, 3) == 0)
        #expect(p.fill(1, 1, 4).isEmpty)          // Same colour: nothing
    }

    @Test func fillGoesAroundCorners() {
        let p = PaintImage(width: 8, height: 6)
        // A U shape: the inside connects to the outside only over the top
        p.line(2, 1, 2, 4, radius: 0, 1)
        p.line(2, 4, 5, 4, radius: 0, 1)
        p.line(5, 1, 5, 4, radius: 0, 1)
        p.fill(0, 5, 2)
        #expect(p.pixel(3, 2) == 2 && p.pixel(7, 0) == 2)
    }

    @Test func filesRoundTrip() throws {
        let p = PaintImage()
        p.line(10, 10, 100, 200, radius: 3, 6)
        p.fill(0, 0, 10)
        let bytes = p.encoded()
        #expect(bytes.count < 4000)     // Mostly two colours: small
        #expect(p.snapshotSize == bytes.count - 8 && p.snapshot().count == p.snapshotSize)
        var failing = 0
        #expect(!p.write { _ in failing += 1; return failing < 3 })     // A failing sink stops it
        let q = try PaintImage(decoding: bytes)
        #expect(q.width == p.width && q.height == p.height && q.pixels == p.pixels)
        #expect(throws: PaintFileError.notADrawing) { try PaintImage(decoding: Array("WPT1xxxx".utf8)) }
        #expect(throws: PaintFileError.corrupt) { try PaintImage(decoding: Array(bytes.dropLast(2))) }
    }

    @Test func undoSnapshots() {
        let p = PaintImage()
        let before = p.snapshot()
        p.dot(50, 50, radius: 5, 1)
        #expect(p.pixel(50, 50) == 1)
        #expect(p.restore(before))
        #expect(p.pixel(50, 50) == 0)
    }

    @Test func thumbnailsKeepThinLines() {
        let p = PaintImage(width: 10, height: 10)
        p.line(0, 5, 9, 5, radius: 0, 1)   // An odd row: the thumbnail's samples are even rows
        let t = p.thumbnail()
        #expect(t.width == 5 && t.height == 5)
        #expect((0..<5).allSatisfy { t.pixel($0, 2) == 1 })
        let file = t.thumbnailFile()
        #expect(file.prefix(4).elementsEqual(PaintImage.thumbnailMagic) && file.count == 8 + t.stride * 5)
        // Written a row at a time from the drawing: the same file
        var streamed: [UInt8] = []
        #expect(p.writeThumbnail { streamed += $0; return true })
        #expect(streamed == file)
        #expect(PaintImage(width: 9, height: 3).writeThumbnail { _ in true })
    }
}
