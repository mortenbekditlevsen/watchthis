// The watch's GATT service: an opcode-based, encrypted command characteristic (CMD), a plaintext DEVICE_INFO and the
// pairing characteristics from Pairing.swift. Same command design as qrbuddy's GATTServer.swift: extending the
// protocol means adding an opcode, not a characteristic. See docs/watch-ble-protocol.md.

// MARK: - UUIDs

let controlServiceUUIDString = "7A1C0001-5B3E-4F2A-9C61-2D8E4B7A0C15"
private let commandUUIDString = "7A1C0011-5B3E-4F2A-9C61-2D8E4B7A0C15"
private let deviceInfoUUIDString = "7A1C0012-5B3E-4F2A-9C61-2D8E4B7A0C15"
private let dataUUIDString = "7A1C0013-5B3E-4F2A-9C61-2D8E4B7A0C15"

private var commandHandle: UInt16 = 0
private var deviceInfoHandle: UInt16 = 0
private var dataHandle: UInt16 = 0

// MARK: - Device info (plaintext JSON, readable before pairing)

private let firmwareVersion = "1.0.0"
private let apiVersion = 1
private let photoWidth = 410    // The display; photos are shown 1:1 (baseline JPEG)
private let photoHeight = 502
private let capabilities = ["SetTime", "StorageInfo", "List", "FileUpload", "FileDelete", "SetName", "GetName",
                            "FileRead", "Weather"]
private let faceFormatVersion = 1   // WatchFaceKit's FaceFile.version

/// Built on first read (after the face handlers are installed at boot)
private var deviceInfoBytes: [UInt8] = []

private func makeDeviceInfo() -> [UInt8] {
    var caps = capabilities
    var face = ""
    if let handlers = faceHandlers, let features = handlers.features_json {
        caps.append("WatchFaces")
        if handlers.set_birthday != nil { caps.append("Birthday") }
        face = ",\"face\":{\"format\":\(faceFormatVersion),\"w\":\(photoWidth),\"h\":\(photoHeight)," +
            "\"features\":\(String(cString: features))}"
    }
    let capsJSON = caps.map { "\"\($0)\"" }.joined(separator: ",")
    // No personal data here (readable without pairing): the watch's name is only available via GetName
    return Array(("{\"version\":\"\(firmwareVersion)\",\"apiVersion\":\(apiVersion),\"capabilities\":[\(capsJSON)]," +
                  "\"photo\":{\"w\":\(photoWidth),\"h\":\(photoHeight)}\(face)}").utf8)
}

/// ATT error for a frame that doesn't decrypt (no session, bad tag, replayed counter): an application error code,
/// not "insufficient authentication/encryption", which would make iOS start BLE-level pairing (a system dialog)
private let attErrorRejectedFrame: Int32 = 0x80

// MARK: - Commands

/// Append-only: a shipped opcode's meaning never changes or gets reused. Layouts in docs/watch-ble-protocol.md.
private enum Opcode: UInt8 {
    case setTime = 0x01         // App -> device: utc(8, int64 LE) tz(UTF-8, 0..63 bytes; empty = keep)
    case storageInfo = 0x02     // App -> device: (empty)
    case list = 0x03            // App -> device: kind(1) start(2)
    case fileBegin = 0x04       // App -> device: kind(1) size(4) crc32(4) id_len(1) id name(UTF-8, rest)
    case fileCommit = 0x05      // App -> device: (empty)
    case fileAbort = 0x06       // App -> device: (empty)
    case fileDelete = 0x07      // App -> device: kind(1) id(rest)
    case setName = 0x08         // App -> device: name(UTF-8, 1..32 bytes; the home screen title)
    case getName = 0x09         // App -> device: (empty)
    case setFaceOrder = 0x0A    // App -> device: active(1) count(1) {id_len(1) id}*
    case getFaceState = 0x0B    // App -> device: (empty)
    case fileRead = 0x0C        // App -> device: kind(1) offset(4) length(2) id(rest)
    case setBirthday = 0x0D     // App -> device: month(1) day(1); 0 0 = none
    case result = 0x80          // Device -> app: request opcode(1) status(1)
    case storageInfoReply = 0x81    // Device -> app: total(4) used(4) photos(2) music(2)
    case listReply = 0x82           // Device -> app: kind(1) start(2) total(2) count(1) {id_len(1) id size(4) name_len(1) name}*
    case progress = 0x83            // Device -> app: received(4)
    case nameReply = 0x84           // Device -> app: name(UTF-8, rest)
    case faceStateReply = 0x85      // Device -> app: active(1) count(1) {id_len id}* builtin_count(1) {id_len id}*
    case fileData = 0x86            // Device -> app: status(1) offset(4) total(4) data(rest)
}

