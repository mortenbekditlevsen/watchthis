# Starter prompt for the iPhone sync app

Copy `docs/watch-ble-protocol.md` and `tools/ble_test_client.py` into the new app repo's `docs/` folder, then give
Claude in Xcode the prompt below. Build it in milestones: each one ends with something you can try on the phone.

---

I'm building a SwiftUI iPhone app (iOS 17+) that syncs with my DIY smartwatches (ESP32 based, custom firmware) over
Bluetooth LE. The complete protocol is in `docs/watch-ble-protocol.md`, which is the source of truth.
`docs/ble_test_client.py` is a working Python reference client that does everything the app must do: read it when
the spec leaves a question open.

What the app does:
- Pair with up to two watches by scanning the QR code the watch shows (with manual entry of the 8-character code as
  a fallback), and remember them.
- For each watch: show and change its name, sync the time (with the phone's time zone), see storage usage, list and
  delete photos and music, upload photos from the photo library and MP3 files from Files.
- Before an upload, check the file against the watch's free space (StorageInfo) and warn if it won't fit. The help
  text should recommend MP3s encoded as mono 64 kbps (see "Fitting more music" in the spec); the app doesn't
  transcode.
- The user opens the "Synk" app on the watch before syncing; the watch only does BLE while Synk is open.
- UI language: Danish.

Architecture I'd like:
1. `WatchProtocol` (no Bluetooth, no UI): frame encoding/decoding, the pairing and resume handshakes as pure
   functions, AES-GCM envelope with counters, command/reply types, CRC-32. Use CryptoKit only. Unit tests against
   the test vectors in section 10 of the spec.
2. `WatchConnection`: one per watch, wraps a `CBPeripheral`: connect, subscribe to notifications, handshake, an
   async/await command API (`setTime`, `getName`, `setName`, `storageInfo`, `list`, `upload`, `delete`), and
   upload with the required flow control (max 8 KB unacknowledged by Progress, plus `canSendWriteWithoutResponse`;
   wait for Progress == size before committing). Several connections can be active at the same time.
3. `PairedWatchStore`: the paired watches in the Keychain (client id, LTK, peripheral identifier, last known name).
4. SwiftUI: a list of watches, an "add watch" flow (QR scanner via `DataScannerViewController`), and a detail
   screen per watch.

Photos must be baseline JPEG at exactly 410 × 502 (scale to fill and crop; `jpegData(compressionQuality: 0.75)`).

Milestones, one at a time; stop after each so I can test on a real watch:
1. `WatchProtocol` + unit tests passing against the test vectors.
2. Scan, pair via QR, resume on reconnect; set the time.
3. Show/change the name, storage info.
4. Photo upload with progress; list and delete.
5. MP3 upload.
6. Two watches.
