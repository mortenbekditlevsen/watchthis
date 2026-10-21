// Thin helpers over LVGL's C API (imported through BridgingHeader.h). LVGL objects are OpaquePointer: their
// structs are private in LVGL 9.

typealias LVObj = OpaquePointer

let partMain = LV_PART_MAIN.rawValue
let partIndicator = LV_PART_INDICATOR.rawValue
let partKnob = LV_PART_KNOB.rawValue

func lvColor(_ c: FaceColor) -> lv_color_t {
    lv_color_make(c.r, c.g, c.b)
}

/// A plain object with nothing drawn (no background, border, padding) and no interaction
func lvPlainObject(_ parent: LVObj?) -> LVObj {
    let obj = lv_obj_create(parent)!
    lv_obj_remove_style_all(obj)
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_CLICKABLE)
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE)
    return obj
}

/// Align `obj` so its `anchor` point is at (x, y) of its parent (which must have the screen's size)
func lvPlace(_ obj: LVObj, _ p: Placement) {
    let align: lv_align_t
    switch p.anchor {
    case .topLeading: align = LV_ALIGN_TOP_LEFT
    case .top: align = LV_ALIGN_TOP_MID
    case .topTrailing: align = LV_ALIGN_TOP_RIGHT
    case .leading: align = LV_ALIGN_LEFT_MID
    case .center: align = LV_ALIGN_CENTER
    case .trailing: align = LV_ALIGN_RIGHT_MID
    case .bottomLeading: align = LV_ALIGN_BOTTOM_LEFT
    case .bottom: align = LV_ALIGN_BOTTOM_MID
    case .bottomTrailing: align = LV_ALIGN_BOTTOM_RIGHT
    }
    // LVGL aligns to the parent's matching point; the offset is from there
    let w = WatchScreen.width, h = WatchScreen.height
    let dx = p.x - [0, w / 2, w][p.anchor.horizontal]
    let dy = p.y - [0, h / 2, h][p.anchor.vertical]
    lv_obj_align(obj, align, Int32(dx), Int32(dy))
}

func lvTextAlign(_ anchor: PlacementAnchor) -> lv_text_align_t {
    [LV_TEXT_ALIGN_LEFT, LV_TEXT_ALIGN_CENTER, LV_TEXT_ALIGN_RIGHT][anchor.horizontal]
}

func lvSetText(_ label: LVObj, _ text: String) {
    text.withCString { new in
        if let old = lv_label_get_text(label), strcmp(old, new) == 0 { return }
        lv_label_set_text(label, new)
    }
}

extension String {
    /// For C APIs that want a mutable char buffer or a path
    var cBytes: [CChar] { utf8.map { CChar(bitPattern: $0) } + [0] }
}

// MARK: - Time and sensors

func currentWallTime() -> WallTime {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var t = tm()
    localtime_r(&seconds, &t)
    return WallTime(year: Int(t.tm_year) + 1900, month: Int(t.tm_mon) + 1, day: Int(t.tm_mday),
                    weekday: Int(t.tm_wday), hour: Int(t.tm_hour), minute: Int(t.tm_min), second: Int(t.tm_sec),
                    millisecond: Int(now.tv_usec) / 1000)
}

nonisolated(unsafe) var batterySource: (@convention(c) () -> Int32)? = nil

func batteryPercent() -> Int {
    guard let source = batterySource else { return -1 }
    return Int(source())
}

// MARK: - Files

func fileExists(_ path: String) -> Bool {
    var st = stat()
    return path.withCString { stat($0, &st) } == 0
}

func readFile(_ path: String, maxSize: Int) -> [UInt8]? {
    guard let f = path.withCString({ fopen($0, "rb") }) else { return nil }
    defer { fclose(f) }
    fseek(f, 0, SEEK_END)
    let size = ftell(f)
    guard size > 0, size <= maxSize else { return nil }
    fseek(f, 0, SEEK_SET)
    var bytes = [UInt8](repeating: 0, count: size)
    guard fread(&bytes, 1, size, f) == size else { return nil }
    return bytes
}

/// Write via a temporary file and rename, so readers never see half a file
func writeFile(_ path: String, _ bytes: [UInt8]) -> Bool {
    let tmp = path + ".tmp"
    guard let f = tmp.withCString({ fopen($0, "wb") }) else { return false }
    let ok = fwrite(bytes, 1, bytes.count, f) == bytes.count
    fclose(f)
    guard ok else {
        _ = tmp.withCString { unlink($0) }
        return false
    }
    _ = path.withCString { unlink($0) }
    return tmp.withCString { t in path.withCString { rename(t, $0) } } == 0
}

func storePath(_ kind: file_store_kind_t, _ id: String) -> String? {
    var buf = [CChar](repeating: 0, count: Int(FILE_STORE_PATH_MAX))
    let ok = id.withCString { file_store_path(kind, $0, &buf, buf.count) }
    return ok ? String(cString: buf) : nil
}
