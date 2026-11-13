// Bøger: books from the phone (file_store kind FILE_STORE_BOOK; WatchFaceKit BookFile). A library of the books, then
// a page at a time: tap the right third for the next page, the left third for the previous one, the middle (or a long
// press) for the menu: chapters, a position slider, the font size, back to the books.
//
// A book doesn't fit in RAM: a page is laid out (WatchFaceKit BookLayout) from a window of the text read with pread.
// Going back a page after a jump (no history) lays out the pages from the paragraph before. Where each book is read to
// is kept in /store/books/<id>.pos (a byte offset of the text), written a little after paging and when the app closes.

private let windowBytes = 3072
private let fontSizes: [Int32] = [20, 24, 28]
private let fontSettingPath = "/store/books/font.bin"
private let pageX: Int32 = 30
private let pageY: Int32 = 58
private let pageW: Int32 = Int32(WatchScreen.width) - 2 * pageX
private let pageH: Int32 = Int32(WatchScreen.height) - pageY - 52
private let lineSpace: Int32 = 4
private let grey = FaceColor(r: 150, g: 150, b: 150)
private let amber = FaceColor(r: 255, g: 176, b: 32)

// MARK: - Books on the watch

private struct BookEntry {
    let id: String
    let name: String
}

private enum BookShelf {
    static func entries() -> [BookEntry] {
        let count = Int(max(0, file_store_list(FILE_STORE_BOOK, nil, 0)))
        guard count > 0, let raw = malloc(count * MemoryLayout<file_store_entry_t>.stride) else { return [] }
        defer { free(raw) }
        let entries = raw.bindMemory(to: file_store_entry_t.self, capacity: count)
        let total = min(count, Int(max(0, file_store_list(FILE_STORE_BOOK, entries, Int32(count)))))
        var result: [BookEntry] = []
        for i in 0..<total {
            let id = withUnsafeBytes(of: entries[i].id) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let name = withUnsafeBytes(of: entries[i].name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            result.append(BookEntry(id: id, name: name.isEmpty ? id : name))
        }
        return result
    }

    /// Next to the book (file_store removes it with the book)
    static func positionPath(_ id: String) -> String { "/store/books/" + id + ".pos" }

    static func position(_ id: String) -> Int {
        guard let b = readFile(positionPath(id), maxSize: 4), b.count == 4 else { return 0 }
        return Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
    }

    static func savePosition(_ id: String, _ offset: Int) {
        _ = writeFile(positionPath(id), [UInt8(offset & 0xFF), UInt8(offset >> 8 & 0xFF), UInt8(offset >> 16 & 0xFF),
                                         UInt8(offset >> 24 & 0xFF)])
    }

    /// 0, 1 or 2 (20, 24, 28 px)
    static var fontSetting: Int {
        get { Int(readFile(fontSettingPath, maxSize: 1)?.first ?? 1).clamped(0, 2) }
        set { _ = writeFile(fontSettingPath, [UInt8(newValue)]) }
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}

/// An open book: its chapters, and its text read a window at a time
private final class OpenBook {
    let id: String
    let fd: Int32
    let textOffset: Int
    let textLength: Int
    let chapters: [BookChapter]

    init?(id: String) {
        guard let path = storePath(FILE_STORE_BOOK, id) else { return nil }
        let fd = path.withCString { wf_open_read($0) }
        guard fd >= 0 else { return nil }
        var head = [UInt8](repeating: 0, count: BookFile.headerSize)
        do throws(BookDecodingError) {
            guard pread(fd, &head, head.count, 0) == head.count else { throw .truncated }
            let h = try BookFile.header(head)
            var table = [UInt8](repeating: 0, count: h.textOffset - BookFile.headerSize)
            guard table.isEmpty || pread(fd, &table, table.count, BookFile.headerSize) == table.count else {
                throw .truncated
            }
            chapters = try BookFile.chapters(table, count: h.chapters)
            textOffset = h.textOffset
            textLength = h.textLength
        } catch {
            close(fd)
            print("books: \(id) can't be read")
            return nil
        }
        self.id = id
        self.fd = fd
    }

    deinit { close(fd) }

    /// Up to `count` bytes of the text from `offset`
    func read(_ offset: Int, _ count: Int) -> [UInt8] {
        let n = max(0, min(count, textLength - offset))
        guard n > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: n)
        let got = pread(fd, &bytes, n, textOffset + offset)
        return got > 0 ? Array(bytes.prefix(got)) : []
    }

    /// The chapter `offset` is in
    func chapter(at offset: Int) -> BookChapter? {
        chapters.last { $0.offset <= offset }
    }
}

// MARK: - Paging

private struct BookPage {
    let start: Int
    let end: Int
    let text: String
}

private struct Pager {
    let font: UnsafePointer<lv_font_t>
    let lines: Int

