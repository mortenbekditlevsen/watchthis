// Vejr: the forecast the phone uploaded (file_store kind FILE_STORE_WEATHER, id "vejr"). Now: an icon, the
// temperature, feels-like, the day's high and low and the wind; then a row per coming day. Scrolls vertically.

private let weatherFileID = "vejr"
/// Older than this, the screen says so
private let staleAfterSeconds: Int64 = 6 * 3600

enum WeatherStore {
    static func load() -> WeatherReport? {
        guard let path = storePath(FILE_STORE_WEATHER, weatherFileID), let bytes = readFile(path, maxSize: 4096) else {
            return nil
        }
        do {
            return try WeatherReport(decoding: bytes)
        } catch {
            return nil
        }
    }
}

/// Draws a weather icon (WatchFaceKit's shapes, in a 100 x 100 box scaled to the object) when LVGL redraws it
final class WeatherIconDrawing {
    let shapes: [IconShape]

    init(_ shapes: [IconShape]) {
        self.shapes = shapes
    }

    /// An object showing the icon; `owner` keeps the drawing alive as long as needed
    static func make(_ parent: LVObj, size: Int32, shapes: [IconShape], owner: inout [WeatherIconDrawing]) -> LVObj {
        let obj = lvPlainObject(parent)
        lv_obj_set_size(obj, size, size)
        let drawing = WeatherIconDrawing(shapes)
        owner.append(drawing)
        lv_obj_add_event_cb(obj, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            Unmanaged<WeatherIconDrawing>.fromOpaque(ud).takeUnretainedValue().draw(e)
        }, LV_EVENT_DRAW_MAIN, Unmanaged.passUnretained(drawing).toOpaque())
        return obj
    }

    func draw(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e), let obj = lv_event_get_current_target_obj(e) else { return }
        var area = lv_area_t()
        lv_obj_get_coords(obj, &area)
        let k = Float(area.x2 - area.x1 + 1) / 100
        func x(_ v: Float) -> Int32 { area.x1 + Int32((v * k).rounded()) }
        func y(_ v: Float) -> Int32 { area.y1 + Int32((v * k).rounded()) }
        for shape in shapes {
            switch shape {
            case .circle(let cx, let cy, let r, let color):
                fillRect(layer, x(cx - r), y(cy - r), x(cx + r), y(cy + r), radius: wf_radius_circle(), color)
            case .roundRect(let rx, let ry, let w, let h, let r, let color):
                fillRect(layer, x(rx), y(ry), x(rx + w), y(ry + h), radius: Int32((r * k).rounded()), color)
            case .line(let x1, let y1, let x2, let y2, let width, let color):
                var dsc = lv_draw_line_dsc_t()
                lv_draw_line_dsc_init(&dsc)
                dsc.p1 = wf_point(x(x1), y(y1))
                dsc.p2 = wf_point(x(x2), y(y2))
                dsc.width = max(1, Int32((width * k).rounded()))
                dsc.color = lvColor(color)
                dsc.opa = color.a
                dsc.round_start = 1
                dsc.round_end = 1
                lv_draw_line(layer, &dsc)
            case .triangle(let x1, let y1, let x2, let y2, let x3, let y3, let color):
                wf_draw_triangle(layer, x(x1), y(y1), x(x2), y(y2), x(x3), y(y3), lvColor(color), color.a)
            }
        }
    }

    private func fillRect(_ layer: UnsafeMutablePointer<lv_layer_t>, _ x1: Int32, _ y1: Int32, _ x2: Int32, _ y2: Int32,
                          radius: Int32, _ color: FaceColor) {
        var dsc = lv_draw_rect_dsc_t()
        lv_draw_rect_dsc_init(&dsc)
        dsc.radius = radius
        dsc.bg_color = lvColor(color)
        dsc.bg_opa = color.a
        var area = lv_area_t(x1: x1, y1: y1, x2: x2 - 1, y2: y2 - 1)
        lv_draw_rect(layer, &dsc, &area)
    }
}

private final class WeatherUI {
    let screen: LVObj
    var icons: [WeatherIconDrawing] = []

    init(screen: LVObj) {
        self.screen = screen
        lv_obj_clean(screen)
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_set_scroll_dir(screen, LV_DIR_VER)
        lv_obj_set_scrollbar_mode(screen, LV_SCROLLBAR_MODE_OFF)
        if let report = WeatherStore.load() {
            build(report)
        } else {
            buildEmpty()
        }
    }

    private func text(_ parent: LVObj, _ s: String, size: Int, color: UInt32 = 0xFFFFFF) -> LVObj {
        let label = lv_label_create(parent)!
        lv_obj_set_style_text_font(label, wf_builtin_font(Int32(size)), partMain)
        lv_obj_set_style_text_color(label, lv_color_hex(color), partMain)
        lvSetText(label, s)
        return label
    }