/// Mirrors file_store_err_t (0..6), plus protocol-level errors.
private enum ResultStatus: UInt8 {
    case ok = 0
    case failed = 1
    case invalid = 2
    case noSpace = 3
    case busy = 4
    case checkFailed = 5
    case notFound = 6

    init(_ err: file_store_err_t) {
        switch err {
        case FILE_STORE_OK: self = .ok
        case FILE_STORE_ERR_INVALID: self = .invalid
        case FILE_STORE_ERR_NO_SPACE: self = .noSpace
        case FILE_STORE_ERR_BUSY: self = .busy
        case FILE_STORE_ERR_CHECK: self = .checkFailed
        case FILE_STORE_ERR_NOT_FOUND: self = .notFound
        default: self = .failed
        }
    }
}

/// Progress notifications during an upload: one every this many bytes (and the phone may pace on them)
// Progress doubles as flow control: the app keeps at most uploadWindow (8 KB, docs/watch-ble-protocol.md) unacknowledged,
// because the OS drops writes-without-response when its queue overflows (macOS/iOS do, silently)
private let progressInterval: UInt32 = 4 * 1024
private var lastProgressNotified: UInt32 = 0
private let maxListReply = 400      // Plaintext bytes per ListReply (fits a 512-byte MTU with the envelope)

private let maxTimeZoneLength = 63
private let maxNameLength = 32
private let maxFileRead = 400       // Data bytes per FileData reply (fits a 512-byte MTU with the envelope)

private func readInt64LE(_ bytes: [UInt8], at offset: Int) -> Int64 {
    var value: UInt64 = 0
    for i in 0 ..< 8 {
        value |= UInt64(bytes[offset + i]) << (8 * UInt64(i))
    }
    return Int64(bitPattern: value)
}

private func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
}

private func appendLE(_ value: UInt32, to bytes: inout [UInt8]) {
    for i in 0 ..< 4 {
        bytes.append(UInt8((value >> (8 * UInt32(i))) & 0xFF))
    }
}

private func appendLE(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(value & 0xFF))
    bytes.append(UInt8(value >> 8))
}

private func fileKind(_ byte: UInt8) -> file_store_kind_t? {
    switch byte {
    case 0: return FILE_STORE_PHOTO
    case 1: return FILE_STORE_MUSIC
    case 2: return FILE_STORE_FACE
    case 3: return FILE_STORE_FACE_ASSET
    case 4: return FILE_STORE_WEATHER
    default: return nil
    }
}

/// Encrypted notification of `plaintext` (opcode first) on CMD to exactly this connection.
private func sendReply(connHandle: UInt16, _ plaintext: [UInt8]) {
    guard let wire = pairingEncryptForWire(connHandle: connHandle, plaintext: plaintext) else { return }
    wire.withUnsafeBytes { buf in
        guard let om = ble_hs_mbuf_from_flat(buf.baseAddress, UInt16(buf.count)) else { return }
        _ = ble_gatts_notify_custom(connHandle, commandHandle, om)
    }
}

private func sendStorageInfo(connHandle: UInt16) {
    var total = 0, used = 0
    _ = file_store_usage(&total, &used)
    var none = file_store_entry_t()
    let photos = max(0, file_store_list(FILE_STORE_PHOTO, &none, 0))
    let music = max(0, file_store_list(FILE_STORE_MUSIC, &none, 0))
    var reply: [UInt8] = [Opcode.storageInfoReply.rawValue]
    appendLE(UInt32(total), to: &reply)
    appendLE(UInt32(used), to: &reply)
    appendLE(UInt16(photos), to: &reply)
    appendLE(UInt16(music), to: &reply)
    sendReply(connHandle: connHandle, reply)
}

