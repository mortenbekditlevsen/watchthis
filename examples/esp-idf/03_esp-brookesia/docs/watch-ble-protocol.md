# Watch BLE protocol (v1)

How a phone app talks to the watch over Bluetooth LE: pairing, time sync, the watch's name, and uploading photos and
MP3s. Everything here is verified against the firmware (`components/ble_sync`, `components/pairing`,
`components/file_store`) with the reference client `tools/ble_test_client.py`, which does exactly what an app has to
do and is the best place to look when something here is unclear.

## 1. Overview

- BLE only runs while the **Synk** app is open on the watch. The user opens Synk, then syncs from the phone.
- One watch trusts **one phone** (a new pairing replaces the old one). One phone can be paired with any number of
  watches; each watch has its own key.
- Pairing is done by the app, not by BLE bonding: the watch shows a QR code with a one-time code (POP), both sides
  derive keys with X25519 + HKDF-SHA256, and every command afterwards is AES-256-GCM encrypted. No BLE-level
  pairing dialog appears on the phone.
- Commands go to one characteristic (CMD) as `opcode || payload`; replies come back as encrypted notifications on
  the same characteristic. File data goes to a second characteristic (DATA) as writes without response.
- All integers are little-endian. Strings are UTF-8 without a terminating NUL.

## 2. Discovery

The watch advertises (connectable, general discoverable) while Synk is open:

