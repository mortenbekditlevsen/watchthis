// Draws faces once, so showing them later is cheap: the static layer of the face on screen straight into the
// memory-mapped slot (StaticSlot), and quarter-size thumbnails for the switcher (files; the whole face at 10:09:36).
// There's no RAM for a whole screen (no PSRAM), so LVGL draws 16-row strips (lv_snapshot of a viewport over the
// face, which moves up a strip per step) on a screen that is never shown; one strip per step(), so the UI keeps
// running meanwhile.
//
// Gradients (radial, angled) are computed here (GradientRaster, dithered) into a strip image under the other
// static parts, so no gradient file is needed.

private let stripRows = 16
private let thumbnailTime = WallTime(year: 2026, month: 10, day: 20, weekday: 2, hour: 10, minute: 9, second: 36)

final class Baker {
    enum Product {
        case slot, thumbnail
    }

    private struct Work {
        let face: WatchFace
        let product: Product
        let screen: LVObj
        let content: LVObj
        let viewport: LVObj
        let rendered: RenderedFace
        let raster: GradientRaster?
        let file: UnsafeMutablePointer<FILE>?
        let tmpPath: String
        var row = 0
    }

    /// The face whose static layer goes into the slot (only ever the one on screen)
    private var slotFace: WatchFace?
    private var thumbnails: [WatchFace] = []
    private var work: Work?
    private var buffer: UnsafeMutablePointer<lv_draw_buf_t>?
    private var stripPixels: UnsafeMutableRawPointer?
    private var stripDsc: UnsafeMutablePointer<lv_image_dsc_t>?
    private var thumbRow = [UInt8](repeating: 0, count: BakeKeys.thumbnailWidth * 2)

    /// A face's layer is in the slot, or its thumbnail file is done
    var onFinished: ((WatchFace, Product) -> Void)?

    var isIdle: Bool { work == nil && slotFace == nil && thumbnails.isEmpty }

    static func hasThumbnail(_ face: WatchFace) -> Bool {
        fileExists(RenderedFace.thumbnailPath(face))
    }

    /// Draw `face`'s static layer into the slot (replacing whatever is drawing into it)
    func bakeSlot(_ face: WatchFace) {
        if let w = work {
            // The face on screen comes first: a thumbnail in progress starts over later
            if w.product == .thumbnail { thumbnails.insert(w.face, at: 0) }
            abandon(w)
            work = nil
        }
        StaticSlot.cancelWrite()
        slotFace = face
    }

    func enqueueThumbnail(_ face: WatchFace) {
        guard !Baker.hasThumbnail(face) else { return }
        let key = BakeKeys.hash(face)
        if let w = work, w.product == .thumbnail, BakeKeys.hash(w.face).utf8.elementsEqual(key.utf8) { return }
        guard !thumbnails.contains(where: { BakeKeys.hash($0).utf8.elementsEqual(key.utf8) }) else { return }
        thumbnails.append(face)
    }

    func cancelAll() {
        slotFace = nil
        thumbnails.removeAll()
        if let w = work { abandon(w) }
        work = nil
        StaticSlot.cancelWrite()
        freeBuffers()
    }

