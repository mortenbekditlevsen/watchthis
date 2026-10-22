// The face on screen's static layer, memory-mapped from the raw `facecache` partition (partitions.csv): LVGL draws
// it as an ordinary image straight from flash (through the cache), with no file system in between (reading it
// through LittleFS cost ~0.27 ms per read, every frame). The Baker draws the layer straight into the slot:
// erase (64 KB blocks, one per step: each stalls the CPU), then strips of rows, then the header.
// Layout: "WFS1" + the face's bake key, then the pixels at 64. The header is written last, so a write that was cut
// off (power, reset, another face chosen) is never taken for a valid layer.

private let headerSize = 64
private let eraseBlock = 64 * 1024
private let magic: [UInt8] = Array("WFS1".utf8)

enum StaticSlot {
    nonisolated(unsafe) private static var partition: UnsafePointer<esp_partition_t>?
    nonisolated(unsafe) private static var base: UnsafeRawPointer?
    nonisolated(unsafe) private static var mapHandle: esp_partition_mmap_handle_t = 0
    nonisolated(unsafe) private static var dsc: UnsafeMutablePointer<lv_image_dsc_t>?
    /// A write in progress: its key, and how many erase blocks are done
    nonisolated(unsafe) private static var writing: (key: String, erased: Int)?

    static let rowBytes = WatchScreen.width * 2
    static let pixelBytes = WatchScreen.height * rowBytes
    private static let blocks = (headerSize + pixelBytes + eraseBlock - 1) / eraseBlock

    /// Find and map the partition (once; LVGL task)
    static func setUp() -> Bool {
        if base != nil { return true }
        guard let p = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, esp_partition_subtype_t(rawValue: 0x40),
                                               "facecache") else {
            print("watch_faces: no facecache partition (flash the partition table)")
            return false
        }
        guard Int(p.pointee.size) >= blocks * eraseBlock else { return false }
        var ptr: UnsafeRawPointer?
        guard esp_partition_mmap(p, 0, Int(p.pointee.size), ESP_PARTITION_MMAP_DATA, &ptr, &mapHandle) == ESP_OK,
              let ptr else {
            print("watch_faces: mapping facecache failed")
            return false
        }
        partition = p
        base = ptr
        return true
    }

    /// The slot holds `key`'s layer, complete
    static func holds(_ key: String) -> Bool {
        guard setUp(), let base, writing == nil else { return false }
        let header = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: headerSize)
        guard header.prefix(4).elementsEqual(magic) else { return false }
        let stored = header.dropFirst(4).prefix { $0 != 0 && $0 != 0xFF }
        return stored.elementsEqual(key.utf8)
    }

    /// An image of the slot's pixels (valid while it holds a layer)
    static func image() -> UnsafePointer<lv_image_dsc_t>? {
        guard let base else { return nil }
        if dsc == nil {
            dsc = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
            dsc!.initialize(to: lv_image_dsc_t())
        }
        wf_image_dsc_init(dsc, LV_COLOR_FORMAT_RGB565, UInt32(WatchScreen.width), UInt32(WatchScreen.height),
                          UInt32(rowBytes), base + headerSize, UInt32(pixelBytes))
        return UnsafePointer(dsc)
    }

    /// Start writing `key`'s layer (whatever the slot held is invalid from the first erase on)
    static func beginWrite(_ key: String) -> Bool {
        guard setUp() else { return false }
        writing = (key, 0)
        return true
    }

    static var isErasing: Bool { writing.map { $0.erased < blocks } ?? false }

    /// Erase the next block (the first one holds the header: the old layer is gone right away)
    static func eraseStep() -> Bool {
        guard var w = writing, let partition, w.erased < blocks else { return false }
        guard esp_partition_erase_range(partition, w.erased * eraseBlock, eraseBlock) == ESP_OK else {
            print("watch_faces: erasing facecache failed")
            writing = nil
            return false
        }
        w.erased += 1
        writing = w
        return true
    }

    /// Rows `y ..< y + rows` of the layer, `rowBytes` each (after erasing)
    static func writeRows(_ y: Int, _ data: UnsafeRawPointer, rows: Int) -> Bool {
        guard let partition, writing != nil, !isErasing else { return false }
        return esp_partition_write(partition, headerSize + y * rowBytes, data, rows * rowBytes) == ESP_OK
    }

    /// All rows written: the header makes the layer valid
    static func finishWrite() -> Bool {
        guard let w = writing, let partition else { return false }
        writing = nil
        var header = [UInt8](repeating: 0, count: 4 + 32)
        for (i, b) in magic.enumerated() { header[i] = b }
        for (i, b) in w.key.utf8.prefix(31).enumerated() { header[4 + i] = b }
        return esp_partition_write(partition, 0, header, header.count) == ESP_OK
    }

    static func cancelWrite() {
        writing = nil
    }

    /// Forget the layer (a font or photo it was drawn with changed): zeroes the magic, no erase needed
    static func invalidate() {
        guard setUp(), let partition else { return }
        writing = nil
        let zeros: [UInt8] = [0, 0, 0, 0]
        _ = esp_partition_write(partition, 0, zeros, 4)
    }
}
