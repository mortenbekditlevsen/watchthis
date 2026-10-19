// BLE lifecycle for the watch: the C API in include/ble_sync.h (start/stop on demand, pairing window, status
// reporting), NimBLE host start/stop, advertising and the GAP event handler. Adapted from qrbuddy's NimBLE.swift and
// Main.swift; the protocol itself lives in GATTServer.swift and Pairing.swift (see docs/watch-ble-protocol.md).

// MARK: - State

private var active = false
private var synced = false
private var statusCallback: ble_sync_status_cb_t? = nil
private(set) var setTimeHandler: ble_sync_set_time_cb_t? = nil
private(set) var setNameHandler: ble_sync_set_name_cb_t? = nil
private(set) var getNameHandler: ble_sync_get_name_cb_t? = nil

/// The connected central (we only ever have one: advertising stops while connected).
private var currentConn: UInt16 = UInt16(BLE_HS_CONN_HANDLE_NONE)
private var sessionUp = false

private var ownAddrType: UInt8 = UInt8(BLE_OWN_ADDR_PUBLIC)
private var deviceName = "Ur"

/// The open pairing window's QR payload (docs/watch-ble-protocol.md, "QR payload"); nil when no window is open.
private var qrPayload: String? = nil

// MARK: - Status

private func currentState() -> ble_sync_state_t {
    if !active {
        return BLE_SYNC_STATE_OFF
    }
    if !synced {
        return BLE_SYNC_STATE_STARTING
    }
    if currentConn != UInt16(BLE_HS_CONN_HANDLE_NONE) {
        return sessionUp ? BLE_SYNC_STATE_SESSION : BLE_SYNC_STATE_CONNECTED
    }
    return (qrPayload != nil) ? BLE_SYNC_STATE_PAIRING : BLE_SYNC_STATE_ADVERTISING
}

private func publish(_ state: ble_sync_state_t) {
    guard let callback = statusCallback else { return }
    if state == BLE_SYNC_STATE_PAIRING, let qrPayload {
        qrPayload.withCString { callback(state, $0) }
    } else {
        callback(state, nil)
    }
}

private func publishCurrentState() {
    publish(currentState())
}

/// Called by Pairing.swift once a connection has completed pairing or resume.
func bleSyncSessionEstablished() {
    sessionUp = true
    qrPayload = nil     // A successful pairing closes the window
    publishCurrentState()
}

// MARK: - Pairing window

private func buildQRPayload(pop: String) -> String {
    "{\"v\":1,\"name\":\"\(deviceName)\",\"svc\":\"\(controlServiceUUIDString)\",\"pop\":\"\(pop)\"}"
}

private func openPairingWindow() {
    var pop = [CChar](repeating: 0, count: Int(PAIRING_POP_LEN) + 1)
    pop.withUnsafeMutableBufferPointer { pairing_open_window($0.baseAddress) }
    qrPayload = buildQRPayload(pop: String(cString: pop))
    updateProvState()
}

// MARK: - Advertising

private func startAdvertising() {
    guard synced, ble_gap_adv_active() == 0 else { return }
    var params = ble_gap_adv_params(
        conn_mode: UInt8(BLE_GAP_CONN_MODE_UND),
        disc_mode: UInt8(BLE_GAP_DISC_MODE_GEN),
        itvl_min: 0,
        itvl_max: 0,
        channel_map: 0,
        filter_policy: 0,
        high_duty_cycle: 0
    )
    let rc = ble_gap_adv_start(ownAddrType, nil, BLE_HS_FOREVER, &params, gapEvent, nil)
    if rc != 0 {
        print("BLE: advertising failed (\(rc))")
    }
}

private func configureAdvertisingData() -> Bool {
    guard let serviceUUID = UUID(uuidString: controlServiceUUIDString) else { return false }
    let flags: GAPFlags = [.lowEnergyGeneralDiscoverableMode, .notSupportedBREDR]
    let serviceUUIDs = GAPCompleteListOf128BitServiceUUIDs(uuids: [serviceUUID])
    let advertisement: LowEnergyAdvertisingData = GAPDataEncoder.encode(flags, serviceUUIDs)
    let name = GAPShortLocalName(name: deviceName)
    let scanResponse: LowEnergyAdvertisingData = GAPDataEncoder.encode(name)

    let rcAdv = advertisement.withUnsafePointer { ble_gap_adv_set_data($0, Int32(advertisement.length)) }
    let rcRsp = scanResponse.withUnsafePointer { ble_gap_adv_rsp_set_data($0, Int32(scanResponse.length)) }
    return (rcAdv == 0) && (rcRsp == 0)
}

// MARK: - NimBLE host callbacks