    init(font: UnsafePointer<lv_font_t>) {
        self.font = font
        lines = max(1, Int((pageH + lineSpace) / (lv_font_get_line_height(font) + lineSpace)))
    }

    func page(_ book: OpenBook, at start: Int) -> BookPage {
        let window = book.read(start, windowBytes)
        let isEnd = start + window.count >= book.textLength
        let font = self.font
        let layout = BookLayout.page(window, start: 0, isEnd: isEnd, lineWidth: Int(pageW), lines: lines) { cp, next in
            Int(lv_font_get_glyph_width(font, cp, next))
        }
        var text: [UInt8] = []
        for (i, line) in layout.lines.enumerated() {
            if i > 0 { text.append(0x0A) }
            text += window[line]
        }
        // At least a character: never stuck
        let end = layout.end > 0 ? start + layout.end : min(book.textLength, start + max(1, window.count))
        return BookPage(start: start, end: end, text: String(decoding: text, as: UTF8.self))
    }

    /// Where the page before the one at `start` starts: pages laid out from the paragraph before
    func pageBefore(_ book: OpenBook, _ start: Int) -> Int {
        guard start > 0 else { return 0 }
        let from = max(0, start - windowBytes)
        let window = book.read(from, start - from)
        // The paragraph before the one `start` is in (or, at a paragraph's start, the one before that)
        let searchFrom = window.count - 1 > 0 && window.last == 0x0A ? window.count - 1 : window.count
        var p = from + BookLayout.paragraphStart(window, before: searchFrom)
        if p == from && from > 0 {
            p = from + BookLayout.characterStart(window, 0)
        }
        var previous = p
        var at = p
        for _ in 0..<64 {
            let next = page(book, at: at).end
            if next >= start || next <= at { return at }
            previous = at
            at = next
        }
        return previous
    }

    /// The start of the paragraph `offset` is in (a jump lands at a paragraph)
    func paragraph(_ book: OpenBook, at offset: Int) -> Int {
        let target = offset.clamped(0, max(0, book.textLength - 1))
        let from = max(0, target - 1024)
        let window = book.read(from, target - from + 1)
        let p = BookLayout.paragraphStart(window, before: target - from)
        return from + (p == 0 && from > 0 ? BookLayout.characterStart(window, 0) : p)
    }
}

// MARK: - UI

private final class BooksUI {
    private let screen: LVObj
    private var root: LVObj?
    private var book: OpenBook?
    private var pager: Pager
    private var current: BookPage?
    private var history: [Int] = []
    private var saveTimer: OpaquePointer?
    private var pressPoint = lv_point_t()
    private var menu: LVObj?
    private var sliderLabel: LVObj?
    private var roller: LVObj?
    private var shelf: [BookEntry] = []
    private var pageLabel: LVObj?
    private var headerLabel: LVObj?
    private var footerLabel: LVObj?

    init(screen: LVObj) {
        self.screen = screen
        pager = Pager(font: wf_read_font(fontSizes[BookShelf.fontSetting]))
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
        // The screen goes off after a minute idle (reading takes longer than the usual 10 s); woken, it's still here
        lv_obj_add_flag(screen, LV_OBJ_FLAG_USER_1)
        lv_obj_add_flag(screen, LV_OBJ_FLAG_USER_2)
        showLibrary()
    }

    func stop() {
        savePosition()
        if let saveTimer { lv_timer_delete(saveTimer) }
        saveTimer = nil
    }

