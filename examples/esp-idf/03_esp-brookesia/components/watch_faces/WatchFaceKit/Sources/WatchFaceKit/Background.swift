// Background drawing helpers shared by the watch and the phone preview.

extension LinearGradient {
    /// Start and end of the gradient line over a box, CSS style: the line goes through the center at `angle`, long
    /// enough that the corners get the first and last colors
    public func endpoints(width: Int, height: Int) -> (from: Point, to: Point) {
        let a = Float(angle) * FaceMath.pi / 180
        let dx = FaceMath.sin(a)
        let dy = -FaceMath.cos(a)
        let half = (abs(Float(width) * dx) + abs(Float(height) * dy)) / 2
        let cx = Float(width) / 2
        let cy = Float(height) / 2
        return (Point(x: cx - dx * half, y: cy - dy * half), Point(x: cx + dx * half, y: cy + dy * half))
    }
}

extension Pattern {
    /// One repeat of the pattern as RGB565 pixels (row by row); tiled over the background. Anti-aliased dots.
    public func tile() -> (width: Int, height: Int, pixels: [UInt16]) {
        let s = max(2, spacing)
        let size = max(1, min(size, s))
        let w = kind == .checker ? 2 * s : s
        let h = w
        var pixels = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var coverage: Float = 0
                switch kind {
                case .stripes:
                    coverage = y < size ? 1 : 0
                case .diagonalStripes:
                    coverage = (x + y) % s < size ? 1 : 0
                case .grid:
                    coverage = (x < size || y < size) ? 1 : 0
                case .checker:
                    coverage = (x < s) != (y < s) ? 1 : 0
                case .dots:
                    let c = Float(s) / 2
                    let dx = Float(x) + 0.5 - c
                    let dy = Float(y) + 0.5 - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    coverage = max(0, min(1, Float(size) / 2 - d + 0.5))
                }
                let a = coverage * Float(foreground.a) / 255
                func mix(_ f: UInt8, _ b: UInt8) -> UInt8 {
                    UInt8((Float(f) * a + Float(b) * (1 - a)).rounded())
                }
                pixels[y * w + x] = RGB565.pack(mix(foreground.r, background.r), mix(foreground.g, background.g),
                                                mix(foreground.b, background.b))
            }
        }
        return (w, h, pixels)
    }
}