/// The host and controller are in sync: the address is known, advertising can start.
private func onSync() {
    _ = ble_hs_util_ensure_addr(0)
    _ = ble_hs_id_infer_auto(0, &ownAddrType)

    var addr = [UInt8](repeating: 0, count: 6)
    _ = addr.withUnsafeMutableBufferPointer { ble_hs_id_copy_addr(ownAddrType, $0.baseAddress, nil) }
    // Last two address bytes tell several watches apart; addr is little-endian
    deviceName = "Ur " + addr[1].toHexadecimal() + addr[0].toHexadecimal()

    // The QR payload contains the name, so (re)build it now that it's known
    if qrPayload != nil, pairing_window_is_open() {
        var pop = [UInt8](repeating: 0, count: Int(PAIRING_POP_LEN))
        if pop.withUnsafeMutableBufferPointer({ pairing_window_pop_bytes($0.baseAddress) }) {
            qrPayload = buildQRPayload(pop: String(decoding: pop, as: UTF8.self))
        }
    }

    synced = true
    if !configureAdvertisingData() {
        print("BLE: setting advertising data failed")
    }
    startAdvertising()
    print("BLE: advertising as \(deviceName)")
    publishCurrentState()
}

private func onReset(_ reason: Int32) {
    print("BLE: host reset (\(reason))")
    synced = false
    publishCurrentState()
}

private func hostTask(_ param: UnsafeMutableRawPointer?) {
    nimble_port_run()   // Returns after nimble_port_stop()
    nimble_port_freertos_deinit()
}

private func gapEvent(event: UnsafeMutablePointer<ble_gap_event>?, arg: UnsafeMutableRawPointer?) -> Int32 {
    guard let event else { return 0 }

    switch Int32(event.pointee.type) {
    case BLE_GAP_EVENT_CONNECT:
        if event.pointee.connect.status == 0 {
            currentConn = event.pointee.connect.conn_handle
            sessionUp = false
        } else {
            startAdvertising()  // A failed attempt also stops advertising
        }
        publishCurrentState()

    case BLE_GAP_EVENT_DISCONNECT:
        file_store_upload_abort()   // An unfinished upload would block the next one ("busy")
        pairingSessionOnDisconnect(connHandle: event.pointee.disconnect.conn.conn_handle)
        currentConn = UInt16(BLE_HS_CONN_HANDLE_NONE)
        sessionUp = false
        startAdvertising()      // Advertising stopped when the phone connected
        publishCurrentState()

    case BLE_GAP_EVENT_ADV_COMPLETE:
        startAdvertising()

    default:
        break
    }
    return 0
}

/// Force-closes a connection (see Pairing.swift: a stale client must not keep the only slot occupied).
@discardableResult
func terminateConnection(_ connHandle: UInt16) -> Int32 {
    ble_gap_terminate(connHandle, UInt8(BLE_ERR_REM_USER_CONN_TERM.rawValue))
}

// MARK: - C API (include/ble_sync.h)

@_cdecl("ble_sync_set_time_handler")
public func ble_sync_set_time_handler(_ handler: ble_sync_set_time_cb_t?) {
    setTimeHandler = handler
}

@_cdecl("ble_sync_set_name_handler")
public func ble_sync_set_name_handler(_ handler: ble_sync_set_name_cb_t?) {
    setNameHandler = handler
}

@_cdecl("ble_sync_get_name_handler")
public func ble_sync_get_name_handler(_ handler: ble_sync_get_name_cb_t?) {
    getNameHandler = handler
}

@_cdecl("ble_sync_start")
public func ble_sync_start(_ callback: ble_sync_status_cb_t?) -> Bool {
    guard !active else { return true }
    statusCallback = callback
    publish(BLE_SYNC_STATE_STARTING)

    guard nimble_port_init() == ESP_OK else {
        print("BLE: nimble_port_init failed")
        publish(BLE_SYNC_STATE_ERROR)
        statusCallback = nil
        return false
    }
    ble_hs_cfg.sync_cb = { onSync() }
    ble_hs_cfg.reset_cb = { reason in onReset(reason) }

    guard registerGATTServices() else {
        print("BLE: registering GATT services failed")
        _ = nimble_port_deinit()
        publish(BLE_SYNC_STATE_ERROR)
        statusCallback = nil
        return false
    }

    if !pairing_has_trust() {
        openPairingWindow()
    }
    updateProvState()

    active = true
    synced = false
    nimble_port_freertos_init(hostTask)
    publishCurrentState()
    return true
}

@_cdecl("ble_sync_stop")
public func ble_sync_stop() {
    guard active else { return }

    _ = ble_gap_adv_stop()
    if nimble_port_stop() == 0 {    // Ends the host task (and with it any connection)
        _ = nimble_port_deinit()    // Frees the controller and host memory
    }

    file_store_upload_abort()
    pairing_close_window()
    pairingResetSessions()
    qrPayload = nil
    currentConn = UInt16(BLE_HS_CONN_HANDLE_NONE)
    sessionUp = false
    synced = false
    active = false
    publish(BLE_SYNC_STATE_OFF)
    statusCallback = nil
}

@_cdecl("ble_sync_is_active")
public func ble_sync_is_active() -> Bool {
    active
}

@_cdecl("ble_sync_reset_pairing")
public func ble_sync_reset_pairing() {
    guard active else { return }
    pairing_clear_trust()
    if currentConn != UInt16(BLE_HS_CONN_HANDLE_NONE) {
        terminateConnection(currentConn)    // Its session belonged to the forgotten phone
    }
    openPairingWindow()
    publishCurrentState()
}

@_cdecl("ble_sync_tick")
public func ble_sync_tick() {
    guard active else { return }
    if pairing_window_tick_expiry() {
        qrPayload = nil
        updateProvState()
        publishCurrentState()
    }
}
