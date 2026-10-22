// Background images: the phone uploads a PNG or baseline JPEG (small to send and store); before a face shows it the
// first time, a low-priority task converts it once into an LVGL image file of raw RGB565 (/store/cache/<id>.bin).
// LVGL then reads just the rows it redraws from that file (through the "S:" stdio driver), so redrawing the area
// under a moving hand is cheap; decoding a compressed image would restart from the top every time.
//
// One conversion at a time. The state is shared between the LVGL task and the worker task through `workerState`
// (atomic); the id/matte fields are only written while the worker is idle.

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

    static func removeCache(_ assetID: String) {
        _ = cachePath(assetID).withCString { unlink($0) }
    }

    /// Point `image` at the converted file if it exists
    static func showIfReady(_ assetID: String, on image: LVObj) -> Bool {
        if wf_atomic_load(&workerState) != stateIdle && workerAsset.utf8.elementsEqual(assetID.utf8) {
            return false // still converting (or failed, see request)
        }
        let path = cachePath(assetID)
        guard fileExists(path) else { return false }
        ("S:" + path).withCString { lv_image_set_src(image, $0) }
        return true
    }

    /// Start converting `assetID` unless that's already done or underway
    static func request(_ assetID: String, matte: FaceColor) {
        let state = wf_atomic_load(&workerState)
        if state == stateDone || state == stateFailed {
            let failed = state == stateFailed
            wf_atomic_store(&workerState, stateIdle)
            if failed && workerAsset.utf8.elementsEqual(assetID.utf8) { return } // don't retry a bad file forever
        } else if state != stateIdle {
            return
        }
        guard fileExists(storePath(FILE_STORE_FACE_ASSET, assetID) ?? ""), !fileExists(cachePath(assetID)) else {
            return
        }
        workerAsset = assetID
        workerMatte = matte
        wf_atomic_store(&workerState, stateBusy)
        // Priority 2: below LVGL (and everything interactive); 8 KB stack (TJPGD/tinfl work memory is on the heap)
        if !wf_task_create({ _ in imageWorkerMain() }, "face_image", 8192, 2) {
            wf_atomic_store(&workerState, stateFailed)
        }
    }

    // MARK: - Conversion (worker task)

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
    let ok = ImageWorker.convert(workerAsset, matte: workerMatte)
    wf_atomic_store(&workerState, ok ? stateDone : stateFailed)
    vTaskDelete(nil)
}

private let stateIdle: Int32 = 0
private let stateBusy: Int32 = 1
private let stateDone: Int32 = 2
private let stateFailed: Int32 = 3
nonisolated(unsafe) private var workerState: Int32 = 0
nonisolated(unsafe) private var workerAsset = ""
nonisolated(unsafe) private var workerMatte = FaceColor.black