    /// A new screenful (the old one goes after this event: a button of it may be what was tapped)
    private func newRoot() -> LVObj {
        if let root { lv_obj_delete_async(root) }
        menu = nil
        pageLabel = nil
        headerLabel = nil
        footerLabel = nil
        let r = lvPlainObject(screen)
        lv_obj_set_size(r, Int32(WatchScreen.width), Int32(WatchScreen.height))
        root = r
        return r
    }

    private func label(_ parent: LVObj, _ text: String, size: Int32, color: lv_color_t) -> LVObj {
        let l = lv_label_create(parent)!
        lv_obj_set_style_text_font(l, wf_builtin_font(size), partMain)
        lv_obj_set_style_text_color(l, color, partMain)
        lvSetText(l, text)
        return l
    }

    private func button(_ parent: LVObj, _ text: String, w: Int32, h: Int32 = 56,
                        color: FaceColor = FaceColor(r: 51, g: 51, b: 51), _ action: @escaping (BooksUI) -> Void) -> LVObj {
        let b = lvPlainObject(parent)
        lv_obj_set_size(b, w, h)
        lv_obj_set_style_radius(b, h / 2, partMain)
        lv_obj_set_style_bg_color(b, lvColor(color), partMain)
        lv_obj_set_style_bg_opa(b, 255, partMain)
        lv_obj_set_style_bg_color(b, lv_color_make(110, 110, 110), partMain | lv_style_selector_t(LV_STATE_PRESSED.rawValue))
        lv_obj_add_flag(b, LV_OBJ_FLAG_CLICKABLE)
        let l = label(b, text, size: 20, color: lv_color_white())
        lv_obj_center(l)
        actions.append(action)
        let index = actions.count - 1
        lv_obj_add_event_cb(b, { e in
            guard let ui = booksUI else { return }
            let i = Int(bitPattern: lv_event_get_user_data(e)) - 1
            if i >= 0 && i < ui.actions.count { ui.actions[i](ui) }
        }, LV_EVENT_CLICKED, UnsafeMutableRawPointer(bitPattern: index + 1))
        return b
    }

    /// Buttons' actions, by index (the event's user data); cleared with the objects
    private var actions: [(BooksUI) -> Void] = []

    // MARK: Library

    private func showLibrary() {
        stop()
        book = nil
        actions.removeAll()
        let r = newRoot()
        let title = label(r, "Bøger", size: 28, color: lv_color_white())
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 24)
        shelf = BookShelf.entries()
        if shelf.isEmpty {
            let empty = label(r, "Ingen bøger endnu.\n\nTilføj bøger fra WatchSync-appen på telefonen.", size: 20,
                              color: lvColor(grey))
            lv_obj_set_width(empty, 320)
            lv_label_set_long_mode(empty, LV_LABEL_LONG_MODE_WRAP)
            lv_obj_set_style_text_align(empty, LV_TEXT_ALIGN_CENTER, partMain)
            lv_obj_center(empty)
            return
        }
        let list = lvPlainObject(r)
        lv_obj_set_pos(list, 20, 76)
        lv_obj_set_size(list, Int32(WatchScreen.width) - 40, Int32(WatchScreen.height) - 76 - 20)
        lv_obj_add_flag(list, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_set_scroll_dir(list, LV_DIR_VER)
        lv_obj_set_flex_flow(list, LV_FLEX_FLOW_COLUMN)
        lv_obj_set_style_pad_row(list, 10, partMain)
        lv_obj_set_style_pad_bottom(list, 30, partMain)
        for entry in shelf {
            let percent = progress(entry.id)
            let row = button(list, "", w: Int32(WatchScreen.width) - 40, h: 76) { ui in ui.open(entry.id) }
            lv_obj_set_style_radius(row, 18, partMain)
            if let l = lv_obj_get_child(row, 0) { lv_obj_delete(l) }
            let name = lv_label_create(row)!
            lv_obj_set_style_text_font(name, wf_read_font(20), partMain)
            lv_obj_set_style_text_color(name, lv_color_white(), partMain)
            lv_obj_set_width(name, Int32(WatchScreen.width) - 40 - 110)
            lv_label_set_long_mode(name, LV_LABEL_LONG_MODE_DOTS)
            lvSetText(name, entry.name)
            lv_obj_align(name, LV_ALIGN_LEFT_MID, 20, 0)
            let p = label(row, "\(percent) %", size: 20, color: lvColor(amber))
            lv_obj_align(p, LV_ALIGN_RIGHT_MID, -20, 0)
        }
    }