    /// One step: an erase block, a strip, or starting the next job. Call when nothing more urgent happens.
    func step() {
        if work == nil {
            startNext()
            return
        }
        guard var w = work, let buffer else { return }
        if w.product == .slot && StaticSlot.isErasing {
            if !StaticSlot.eraseStep() { fail(w) }
            return
        }
        // The gradient rows of this strip, under the other static parts
        if let raster = w.raster, let stripPixels, let strip = w.rendered.gradientStrip {
            var row: [UInt8] = []
            for r in 0..<min(stripRows, WatchScreen.height - w.row) {
                raster.row(w.row + r, into: &row)
                row.withUnsafeBytes {
                    (stripPixels + r * StaticSlot.rowBytes).copyMemory(from: $0.baseAddress!, byteCount: row.count)
                }
            }
            lv_obj_set_y(strip, Int32(w.row))
            lv_obj_invalidate(strip)
        }
        lv_obj_set_y(w.content, -Int32(w.row))
        lv_obj_update_layout(w.screen)
        guard lv_snapshot_take_to_draw_buf(w.viewport, LV_COLOR_FORMAT_RGB565, buffer) == LV_RESULT_OK else {
            fail(w)
            return
        }
        let rows = min(stripRows, WatchScreen.height - w.row)
        let rowStride = Int(buffer.pointee.header.stride)
        let data = UnsafeRawPointer(buffer.pointee.data!)
        var ok = true
        switch w.product {
        case .slot:
            if rowStride == StaticSlot.rowBytes {
                ok = StaticSlot.writeRows(w.row, data, rows: rows)
            } else {
                for r in 0..<rows where ok {
                    ok = StaticSlot.writeRows(w.row + r, data + r * rowStride, rows: 1)
                }
            }
        case .thumbnail:
            ok = writeThumbnailRows(w, data, rowStride: rowStride, rows: rows)
        }
        w.row += stripRows
        guard ok else {
            fail(w)
            return
        }
        if w.row < WatchScreen.height {
            work = w
            return
        }
        // Done
        lv_obj_delete(w.screen)
        work = nil
        switch w.product {
        case .slot:
            if StaticSlot.finishWrite() {
                print("watch_faces: \(w.face.id) static layer in the slot")
                onFinished?(w.face, .slot)
            }
        case .thumbnail:
            if let file = w.file { fclose(file) }
            let path = RenderedFace.thumbnailPath(w.face)
            if w.tmpPath.withCString({ t in path.withCString { rename(t, $0) } }) == 0 {
                print("watch_faces: \(w.face.id) thumbnail done")
                onFinished?(w.face, .thumbnail)
            }
        }
        if isIdle { freeBuffers() }
    }