    private func buildEmpty() {
        let title = text(screen, "Ingen vejrudsigt endnu", size: 28)
        lv_obj_align(title, LV_ALIGN_CENTER, 0, -40)
        let hint = text(screen, "Vælg et sted i WatchSync-appen,\nog åbn Synk på uret.", size: 20, color: 0x9A9A9A)
        lv_obj_set_style_text_align(hint, LV_TEXT_ALIGN_CENTER, partMain)
        lv_obj_align(hint, LV_ALIGN_CENTER, 0, 30)
    }

    private func build(_ report: WeatherReport) {
        let t = currentWallTime()
        let now = report.now
        let windy = now.wind >= WeatherReport.windyFrom

        let location = text(screen, report.location, size: 20, color: 0x9A9A9A)
        lv_obj_align(location, LV_ALIGN_TOP_MID, 0, 26)

        let icon = WeatherIconDrawing.make(screen, size: 150,
                                           shapes: WeatherIcon.shapes(now.condition, isDay: now.isDay, windy: windy),
                                           owner: &icons)
        lv_obj_set_pos(icon, 30, 62)
        let temperature = text(screen, WeatherText.temperature(now.temperature), size: 66)
        lv_obj_set_pos(temperature, 205, 78)
        let feels = text(screen, "Føles som " + WeatherText.temperature(now.feelsLike), size: 20, color: 0xB0B0B0)
        lv_obj_set_pos(feels, 205, 160)

        let description = text(screen, WeatherText.description(now), size: 28)
        lv_obj_align(description, LV_ALIGN_TOP_MID, 0, 226)

        var details = "Vind " + WeatherText.wind(now.wind)
        if let today = report.day(for: t) {
            details = "H " + WeatherText.temperature(today.high) + "   L " + WeatherText.temperature(today.low) + "   " + details
        }
        let detailsLabel = text(screen, details, size: 20, color: 0xB0B0B0)
        lv_obj_align(detailsLabel, LV_ALIGN_TOP_MID, 0, 270)

        var y: Int32 = 318
        for day in report.days(from: t) {
            let row = lvPlainObject(screen)
            lv_obj_set_size(row, 370, 64)
            lv_obj_set_pos(row, 20, y)
            lv_obj_set_style_border_side(row, LV_BORDER_SIDE_TOP, partMain)
            lv_obj_set_style_border_width(row, 1, partMain)
            lv_obj_set_style_border_color(row, lv_color_hex(0x2A2A2A), partMain)

            let name = text(row, WeatherText.dayName(day, today: t), size: 28)
            lv_obj_align(name, LV_ALIGN_LEFT_MID, 8, 0)
            let dayIcon = WeatherIconDrawing.make(row, size: 52,
                                                  shapes: WeatherIcon.shapes(day.condition, isDay: true,
                                                                             windy: day.windMax >= WeatherReport.windyFrom),
                                                  owner: &icons)
            lv_obj_align(dayIcon, LV_ALIGN_LEFT_MID, 160, 0)
            let low = text(row, WeatherText.temperature(day.low), size: 28, color: 0x8A8A8A)
            lv_obj_align(low, LV_ALIGN_RIGHT_MID, -8, 0)
            let high = text(row, WeatherText.temperature(day.high), size: 28)
            lv_obj_align(high, LV_ALIGN_RIGHT_MID, -78, 0)
            y += 64
        }

        let ageSeconds = Int64(time(nil)) - report.updated
        let updated = text(screen, updatedText(report.updated, today: t), size: 20,
                           color: ageSeconds > staleAfterSeconds ? 0xFF8A00 : 0x7A7A7A)
        lv_obj_set_style_text_align(updated, LV_TEXT_ALIGN_CENTER, partMain)
        lv_obj_set_pos(updated, 0, y + 16)
        lv_obj_set_width(updated, Int32(WatchScreen.width))
        // Room to scroll the last line clear of the rounded bottom corners
        let spacer = lvPlainObject(screen)
        lv_obj_set_size(spacer, 1, 40)
        lv_obj_set_pos(spacer, 0, y + (ageSeconds > staleAfterSeconds ? 80 : 50))
    }

    private func updatedText(_ unix: Int64, today: WallTime) -> String {
        var seconds = time_t(unix)
        var t = tm()
        localtime_r(&seconds, &t)
        let clock = (t.tm_hour < 10 ? "0" : "") + "\(t.tm_hour):" + (t.tm_min < 10 ? "0" : "") + "\(t.tm_min)"
        let sameDay = Int(t.tm_year) + 1900 == today.year && Int(t.tm_mon) + 1 == today.month && Int(t.tm_mday) == today.day
        let when = sameDay ? "i dag kl. " + clock : "\(t.tm_mday)/\(t.tm_mon + 1) kl. " + clock
        if Int64(time(nil)) - unix > staleAfterSeconds {
            return "Opdateret " + when + "\nÅbn Synk for en ny vejrudsigt"
        }
        return "Opdateret " + when
    }
}

nonisolated(unsafe) private var weatherUI: WeatherUI?

@_cdecl("weather_app_show")
public func weather_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    weatherUI = WeatherUI(screen: screen)
}

@_cdecl("weather_app_hide")
public func weather_app_hide() {
    // The screen (and the icon objects) are deleted by the app framework after this; the drawings must outlive
    // them, so they are kept until the next show
}
