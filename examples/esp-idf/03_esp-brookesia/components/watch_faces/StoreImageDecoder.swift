// An LVGL image decoder for the watch's own RGB565 files (/store/cache/*.v2.bin: converted backgrounds, pre-drawn
// gradients, baked static layers and thumbnails). LVGL's file decoder opens the file for every draw and seeks before
// every row, and in LittleFS each open walks the directory and each seek the file's block list. This one keeps up
// to 4 files open (the switcher shows 3 at once) and reads with pread: whole rows for wide areas, and just the
// area's columns for narrow ones (a moving hand redraws many narrow areas; reading whole rows for those read up to
// 20 times more than needed).
//
// Switcher thumbnails ("tq_" files, a quarter of the screen) are shown at twice their size: LVGL can't scale images
// it gets in pieces (it draws each piece 1:1), so this decoder presents them at 2x and doubles the pixels itself,
// blending neighbours.

private let maxRows = 8
private let maxOpenFiles = 4

enum StoreImageDecoder {
    private struct OpenFile {
        let path: String
        let fd: Int32
        /// In the file
        let width: Int
        let height: Int
        /// 2 for thumbnails (shown at twice their size), else 1
        let scale: Int
    }

    nonisolated(unsafe) private static var decoder: UnsafeMutablePointer<lv_image_decoder_t>?
    /// Least recently used first
    nonisolated(unsafe) private static var files: [OpenFile] = []
    /// maxRows rows of the widest image (the screen)
    nonisolated(unsafe) private static var buffer: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static let bufferBytes = maxRows * WatchScreen.width * 2
    nonisolated(unsafe) private static var served: UnsafeMutablePointer<lv_draw_buf_t>?
    /// What `buffer` holds: file, first row, rows, first column, columns
    nonisolated(unsafe) private static var held: (fd: Int32, y: Int, rows: Int, x: Int, w: Int)?
    /// Diagnostics (Carousel's slow-frame log): time spent reading files and rows read since the last reset
    nonisolated(unsafe) static var readMicros: Int64 = 0
    nonisolated(unsafe) static var rowsRead = 0

    static func register() {
        guard decoder == nil else { return }
        // The newest decoder is asked first, so this one gets our files before LVGL's
        decoder = lv_image_decoder_create()
        lv_image_decoder_set_info_cb(decoder, { _, dsc, header in StoreImageDecoder.info(dsc, header) })
        lv_image_decoder_set_open_cb(decoder, { _, dsc in StoreImageDecoder.openSource(dsc) })
        lv_image_decoder_set_get_area_cb(decoder, { _, dsc, full, decoded in
            StoreImageDecoder.getArea(dsc, full, decoded)
        })
        lv_image_decoder_set_close_cb(decoder, { _, dsc in dsc?.pointee.decoded = nil })
    }

    /// Closes the files and frees the buffer (when files may be deleted, and when the faces close)
    static func release() {
        for f in files { close(f.fd) }
        files.removeAll()
        held = nil
        if let buffer { free(buffer) }
        buffer = nil
    }

    /// The file path of `dsc`'s source if it is one of ours ("S:/store/cache/...v2.bin")
    private static func ourPath(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?) -> String? {
        guard let dsc, dsc.pointee.src_type == LV_IMAGE_SRC_FILE, let src = dsc.pointee.src else { return nil }
        let full = String(cString: src.assumingMemoryBound(to: CChar.self))
        let prefix = "S:" + ImageWorker.cacheDir + "/"
        guard full.utf8.starts(with: prefix.utf8),
              full.utf8.reversed().starts(with: ImageWorker.cacheSuffix.utf8.reversed()) else { return nil }
        return String(decoding: full.utf8.dropFirst(2), as: UTF8.self)
    }

