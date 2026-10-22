// Draws WatchFaceKit's weather icons with Core Graphics (the app; `wfce weather-icons`), like the watch does.

import CoreGraphics
import WatchFaceKit

public enum WeatherIconPainter {
    /// Draws into `rect` of a context with y pointing down
    public static func draw(_ shapes: [IconShape], in rect: CGRect, context c: CGContext) {
        let k = min(rect.width, rect.height) / 100
        func p(_ x: Float, _ y: Float) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * k, y: rect.minY + CGFloat(y) * k)
        }
        for shape in shapes {
            switch shape {
            case .circle(let x, let y, let r, let color):
                c.setFillColor(cg(color))
                let center = p(x, y), radius = CGFloat(r) * k
                c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            case .roundRect(let x, let y, let w, let h, let r, let color):
                c.setFillColor(cg(color))
                let origin = p(x, y)
                c.addPath(CGPath(roundedRect: CGRect(x: origin.x, y: origin.y, width: CGFloat(w) * k, height: CGFloat(h) * k),
                                 cornerWidth: CGFloat(r) * k, cornerHeight: CGFloat(r) * k, transform: nil))
                c.fillPath()
            case .line(let x1, let y1, let x2, let y2, let width, let color):
                c.setStrokeColor(cg(color))
                c.setLineWidth(CGFloat(width) * k)
                c.setLineCap(.round)
                c.move(to: p(x1, y1))
                c.addLine(to: p(x2, y2))
                c.strokePath()
            case .triangle(let x1, let y1, let x2, let y2, let x3, let y3, let color):
                c.setFillColor(cg(color))
                c.addLines(between: [p(x1, y1), p(x2, y2), p(x3, y3)])
                c.closePath()
                c.fillPath()
            }
        }
    }

    public static func image(_ condition: WeatherCondition, isDay: Bool, windy: Bool, size: Int,
                             background: FaceColor = .black) -> CGImage? {
        guard let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(size))
        c.scaleBy(x: 1, y: -1)
        draw(WeatherIcon.shapes(condition, isDay: isDay, windy: windy, background: background),
             in: CGRect(x: 0, y: 0, width: size, height: size), context: c)
        return c.makeImage()
    }
}
