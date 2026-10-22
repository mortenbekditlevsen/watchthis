// Background images: the phone uploads a PNG or baseline JPEG (small to send and store); before a face shows it the
// first time, a low-priority task converts it once into an LVGL image file of raw RGB565 (/store/cache/<id>.bin).
// LVGL then reads just the rows it redraws from that file (through the "S:" stdio driver), so redrawing the area
// under a moving hand is cheap; decoding a compressed image would restart from the top every time.
//
// Expensive gradients (radial, angled) are pre-drawn the same way (GradientRaster), so redraws only read rows.
//
// One job at a time. The state is shared between the LVGL task and the worker task through `workerState` (atomic);
// `workerJob` is only written while the worker is idle.

/// What to prepare: an uploaded image, or a gradient to draw. `key` names the cache file.
enum BackgroundJob {
    case asset(id: String, matte: FaceColor)
    case gradient(GradientRaster)

    var key: String {
        switch self {
        case .asset(let id, _): id
        case .gradient(let raster): raster.cacheKey
        }
    }
}

extension BackgroundJob {
    /// What a background needs prepared first, if anything
    static func needed(for background: Background) -> BackgroundJob? {
        switch background {
        case .image(let i): return .asset(id: i.assetID, matte: i.fallback)
        default: return nil
        }
    }
}

enum ImageWorker {
    static let cacheDir = "/store/cache"

    /// Bump the suffix when the conversion changes, so existing caches are made again (see removeStaleCaches)
    static let cacheSuffix = ".v2.bin"

    static func cachePath(_ assetID: String) -> String {
        cacheDir + "/" + assetID + cacheSuffix
    }