private func sendList(connHandle: UInt16, kind: file_store_kind_t, kindByte: UInt8, start: Int) {
    // Count first, then fetch exactly that many (sorted, so pages are consistent). malloc, not allocate(): with BLE
    // running the heap is tight, and a failed allocation must become an error reply, not a write through NULL
    let count0 = Int(max(0, file_store_list(kind, nil, 0)))
    let maxEntries = max(1, count0)
    guard let raw = malloc(maxEntries * MemoryLayout<file_store_entry_t>.stride) else {
        sendResult(connHandle: connHandle, opcode: .list, status: .failed)
        return
    }
    defer { free(raw) }
    let entries = raw.bindMemory(to: file_store_entry_t.self, capacity: maxEntries)
    let total = Int(max(0, file_store_list(kind, entries, Int32(maxEntries))))

    var body: [UInt8] = []
    var count = 0
    var i = start
    while i < min(total, maxEntries) {
        let id = withUnsafeBytes(of: entries[i].id) { Array($0.prefix { $0 != 0 }) }
        let name = withUnsafeBytes(of: entries[i].name) { Array($0.prefix { $0 != 0 }) }
        let entrySize = 1 + id.count + 4 + 1 + name.count
        if 9 + body.count + entrySize > maxListReply || count == 255 {
            break
        }
        body.append(UInt8(id.count))
        body.append(contentsOf: id)
        appendLE(entries[i].size, to: &body)
        body.append(UInt8(name.count))
        body.append(contentsOf: name)
        count += 1
        i += 1
    }
    var reply: [UInt8] = [Opcode.listReply.rawValue, kindByte]
    appendLE(UInt16(start), to: &reply)
    appendLE(UInt16(total), to: &reply)
    reply.append(UInt8(count))
    reply.append(contentsOf: body)
    sendReply(connHandle: connHandle, reply)
}

private func sendFileData(connHandle: UInt16, kind: file_store_kind_t, offset: UInt32, length: Int, id: [UInt8]) {
    var reply: [UInt8] = [Opcode.fileData.rawValue]
    func fail(_ status: ResultStatus) {
        reply.append(status.rawValue)
        appendLE(offset, to: &reply)
        appendLE(UInt32(0), to: &reply)
        sendReply(connHandle: connHandle, reply)
    }
    var path = [CChar](repeating: 0, count: Int(FILE_STORE_PATH_MAX))
    let idC = id.map { CChar(bitPattern: $0) } + [0]
    guard file_store_id_valid(idC), file_store_path(kind, idC, &path, path.count),
          let file = fopen(path, "rb") else {
        fail(.notFound)
        return
    }
    defer { fclose(file) }
    fseek(file, 0, SEEK_END)
    let total = UInt32(max(0, ftell(file)))
    guard offset <= total, fseek(file, Int(offset), SEEK_SET) == 0 else {
        fail(.invalid)
        return
    }
    var data = [UInt8](repeating: 0, count: min(length, maxFileRead, Int(total - offset)))
    let n = data.isEmpty ? 0 : fread(&data, 1, data.count, file)
    reply.append(ResultStatus.ok.rawValue)
    appendLE(offset, to: &reply)
    appendLE(total, to: &reply)
    reply.append(contentsOf: data.prefix(n))
    sendReply(connHandle: connHandle, reply)
}

/// Encrypted notification to exactly this connection (not ble_gatts_chr_updated(), which would broadcast a shared
/// value to every subscriber).
private func sendResult(connHandle: UInt16, opcode: Opcode, status: ResultStatus) {
    sendReply(connHandle: connHandle, [Opcode.result.rawValue, opcode.rawValue, status.rawValue])
}

