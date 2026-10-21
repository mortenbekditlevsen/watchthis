// swift-tools-version: 6.0
// WatchFaceKit: the watch face format (model, binary codec, layout, hand geometry, builtin faces, PNG decoding,
// LVGL binfont writing), shared by the watch firmware (Embedded Swift, compiled directly from Sources/WatchFaceKit
// by ../CMakeLists.txt) and the iOS app. Keep WatchFaceKit free of Foundation, Codable and existentials so it builds
// in Embedded mode.
//
// WatchFaceGraphics (Apple platforms only): draws faces with Core Graphics (the app's preview, `wfce render`) and
// rasterizes fonts with Core Text into binfonts for the watch.
import PackageDescription

let package = Package(
    name: "WatchFaceKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WatchFaceKit", targets: ["WatchFaceKit"]),
        .library(name: "WatchFaceGraphics", targets: ["WatchFaceGraphics"]),
        .executable(name: "wfce", targets: ["wfce"]),
    ],
    targets: [
        .target(name: "WatchFaceKit"),
        .target(
            name: "WatchFaceGraphics",
            dependencies: ["WatchFaceKit"],
            resources: [.copy("Resources/Montserrat-Medium.ttf"), .copy("Resources/OFL.txt")]
        ),
        .executableTarget(name: "wfce", dependencies: ["WatchFaceKit", "WatchFaceGraphics"]),
        .testTarget(name: "WatchFaceKitTests", dependencies: ["WatchFaceKit", "WatchFaceGraphics"]),
    ]
)
