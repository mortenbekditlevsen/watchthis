// Geometry shared by the watch renderer and the phone preview, so both draw the same shapes. No libm: sin/cos are
// computed here so the results don't depend on the platform.

public struct Point: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public enum FaceMath {
    public static let pi: Float = 3.14159265358979

    /// Radians
    public static func sin(_ angle: Float) -> Float {
        let twoPi = 2 * pi
        var x = angle - (angle / twoPi).rounded() * twoPi // -pi...pi
        if x > pi / 2 { x = pi - x } else if x < -pi / 2 { x = -pi - x } // -pi/2...pi/2
        let x2 = x * x
        // Taylor series to x^11; error < 1e-7 on -pi/2...pi/2
        return x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42 * (1 - x2 / 72 * (1 - x2 / 110)))))
    }

    public static func cos(_ angle: Float) -> Float {
        sin(angle + pi / 2)
    }

    /// The point at `radius` from `center` in the direction of a clock angle (degrees, 0 = 12 o'clock, clockwise)
    public static func point(center: Point, radius: Float, clockDegrees: Float) -> Point {
        let a = clockDegrees * pi / 180
        return Point(x: center.x + radius * sin(a), y: center.y - radius * cos(a))
    }
}

// MARK: - Time

public struct WallTime: Equatable, Sendable {
    public var year: Int
    /// 1...12
    public var month: Int
    /// 1...31
    public var day: Int
    /// 0 = Sunday
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var millisecond: Int

    public init(year: Int, month: Int, day: Int, weekday: Int, hour: Int, minute: Int, second: Int,
                millisecond: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
    }

    /// Before this, the clock has not been set yet (it counts from 1970)
    public var isValid: Bool { year >= 2024 }
}

extension Hand {
    /// Clock angle in tenths of a degree (0...3599, 0 = 12 o'clock, clockwise), as LVGL's image rotation wants it
    public func angleTenths(at t: WallTime) -> Int {
        let tenths: Int
        switch kind {
        case .hour:
            tenths = (t.hour % 12) * 300 + t.minute * 5 + (smooth ? t.second / 12 : 0)
        case .minute:
            tenths = t.minute * 60 + t.second + (smooth ? t.millisecond / 1000 : 0)
        case .second:
            tenths = t.second * 60 + (smooth ? t.millisecond * 6 / 100 : 0)
        }
        return tenths % 3600
    }

    /// Whether the hand needs more than one update per second
    public var needsFastUpdates: Bool { kind == .second && smooth }
}

// MARK: - Hand shapes

public enum HandGeometry {
    /// The hand as a union of convex polygons, pointing up (to 12 o'clock): the pivot is at (0, 0), the tip at
    /// (0, -length) and the end of the tail at (0, tail).
    public static func polygons(for hand: Hand) -> [[Point]] {
        let l = Float(max(1, hand.length))
        let t = Float(hand.tail)
        let w = Float(max(1, hand.width))
        let hw = w / 2
        switch hand.shape {
        case .line:
            return [rect(x0: -hw, y0: -l, x1: hw, y1: t)]
        case .rounded:
            return [stadium(top: -l, bottom: t, halfWidth: hw)]
        case .tapered:
            let tip = max(0.5, hw * 0.3)
            return [[Point(x: -hw, y: t), Point(x: hw, y: t), Point(x: tip, y: -l), Point(x: -tip, y: -l)]]
        case .sword:
            let shoulder = -l * 0.75
            return [[Point(x: -hw * 0.6, y: t), Point(x: hw * 0.6, y: t), Point(x: hw, y: shoulder),
                     Point(x: 0, y: -l), Point(x: -hw, y: shoulder)]]
        case .arrow:
            let shaft = max(1, w / 3) / 2
            let headLength = min(l * 0.3, w * 2.5)
            let headWidth = hw * 1.4
            return [rect(x0: -shaft, y0: -l + headLength, x1: shaft, y1: t),
                    [Point(x: -headWidth, y: -l + headLength), Point(x: headWidth, y: -l + headLength),
                     Point(x: 0, y: -l)]]
        case .lollipop:
            let shaft = max(1, w / 3) / 2
            let discRadius = max(3, hw * 1.6)
            return [rect(x0: -shaft, y0: -l, x1: shaft, y1: t),
                    circle(center: Point(x: 0, y: -l * 0.78), radius: discRadius)]
        }
    }

    static func rect(x0: Float, y0: Float, x1: Float, y1: Float) -> [Point] {
        [Point(x: x0, y: y0), Point(x: x1, y: y0), Point(x: x1, y: y1), Point(x: x0, y: y1)]
    }

    static func circle(center: Point, radius: Float, segments: Int = 24) -> [Point] {
        (0..<segments).map { i in
            FaceMath.point(center: center, radius: radius, clockDegrees: Float(i) * 360 / Float(segments))
        }
    }

    /// A rectangle with half-circle ends, from y = top to y = bottom
    static func stadium(top: Float, bottom: Float, halfWidth r: Float) -> [Point] {
        let topCenter = Point(x: 0, y: min(top + r, (top + bottom) / 2))
        let bottomCenter = Point(x: 0, y: max(bottom - r, (top + bottom) / 2))
        var points: [Point] = []
        for i in 0...8 { // 270 -> 450 degrees: the top half circle, left to right
            points.append(FaceMath.point(center: topCenter, radius: r, clockDegrees: 270 + Float(i) * 22.5))
        }
        for i in 0...8 { // 90 -> 270 degrees: the bottom half circle, right to left
            points.append(FaceMath.point(center: bottomCenter, radius: r, clockDegrees: 90 + Float(i) * 22.5))
        }
        return points
    }
}

