import CoreText
import Testing
import WatchFaceGraphics
@testable import WatchFaceKit

@Suite struct GraphicsTests {
    @Test func rasterizedGlyphsAreUpright() throws {
        let font = FaceFonts.rasterize(FaceFonts.builtin(size: 40), glyphs: "L")
        let l = try #require(font.glyphs.first)
        #expect(l.width > 5 && l.height > 20)
        // An L: the bottom row is inked across, the top row only at the left
        let ink = { (row: Int) in l.alpha[(row * l.width)..<((row + 1) * l.width)].filter { $0 > 128 }.count }
        #expect(ink(l.height - 1) > 2 * ink(0))
        #expect(l.offsetY >= -1 && l.offsetY <= 1) // sits on the baseline
        let decoded = try BinFont(decoding: font.encoded())
        #expect(decoded.glyphs.count == 1)
    }

    @Test(arguments: WatchFace.builtins.map(\.id))
    func builtinsRender(id: String) throws {
        let face = try #require(WatchFace.builtins.first { $0.id == id })
        let image = try #require(FacePainter(face: face, time: .now()).image())
        #expect(image.width == WatchScreen.width && image.height == WatchScreen.height)
    }

    @Test func fontAssetIDsAreStable() {
        let spec = FontSpec(name: "AvenirNext-Bold", size: 80)
        #expect(spec.assetID(glyphs: "0123456789:") == spec.assetID(glyphs: ":9876543210:"))
        #expect(spec.assetID(glyphs: "0123456789:") != FontSpec(name: "AvenirNext-Bold", size: 81).assetID(glyphs: "0"))
        #expect(FaceID.isValid(spec.assetID(glyphs: "abc")))
    }
}
