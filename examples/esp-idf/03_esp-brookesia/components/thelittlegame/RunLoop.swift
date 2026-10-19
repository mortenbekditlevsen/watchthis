// Watch version: the app's LVGL timer drives rendering (see WatchBridge.swift), so only the callback type that
// Level uses is left.
final class RunLoop {
    typealias Callback = (Button.Value) -> Void
}