    private func progress(_ id: String) -> Int {
        guard let path = storePath(FILE_STORE_BOOK, id) else { return 0 }
        let fd = path.withCString { wf_open_read($0) }
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var head = [UInt8](repeating: 0, count: BookFile.headerSize)
        guard pread(fd, &head, head.count, 0) == head.count, let h = try? BookFile.header(head), h.textLength > 0 else {
            return 0
        }
        return min(100, BookShelf.position(id) * 100 / h.textLength)
    }

    // MARK: Reading

    private func open(_ id: String) {
        guard let b = OpenBook(id: id) else { return }
        book = b
        history.removeAll()
        actions.removeAll()
        let r = newRoot()
        let header = lv_label_create(r)!
        lv_obj_set_style_text_font(header, wf_read_font(20), partMain)
        lv_obj_set_style_text_color(header, lvColor(grey), partMain)
        lv_obj_set_width(header, 300)
        lv_label_set_long_mode(header, LV_LABEL_LONG_MODE_DOTS)
        lv_obj_set_style_text_align(header, LV_TEXT_ALIGN_CENTER, partMain)
        lv_obj_align(header, LV_ALIGN_TOP_MID, 0, 18)
        headerLabel = header

        let page = lv_label_create(r)!
        lv_obj_set_pos(page, pageX, pageY)
        // Lines are already broken (BookLayout): a little slack so the label never breaks one again
        lv_obj_set_width(page, pageW + 24)
        lv_label_set_long_mode(page, LV_LABEL_LONG_MODE_CLIP)
        lv_obj_set_style_text_color(page, lv_color_white(), partMain)
        lv_obj_set_style_text_line_space(page, lineSpace, partMain)
        pageLabel = page

        let footer = label(r, "", size: 16, color: lvColor(grey))
        lv_obj_align(footer, LV_ALIGN_BOTTOM_MID, 0, -18)
        footerLabel = footer

        // Taps anywhere (over the text too): left third back, right third on, the middle for the menu
        lv_obj_add_flag(r, LV_OBJ_FLAG_CLICKABLE)
        for code in [LV_EVENT_PRESSED, LV_EVENT_SHORT_CLICKED, LV_EVENT_LONG_PRESSED] {
            lv_obj_add_event_cb(r, { e in booksUI?.touch(lv_event_get_code(e)) }, code, nil)
        }
        show(at: BookShelf.position(id).clamped(0, max(0, b.textLength - 1)))
    }

    private func show(at start: Int) {
        guard let book, let pageLabel else { return }
        lv_obj_set_style_text_font(pageLabel, pager.font, partMain)
        let page = pager.page(book, at: start)
        current = page
        lvSetText(pageLabel, page.text)
        if let headerLabel { lvSetText(headerLabel, book.chapter(at: start)?.title ?? "") }
        if let footerLabel {
            lvSetText(footerLabel, "\(book.textLength > 0 ? min(100, page.end * 100 / book.textLength) : 100) %")
        }
        scheduleSave()
    }

    private func touch(_ code: lv_event_code_t) {
        var p = lv_point_t()
        lv_indev_get_point(lv_indev_active(), &p)
        switch code {
        case LV_EVENT_PRESSED:
            pressPoint = p
        case LV_EVENT_LONG_PRESSED:
            showMenu()
        default:
            // A tap, not a swipe that ended near where it began
            guard abs(p.x - pressPoint.x) <= 20, abs(p.y - pressPoint.y) <= 20, menu == nil else { return }
            let third = Int32(WatchScreen.width) / 3
            if p.x < third {
                previousPage()
            } else if p.x >= 2 * third {
                nextPage()
            } else {
                showMenu()
            }
        }
    }

