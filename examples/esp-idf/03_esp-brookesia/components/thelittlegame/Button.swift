// Watch version: there are no GPIO buttons to poll -- the app turns swipes, taps and the BOOT button into these
// values and passes them in through thelittlegame_button() (see WatchBridge.swift).
class Button {
    enum Value {
        case up, down, left, right, select, fire
    }
}
