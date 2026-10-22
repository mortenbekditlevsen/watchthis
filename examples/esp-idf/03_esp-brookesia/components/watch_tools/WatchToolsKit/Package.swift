// swift-tools-version: 6.0
// WatchToolsKit: the logic of the Stopur and Timer apps (stopwatch, countdown, presets and recent timers, how times
// are shown), compiled into the firmware by ../CMakeLists.txt (Embedded Swift: no Foundation, no existentials) and
// tested here on a computer with `swift test`.
import PackageDescription

let package = Package(
    name: "WatchToolsKit",
    products: [.library(name: "WatchToolsKit", targets: ["WatchToolsKit"])],
    targets: [
        .target(name: "WatchToolsKit"),
        .testTarget(name: "WatchToolsKitTests", dependencies: ["WatchToolsKit"]),
    ]
)