/// An anti-aliased 8-bit coverage bitmap of a hand pointing up; LVGL rotates it around the pivot (an A8 image).
public struct HandMask: Sendable {
    public let width: Int
    public let height: Int
    public let pivotX: Int
    public let pivotY: Int
    /// width * height coverage values, row by row
    public let alpha: [UInt8]

    public init(hand: Hand) {
        let polygons = HandGeometry.polygons(for: hand)
        var minX: Float = 0, maxX: Float = 0, minY: Float = 0, maxY: Float = 0
        for polygon in polygons {
            for p in polygon {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
        }
        // One pixel of margin so the edges stay anti-aliased; keep the pivot on a whole pixel
        let left = Int((-minX).rounded(.up)) + 1
        let right = Int(maxX.rounded(.up)) + 1
        let top = Int((-minY).rounded(.up)) + 1
        let bottom = Int(maxY.rounded(.up)) + 1
        width = left + right
        height = top + bottom
        pivotX = left
        pivotY = top

        // Coverage row by row: in each of 4 sub-rows per pixel row, every (convex) polygon covers one span of x;
        // the spans are merged and their exact horizontal coverage added up. A few edge tests per row, instead of
        // testing 16 points per pixel against every edge (that took ~1 s per face on the watch, without an FPU).
        let subRows = 4
        var alpha = [UInt8](repeating: 0, count: width * height)
        var coverage = [Float](repeating: 0, count: width)
        var spans: [(Float, Float)] = []
        for py in 0..<height {
            for i in 0..<width { coverage[i] = 0 }
            for sub in 0..<subRows {
                let y = Float(py - top) + (Float(sub) + 0.5) / Float(subRows)
                spans.removeAll(keepingCapacity: true)
                for polygon in polygons {
                    if let span = HandMask.span(polygon, y: y) { spans.append(span) }
                }
                spans.sort { $0.0 < $1.0 }
                var i = 0
                while i < spans.count {
                    var (x0, x1) = spans[i]
                    i += 1
                    while i < spans.count && spans[i].0 <= x1 {
                        x1 = max(x1, spans[i].1)
                        i += 1
                    }
                    // In pixel coordinates; add how much of each pixel [px, px + 1) the span covers
                    let a = x0 + Float(left), b = x1 + Float(left)
                    var px = max(0, Int(a.rounded(.down)))
                    let last = min(width - 1, Int(b.rounded(.down)))
                    while px <= last {
                        let covered = min(b, Float(px + 1)) - max(a, Float(px))
                        if covered > 0 { coverage[px] += covered }
                        px += 1
                    }
                }
            }
            for px in 0..<width {
                alpha[py * width + px] = UInt8(min(255, (coverage[px] / Float(subRows) * 255).rounded()))
            }
        }
        self.alpha = alpha
    }

    /// Where a horizontal line at `y` crosses a convex polygon: the span of x it covers, or nil
    static func span(_ polygon: [Point], y: Float) -> (Float, Float)? {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for i in 0..<polygon.count {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let (y0, y1) = (min(p.y, q.y), max(p.y, q.y))
            guard y >= y0 && y <= y1 else { continue }
            let x = y1 - y0 < 1e-6 ? p.x : p.x + (q.x - p.x) * (y - p.y) / (q.y - p.y)
            lo = min(lo, x)
            hi = max(hi, x)
            if y1 - y0 < 1e-6 {
                lo = min(lo, q.x)
                hi = max(hi, q.x)
            }
        }
        return lo <= hi ? (lo, hi) : nil
    }

    /// Convex polygon, either winding
    static func contains(_ polygon: [Point], x: Float, y: Float) -> Bool {
        var sign: Float = 0
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
            if cross == 0 { continue }
            if sign == 0 {
                sign = cross
            } else if (cross > 0) != (sign > 0) {
                return false
            }
        }
        return true
    }
}

// MARK: - Dial

public struct TickSegment: Equatable, Sendable {
    public var from: Point
    public var to: Point
    public var width: Int
    public var color: FaceColor
}

public struct NumeralLabel: Equatable, Sendable {
    public var hour: Int
    public var text: String
    /// Where the label's center goes
    public var center: Point
}

extension AnalogClock {
    public var center: Point { Point(x: Float(centerX), y: Float(centerY)) }

    public func tickSegments() -> [TickSegment] {
        guard ticks.mode != .hidden else { return [] }
        let outer = Float(radius - ticks.inset)
        var segments: [TickSegment] = []
        for i in 0..<60 {
            let isHour = i % 5 == 0
            if !isHour && ticks.mode != .hoursAndMinutes { continue }
            let style = isHour ? ticks.major : ticks.minor
            let angle = Float(i * 6)
            segments.append(TickSegment(
                from: FaceMath.point(center: center, radius: outer - Float(style.length), clockDegrees: angle),
                to: FaceMath.point(center: center, radius: outer, clockDegrees: angle),
                width: style.width, color: style.color))
        }
        return segments
    }

    public func numeralLabels() -> [NumeralLabel] {
        var labels: [NumeralLabel] = []
        for hour in 1...12 where numerals.mode.shows(hour: hour) {
            labels.append(NumeralLabel(
                hour: hour, text: numerals.roman ? FaceText.roman(hour) : "\(hour)",
                center: FaceMath.point(center: center, radius: Float(radius - numerals.inset),
                                       clockDegrees: Float(hour * 30))))
        }
        return labels
    }
}