/// Handles one decrypted command; returns an ATT error code (0 = accepted).
private func handleCommand(_ bytes: [UInt8], connHandle: UInt16) -> Int32 {
    guard let first = bytes.first, let opcode = Opcode(rawValue: first) else {
        return Int32(BLE_ATT_ERR_REQ_NOT_SUPPORTED)
    }
    let payload = Array(bytes.dropFirst())

    switch opcode {
    case .setTime:
        guard payload.count >= 8, payload.count - 8 <= maxTimeZoneLength else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        let utc = readInt64LE(payload, at: 0)
        guard let tz = String(validating: Array(payload[8...]), as: UTF8.self) else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        var ok = false
        if let handler = setTimeHandler {
            ok = tz.withCString { handler(utc, $0) }
        }
        sendResult(connHandle: connHandle, opcode: .setTime, status: ok ? .ok : .failed)
        return 0

    case .storageInfo:
        sendStorageInfo(connHandle: connHandle)
        return 0

    case .list:
        guard payload.count == 3, let kind = fileKind(payload[0]) else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        sendList(connHandle: connHandle, kind: kind, kindByte: payload[0], start: Int(payload[1]) | (Int(payload[2]) << 8))
        return 0

    case .fileBegin:
        guard payload.count >= 10, let kind = fileKind(payload[0]) else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        let size = readUInt32LE(payload, at: 1)
        let crc = readUInt32LE(payload, at: 5)
        let idLength = Int(payload[9])
        guard idLength > 0, payload.count >= 10 + idLength else { return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN) }
        let id = Array(payload[10 ..< 10 + idLength]) + [0]
        let name = Array(payload[(10 + idLength)...]) + [0]
        let err = id.withUnsafeBufferPointer { idBuf in
            name.withUnsafeBufferPointer { nameBuf in
                idBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: id.count) { idPtr in
                    nameBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: name.count) { namePtr in
                        file_store_upload_begin(kind, idPtr, namePtr, size, crc)
                    }
                }
            }
        }
        lastProgressNotified = 0
        sendResult(connHandle: connHandle, opcode: .fileBegin, status: ResultStatus(err))
        return 0

    case .fileCommit:
        sendResult(connHandle: connHandle, opcode: .fileCommit, status: ResultStatus(file_store_upload_commit()))
        return 0

    case .fileAbort:
        file_store_upload_abort()
        sendResult(connHandle: connHandle, opcode: .fileAbort, status: .ok)
        return 0

    case .fileDelete:
        guard payload.count >= 2, let kind = fileKind(payload[0]) else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        let id = Array(payload[1...]) + [0]
        let err = id.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: CChar.self, capacity: id.count) { file_store_remove(kind, $0) }
        }
        sendResult(connHandle: connHandle, opcode: .fileDelete, status: ResultStatus(err))
        return 0

    case .setName:
        guard !payload.isEmpty, payload.count <= maxNameLength,
              let name = String(validating: payload, as: UTF8.self) else {
            sendResult(connHandle: connHandle, opcode: .setName, status: .invalid)
            return 0
        }
        var ok = false
        if let handler = setNameHandler {
            ok = name.withCString { handler($0) }
        }
        sendResult(connHandle: connHandle, opcode: .setName, status: ok ? .ok : .invalid)
        return 0

    case .getName:
        var reply: [UInt8] = [Opcode.nameReply.rawValue]
        if let getter = getNameHandler, let name = getter() {
            reply.append(contentsOf: Array(String(cString: name).utf8))
        }
        sendReply(connHandle: connHandle, reply)
        return 0

    case .setFaceOrder:
        var status = ResultStatus.invalid
        if let handlers = faceHandlers, let setOrder = handlers.set_order {
            status = payload.withUnsafeBufferPointer {
                ResultStatus(rawValue: setOrder($0.baseAddress, $0.count)) ?? .failed
            }
        }
        sendResult(connHandle: connHandle, opcode: .setFaceOrder, status: status)
        return 0

    case .getFaceState:
        guard let handlers = faceHandlers, let getState = handlers.get_state else {
            sendResult(connHandle: connHandle, opcode: .getFaceState, status: .invalid)
            return 0
        }
        var buf = [UInt8](repeating: 0, count: maxListReply)
        let n = buf.withUnsafeMutableBufferPointer { getState($0.baseAddress, $0.count) }
        guard n >= 0 else {
            sendResult(connHandle: connHandle, opcode: .getFaceState, status: .failed)
            return 0
        }
        sendReply(connHandle: connHandle, [Opcode.faceStateReply.rawValue] + buf.prefix(Int(n)))
        return 0

    case .fileRead:
        guard payload.count >= 8, let kind = fileKind(payload[0]) else {
            return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN)
        }
        let offset = readUInt32LE(payload, at: 1)
        let length = Int(payload[5]) | (Int(payload[6]) << 8)
        sendFileData(connHandle: connHandle, kind: kind, offset: offset, length: length, id: Array(payload[7...]))
        return 0

    case .setBirthday:
        guard payload.count == 2 else { return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN) }
        var status = ResultStatus.invalid
        if let handlers = faceHandlers, let setBirthday = handlers.set_birthday {
            status = ResultStatus(rawValue: setBirthday(payload[0], payload[1])) ?? .failed
        }
        sendResult(connHandle: connHandle, opcode: .setBirthday, status: status)
        return 0

    case .result, .storageInfoReply, .listReply, .progress, .nameReply, .faceStateReply, .fileData:
        return Int32(BLE_ATT_ERR_REQ_NOT_SUPPORTED)    // Device -> app only
    }
}