    /// Deletes cache files from older conversions (v1 swapped red and blue in JPEGs)
    static func removeStaleCaches() {
        guard let dir = cacheDir.withCString({ opendir($0) }) else { return }
        var stale: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            // UTF-8 comparisons: String == would pull Unicode normalization tables into the firmware
            let isDots = name.utf8.allSatisfy { $0 == 0x2E }
            if !isDots && !name.utf8.reversed().starts(with: cacheSuffix.utf8.reversed()) {
                stale.append(name)
            }
        }
        closedir(dir)
        for name in stale {
            _ = (cacheDir + "/" + name).withCString { unlink($0) }
        }
    }

    /// Files drawn on the watch (not converted uploads): thumbnails ("tq_"), and from older firmware pre-drawn
    /// gradients ("grad_"), static layers ("st_") and half-size thumbnails ("th_"), which are just deleted
    static let drawnPrefixes = ["grad_", "st_", "th_", "tq_"]

    static func isDrawn(_ name: String) -> Bool {
        drawnPrefixes.contains { name.utf8.starts(with: $0.utf8) }
    }

    /// Deletes drawn files no face uses any more (each edit of a face makes new ones). At boot, before the worker
    /// and the baker run.
    static func removeUnusedDrawn(keep keys: [String]) {
        guard let dir = cacheDir.withCString({ opendir($0) }) else { return }
        var unused: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard isDrawn(name) else { continue }
            let used = keys.contains { key in
                name.utf8.elementsEqual((key + cacheSuffix).utf8)
            }
            if !used { unused.append(name) }
        }
        closedir(dir)
        for name in unused {
            _ = (cacheDir + "/" + name).withCString { unlink($0) }
        }
    }

    /// Deletes all baked static layers and thumbnails (a face asset changed); LVGL task, with no face showing one
    static func removeBaked() {
        StoreImageDecoder.release()
        guard let dir = cacheDir.withCString({ opendir($0) }) else { return }
        var baked: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name.utf8.starts(with: "tq_".utf8) { baked.append(name) }
        }
        closedir(dir)
        for name in baked {
            _ = (cacheDir + "/" + name).withCString { unlink($0) }
        }
    }

    static func hasRoomToConvert() -> Bool {
        heap_caps_get_largest_free_block(UInt32(MALLOC_CAP_INTERNAL)) >= 48 * 1024
    }

    /// LVGL task only; cleared when faces or assets change (Carousel), so a replaced file gets another try
    nonisolated(unsafe) static var failedAssets: [String] = []

    static func removeCache(_ assetID: String) {
        _ = cachePath(assetID).withCString { unlink($0) }
    }

    /// Point `image` at the prepared file if it exists
    static func showIfReady(_ key: String, on image: LVObj) -> Bool {
        if wf_atomic_load(&workerState) != stateIdle, let job = workerJob, job.key.utf8.elementsEqual(key.utf8) {
            return false // still preparing (or failed, see request)
        }
        let path = cachePath(key)
        guard fileExists(path) else { return false }
        ("S:" + path).withCString { lv_image_set_src(image, $0) }
        return true
    }

    /// Start preparing `job` unless that's already done or underway
    static func request(_ job: BackgroundJob) {
        let state = wf_atomic_load(&workerState)
        if state == stateDone || state == stateFailed {
            if state == stateFailed, let failed = workerJob { failedAssets.append(failed.key) }
            wf_atomic_store(&workerState, stateIdle)
        } else if state != stateIdle {
            return
        }
        let key = job.key
        // Don't retry a file that can't be converted (until something is uploaded: the carousel clears the list)
        guard !failedAssets.contains(where: { $0.utf8.elementsEqual(key.utf8) }), !fileExists(cachePath(key)) else {
            return
        }
        if case .asset(let id, _) = job {
            guard fileExists(storePath(FILE_STORE_FACE_ASSET, id) ?? "") else { return }
            // The conversion needs ~45 KB (PNG: inflate state + 32 KB window). With BLE on (Synk, or charging) there
            // may not be that much: wait, the face asks again on its next tick. (A gradient needs one row.)
            guard hasRoomToConvert() else { return }
        }
        workerJob = job
        wf_atomic_store(&workerState, stateBusy)
        // Priority 2: below LVGL (and everything interactive); 8 KB stack (TJPGD/tinfl work memory is on the heap)
        if !wf_task_create({ _ in imageWorkerMain() }, "face_image", 8192, 2) {
            wf_atomic_store(&workerState, stateFailed)
        }
    }

    // MARK: - Conversion (worker task)

    static func prepare(_ job: BackgroundJob) -> Bool {
        switch job {
        case .asset(let id, let matte): convert(id, matte: matte)
        case .gradient(let raster): draw(raster)
        }
    }

    /// Draws a gradient into its cache file, row by row
    static func draw(_ raster: GradientRaster) -> Bool {
        _ = cacheDir.withCString { mkdir($0, 0o775) }
        let target = cachePath(raster.cacheKey)
        let tmp = target + ".tmp"
        guard let output = tmp.withCString({ fopen($0, "wb") }) else { return false }
        let start = lv_tick_get()
        var ok = writeHeader(output, width: raster.width, height: raster.height)
        var row: [UInt8] = []
        for y in 0..<raster.height where ok {
            raster.row(y, into: &row)
            ok = fwrite(row, 1, row.count, output) == row.count
        }
        fclose(output)
        guard ok, tmp.withCString({ t in target.withCString { rename(t, $0) } }) == 0 else {
            _ = tmp.withCString { unlink($0) }
            return false
        }
        print("watch_faces: gradient \(raster.cacheKey) drawn in \(lv_tick_elaps(start)) ms")
        return true
    }

    static func convert(_ assetID: String, matte: FaceColor) -> Bool {
        guard let source = storePath(FILE_STORE_FACE_ASSET, assetID) else { return false }
        _ = cacheDir.withCString { mkdir($0, 0o775) }
        let target = cachePath(assetID)
        let tmp = target + ".tmp"
        guard let input = source.withCString({ fopen($0, "rb") }) else { return false }
        defer { fclose(input) }
        guard let output = tmp.withCString({ fopen($0, "wb") }) else { return false }
        var head = [UInt8](repeating: 0, count: 2)
        let isJPEG = fread(&head, 1, 2, input) == 2 && head[0] == 0xFF && head[1] == 0xD8
        fseek(input, 0, SEEK_SET)
        let start = lv_tick_get()
        let ok = isJPEG ? convertJPEG(input, output) : convertPNG(input, output, matte: matte)
        fclose(output)
        guard ok, tmp.withCString({ t in target.withCString { rename(t, $0) } }) == 0 else {
            print("watch_faces: background \(assetID) could not be prepared")
            _ = tmp.withCString { unlink($0) }
            return false
        }
        print("watch_faces: background \(assetID) prepared in \(lv_tick_elaps(start)) ms")
        return true
    }

    static func writeHeader(_ output: UnsafeMutablePointer<FILE>, width: Int, height: Int) -> Bool {
        let header = RGB565.lvglImageHeader(width: width, height: height)
        return fwrite(header, 1, header.count, output) == header.count
    }

    static func convertPNG(_ input: UnsafeMutablePointer<FILE>, _ output: UnsafeMutablePointer<FILE>,
                           matte: FaceColor) -> Bool {
        let dictSize = Int(TINFL_LZ_DICT_SIZE)
        guard let inflater = malloc(MemoryLayout<tinfl_decompressor>.size)?
            .bindMemory(to: tinfl_decompressor.self, capacity: 1) else { return false }
        defer { free(inflater) }
        inflater.pointee.m_state = 0 // tinfl_init()
        guard let dict = malloc(dictSize)?.bindMemory(to: UInt8.self, capacity: dictSize) else { return false }
        defer { free(dict) }
        let readSize = 1024
        guard let readBuffer = malloc(readSize)?.bindMemory(to: UInt8.self, capacity: readSize) else { return false }
        defer { free(readBuffer) }

        var parser = PNGChunkParser()
        var rows: PNGRowDecoder?
        var dictPos = 0
        var inflateDone = false
        var writeFailed = false
        let flags = UInt32(TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_HAS_MORE_INPUT)
        do throws(PNGError) {
            while !parser.finished {
                let n = fread(readBuffer, 1, readSize, input)
                guard n > 0 else { break }
                try parser.feed(UnsafeBufferPointer(start: readBuffer, count: n)) { idat, header throws(PNGError) in
                    if rows == nil {
                        rows = PNGRowDecoder(header: header, matte: matte)
                        if !writeHeader(output, width: header.info.width, height: header.info.height) {
                            writeFailed = true
                        }
                    }
                    var next = idat.baseAddress
                    var remaining = idat.count
                    while !inflateDone && !writeFailed {
                        var inSize = remaining
                        var outSize = dictSize - dictPos
                        let status = tinfl_decompress(inflater, next, &inSize, dict, dict + dictPos, &outSize, flags)
                        next = next.map { $0 + inSize }
                        remaining -= inSize
                        if outSize > 0 {
                            try rows!.feed(UnsafeBufferPointer(start: dict + dictPos, count: outSize)) { row in
                                if fwrite(row.baseAddress, 1, row.count, output) != row.count { writeFailed = true }
                            }
                            dictPos = (dictPos + outSize) % dictSize
                        }
                        if status.rawValue < 0 { throw .corrupt }
                        if status == TINFL_STATUS_DONE { inflateDone = true }
                        if status == TINFL_STATUS_NEEDS_MORE_INPUT && remaining == 0 { break }
                    }
                }
                if writeFailed { return false }
            }
        } catch {
            return false
        }
        return rows?.isComplete == true && !writeFailed
    }

    // MARK: JPEG (LVGL's TJPGD)

    final class JPEGContext {
        let input: UnsafeMutablePointer<FILE>
        let output: UnsafeMutablePointer<FILE>
        var width = 0
        var bandHeight = 0
        var bandTop = 0
        var band: UnsafeMutablePointer<UInt16>?
        var failed = false

        init(input: UnsafeMutablePointer<FILE>, output: UnsafeMutablePointer<FILE>) {
            self.input = input
            self.output = output
        }
    }

    static func convertJPEG(_ input: UnsafeMutablePointer<FILE>, _ output: UnsafeMutablePointer<FILE>) -> Bool {
        let poolSize = 4096
        guard let pool = malloc(poolSize) else { return false }
        defer { free(pool) }
        guard let jd = malloc(MemoryLayout<JDEC>.size)?.bindMemory(to: JDEC.self, capacity: 1) else { return false }
        defer { free(jd) }
        let context = JPEGContext(input: input, output: output)
        let device = Unmanaged.passUnretained(context).toOpaque()

        let read: @convention(c) (UnsafeMutablePointer<JDEC>?, UnsafeMutablePointer<UInt8>?, Int) -> Int = {
            jd, buffer, count in
            let c = Unmanaged<JPEGContext>.fromOpaque(jd!.pointee.device!).takeUnretainedValue()
            guard let buffer else {
                return fseek(c.input, count, SEEK_CUR) == 0 ? count : 0
            }
            return fread(buffer, 1, count, c.input)
        }
        guard lv_tjpgd_jd_prepare(jd, read, pool, poolSize, device) == JDR_OK else { return false }
        context.width = Int(jd.pointee.width)
        let height = Int(jd.pointee.height)
        context.bandHeight = Int(jd.pointee.msy) * 8
        guard let band = malloc(context.width * context.bandHeight * 2)?
            .bindMemory(to: UInt16.self, capacity: context.width * context.bandHeight) else { return false }
        defer { free(band) }
        context.band = band
        guard writeHeader(output, width: context.width, height: height) else { return false }

        // Blocks arrive left to right, top to bottom, as RGB888 -- in memory order B, G, R (LVGL's TJPGD, like
        // cats_jpeg_decoder.cpp). A row of blocks (a band) is written out at once
        let write: @convention(c) (UnsafeMutablePointer<JDEC>?, UnsafeMutableRawPointer?,
                                   UnsafeMutablePointer<JRECT>?) -> Int32 = { jd, bitmap, rect in
            let c = Unmanaged<JPEGContext>.fromOpaque(jd!.pointee.device!).takeUnretainedValue()
            let r = rect!.pointee
            let rgb = bitmap!.bindMemory(to: UInt8.self, capacity: 1)
            var i = 0
            for y in Int(r.top)...Int(r.bottom) {
                let row = (y - c.bandTop) * c.width
                for x in Int(r.left)...Int(r.right) {
                    c.band![row + x] = RGB565.pack(rgb[i + 2], rgb[i + 1], rgb[i])
                    i += 3
                }
            }
            if Int(r.right) == c.width - 1 {
                let rows = Int(r.bottom) - c.bandTop + 1
                let bytes = rows * c.width * 2
                if fwrite(c.band, 1, bytes, c.output) != bytes {
                    c.failed = true
                    return 0 // stop decoding
                }
                c.bandTop += rows
            }
            return 1
        }
        let result = lv_tjpgd_jd_decomp(jd, write, 0)
        return result == JDR_OK && !context.failed && context.bandTop == height
    }
}

private func imageWorkerMain() {
    guard let job = workerJob else {
        wf_atomic_store(&workerState, stateFailed)
        vTaskDelete(nil)
        return
    }
    let ok = ImageWorker.prepare(job)
    // Out of memory (something else took it meanwhile) isn't the file's fault: try again later
    let failure = ImageWorker.hasRoomToConvert() ? stateFailed : stateIdle
    wf_atomic_store(&workerState, ok ? stateDone : failure)
    vTaskDelete(nil)
}

private let stateIdle: Int32 = 0
private let stateBusy: Int32 = 1
private let stateDone: Int32 = 2
private let stateFailed: Int32 = 3
nonisolated(unsafe) private var workerState: Int32 = 0
nonisolated(unsafe) private var workerJob: BackgroundJob?
