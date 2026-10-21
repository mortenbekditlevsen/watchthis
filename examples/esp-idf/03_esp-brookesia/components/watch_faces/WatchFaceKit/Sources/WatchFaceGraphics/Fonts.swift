// Fonts for drawing faces on the phone, and rasterizing them for the watch.

import CoreGraphics
import CoreText
import Foundation
import WatchFaceKit

/// A font the user picked for a face: rasterized into a face asset (binfont) when the face is synced
public struct FontSpec: Codable, Equatable, Hashable, Sendable {
    /// PostScript name, e.g. "AvenirNext-Bold"
    public var name: String
    public var size: Int

    public init(name: String, size: Int) {
        self.name = name
        self.size = size
    }

    public func ctFont() -> CTFont {
        CTFontCreateWithName(name as CFString, CGFloat(size), nil)
    }

    /// A face asset id for this font with this glyph subset: same input, same id (so faces share fonts)
    public func assetID(glyphs: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in "\(name)|\(size)|\(String(Set(glyphs).sorted()))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return "fnt_" + String(hash, radix: 16)
    }
}

public enum FaceFonts {
    /// Montserrat Medium, the firmware's builtin font (bundled; OFL)
    public static let montserratName: String = {
        guard let url = Bundle.module.url(forResource: "Montserrat-Medium", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return "Helvetica" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? "Montserrat-Medium"
    }()

    /// What the watch uses for a builtin size (66 is a condensed light oblique font there)
    public static func builtin(size: Int) -> CTFont {
        let nearest = FontRef.nearestBuiltinSize(size)
        if nearest == 66 {
            let condensed = CTFontCreateWithName("Futura-CondensedMedium" as CFString, 66, nil)
            return CTFontCreateCopyWithSymbolicTraits(condensed, 66, nil, .traitItalic, .traitItalic) ?? condensed
        }
        return CTFontCreateWithName(montserratName as CFString, CGFloat(nearest), nil)
    }

    /// Rasterizes the characters of `glyphs` (each once) with 4-bit anti-aliasing, as the watch draws them
    public static func rasterize(_ font: CTFont, glyphs: String) -> BinFont {
        let size = Int(CTFontGetSize(font).rounded())
        let ascent = Int(CTFontGetAscent(font).rounded(.up))
        let descent = Int(CTFontGetDescent(font).rounded(.up))
        var result: [BinFontGlyph] = []
        for scalar in Set(glyphs.unicodeScalars).sorted(by: { $0.value < $1.value }) where scalar.value <= 0xFFFF {
            var character = UniChar(scalar.value)
            var glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { continue }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1)
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
                result.append(BinFontGlyph(codepoint: scalar.value, advance: Float(advance.width), offsetX: 0,
                                           offsetY: 0, width: 0, height: 0, alpha: []))
                continue
            }
            let x0 = Int(bounds.minX.rounded(.down)), y0 = Int(bounds.minY.rounded(.down))
            let width = Int(bounds.maxX.rounded(.up)) - x0, height = Int(bounds.maxY.rounded(.up)) - y0
            var alpha = [UInt8](repeating: 0, count: width * height)
            alpha.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
                context.setShouldAntialias(true)
                context.setFillColor(gray: 1, alpha: 1)
                var position = CGPoint(x: -CGFloat(x0), y: -CGFloat(y0))
                CTFontDrawGlyphs(font, &glyph, &position, 1, context)
            }
            // The bitmap context's first row is the top row (CG draws with y up into memory bottom-up for
            // alphaOnly contexts created with data: row 0 is the top of the image)
            result.append(BinFontGlyph(codepoint: scalar.value, advance: Float(advance.width), offsetX: x0,
                                       offsetY: y0, width: width, height: height, alpha: alpha))
        }
        return BinFont(size: size, ascent: ascent, descent: descent, glyphs: result)
    }
}