    /// Each thumbnail pixel is the average of 4 x 4 (a strip of 16 rows makes 4 thumbnail rows)
    private func writeThumbnailRows(_ w: Work, _ data: UnsafeRawPointer, rowStride: Int, rows: Int) -> Bool {
        guard let file = w.file else { return false }
        let scale = BakeKeys.thumbnailScale
        let pixels = data.bindMemory(to: UInt16.self, capacity: rowStride / 2 * stripRows)
        var r = 0
        while r + scale <= rows && (w.row + r) / scale < BakeKeys.thumbnailHeight {
            for x in 0..<BakeKeys.thumbnailWidth {
                var red = 0, green = 0, blue = 0
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let v = pixels[(r + dy) * rowStride / 2 + x * scale + dx]
                        red += Int(v >> 11)
                        green += Int(v >> 5 & 63)
                        blue += Int(v & 31)
                    }
                }
                let n = scale * scale
                let v = UInt16(((red + n / 2) / n) << 11 | ((green + n / 2) / n) << 5 | (blue + n / 2) / n)
                thumbRow[2 * x] = UInt8(truncatingIfNeeded: v)
                thumbRow[2 * x + 1] = UInt8(truncatingIfNeeded: v >> 8)
            }
            if fwrite(thumbRow, 1, thumbRow.count, file) != thumbRow.count { return false }
            r += scale
        }
        return true
    }

    private func startNext() {
        let product: Product
        let face: WatchFace
        if let f = slotFace {
            slotFace = nil
            if StaticSlot.holds(BakeKeys.staticKey(f)) { return }
            (product, face) = (.slot, f)
        } else if !thumbnails.isEmpty {
            let f = thumbnails.removeFirst()
            if Baker.hasThumbnail(f) { return }
            (product, face) = (.thumbnail, f)
        } else {
            return
        }
        if let job = BackgroundJob.needed(for: face.background), !fileExists(ImageWorker.cachePath(job.key)) {
            // Its background photo isn't converted yet (ImageWorker): later
            ImageWorker.request(job)
            requeue(face, product)
            return
        }
        guard allocateBuffers() else {
            requeue(face, product) // no memory now: try again later
            return
        }
        // A screen that is never loaded, with a viewport one strip high over the face
        let screen = lv_obj_create(nil)!
        lv_obj_remove_style_all(screen)
        lv_obj_set_size(screen, Int32(WatchScreen.width), Int32(WatchScreen.height))
        let viewport = lvPlainObject(screen)
        lv_obj_set_size(viewport, Int32(WatchScreen.width), Int32(stripRows))
        let content = lvPlainObject(viewport)
        lv_obj_set_size(content, Int32(WatchScreen.width), Int32(WatchScreen.height))
        let raster = GradientRaster(face.background)
        let strip = raster != nil ? UnsafePointer(stripDsc) : nil
        let mode: RenderMode = product == .slot ? .bakeStatic(gradientStrip: strip)
                                                : .bakeThumbnail(gradientStrip: strip, time: thumbnailTime)
        let rendered = RenderedFace(face: face, parent: content, mode: mode)

        var file: UnsafeMutablePointer<FILE>?
        let tmpPath = RenderedFace.thumbnailPath(face) + ".tmp"
        switch product {
        case .slot:
            guard StaticSlot.beginWrite(BakeKeys.staticKey(face)) else {
                lv_obj_delete(screen)
                return
            }
        case .thumbnail:
            _ = ImageWorker.cacheDir.withCString { mkdir($0, 0o775) }
            file = tmpPath.withCString { fopen($0, "wb") }
            guard let file else {
                lv_obj_delete(screen)
                return
            }
            _ = ImageWorker.writeHeader(file, width: BakeKeys.thumbnailWidth, height: BakeKeys.thumbnailHeight)
        }
        work = Work(face: face, product: product, screen: screen, content: content, viewport: viewport,
                    rendered: rendered, raster: raster, file: file, tmpPath: tmpPath)
    }

    private func requeue(_ face: WatchFace, _ product: Product) {
        switch product {
        case .slot: if slotFace == nil { slotFace = face }
        case .thumbnail: thumbnails.append(face)
        }
    }

    private func allocateBuffers() -> Bool {
        if buffer == nil {
            buffer = lv_draw_buf_create(UInt32(WatchScreen.width), UInt32(stripRows), LV_COLOR_FORMAT_RGB565, 0)
        }
        if stripPixels == nil {
            stripPixels = malloc(stripRows * StaticSlot.rowBytes)
        }
        if stripDsc == nil, let stripPixels {
            stripDsc = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
            stripDsc!.initialize(to: lv_image_dsc_t())
            wf_image_dsc_init(stripDsc, LV_COLOR_FORMAT_RGB565, UInt32(WatchScreen.width), UInt32(stripRows),
                              UInt32(StaticSlot.rowBytes), stripPixels, UInt32(stripRows * StaticSlot.rowBytes))
        }
        guard buffer != nil, stripPixels != nil else {
            freeBuffers()
            return false
        }
        return true
    }

    /// ~26 KB, only while baking
    private func freeBuffers() {
        if let buffer { lv_draw_buf_destroy(buffer) }
        buffer = nil
        if let stripPixels { free(stripPixels) }
        stripPixels = nil
        if let stripDsc { stripDsc.deallocate() }
        stripDsc = nil
    }

    private func fail(_ w: Work) {
        print("watch_faces: baking \(w.face.id) failed")
        abandon(w)
        work = nil
    }

    private func abandon(_ w: Work) {
        if let file = w.file {
            fclose(file)
            _ = w.tmpPath.withCString { unlink($0) }
        }
        if w.product == .slot { StaticSlot.cancelWrite() }
        lv_obj_delete(w.screen)
    }
}
