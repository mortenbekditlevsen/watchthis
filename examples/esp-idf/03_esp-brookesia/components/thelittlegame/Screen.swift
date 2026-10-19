// Watch version of the game's Screen: just the pixel buffer, which the Little Game app
// (components/brookesia_app_thelittlegame) draws with LVGL; see WatchBridge.swift. The levels still set the
// physical game's red/blue LED levels, but the watch doesn't show them.
struct Screen {
    var current: [Color]
    var red: Double = 0
    var blue: Double = 0

    let width: Int
    let height: Int
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.current = .init(repeating: .off, count: width * height)
    }

    func get(x: Int, y: Int) -> Color {
        current[y + x * height]
    }

    mutating func setPixel(x: Int, y: Int, color: Color) {
        current[y + x * height] = color
    }
    mutating func addPixel(x: Int, y: Int, color: Color) {
        let c = current[y + x * height]
        current[y + x * height] = Color(r: (c.r + color.r) / 2,
                                        g: (c.g + color.g) / 2,
                                        b: (c.b + color.b) / 2)
    }
}
