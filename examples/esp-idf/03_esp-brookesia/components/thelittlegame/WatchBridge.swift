// C entry points used by the Little Game app (components/brookesia_app_thelittlegame); declared in
// include/thelittlegame.h. Plays the role Main.swift + RunLoop.run() have on the LED-matrix build.

private let game = Game(
    levels: [
        createLabyrinthLevel(),
        createDigitalPetLevel(),
        createMemoryLevel()
    ]
)
private var screen = Screen(width: Int(LITTLEGAME_WIDTH), height: Int(LITTLEGAME_HEIGHT))

/// The palette is tuned for 0...16 (like the SwiftUI playground, which divides by 16); scale up to 0...255.
private func scale(_ v: UInt8) -> UInt8 {
    UInt8(min(Int(v) * 16, 255))
}

@_cdecl("thelittlegame_tick")
func thelittlegame_tick(
    _ time: Double,
    _ rgb: UnsafeMutablePointer<UInt8>!
) {
    game.render(screen: &screen, time: time)

    // Row-major from the top row; the game's y axis points up (row 0 on screen is y == height - 1)
    var i = 0
    for row in 0 ..< screen.height {
        for x in 0 ..< screen.width {
            let c = screen.get(x: x, y: screen.height - 1 - row)
            rgb[i] = scale(c.r)
            rgb[i + 1] = scale(c.g)
            rgb[i + 2] = scale(c.b)
            i += 3
        }
    }
}

@_cdecl("thelittlegame_button")
func thelittlegame_button(_ button: Int32) {
    let value: Button.Value
    switch button {
    case LITTLEGAME_BUTTON_UP: value = .up
    case LITTLEGAME_BUTTON_DOWN: value = .down
    case LITTLEGAME_BUTTON_LEFT: value = .left
    case LITTLEGAME_BUTTON_RIGHT: value = .right
    case LITTLEGAME_BUTTON_SELECT: value = .select
    case LITTLEGAME_BUTTON_FIRE: value = .fire
    default: return
    }
    game.buttonTapped(button: value)
}