| Field | Value |
|---|---|
| Complete list of 128-bit service UUIDs | `7A1C0001-5B3E-4F2A-9C61-2D8E4B7A0C15` |
| Short local name (scan response) | `Ur XXXX` (last 4 hex digits of the watch's BLE address) |

Scan for the service UUID, not the name: CoreBluetooth often doesn't report the scan-response name. Only one
connection is accepted at a time; advertising stops while a phone is connected. Remember the peripheral's
identifier after pairing to reconnect to the right watch later (CoreBluetooth identifiers are stable per phone).

## 3. GATT service

Service `7A1C0001-5B3E-4F2A-9C61-2D8E4B7A0C15`:

| Characteristic | UUID | Properties | Purpose |
|---|---|---|---|
| CMD | `7A1C0011-…` | Write, Notify | Encrypted commands (§7); encrypted replies as notifications |
| DEVICE_INFO | `7A1C0012-…` | Read | Plaintext JSON, readable before pairing (§4) |
| DATA | `7A1C0013-…` | Write without response | Encrypted upload chunks (§8) |
| PROV_STATE | `7A1C0020-…` | Read, Notify | 1 byte: 0 = not paired, 1 = paired, 2 = pairing window open |
| PROV_HANDSHAKE | `7A1C0021-…` | Write, Notify | Pairing/resume handshake (§5) |

(All UUIDs share the suffix `-5B3E-4F2A-9C61-2D8E4B7A0C15`.)

Subscribe to notifications on PROV_HANDSHAKE and CMD right after connecting. The watch's preferred ATT MTU is 512;
iOS negotiates it automatically (`maximumWriteValueLength(for: .withoutResponse)` is typically 509 after that).

## 4. DEVICE_INFO

Plaintext JSON, readable without pairing. It deliberately contains nothing personal (the watch's name is only
available encrypted, via GetName):

```json
{"version":"1.0.0","apiVersion":1,
 "capabilities":["SetTime","StorageInfo","List","FileUpload","FileDelete","SetName","GetName"],
 "photo":{"w":410,"h":502}}
```

Check `apiVersion` (this document describes 1) and use `capabilities` to enable features; future firmware only
adds capabilities and opcodes.

## 5. Pairing and resume

### 5.1 QR code

While no phone is paired, or after "Par ny telefon" in Synk, the watch opens a **pairing window** (5 minutes) and
shows a QR code containing:

```json
{"v":1,"name":"Ur C732","svc":"7A1C0001-5B3E-4F2A-9C61-2D8E4B7A0C15","pop":"Q4STKYSY"}
```

`pop` is the proof-of-possession code: 8 characters from `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, also printed under the
QR code for manual entry (uppercase it; ignore spaces). After 5 wrong confirmations the window closes; the user
opens a new one in Synk.

### 5.2 Primitives

| | |
|---|---|
| Key agreement | X25519, fresh ephemeral key pair per handshake on both sides |
| KDF | `HKDF-SHA256(ikm, salt, info)` → 32 bytes; an empty salt means HKDF's default (32 zero bytes) |
| Confirm tag | `HMAC-SHA256(key: session_key, message: info)`, first 16 bytes |
| Info strings (ASCII) | `watch-pair-v1`, `watch-resume-v1`, `watch-ltk-v1`, `watch-confirm-device-v1`, `watch-confirm-client-v1` |
| Client id | 16 random bytes chosen by the app at pairing; store it with the LTK |

### 5.3 Pairing (first time, needs the POP)

All messages are writes to / notifications from PROV_HANDSHAKE, `opcode(1) || payload`:

| # | Direction | Opcode | Payload |
|---|---|---|---|
| 1 | app → watch | `0x01` ClientHello | client_id(16) client_pub(32) |
| 2 | watch → app | `0x02` DeviceHello | device_pub(32) device_tag(16) |
| 3 | app → watch | `0x03` ClientConfirm | client_tag(16) |
| 4 | watch → app | `0x04` PairingComplete | (empty) |

```
shared      = X25519(client_priv, device_pub)
session_key = HKDF(shared, salt = POP as ASCII bytes, info = "watch-pair-v1")
device_tag  = Tag(session_key, "watch-confirm-device-v1")   -- app verifies; mismatch = wrong code
client_tag  = Tag(session_key, "watch-confirm-client-v1")
LTK         = HKDF(session_key, salt = empty, info = "watch-ltk-v1")
```

After PairingComplete, store `client_id` and `LTK` (Keychain) together with the watch's peripheral identifier.
The connection is now an established session using `session_key` (§6).

### 5.4 Resume (every later connection)

| # | Direction | Opcode | Payload |
|---|---|---|---|
| 1 | app → watch | `0x05` ResumeHello | client_id(16) client_pub(32) |
| 2 | watch → app | `0x06` ResumeDeviceHello | device_pub(32) device_tag(16) |
| 3 | app → watch | `0x07` ResumeClientConfirm | client_tag(16) |
| 4 | watch → app | `0x08` ResumeComplete | (empty) |

Same as pairing, but `session_key = HKDF(shared, salt = LTK, info = "watch-resume-v1")`.

### 5.5 Errors

Any step can be answered with `0x7F` Nack, `reason(1)`:

| Reason | Meaning | What the app should do |
|---|---|---|
| 1 | Not paired (unknown client id on resume) | The watch was paired with another phone or reset: forget it, pair again with a new QR code. The watch disconnects after this Nack. |
| 2 | Bad confirm | Wrong POP (or corrupted handshake): ask for the code again |
| 3 | Pairing window closed | Ask the user to open "Par ny telefon" in Synk |
| 4 | Rate limited | Reserved, not sent by firmware v1 (after 5 wrong codes the window closes instead: reason 3) |

## 6. Encrypted frames

Every write to CMD and DATA after the handshake, and every CMD notification from the watch:

```
wire  = counter(4, LE) || AES-256-GCM-Encrypt(key = session_key, nonce, plaintext) || tag(16)
nonce = direction(1) || counter(4, LE) || 7 zero bytes          (12 bytes)
        direction 0x00 = app → watch, 0x01 = watch → app
```

No associated data. Each direction has its own counter, starting at 0 in every session:

- **App → watch:** one counter shared by CMD and DATA writes. It must **strictly increase** within the session
  (gaps are allowed). The watch rejects frames with a counter it has already passed (replay protection), with a
  bad tag, or without an established session: a CMD write then fails with ATT error `0x80` (application error);
  a DATA write (no response) is dropped silently and only shows up as a missing upload Progress.
- **Watch → app:** the counter in the frame; just use it for the nonce.

The plaintext of a command is `opcode(1) || payload`.

## 7. Commands

Write to CMD **with response**. Replies arrive as encrypted CMD notifications. Most commands are answered with
`Result`; a few with their own reply. An ATT error on the write itself means a malformed frame or command.

| Opcode | Command | Payload (app → watch) | Reply |
|---|---|---|---|
| `0x01` | SetTime | utc(8, int64 seconds) tz(0–63 bytes, POSIX TZ string; empty = keep) | Result |
| `0x02` | StorageInfo | (empty) | StorageInfoReply |
| `0x03` | List | kind(1) start(2) | ListReply |
| `0x04` | FileBegin | kind(1) size(4) crc32(4) id_len(1) id name(rest) | Result |
| `0x05` | FileCommit | (empty) | Result |
| `0x06` | FileAbort | (empty) | Result |
| `0x07` | FileDelete | kind(1) id(rest) | Result |
| `0x08` | SetName | name(1–32 bytes) | Result |
| `0x09` | GetName | (empty) | NameReply |

Replies (watch → app):

| Opcode | Reply | Payload |
|---|---|---|
| `0x80` | Result | request_opcode(1) status(1) |
| `0x81` | StorageInfoReply | total(4) used(4) photos(2) music(2) — bytes and file counts |
| `0x82` | ListReply | kind(1) start(2) total(2) count(1), then `count` × { id_len(1) id size(4) name_len(1) name } |
| `0x83` | Progress | received(4) — upload bytes stored so far (§8) |
| `0x84` | NameReply | name(rest) |

Result status codes:

| Status | Meaning |
|---|---|
| 0 | OK |
| 1 | Failed (I/O error) |
| 2 | Invalid (bad kind/id/size/name, or no upload in progress) |
| 3 | No space |
| 4 | Busy (another upload is in progress) |
| 5 | Check failed (size, CRC or file format doesn't match at commit) |
| 6 | Not found |

Notes:

- **kind:** 0 = photo, 1 = music.
- **SetTime:** the watch stores the time in its RTC and the TZ string in flash. iOS has no POSIX TZ API; derive
  the string from `TimeZone` (standard/daylight offsets and transition rules) or map common IANA zones, e.g.
  `Europe/Copenhagen` → `CET-1CEST,M3.5.0,M10.5.0/3`. Note the POSIX sign convention (`CET-1` = UTC+1).
- **SetName:** the home screen title; shown immediately and kept across restarts. 1–32 bytes, no control
  characters. Danish letters (ÆØÅæøå) are supported.
- **List:** pages are sorted by id. Request `start = 0`, then `start += count` until `start >= total` (or
  `count == 0`). A page holds as many entries as fit in ~400 bytes.
- **FileDelete** of a preloaded cat photo works like any other photo (ids `cat_01` … `cat_50`).

## 8. Uploading a file

1. `FileBegin(kind, size, crc32, id, name)` → Result OK. `crc32` is the standard CRC-32 (IEEE, as zlib's
   `crc32`; Swift: zlib's `crc32` via `import zlib` or a small table implementation). Uploading an existing id
   replaces that file at commit.
2. Send the file as DATA writes (without response). Plaintext per write: `offset(4) || bytes`, in order, offsets
   contiguous. Chunk size = `maximumWriteValueLength(for: .withoutResponse) − 4 (counter) − 16 (tag) − 4
   (offset)`, e.g. 485 bytes.
3. **Flow control (required):** the watch notifies `Progress(received)` every 4 KB and for the last byte. Never
   have more than **8 KB** sent but not yet acknowledged by Progress. Also respect CoreBluetooth's own flow control
   (`canSendWriteWithoutResponse` / `peripheralIsReady(toSendWriteWithoutResponse:)`). Without this, the OS
   silently drops writes when its queue overflows and the upload stalls.
4. Wait until `Progress.received == size`, then send `FileCommit` → Result OK. (Committing earlier fails with
   status 5: a write with response can overtake queued writes without response.)
5. On any error: `FileAbort`. A Result for `0x04` arriving during the transfer means a DATA write was rejected
   (out of order, I/O error): abort and start over. If the connection drops, the watch discards the partial file.

Measured throughput: ~70 KB/s (a 93 KB photo in 1.3 s).

### File rules

| | Photo (kind 0) | Music (kind 1) |
|---|---|---|
| Format | **Baseline** JPEG (progressive JPEGs can't be decoded); checked: starts with `FF D8` | MP3; checked: starts with an ID3 tag or an MPEG frame sync |
| Size | 410 × 502 pixels (the screen); crop to fill. Quality ~75 gives 50–100 KB | Any (storage permitting); **mono, 64 kbps recommended** (see below) |
| id | 1–31 characters from `A–Z a–z 0–9 _ -` | same |
| name | Display name, UTF-8, up to 63 bytes (optional) | same |

iOS's `UIImage.jpegData(compressionQuality:)` writes baseline JPEGs. Total storage is ~11 MB, shared by photos and
music (StorageInfo has the exact numbers).

### Fitting more music

The watch has one small mono speaker and mixes stereo down to mono, so stereo and high bitrates only cost space:

| Encoding | Size | Music in ~7.5 MB (storage minus the preloaded cats) |
|---|---|---|
| 128 kbps stereo (typical download) | ~1 MB/min | ~8 min |
| **64 kbps mono (recommended)** | ~0.5 MB/min | ~15 min |
| 48 kbps mono (speech, podcasts) | ~0.35 MB/min | ~20 min |

Any MP3 sample rate works (MPEG-1 at 44.1/48 kHz, MPEG-2 at 22.05/24 kHz). To convert on a computer:

```sh
ffmpeg -i in.mp3 -ac 1 -b:a 64k out.mp3
lame -m m -b 64 in.mp3 out.mp3        # alternative
```

More room: delete preloaded cat photos you don't need (ids `cat_01` … `cat_50`, ~70 KB each, 3.6 MB in all).

## 9. Typical session

```
connect → subscribe PROV_HANDSHAKE + CMD notifications → read DEVICE_INFO (optional)
→ Resume handshake (or Pairing, first time)
→ SetTime(now, tz) → GetName → StorageInfo → List(photo) …
→ upload: FileBegin → DATA… (flow control) → Progress == size → FileCommit
→ disconnect
```

## 10. Test vectors

From `tools/protocol_test_vectors.py` (fixed keys; run it to regenerate). All values hex.

```
Inputs
client private key           0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20
client public key            07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c
device private key           4142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60
device public key            64b101b1d0be5a8704bd078f9895001fc03e8e9f9522f188dd128d9846d48466
client id                    a0a1a2a3a4a5a6a7a8a9aaabacadaeaf
POP                          7K2M9XAB

Pairing
X25519 shared secret         26c2c17fdb82161cb21ad16e721315355b64d1763119b10bfc962530dc7cc163
session key                  cc101e1f3d732d6a6d19ad16e8ed98c86f0c841caf03307fe041d4c8a1fc64a0
device confirm tag           a7f2aa7ed09df86dac62478403ff9b2c
client confirm tag           3c1a5843211271e6b34f45b143ff5174
LTK                          dfceb0a4d8eaf19c552207920c2e3afaaf8f5dbda3cfe559c593748463369e87
ClientHello                  01a0a1a2a3a4a5a6a7a8a9aaabacadaeaf07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c
DeviceHello                  0264b101b1d0be5a8704bd078f9895001fc03e8e9f9522f188dd128d9846d48466a7f2aa7ed09df86dac62478403ff9b2c
ClientConfirm                033c1a5843211271e6b34f45b143ff5174

Resume (same ephemeral keys, for brevity)
session key                  22a9781b579af01cab5511e4fb4cb748041d1694ff4841f3e218f2fdb439988f
device confirm tag           d0a05c4fae5ca260f5f85f449f96f9d5
client confirm tag           67d07d6625c49ba1c4dc8a89957eeb0a

Frames (pairing session key)
SetTime plaintext            010078e768000000004345542d31434553542c4d332e352e302c4d31302e352e302f33
nonce app->watch, ctr 0      000000000000000000000000
wire app->watch, ctr 0       00000000e833a8ea61aeadfdbcfbf7cfe2552de2fb192cb3e8359ab8a4d49399e103e8f807b29866cebb20397479d8e3d6724b925d36f9
Result(SetTime, ok)          800100
nonce watch->app, ctr 0      010000000000000000000000
wire watch->app, ctr 0       000000005e2f658a6fbc1fd8becd52168020248736252b
DATA plaintext (offset 0)    00000000ffd8ffe0
wire app->watch, ctr 1       01000000ebcc9da4e3572187a9cae801cde9faf57d44bfe07d224dd7
```

## 11. Notes for an iOS app

- **CryptoKit covers everything:** `Curve25519.KeyAgreement.PrivateKey` / `PublicKey(rawRepresentation:)`,
  `sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt:, sharedInfo:, outputByteCount: 32)`
  (an empty salt, `Data()`, is equivalent to HKDF's default of zero bytes), `HMAC<SHA256>.authenticationCode`,
  `AES.GCM.seal(_:using:nonce:)` (`AES.GCM.Nonce(data:)` with the 12-byte nonce; wire = counter ‖ ciphertext ‖ tag).
  Unit-test against §10 before touching Bluetooth. (For the LTK, the IKM is the session key itself: wrap it with
  `HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data:), …)`.)
- **Bluetooth:** `CBCentralManager`; `NSBluetoothAlwaysUsageDescription` in Info.plist. Several watches can be
  connected at the same time (one `CBPeripheral` + session state each).
- **QR code:** `DataScannerViewController` (VisionKit) or AVFoundation; `NSCameraUsageDescription`. Allow typing
  the 8-character code as a fallback.
- **Storage per watch (Keychain):** client id, LTK, peripheral identifier, the last known name.
- **Photos:** `PhotosPicker` → scale to fill 410 × 502 and crop → `jpegData(compressionQuality: 0.75)`.
- **Music:** `.fileImporter(allowedContentTypes: [.mp3])` (Apple Music tracks are DRM-protected and not available).
  Don't transcode on the phone: iOS has no MP3 encoder (AVFoundation writes AAC, which the watch can't play).
  Instead, before uploading, compare the file size with StorageInfo's free space and warn if it won't fit, and
  point users to "Fitting more music" (§8) in the help text.