// MARK: - Access callbacks

@_cdecl("ble_sync_command_access_cb")
func command_access_cb(
    connHandle: UInt16,
    attrHandle: UInt16,
    ctxt: UnsafeMutablePointer<ble_gatt_access_ctxt>?,
    arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctxt, ctxt.pointee.op == UInt8(BLE_GATT_ACCESS_OP_WRITE_CHR) else { return 1 }

    // Opcode + the largest payload (FileBegin: 10 + id + name) + the encryption envelope (4-byte counter + 16-byte tag)
    var buffer = [UInt8](repeating: 0, count: 1 + 10 + Int(FILE_STORE_ID_MAX) + Int(FILE_STORE_NAME_MAX) + 20)
    var writtenLen: UInt16 = 0
    let result = buffer.withUnsafeMutableBytes { buf in
        ble_hs_mbuf_to_flat(ctxt.pointee.om, buf.baseAddress, UInt16(buf.count), &writtenLen)
    }
    guard result == 0 else { return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN) }

    guard let plaintext = pairingDecryptFromWire(connHandle: connHandle, wire: Array(buffer[..<Int(writtenLen)])) else {
        // No session, malformed envelope or bad tag: drop it without saying which
        return attErrorRejectedFrame
    }
    return handleCommand(plaintext, connHandle: connHandle)
}

/// DATA: write-without-response, encrypted like CMD; plaintext = offset(4, LE) || bytes of the current upload.
@_cdecl("ble_sync_data_access_cb")
func data_access_cb(
    connHandle: UInt16,
    attrHandle: UInt16,
    ctxt: UnsafeMutablePointer<ble_gatt_access_ctxt>?,
    arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctxt, ctxt.pointee.op == UInt8(BLE_GATT_ACCESS_OP_WRITE_CHR) else { return 1 }

    var buffer = [UInt8](repeating: 0, count: 520)     // >= MTU (512) - 3
    var writtenLen: UInt16 = 0
    let result = buffer.withUnsafeMutableBytes { buf in
        ble_hs_mbuf_to_flat(ctxt.pointee.om, buf.baseAddress, UInt16(buf.count), &writtenLen)
    }
    guard result == 0 else { return Int32(BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN) }
    guard let plaintext = pairingDecryptFromWire(connHandle: connHandle, wire: Array(buffer[..<Int(writtenLen)])),
          plaintext.count > 4 else {
        return attErrorRejectedFrame
    }

    let offset = readUInt32LE(plaintext, at: 0)
    let err = plaintext.withUnsafeBufferPointer { buf in
        file_store_upload_write(offset, buf.baseAddress! + 4, plaintext.count - 4)
    }
    if err != FILE_STORE_OK {
        // Out of order / no upload / I/O error: tell the phone (it must abort and retry)
        sendResult(connHandle: connHandle, opcode: .fileBegin, status: ResultStatus(err))
        return 0
    }

    var received: UInt32 = 0, size: UInt32 = 0
    if file_store_upload_progress(&received, &size),
       received - lastProgressNotified >= progressInterval || received == size {
        lastProgressNotified = received
        var reply: [UInt8] = [Opcode.progress.rawValue]
        appendLE(received, to: &reply)
        sendReply(connHandle: connHandle, reply)
    }
    return 0
}