    /// The open file for `p` (opened, and its header read, if it isn't yet)
    private static func use(_ p: String) -> OpenFile? {
        if let i = files.firstIndex(where: { $0.path.utf8.elementsEqual(p.utf8) }) {
            let f = files.remove(at: i)
            files.append(f)
            return f
        }
        let fd = p.withCString { wf_open_read($0) }
        guard fd >= 0 else { return nil }
        var header = [UInt8](repeating: 0, count: 12)
        guard pread(fd, &header, 12, 0) == 12, header[0] == 0x19, header[1] == 0x12 else {
            close(fd)
            return nil
        }
        let w = Int(header[4]) | Int(header[5]) << 8
        let h = Int(header[6]) | Int(header[7]) << 8
        guard w > 0, w <= WatchScreen.width, h > 0 else {
            close(fd)
            return nil
        }
        if files.count >= maxOpenFiles {
            let oldest = files.removeFirst()
            close(oldest.fd)
            if held?.fd == oldest.fd { held = nil }
        }
        let isThumbnail = p.utf8.dropFirst(ImageWorker.cacheDir.utf8.count + 1).starts(with: "tq_".utf8)
        let f = OpenFile(path: p, fd: fd, width: w, height: h, scale: isThumbnail ? 2 : 1)
        files.append(f)
        return f
    }

    private static func info(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?,
                             _ header: UnsafeMutablePointer<lv_image_header_t>?) -> lv_result_t {
        guard let p = ourPath(dsc), let header, let f = use(p) else { return LV_RESULT_INVALID }
        wf_image_header_set(header, UInt32(f.width * f.scale), UInt32(f.height * f.scale))
        return LV_RESULT_OK
    }

    private static func openSource(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?) -> lv_result_t {
        guard let p = ourPath(dsc), use(p) != nil else { return LV_RESULT_INVALID }
        dsc?.pointee.decoded = nil // drawn piece by piece through getArea
        return LV_RESULT_OK
    }

    /// Serves strips of the requested area (image-relative), top to bottom
    private static func getArea(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>?,
                                _ full: UnsafePointer<lv_area_t>?,
                                _ decoded: UnsafeMutablePointer<lv_area_t>?) -> lv_result_t {
        guard let dsc, let full, let decoded, let p = ourPath(dsc), let f = use(p) else { return LV_RESULT_INVALID }
        if buffer == nil { buffer = malloc(bufferBytes) }
        if served == nil {
            served = UnsafeMutablePointer<lv_draw_buf_t>.allocate(capacity: 1)
            served!.initialize(to: lv_draw_buf_t())
        }
        guard let buffer, let served else { return LV_RESULT_INVALID }
        if f.scale == 2 { return getScaledArea(dsc, f, full, decoded, buffer, served) }

        let y = decoded.pointee.y1 == wf_coord_min() ? max(0, Int(full.pointee.y1)) : Int(decoded.pointee.y2) + 1
        guard y <= Int(full.pointee.y2), y < f.height else { return LV_RESULT_INVALID }
        let rows = min(maxRows, Int(full.pointee.y2) - y + 1, f.height - y)
        let x1 = max(0, Int(full.pointee.x1)), x2 = min(f.width - 1, Int(full.pointee.x2))
        guard x1 <= x2 else { return LV_RESULT_INVALID }
        // Wide areas: whole rows in one read. Narrow ones: just their columns, a read per row.
        let wide = (x2 - x1 + 1) * 2 >= f.width
        let (x, w) = wide ? (0, f.width) : (x1, x2 - x1 + 1)

        if let h = held, h.fd == f.fd, h.x == x, h.w == w, h.y == y, h.rows >= rows {
            // Already there (several areas over the same rows)
        } else {
            let started = esp_timer_get_time()
            var ok = true
            if wide {
                let bytes = rows * w * 2
                ok = pread(f.fd, buffer, bytes, 12 + y * f.width * 2) == bytes
            } else {
                for r in 0..<rows where ok {
                    ok = pread(f.fd, buffer + r * w * 2, w * 2, 12 + ((y + r) * f.width + x) * 2) == w * 2
                }
            }
            readMicros += esp_timer_get_time() - started
            rowsRead += rows
            guard ok else {
                held = nil
                return LV_RESULT_INVALID
            }
            held = (f.fd, y, rows, x, w)
        }
        lv_draw_buf_init(served, UInt32(w), UInt32(rows), LV_COLOR_FORMAT_RGB565, UInt32(w * 2), buffer,
                         UInt32(rows * w * 2))
        decoded.pointee.x1 = Int32(x)
        decoded.pointee.x2 = Int32(x + w - 1)
        decoded.pointee.y1 = Int32(y)
        decoded.pointee.y2 = Int32(y + rows - 1)
        dsc.pointee.decoded = UnsafePointer(served)
        return LV_RESULT_OK
    }

