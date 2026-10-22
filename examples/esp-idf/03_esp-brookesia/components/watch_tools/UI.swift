// Small LVGL helpers for the Stopur and Timer apps. LVGL objects are OpaquePointer (their structs are private).

typealias LVObj = OpaquePointer

let partMain = LV_PART_MAIN.rawValue
let partIndicator = LV_PART_INDICATOR.rawValue
let partKnob = LV_PART_KNOB.rawValue
let partSelected = LV_PART_SELECTED.rawValue
let stateDisabled = LV_STATE_DISABLED.rawValue

let screenWidth: Int32 = 410
let screenHeight: Int32 = 502

enum Palette {
    static let green: UInt32 = 0x2ECC71
    static let red: UInt32 = 0xE74C3C
    static let orange: UInt32 = 0xFF8A00
    static let blue: UInt32 = 0x3F8CFF
    static let grey: UInt32 = 0x3A3A3A
    static let dimText: UInt32 = 0x9A9A9A
}

/// Monotonic microseconds; keeps counting while the watch sleeps
func now() -> Int64 {
    esp_timer_get_time()
}

func label(_ parent: LVObj, _ text: String, size: Int32, color: UInt32 = 0xFFFFFF) -> LVObj {
    let label = lv_label_create(parent)!
    lv_obj_set_style_text_font(label, wt_font(size), partMain)
    lv_obj_set_style_text_color(label, lv_color_hex(color), partMain)
    setText(label, text)
    return label
}

func setText(_ label: LVObj, _ text: String) {
    text.withCString { new in
        if let old = lv_label_get_text(label), strcmp(old, new) == 0 { return }
        lv_label_set_text(label, new)
    }
}

/// A button with a centered label; `tag` comes back in the click callback as the event's user data
func button(_ parent: LVObj, _ labelText: String, color: UInt32, width: Int32, height: Int32, round: Bool = false,
            size: Int32 = 28, tag: Int = 0,
            onClick: @convention(c) (OpaquePointer?) -> Void) -> (button: LVObj, label: LVObj) {
    let button = lv_button_create(parent)!
    lv_obj_set_size(button, width, height)
    lv_obj_set_style_radius(button, round ? wt_radius_circle() : 22, partMain)
    lv_obj_set_style_shadow_width(button, 0, partMain)
    setButtonColor(button, color)
    // The label inherits the text color, so it dims with the button: dark with dim text when disabled
    lv_obj_set_style_text_color(button, lv_color_white(), partMain)
    lv_obj_set_style_bg_color(button, lv_color_hex(0x1E1E1E), partMain | stateDisabled)
    lv_obj_set_style_text_color(button, lv_color_hex(0x5A5A5A), partMain | stateDisabled)
    let text = lv_label_create(button)!
    lv_obj_set_style_text_font(text, wt_font(size), partMain)
    setText(text, labelText)
    lv_obj_center(text)
    lv_obj_add_event_cb(button, onClick, LV_EVENT_CLICKED, UnsafeMutableRawPointer(bitPattern: tag + 1))
    return (button, text)
}

func setButtonColor(_ button: LVObj, _ color: UInt32) {
    lv_obj_set_style_bg_color(button, lv_color_hex(color), partMain)
    lv_obj_set_style_bg_opa(button, 255, partMain)
}

func setEnabled(_ obj: LVObj, _ enabled: Bool) {
    if enabled {
        lv_obj_remove_state(obj, LV_STATE_DISABLED)
    } else {
        lv_obj_add_state(obj, LV_STATE_DISABLED)
    }
}

/// The `tag` given to `button`
func eventTag(_ e: OpaquePointer?) -> Int {
    Int(bitPattern: lv_event_get_user_data(e)) - 1
}

/// A full-screen black background without scrolling
func prepareScreen(_ screen: LVObj) {
    lv_obj_clean(screen)
    lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
    lv_obj_set_style_bg_opa(screen, 255, partMain)
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
}

// MARK: - Files

func readFile(_ path: String, maxSize: Int) -> [UInt8]? {
    guard let f = path.withCString({ fopen($0, "rb") }) else { return nil }
    defer { fclose(f) }
    var bytes = [UInt8](repeating: 0, count: maxSize)
    let n = fread(&bytes, 1, maxSize, f)
    return Array(bytes.prefix(n))
}

func writeFile(_ path: String, _ bytes: [UInt8]) {
    guard let f = path.withCString({ fopen($0, "wb") }) else { return }
    _ = fwrite(bytes, 1, bytes.count, f)
    fclose(f)
}
