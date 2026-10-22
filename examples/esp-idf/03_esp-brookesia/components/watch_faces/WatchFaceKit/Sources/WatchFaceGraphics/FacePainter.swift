// Draws a face with Core Graphics the way the watch draws it with LVGL (same geometry and texts from WatchFaceKit),
// for the app's editor preview and `wfce render`.

import CoreGraphics
import CoreText
import Foundation
import WatchFaceKit

public struct FacePainter {
    public var face: WatchFace
    public var time: WallTime
    public var steps: Int
    public var battery: Int
    /// The font for an asset font id (the user's pick); nil = draw with the builtin 20 px font
    public var assetFont: (String) -> CTFont?
    /// A background image asset (already 410 x 502)
    public var assetImage: (String) -> CGImage?

    public init(face: WatchFace, time: WallTime, steps: Int = 4321, battery: Int = 87,
                assetFont: @escaping (String) -> CTFont? = { _ in nil },
                assetImage: @escaping (String) -> CGImage? = { _ in nil }) {
        self.face = face
        self.time = time
        self.steps = steps
        self.battery = battery
        self.assetFont = assetFont
        self.assetImage = assetImage
    }

    public static let size = CGSize(width: WatchScreen.width, height: WatchScreen.height)

    public func image(scale: CGFloat = 1) -> CGImage? {
        let w = Int(Self.size.width * scale), h = Int(Self.size.height * scale)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        // Watch coordinates: origin top left, y down
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: scale, y: -scale)
        draw(in: context)
        return context.makeImage()
    }

    /// Draws into a context whose coordinates are watch pixels with y pointing down
    public func draw(in context: CGContext) {
        drawBackground(context)
        for element in face.elements {
            draw(element, context)
        }
    }

    // MARK: - Background

    private func gradient(_ stops: [GradientStop]) -> CGGradient? {
        let colors = stops.map { cg($0.color) } as CFArray
        let locations = stops.map { CGFloat($0.location) / 255 }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations)
    }

    private func drawBackground(_ c: CGContext) {
        let bounds = CGRect(origin: .zero, size: Self.size)
        c.setFillColor(cg(.black))
        c.fill(bounds)
        switch face.background {
        case .color(let color):
            c.setFillColor(cg(color))
            c.fill(bounds)
        case .linearGradient(let g):
            guard let gradient = gradient(g.stops) else { return }
            let (from, to) = g.endpoints(width: WatchScreen.width, height: WatchScreen.height)
            c.drawLinearGradient(gradient, start: point(from), end: point(to),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radialGradient(let g):
            guard let gradient = gradient(g.stops) else { return }
            let center = CGPoint(x: g.centerX, y: g.centerY)
            c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                 endRadius: CGFloat(max(1, g.radius)), options: [.drawsAfterEndLocation])
        case .pattern(let p):
            let tile = p.tile()
            guard let image = rgb565Image(tile.pixels, width: tile.width, height: tile.height) else { return }
            c.saveGState()
            c.clip(to: bounds)
            c.draw(image, in: CGRect(x: 0, y: 0, width: tile.width, height: tile.height), byTiling: true)
            c.restoreGState()
        case .image(let i):
            c.setFillColor(cg(i.fallback))
            c.fill(bounds)
            if let image = assetImage(i.assetID) {
                c.saveGState()
                // Images are stored top row first; flip back for drawing
                c.translateBy(x: 0, y: CGFloat(image.height))
                c.scaleBy(x: 1, y: -1)
                c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                c.restoreGState()
            }
            if i.dim > 0 {
                c.setFillColor(CGColor(gray: 0, alpha: CGFloat(i.dimOpacity) / 255))
                c.fill(bounds)
            }
        case .unknown:
            break
        }
    }

    // MARK: - Elements

    private func draw(_ element: Element, _ c: CGContext) {
        switch element {
        case .digitalTime(let e):
            drawText(FaceText.time(e, time), e.style, e.placement, c)
        case .date(let e):
            drawText(FaceText.date(e, time), e.style, e.placement, c)
        case .text(let e):
            drawText(e.text, e.style, e.placement, c)
        case .steps(let e):
            drawSteps(e, c)
        case .battery(let e):
            drawBattery(e, c)
        case .analogClock(let e):
            drawClock(e, c)
        case .unknown:
            break
        }
    }

    public func font(_ ref: FontRef) -> CTFont {
        switch ref {
        case .builtin(let size): return FaceFonts.builtin(size: size)
        case .asset(let id): return assetFont(id) ?? FaceFonts.builtin(size: 20)
        }
    }

    /// The box LVGL gives a label: the text's width by the font's line height
    public func textBox(_ text: String, _ style: TextStyle, _ placement: Placement) -> CGRect {
        let line = makeLine(text, style)
        let ctFont = font(style.font)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let height = CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont)
        return box(width: width, height: height, placement)
    }

    func box(width: CGFloat, height: CGFloat, _ p: Placement) -> CGRect {
        let x = CGFloat(p.x) - width * CGFloat(p.anchor.horizontal) / 2
        let y = CGFloat(p.y) - height * CGFloat(p.anchor.vertical) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func makeLine(_ text: String, _ style: TextStyle) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style.font),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg(style.color),
            NSAttributedString.Key(kCTKernAttributeName as String): CGFloat(style.letterSpacing),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private func drawText(_ text: String, _ style: TextStyle, _ placement: Placement, _ c: CGContext,
                          centeredIn rect: CGRect? = nil) {
        guard !text.isEmpty else { return }
        let line = makeLine(text, style)
        let ctFont = font(style.font)
        let frame = rect.map { r in
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            let h = CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont)
            return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        } ?? textBox(text, style, placement)
        c.saveGState()
        // Core Text draws with y up: flip around the baseline
        c.textMatrix = .identity
        c.translateBy(x: frame.minX, y: frame.minY + CTFontGetAscent(ctFont))
        c.scaleBy(x: 1, y: -1)
        c.textPosition = .zero
        CTLineDraw(line, c)
        c.restoreGState()
    }

    private func drawSteps(_ e: Steps, _ c: CGContext) {
        guard e.style == .ring else {
            drawText(FaceText.steps(steps), e.text, e.placement, c)
            return
        }
        let r = CGFloat(e.radius)
        let frame = box(width: 2 * r, height: 2 * r, e.placement)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let ringRadius = r - CGFloat(e.ringWidth) / 2
        c.setLineWidth(CGFloat(e.ringWidth))
        c.setStrokeColor(cg(e.trackColor))
        c.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        c.strokePath()
        let fraction = min(1, CGFloat(steps) / CGFloat(max(1, e.goal)))
        if fraction > 0 {
            c.setStrokeColor(cg(e.ringColor))
            c.setLineCap(.round)
            c.addArc(center: center, radius: ringRadius, startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * fraction,
                     clockwise: false)
            c.strokePath()
        }
        drawText(FaceText.steps(steps), e.text, e.placement, c, centeredIn: frame)
    }

    private func drawBattery(_ e: Battery, _ c: CGContext) {
        guard e.style == .bar else {
            drawText(FaceText.battery(battery), e.text, e.placement, c)
            return
        }
        let frame = box(width: 40, height: 18, e.placement)
        c.setStrokeColor(cg(e.text.color))
        c.setLineWidth(2)
        c.addPath(CGPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil))
        c.strokePath()
        let inner = frame.insetBy(dx: 5, dy: 5)
        c.setFillColor(cg(e.text.color))
        c.fill(CGRect(x: inner.minX, y: inner.minY, width: inner.width * CGFloat(max(0, battery)) / 100,
                      height: inner.height))
    }

    private func drawClock(_ e: AnalogClock, _ c: CGContext) {
        let center = CGPoint(x: e.centerX, y: e.centerY)
        let r = CGFloat(e.radius)
        let dial = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        if e.dial.fill.a > 0 {
            c.setFillColor(cg(e.dial.fill))
            c.fillEllipse(in: dial)
        }
        if e.dial.borderWidth > 0 {
            let w = CGFloat(e.dial.borderWidth)
            c.setStrokeColor(cg(e.dial.borderColor))
            c.setLineWidth(w)
            c.strokeEllipse(in: dial.insetBy(dx: w / 2, dy: w / 2))
        }
        c.setLineCap(.butt)
        for tick in e.tickSegments() {
            c.setStrokeColor(cg(tick.color))
            c.setLineWidth(CGFloat(tick.width))
            c.move(to: point(tick.from))
            c.addLine(to: point(tick.to))
            c.strokePath()
        }
        for numeral in e.numeralLabels() {
            drawText(numeral.text, e.numerals.style,
                     Placement(x: Int(numeral.center.x.rounded()), y: Int(numeral.center.y.rounded())), c)
        }
        for hand in e.hands {
            let angle = CGFloat(hand.angleTenths(at: time)) / 10 * .pi / 180
            c.saveGState()
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: angle)
            c.setFillColor(cg(hand.color))
            for polygon in HandGeometry.polygons(for: hand) {
                c.addLines(between: polygon.map(point))
                c.closePath()
            }
            c.fillPath()
            c.restoreGState()
        }
        if e.capRadius > 0 {
            let cr = CGFloat(e.capRadius)
            c.setFillColor(cg(e.capColor))
            c.fillEllipse(in: CGRect(x: center.x - cr, y: center.y - cr, width: 2 * cr, height: 2 * cr))
        }
    }

    // MARK: - Helpers

    private func point(_ p: Point) -> CGPoint {
        CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }
}

public func cg(_ color: FaceColor) -> CGColor {
    CGColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255,
            alpha: CGFloat(color.a) / 255)
}

func rgb565Image(_ pixels: [UInt16], width: Int, height: Int) -> CGImage? {
    var rgba = [UInt8]()
    rgba.reserveCapacity(pixels.count * 4)
    for v in pixels {
        let r = UInt8((v >> 11) & 0x1F), g = UInt8((v >> 5) & 0x3F), b = UInt8(v & 0x1F)
        rgba += [r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2, 255]
    }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

extension WallTime {
    /// The current time (local time zone), for previews
    public static func now(_ date: Date = Date(), calendar: Calendar = .current) -> WallTime {
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second, .nanosecond], from: date)
        return WallTime(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1, weekday: (c.weekday ?? 1) - 1,
                        hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0,
                        millisecond: (c.nanosecond ?? 0) / 1_000_000)
    }
}
