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

/// Text in the big font with every digit in a cell as wide as the widest digit ("tabular figures"), so a running time
/// doesn't jitter as digits change. The row stays centered on its alignment point whatever its length.
final class DigitDisplay {
    let row: LVObj
    private var cells: [LVObj] = []
    private var shown: [UInt8] = []
    private let font: UnsafePointer<lv_font_t>
    private let digitWidth: Int32
    private let color: UInt32

    /// Aligns the row's center to `align` + (x, y) of `parent`
    init(_ parent: LVObj, size: Int32, color: UInt32 = 0xFFFFFF, align: lv_align_t, x: Int32, y: Int32) {
        font = wt_font(size)
        self.color = color
        var widest: UInt32 = 0
        for d in UInt32(0x30)...UInt32(0x39) {
            widest = max(widest, UInt32(lv_font_get_glyph_width(font, d, 0)))
        }
        digitWidth = Int32(widest)
        row = lv_obj_create(parent)!
        lv_obj_remove_style_all(row)
        lv_obj_remove_flag(row, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW)
        // The big font is slanted: the last character sticks out past its cell, and the row would clip it. Room on
        // both sides keeps the row centered
        lv_obj_set_style_pad_left(row, 16, partMain)
        lv_obj_set_style_pad_right(row, 16, partMain)
        lv_obj_set_size(row, wt_size_content(), wt_size_content())
        // lv_obj_align is kept: LVGL re-aligns the row whenever its width changes
        lv_obj_align(row, align, x, y)
    }

    func setText(_ text: String) {
        let bytes = Array(text.utf8)
        guard bytes != shown else { return }
        // One cell per character; rebuilt only when the length changes
        if bytes.count != shown.count {
            lv_obj_clean(row)
            cells = []
            for _ in bytes {
                let cell = lv_label_create(row)!
                lv_obj_set_style_text_font(cell, font, partMain)
                lv_obj_set_style_text_color(cell, lv_color_hex(color), partMain)
                lv_obj_set_style_text_align(cell, LV_TEXT_ALIGN_CENTER, partMain)
                cells.append(cell)
            }
            shown = []
        }
        for (i, byte) in bytes.enumerated() where i >= shown.count || shown[i] != byte {
            let isDigit = byte >= 0x30 && byte <= 0x39
            lv_obj_set_width(cells[i], isDigit ? digitWidth
                                                : Int32(lv_font_get_glyph_width(font, UInt32(byte), 0)))
            String(decoding: [byte], as: UTF8.self).withCString { lv_label_set_text(cells[i], $0) }
        }
        shown = bytes
    }
}
