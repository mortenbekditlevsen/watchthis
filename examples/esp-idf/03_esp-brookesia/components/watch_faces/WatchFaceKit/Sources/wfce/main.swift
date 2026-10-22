// wfce: write, inspect and preview watch face files on a computer, e.g. to test uploads with
// tools/ble_test_client.py.
//
//   swift run wfce list                                the builtin faces
//   swift run wfce builtin <id> <out.wf>               a builtin face as a file (with id "<id>_kopi")
//   swift run wfce dump <file.wf>                      decode a face file and print it
//   swift run wfce render <id|file.wf> <out.png> [HH:MM:SS]   draw a face as the phone preview does
//   swift run wfce font <PostScript name> <size> <characters> <out.fnt>   rasterize a font subset (LVGL binfont)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatchFaceGraphics
import WatchFaceKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadFace(_ arg: String) -> WatchFace {
    if let face = WatchFace.builtins.first(where: { $0.id == arg }) { return face }
    do {
        return try WatchFace(decoding: [UInt8](Data(contentsOf: URL(fileURLWithPath: arg))))
    } catch {
        fail("no builtin face or readable face file \(arg): \(error)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "list":
    for face in WatchFace.builtins {
        print("\(face.id)\t\(face.name)\t\(face.encoded().count) bytes")
    }
case "builtin":
    guard args.count == 3 else { fail("usage: wfce builtin <id> <out.wf>") }
    var face = loadFace(args[1])
    face.id = args[1] + "_kopi"
    face.name += " (kopi)"
    try Data(face.encoded()).write(to: URL(fileURLWithPath: args[2]))
case "dump":
    guard args.count == 2 else { fail("usage: wfce dump <file.wf>") }
    let face = loadFace(args[1])
    dump(face)
    print("features:", FaceFeature.required(by: face).joined(separator: ", "))
    print("assets:", FaceFeature.assets(of: face).joined(separator: ", "))
case "render":
    guard args.count >= 3 else { fail("usage: wfce render <id|file.wf> <out.png> [HH:MM:SS]") }
    var time = WallTime(year: 2026, month: 10, day: 20, weekday: 2, hour: 10, minute: 9, second: 36)
    if args.count > 3 {
        let parts = args[3].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { fail("time must be HH:MM:SS") }
        (time.hour, time.minute, time.second) = (parts[0], parts[1], parts[2])
    }
    guard let image = FacePainter(face: loadFace(args[1]), time: time).image(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        fail("could not render")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(args[2])") }
case "weather-icons":
    // Every condition: day, night, and day + windy, on black
    guard args.count == 2 else { fail("usage: wfce weather-icons <out.png>") }
    let cell = 120, conditions = WeatherCondition.allCases
    let c = CGContext(data: nil, width: cell * 3, height: cell * conditions.count, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    c.fill(CGRect(x: 0, y: 0, width: cell * 3, height: cell * conditions.count))
    c.translateBy(x: 0, y: CGFloat(cell * conditions.count))
    c.scaleBy(x: 1, y: -1)
    for (row, condition) in conditions.enumerated() {
        for (column, (isDay, windy)) in [(true, false), (false, false), (true, true)].enumerated() {
            WeatherIconPainter.draw(WeatherIcon.shapes(condition, isDay: isDay, windy: windy),
                                    in: CGRect(x: column * cell + 10, y: row * cell + 10, width: 100, height: 100), context: c)
        }
    }
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, c.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(args[1])") }
case "weather-sample":
    // A forecast for the Vejr app with every condition, from today
    guard args.count == 2 else { fail("usage: wfce weather-sample <out.wx>") }
    let today = WallTime.now()
    let calendar = Calendar.current
    let days = WeatherCondition.allCases.prefix(WeatherReport.maxDays).enumerated().map { i, condition in
        let date = calendar.date(byAdding: .day, value: i, to: Date())!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return WeatherDay(year: c.year!, month: c.month!, day: c.day!, condition: condition, high: 120 - i * 15,
                          low: 40 - i * 15, precipitation: i * 12, precipitationProbability: i * 10, windMax: 60 + i * 12)
    }
    let report = WeatherReport(location: "Prøveby", updated: Int64(Date().timeIntervalSince1970),
                               now: WeatherNow(condition: .partlyCloudy, isDay: today.hour >= 7 && today.hour < 18,
                                               temperature: 87, feelsLike: 51, wind: 115, gusts: 180), days: days)
    try Data(report.encoded()).write(to: URL(fileURLWithPath: args[1]))
case "font":
    guard args.count == 5, let size = Int(args[2]) else {
        fail("usage: wfce font <PostScript name> <size> <characters> <out.fnt>")
    }
    let spec = FontSpec(name: args[1], size: size)
    let font = FaceFonts.rasterize(spec.ctFont(), glyphs: args[3])
    try Data(font.encoded()).write(to: URL(fileURLWithPath: args[4]))
    print("\(font.glyphs.count) glyphs, \(font.encoded().count) bytes; asset id \(spec.assetID(glyphs: args[3]))")
default:
    fail("usage: wfce list | builtin <id> <out.wf> | dump <file.wf> | render <id|file.wf> <out.png> [HH:MM:SS] | "
         + "font <name> <size> <chars> <out.fnt>")
}
