// Launcher icons for the watch's apps (`wfce launcher-icon <name> <out.c>`): drawn with Core Graphics at 112 x 112
// and written as an LVGL ARGB8888 image in C, like the other apps' assets/esp_brookesia_app_icon_launcher_*.c. In the
// launcher's style: a rounded square with a gradient, a flat picture on it.
import CoreGraphics
import Foundation

enum LauncherIcon {
    static let size = 112

    static let names = ["advent", "photos"]

    static func comment(_ name: String) -> String {
        name == "advent" ? "an advent calendar door, open, with a star behind it" : "two photos, a landscape on top"
    }

    /// The icon's pixels, row by row: B, G, R, A (not premultiplied), as LVGL's ARGB8888 wants them
    static func pixels(_ name: String) -> [UInt8]? {
        let n = size
        guard let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y down, as on the watch
        c.translateBy(x: 0, y: CGFloat(n))
        c.scaleBy(x: 1, y: -1)
        switch name {
        case "advent": drawAdvent(c)
        case "photos": drawPhotos(c)
        default: return nil
        }
        guard let data = c.data else { return nil }
        let rgba = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var out = [UInt8](repeating: 0, count: n * n * 4)
        for p in 0..<(n * n) {
            let a = Int(rgba[p * 4 + 3])
            func unpremultiply(_ v: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, Int(v) * 255 / a)) }
            out[p * 4] = unpremultiply(rgba[p * 4 + 2])
            out[p * 4 + 1] = unpremultiply(rgba[p * 4 + 1])
            out[p * 4 + 2] = unpremultiply(rgba[p * 4])
            out[p * 4 + 3] = UInt8(a)
        }
        return out
    }

    static func cSource(_ name: String, symbol: String, pixels: [UInt8]) -> String {
        var s = """
        /*
         * SPDX-License-Identifier: CC0-1.0
         *
         * Generated launcher icon: \(comment(name)). Made with `swift run wfce launcher-icon \(name) <out.c>`
         * (components/watch_faces/WatchFaceKit).
         */
        #include "lvgl.h"

        #ifndef LV_ATTRIBUTE_MEM_ALIGN
        #define LV_ATTRIBUTE_MEM_ALIGN
        #endif

        static const LV_ATTRIBUTE_MEM_ALIGN LV_ATTRIBUTE_LARGE_CONST uint8_t \(symbol)_map[] = {

        """
        for row in stride(from: 0, to: pixels.count, by: 16) {
            let bytes = pixels[row..<min(row + 16, pixels.count)].map { String(format: "0x%02x", $0) }
            s += "    " + bytes.joined(separator: ", ") + ",\n"
        }
        s += """
        };

        const lv_image_dsc_t \(symbol) = {
            .header = {
                .magic = LV_IMAGE_HEADER_MAGIC,
                .cf = LV_COLOR_FORMAT_ARGB8888,
                .w = \(size),
                .h = \(size),
            },
            .data_size = sizeof(\(symbol)_map),
            .data = \(symbol)_map,
        };

        """
        return s
    }

    // MARK: Drawing

    static func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    /// The rounded square with a top-to-bottom gradient; later drawing is clipped to it
    static func background(_ c: CGContext, _ top: UInt32, _ bottom: UInt32) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: 25, cornerHeight: 25, transform: nil))
        c.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    static func star(_ c: CGContext, _ center: CGPoint, _ r: CGFloat, points: Int = 5, inner: CGFloat = 0.45) {
        for i in 0..<(points * 2) {
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let radius = i % 2 == 0 ? r : r * inner
            let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if i == 0 { c.move(to: p) } else { c.addLine(to: p) }
        }
        c.closePath()
        c.fillPath()
    }

    static func drawAdvent(_ c: CGContext) {
        background(c, 0xD8323F, 0x8E0F22)
        // The doorway in a gold frame, night and a star inside
        let frame = CGRect(x: 38, y: 24, width: 50, height: 64)
        c.setFillColor(color(0xF2C14E))
        c.addPath(CGPath(roundedRect: frame.insetBy(dx: -4, dy: -4), cornerWidth: 5, cornerHeight: 5, transform: nil))
        c.fillPath()
        c.setFillColor(color(0x13214A))
        c.fill(frame)
        c.setFillColor(color(0xFFD966))
        star(c, CGPoint(x: 63, y: 54), 15)
        c.setFillColor(color(0xFFF4C2))
        for (x, y, r) in [(48.0, 34.0, 3.0), (78.0, 36.0, 2.4), (76.0, 76.0, 3.0), (50.0, 78.0, 2.0)] {
            star(c, CGPoint(x: x, y: y), r, points: 4, inner: 0.3)
        }
        // The door, swung open towards us on its left hinge (its back, cream card, showing)
        c.setFillColor(color(0xEFE2C4))
        c.move(to: CGPoint(x: 38, y: 24))
        c.addLine(to: CGPoint(x: 20, y: 16))
        c.addLine(to: CGPoint(x: 20, y: 96))
        c.addLine(to: CGPoint(x: 38, y: 88))
        c.closePath()
        c.fillPath()
        c.setStrokeColor(color(0xC8922A))
        c.setLineWidth(2.5)
        c.setLineJoin(.round)
        c.move(to: CGPoint(x: 38, y: 24))
        c.addLine(to: CGPoint(x: 20, y: 16))
        c.addLine(to: CGPoint(x: 20, y: 96))
        c.addLine(to: CGPoint(x: 38, y: 88))
        c.strokePath()
    }

    static func drawPhotos(_ c: CGContext) {
        background(c, 0x8E7CF0, 0x4A3BB5)
        func photo(_ angle: CGFloat, _ dx: CGFloat, _ dy: CGFloat, picture: (CGContext, CGRect) -> Void) {
            c.saveGState()
            c.translateBy(x: 56 + dx, y: 58 + dy)
            c.rotate(by: angle)
            let outer = CGRect(x: -34, y: -28, width: 68, height: 56)
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: color(0x000000, 0.35))
            c.setFillColor(color(0xFFFFFF))
            c.addPath(CGPath(roundedRect: outer, cornerWidth: 4, cornerHeight: 4, transform: nil))
            c.fillPath()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            let inner = outer.insetBy(dx: 5, dy: 5)
            c.clip(to: inner)
            picture(c, inner)
            c.restoreGState()
        }
        photo(-0.22, -6, -4) { c, r in
            c.setFillColor(color(0xF3C98B))
            c.fill(r)
        }
        photo(0.12, 4, 6) { c, r in
            c.setFillColor(color(0x7CC8F5))
            c.fill(r)
            c.setFillColor(color(0xFFD23F))
            c.fillEllipse(in: CGRect(x: r.maxX - 20, y: r.minY + 5, width: 12, height: 12))
            c.setFillColor(color(0x4FAF5B))
            c.move(to: CGPoint(x: r.minX, y: r.maxY))
            c.addLine(to: CGPoint(x: r.minX, y: r.maxY - 16))
            c.addLine(to: CGPoint(x: r.minX + 20, y: r.maxY - 30))
            c.addLine(to: CGPoint(x: r.minX + 38, y: r.maxY - 12))
            c.addLine(to: CGPoint(x: r.minX + 46, y: r.maxY - 20))
            c.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 6))
            c.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            c.closePath()
            c.fillPath()
        }
    }
}