    /// A thumbnail at twice its size: full-width rows (they're narrow), each from the 1 or 2 file rows it lies on
    private static func getScaledArea(_ dsc: UnsafeMutablePointer<lv_image_decoder_dsc_t>,
                                      _ f: OpenFile,
                                      _ full: UnsafePointer<lv_area_t>,
                                      _ decoded: UnsafeMutablePointer<lv_area_t>,
                                      _ buffer: UnsafeMutableRawPointer,
                                      _ served: UnsafeMutablePointer<lv_draw_buf_t>) -> lv_result_t {
        let w = f.width * 2, h = f.height * 2
        let y = decoded.pointee.y1 == wf_coord_min() ? max(0, Int(full.pointee.y1)) : Int(decoded.pointee.y2) + 1
        guard y <= Int(full.pointee.y2), y < h else { return LV_RESULT_INVALID }
        let rows = min(maxRows, Int(full.pointee.y2) - y + 1, h - y)
        // Source rows y/2 ... (y + rows)/2 + 1 (the last one for blending), read in one go after the output
        let firstSource = y / 2
        let sourceRows = min(f.height - firstSource, (y + rows - 1) / 2 - firstSource + 2)
        let source = buffer + rows * w * 2
        guard rows * w * 2 + sourceRows * f.width * 2 <= bufferBytes else { return LV_RESULT_INVALID }
        let started = esp_timer_get_time()
        guard pread(f.fd, source, sourceRows * f.width * 2, 12 + firstSource * f.width * 2) == sourceRows * f.width * 2
        else { return LV_RESULT_INVALID }
        readMicros += esp_timer_get_time() - started
        rowsRead += sourceRows
        let src = source.bindMemory(to: UInt16.self, capacity: sourceRows * f.width)
        let out = buffer.bindMemory(to: UInt16.self, capacity: rows * w)
        for r in 0..<rows {
            let sy = (y + r) / 2 - firstSource
            let blendRows = (y + r) % 2 == 1 && sy + 1 < sourceRows
            for x in 0..<w {
                let sx = x / 2
                let blendCols = x % 2 == 1 && sx + 1 < f.width
                var p = src[sy * f.width + sx]
                if blendCols { p = StoreImageDecoder.mix(p, src[sy * f.width + sx + 1]) }
                if blendRows {
                    var q = src[(sy + 1) * f.width + sx]
                    if blendCols { q = StoreImageDecoder.mix(q, src[(sy + 1) * f.width + sx + 1]) }
                    p = StoreImageDecoder.mix(p, q)
                }
                out[r * w + x] = p
            }
        }
        held = nil // the buffer now holds scaled rows
        lv_draw_buf_init(served, UInt32(w), UInt32(rows), LV_COLOR_FORMAT_RGB565, UInt32(w * 2), buffer,
                         UInt32(rows * w * 2))
        decoded.pointee.x1 = 0
        decoded.pointee.x2 = Int32(w - 1)
        decoded.pointee.y1 = Int32(y)
        decoded.pointee.y2 = Int32(y + rows - 1)
        dsc.pointee.decoded = UnsafePointer(served)
        return LV_RESULT_OK
    }

    /// The average of two RGB565 pixels
    static func mix(_ a: UInt16, _ b: UInt16) -> UInt16 {
        let r = (Int(a >> 11) + Int(b >> 11)) / 2
        let g = (Int(a >> 5 & 63) + Int(b >> 5 & 63)) / 2
        let bl = (Int(a & 31) + Int(b & 31)) / 2
        return UInt16(r << 11 | g << 5 | bl)
    }
}