@_cdecl("ble_sync_device_info_access_cb")
func device_info_access_cb(
    connHandle: UInt16,
    attrHandle: UInt16,
    ctxt: UnsafeMutablePointer<ble_gatt_access_ctxt>?,
    arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctxt, ctxt.pointee.op == UInt8(BLE_GATT_ACCESS_OP_READ_CHR) else { return 1 }
    if deviceInfoBytes.isEmpty {
        deviceInfoBytes = makeDeviceInfo()
    }
    let result = deviceInfoBytes.withUnsafeBytes { buf in
        r_os_mbuf_append(ctxt.pointee.om, buf.baseAddress, UInt16(buf.count))
    }
    return result == 0 ? 0 : Int32(BLE_ATT_ERR_INSUFFICIENT_RES)
}

// MARK: - Registration

/// The service definition, built once: NimBLE keeps pointers to it while registered, and BLE is started and stopped
/// repeatedly (each start re-registers the same definition).
private let services: UnsafeMutablePointer<ble_gatt_svc_def> = {
    // One service with every characteristic (NimBLE doesn't merge services that share a UUID)
    let chrs = [
        ble_gatt_chr_def(
            uuid: makeNimBLEUUID(commandUUIDString),
            access_cb: command_access_cb,
            arg: nil,
            descriptors: nil,
            flags: ble_gatt_chr_flags(BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_NOTIFY),
            min_key_size: 0,
            val_handle: &commandHandle,
            cpfd: nil
        ),
        ble_gatt_chr_def(
            uuid: makeNimBLEUUID(dataUUIDString),
            access_cb: data_access_cb,
            arg: nil,
            descriptors: nil,
            flags: ble_gatt_chr_flags(BLE_GATT_CHR_F_WRITE_NO_RSP),
            min_key_size: 0,
            val_handle: &dataHandle,
            cpfd: nil
        ),
        ble_gatt_chr_def(
            uuid: makeNimBLEUUID(deviceInfoUUIDString),
            access_cb: device_info_access_cb,
            arg: nil,
            descriptors: nil,
            flags: ble_gatt_chr_flags(BLE_GATT_CHR_F_READ),
            min_key_size: 0,
            val_handle: &deviceInfoHandle,
            cpfd: nil
        ),
    ] + pairingCharacteristics()

    let characteristics = UnsafeMutablePointer<ble_gatt_chr_def>.allocate(capacity: chrs.count + 1)
    for (i, chr) in chrs.enumerated() {
        characteristics[i] = chr
    }
    characteristics[chrs.count] = ble_gatt_chr_def()   // Zeroed sentinel

    let svcs = UnsafeMutablePointer<ble_gatt_svc_def>.allocate(capacity: 2)
    svcs[0] = ble_gatt_svc_def(
        type: UInt8(BLE_GATT_SVC_TYPE_PRIMARY),
        uuid: makeNimBLEUUID(controlServiceUUIDString),
        includes: nil,
        characteristics: characteristics
    )
    svcs[1] = ble_gatt_svc_def()   // Zeroed sentinel
    return svcs
}()

/// Registers the service with a freshly initialized NimBLE host (before the host task starts).
func registerGATTServices() -> Bool {
    (ble_gatts_count_cfg(services) == 0) && (ble_gatts_add_svcs(services) == 0)
}
