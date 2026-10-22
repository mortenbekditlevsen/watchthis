// Which faces exist and in which order the user swipes through them.
//
// Faces are the builtins (WatchFace.builtins) plus the uploaded ones (file_store kind FILE_STORE_FACE); an uploaded
// face with a builtin's id replaces it. The order is set by the phone (SetFaceOrder) and kept in a small state file
// with the same layout as that command: active(1) count(1) {id_len(1) id}*. Faces not in it are not shown (so the
// phone can hide builtins). Without a state file: the builtins, then the uploaded faces by id.

enum FaceStore {
    static let statePath = "/store/faces/state.bin"
    static let maxFaceFileSize = 16 * 1024

    static func installedIDs() -> [String] {
        let count = Int(max(0, file_store_list(FILE_STORE_FACE, nil, 0)))
        guard count > 0, let raw = malloc(count * MemoryLayout<file_store_entry_t>.stride) else { return [] }
        defer { free(raw) }
        let entries = raw.bindMemory(to: file_store_entry_t.self, capacity: count)
        let total = min(count, Int(max(0, file_store_list(FILE_STORE_FACE, entries, Int32(count)))))
        var ids: [String] = []
        for i in 0..<total {
            ids.append(withUnsafeBytes(of: entries[i].id) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
        }
        return ids
    }

    static func load(_ id: String) -> WatchFace? {
        if let path = storePath(FILE_STORE_FACE, id), let bytes = readFile(path, maxSize: maxFaceFileSize) {
            do {
                return try WatchFace(decoding: bytes)
            } catch {
                print("watch_faces: face \(id) can't be read")
            }
        }
        return WatchFace.builtins.first { $0.id.utf8.elementsEqual(id.utf8) }
    }

    static func exists(_ id: String, installed: [String]) -> Bool {
        installed.contains { $0.utf8.elementsEqual(id.utf8) } || WatchFace.builtins.contains {
            $0.id.utf8.elementsEqual(id.utf8)
        }
    }

    /// Parses the SetFaceOrder / state file layout
    static func parseOrder(_ bytes: UnsafeBufferPointer<UInt8>) -> (active: Int, ids: [String])? {
        guard bytes.count >= 2 else { return nil }
        let active = Int(bytes[0])
        let count = Int(bytes[1])
        var ids: [String] = []
        var i = 2
        for _ in 0..<count {
            guard i < bytes.count else { return nil }
            let n = Int(bytes[i])
            i += 1
            guard i + n <= bytes.count else { return nil }
            let id = String(decoding: UnsafeBufferPointer(rebasing: bytes[i..<i + n]), as: UTF8.self)
            guard FaceID.isValid(id) else { return nil }
            ids.append(id)
            i += n
        }
        guard i == bytes.count, ids.isEmpty || active < ids.count else { return nil }
        return (active, ids)
    }

    static func encodeOrder(active: Int, ids: [String]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(clamping: active), UInt8(clamping: ids.count)]
        for id in ids.prefix(255) {
            bytes.append(UInt8(id.utf8.count))
            bytes.append(contentsOf: id.utf8)
        }
        return bytes
    }

    static func readState() -> (active: Int, ids: [String])? {
        guard let bytes = readFile(statePath, maxSize: 4096) else { return nil }
        return bytes.withUnsafeBufferPointer { parseOrder($0) }
    }

    /// The faces to swipe through, and which one shows
    static func visible() -> (active: Int, ids: [String]) {
        let installed = installedIDs()
        var active = 0
        var ids: [String]
        if let state = readState() {
            ids = []
            for (i, id) in state.ids.enumerated() where exists(id, installed: installed) {
                if i == state.active { active = ids.count }
                ids.append(id)
            }
        } else {
            ids = WatchFace.builtins.map { $0.id }
            for id in installed where !ids.contains(where: { $0.utf8.elementsEqual(id.utf8) }) {
                ids.append(id)
            }
        }
        if ids.isEmpty {
            ids = [WatchFace.classic.id]
        }
        return (min(active, ids.count - 1), ids)
    }

    static func saveActive(_ active: Int, ids: [String]) {
        _ = writeFile(statePath, encodeOrder(active: active, ids: ids))
    }
}

// MARK: - Changes from the phone (BLE host task)

/// Set when faces or their order changed; the carousel reloads on its next tick
nonisolated(unsafe) var facesChanged: Int32 = 0

private func checkUpload(_ kind: file_store_kind_t, _ path: UnsafePointer<CChar>?) -> Bool {
    if kind == FILE_STORE_WEATHER, let path {
        guard let bytes = readFile(String(cString: path), maxSize: 4096) else { return false }
        do {
            _ = try WeatherReport(decoding: bytes)
            return true
        } catch {
            return false
        }
    }
    guard kind == FILE_STORE_FACE, let path else { return true }
    guard let bytes = readFile(String(cString: path), maxSize: FaceStore.maxFaceFileSize) else { return false }
    do {
        _ = try WatchFace(decoding: bytes)
        return true
    } catch {
        return false
    }
}

private func uploadChanged(_ kind: file_store_kind_t, _ id: UnsafePointer<CChar>?, _ removed: Bool) {
    guard let id else { return }
    if kind == FILE_STORE_FACE_ASSET {
        ImageWorker.removeCache(String(cString: id)) // stale (replaced) or unused (removed)
    }
    if kind == FILE_STORE_FACE || kind == FILE_STORE_FACE_ASSET {
        wf_atomic_store(&facesChanged, 1)
    }
}

@_cdecl("watch_faces_init")
public func watch_faces_init() {
    ImageWorker.removeStaleCaches()
    Birthday.load()
    file_store_set_hooks({ kind, path in checkUpload(kind, path) }, { kind, id, removed in
        uploadChanged(kind, id, removed)
    })
}

@_cdecl("watch_faces_get_state")
public func watch_faces_get_state(_ buf: UnsafeMutablePointer<UInt8>?, _ max: Int) -> Int32 {
    guard let buf else { return -1 }
    let visible = FaceStore.visible()
    var reply = FaceStore.encodeOrder(active: visible.active, ids: visible.ids)
    reply.append(UInt8(WatchFace.builtins.count))
    for face in WatchFace.builtins {
        reply.append(UInt8(face.id.utf8.count))
        reply.append(contentsOf: face.id.utf8)
    }
    guard reply.count <= max else { return -1 }
    reply.withUnsafeBufferPointer { buf.update(from: $0.baseAddress!, count: $0.count) }
    return Int32(reply.count)
}

@_cdecl("watch_faces_set_order")
public func watch_faces_set_order(_ payload: UnsafePointer<UInt8>?, _ len: Int) -> UInt8 {
    guard let payload, FaceStore.parseOrder(UnsafeBufferPointer(start: payload, count: len)) != nil else {
        return 2 // invalid
    }
    let bytes = Array(UnsafeBufferPointer(start: payload, count: len))
    guard writeFile(FaceStore.statePath, bytes) else { return 1 }
    wf_atomic_store(&facesChanged, 1)
    return 0
}

nonisolated(unsafe) private var featuresJSON: UnsafeMutablePointer<CChar>? = nil

@_cdecl("watch_faces_features_json")
public func watch_faces_features_json() -> UnsafePointer<CChar>? {
    if featuresJSON == nil {
        let json = "[" + FaceFeature.all.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        featuresJSON = json.withCString { strdup($0) }
    }
    return UnsafePointer(featuresJSON)
}