    private func nextPage() {
        guard let book, let current, current.end < book.textLength else { return }
        history.append(current.start)
        if history.count > 200 { history.removeFirst() }
        show(at: current.end)
    }

    private func previousPage() {
        guard let book, let current, current.start > 0 else { return }
        show(at: history.popLast() ?? pager.pageBefore(book, current.start))
    }

    private func jump(to offset: Int) {
        guard let book else { return }
        history.removeAll()
        show(at: pager.paragraph(book, at: offset))
    }

    // MARK: Position

    private func scheduleSave() {
        if let saveTimer {
            lv_timer_reset(saveTimer)
            return
        }
        saveTimer = lv_timer_create({ _ in
            guard let ui = booksUI else { return }
            ui.savePosition()
            if let t = ui.saveTimer { lv_timer_delete(t) }
            ui.saveTimer = nil
        }, 2000, nil)
    }

    private func savePosition() {
        guard let book, let current else { return }
        if BookShelf.position(book.id) != current.start {
            BookShelf.savePosition(book.id, current.start)
        }
    }

    // MARK: Menu

    private func closeMenu() {
        if let menu { lv_obj_delete_async(menu) }    // (From one of its buttons' events)
        menu = nil
        roller = nil
        sliderLabel = nil
    }

    private func menuPanel() -> LVObj {
        closeMenu()
        let m = lvPlainObject(root)
        lv_obj_set_size(m, Int32(WatchScreen.width), Int32(WatchScreen.height))
        lv_obj_set_style_bg_color(m, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(m, 255, partMain)
        lv_obj_add_flag(m, LV_OBJ_FLAG_CLICKABLE)    // Taps don't reach the page under it
        menu = m
        return m
    }

    private func showMenu() {
        guard let book, let current else { return }
        let m = menuPanel()
        let w = Int32(WatchScreen.width) - 80
        let resume = button(m, "Fortsæt læsning", w: w, color: amber) { ui in ui.closeMenu() }
        lv_obj_align(resume, LV_ALIGN_TOP_MID, 0, 40)
        if let l = lv_obj_get_child(resume, 0) { lv_obj_set_style_text_color(l, lv_color_black(), partMain) }

        let chapters = button(m, "Kapitler", w: w) { ui in ui.showChapters() }
        lv_obj_align(chapters, LV_ALIGN_TOP_MID, 0, 108)
        if book.chapters.count < 2 { lv_obj_add_state(chapters, LV_STATE_DISABLED) }

        // Where in the book: dragged, then jumped to when let go
        let percent = book.textLength > 0 ? current.start * 1000 / book.textLength : 0
        let pos = label(m, "\(percent / 10) %", size: 20, color: lv_color_white())
        lv_obj_align(pos, LV_ALIGN_TOP_MID, 0, 182)
        sliderLabel = pos
        let slider = lv_slider_create(m)!
        lv_obj_set_size(slider, w - 20, 22)
        lv_obj_align(slider, LV_ALIGN_TOP_MID, 0, 222)
        lv_slider_set_range(slider, 0, 1000)
        lv_slider_set_value(slider, Int32(percent), false)
        lv_obj_set_style_bg_color(slider, lv_color_make(51, 51, 51), partMain)
        lv_obj_set_style_bg_color(slider, lvColor(amber), partIndicator)
        lv_obj_set_style_bg_color(slider, lv_color_white(), partKnob)
        lv_obj_set_style_pad_all(slider, 8, partKnob)
        lv_obj_remove_flag(slider, LV_OBJ_FLAG_GESTURE_BUBBLE)
        lv_obj_add_event_cb(slider, { e in
            guard let ui = booksUI, let s = lv_event_get_target_obj(e) else { return }
            if let l = ui.sliderLabel { lvSetText(l, "\(lv_slider_get_value(s) / 10) %") }
        }, LV_EVENT_VALUE_CHANGED, nil)
        lv_obj_add_event_cb(slider, { e in
            guard let ui = booksUI, let s = lv_event_get_target_obj(e), let book = ui.book else { return }
            let target = Int(lv_slider_get_value(s)) * book.textLength / 1000
            ui.closeMenu()
            ui.jump(to: target)
        }, LV_EVENT_RELEASED, nil)

        // Font size
        let sizeLabel = label(m, "Skriftstørrelse", size: 20, color: lvColor(grey))
        lv_obj_align(sizeLabel, LV_ALIGN_TOP_MID, 0, 272)
        let setting = BookShelf.fontSetting
        for (i, name) in ["S", "M", "L"].enumerated() {
            let b = button(m, name, w: 80, color: i == setting ? amber : FaceColor(r: 51, g: 51, b: 51)) { ui in
                ui.setFont(i)
            }
            lv_obj_align(b, LV_ALIGN_TOP_MID, Int32(i - 1) * 100, 306)
        }

        let back = button(m, "Bøger", w: w) { ui in ui.showLibrary() }
        lv_obj_align(back, LV_ALIGN_TOP_MID, 0, 390)
    }

    private func setFont(_ i: Int) {
        BookShelf.fontSetting = i
        pager = Pager(font: wf_read_font(fontSizes[i]))
        closeMenu()
        if let current {
            history.removeAll()
            show(at: current.start)
        }
    }

    private func showChapters() {
        guard let book, let current else { return }
        let m = menuPanel()
        let title = label(m, "Kapitler", size: 28, color: lv_color_white())
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 24)
        // One roller holds all the titles (an object per chapter would take too much RAM in a long book)
        let r = lv_roller_create(m)!
        var options: [UInt8] = []
        for (i, c) in book.chapters.enumerated() {
            if i > 0 { options.append(0x0A) }
            // A roller option is one line: no newlines, and not empty
            let t = Array(c.title.utf8).filter { $0 != 0x0A }
            options += t.isEmpty ? Array("Kapitel \(i + 1)".utf8) : t
        }
        String(decoding: options, as: UTF8.self).withCString { lv_roller_set_options(r, $0, LV_ROLLER_MODE_NORMAL) }
        lv_obj_set_width(r, Int32(WatchScreen.width) - 60)
        lv_roller_set_visible_row_count(r, 6)
        lv_obj_set_style_text_font(r, wf_read_font(20), partMain)
        lv_obj_set_style_bg_color(r, lv_color_black(), partMain)
        lv_obj_set_style_text_color(r, lvColor(grey), partMain)
        lv_obj_set_style_border_width(r, 0, partMain)
        lv_obj_set_style_bg_color(r, lv_color_make(51, 51, 51), lv_style_selector_t(LV_PART_SELECTED.rawValue))
        lv_obj_set_style_text_color(r, lv_color_white(), lv_style_selector_t(LV_PART_SELECTED.rawValue))
        lv_obj_align(r, LV_ALIGN_TOP_MID, 0, 76)
        lv_obj_remove_flag(r, LV_OBJ_FLAG_GESTURE_BUBBLE)
        let index = book.chapters.lastIndex { $0.offset <= current.start } ?? 0
        lv_roller_set_selected(r, UInt32(index), false)
        roller = r

        let go = button(m, "Gå til kapitel", w: 220, color: amber) { ui in
            guard let book = ui.book, let roller = ui.roller else { return }
            let i = Int(lv_roller_get_selected(roller))
            guard i < book.chapters.count else { return }
            ui.closeMenu()
            ui.history.removeAll()
            ui.show(at: book.chapters[i].offset.clamped(0, max(0, book.textLength - 1)))
        }
        lv_obj_align(go, LV_ALIGN_BOTTOM_MID, 70, -40)
        if let l = lv_obj_get_child(go, 0) { lv_obj_set_style_text_color(l, lv_color_black(), partMain) }
        let cancel = button(m, "Tilbage", w: 120) { ui in ui.showMenu() }
        lv_obj_align(cancel, LV_ALIGN_BOTTOM_MID, -110, -40)
    }
}

nonisolated(unsafe) private var booksUI: BooksUI?

@_cdecl("books_app_show")
public func books_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    booksUI = BooksUI(screen: screen)
}

@_cdecl("books_app_hide")
public func books_app_hide() {
    // Where it was read to is saved now; the objects are deleted by the app framework after this
    booksUI?.stop()
}
