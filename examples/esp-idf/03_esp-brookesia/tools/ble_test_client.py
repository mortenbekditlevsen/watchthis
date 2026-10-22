#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""
Test client for the watch's BLE protocol (docs/watch-ble-protocol.md): pairs with the watch, sets the time and
lists/uploads/deletes files. Does exactly what the phone app has to do, so it doubles as a reference implementation.

Setup (once):
    python3 -m venv tools/.venv && tools/.venv/bin/pip install bleak cryptography

Usage (open the "Synk" app on the watch first):
    tools/.venv/bin/python tools/ble_test_client.py pair 7K2M9XAB      # code shown under the QR code
    tools/.venv/bin/python tools/ble_test_client.py time [--tz CET-1CEST,M3.5.0,M10.5.0/3]
    tools/.venv/bin/python tools/ble_test_client.py info
    tools/.venv/bin/python tools/ble_test_client.py list photo|music|face|asset|weather
    tools/.venv/bin/python tools/ble_test_client.py upload photo|music|face|asset|weather FILE ID [--name NAME]
    tools/.venv/bin/python tools/ble_test_client.py delete photo|music|face|asset|weather ID
    tools/.venv/bin/python tools/ble_test_client.py read face|asset ID OUT     # download a file
    tools/.venv/bin/python tools/ble_test_client.py name ["Mit ur"]    # show / set the home screen title
    tools/.venv/bin/python tools/ble_test_client.py birthday MM-DD|none  # Danish flag on the faces that day
    tools/.venv/bin/python tools/ble_test_client.py faces              # watch faces: order, active, builtins
    tools/.venv/bin/python tools/ble_test_client.py face-order ID... [--active N]   # which faces to show, in order

Watch face files (.wf) can be made with WatchFaceKit's CLI: `swift run wfce builtin klassisk klassisk_kopi.wf`
(in components/watch_faces/WatchFaceKit); assets are PNG/baseline JPEG backgrounds or LVGL binfonts. A sample
forecast for the Vejr app: `swift run wfce weather-sample vejr.wx`, then `upload weather vejr.wx vejr`.

The pairing (client id + long-term key) is kept in tools/.ble_test_client.json.
"""
import argparse
import asyncio
import binascii
import hmac
import json
import os
import struct
import sys
import time
from hashlib import sha256
from pathlib import Path

from bleak import BleakClient, BleakScanner
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SERVICE = "7a1c0001-5b3e-4f2a-9c61-2d8e4b7a0c15"
CMD = "7a1c0011-5b3e-4f2a-9c61-2d8e4b7a0c15"
DEVICE_INFO = "7a1c0012-5b3e-4f2a-9c61-2d8e4b7a0c15"
DATA = "7a1c0013-5b3e-4f2a-9c61-2d8e4b7a0c15"
PROV_STATE = "7a1c0020-5b3e-4f2a-9c61-2d8e4b7a0c15"
PROV_HANDSHAKE = "7a1c0021-5b3e-4f2a-9c61-2d8e4b7a0c15"

INFO_PAIR = b"watch-pair-v1"
INFO_RESUME = b"watch-resume-v1"
INFO_LTK = b"watch-ltk-v1"
CONFIRM_DEVICE = b"watch-confirm-device-v1"
CONFIRM_CLIENT = b"watch-confirm-client-v1"

KINDS = {"photo": 0, "music": 1, "face": 2, "asset": 3, "weather": 4}
STATUS = {0: "ok", 1: "failed", 2: "invalid", 3: "no space", 4: "busy", 5: "check failed (size/CRC/format)",
          6: "not found"}
NACK = {1: "not paired", 2: "bad confirm (wrong code?)", 3: "pairing window closed", 4: "rate limited"}

UPLOAD_WINDOW = 8 * 1024    # Max unacknowledged upload bytes (see Watch.upload)

STATE_FILE = Path(__file__).with_name(".ble_test_client.json")


def hkdf(ikm: bytes, salt: bytes, info: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt or None, info=info).derive(ikm)


def tag(key: bytes, info: bytes) -> bytes:
    return hmac.new(key, info, sha256).digest()[:16]


def raw_pub(key: X25519PrivateKey) -> bytes:
    return key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def nonce(direction: int, counter: int) -> bytes:
    return bytes([direction]) + struct.pack("<I", counter) + bytes(7)


class Watch:
    def __init__(self, client: BleakClient):
        self.client = client
        self.session = None
        self.tx_counter = 0         # One counter for every encrypted write (CMD and DATA)
        self.handshake = asyncio.Queue()
        self.replies = asyncio.Queue()

    async def start_notifications(self):
        await self.client.start_notify(PROV_HANDSHAKE, lambda _, d: self.handshake.put_nowait(bytes(d)))
        await self.client.start_notify(CMD, lambda _, d: self.replies.put_nowait(bytes(d)))

    async def _handshake(self, hello_opcode: int, client_id: bytes, salt_for, info: bytes, confirm_opcode: int):
        key = X25519PrivateKey.generate()
        await self.client.write_gatt_char(PROV_HANDSHAKE, bytes([hello_opcode]) + client_id + raw_pub(key), True)
        reply = await asyncio.wait_for(self.handshake.get(), 10)
        if reply[0] == 0x7F:
            raise RuntimeError(f"watch refused: {NACK.get(reply[1], reply[1])}")
        device_pub, device_tag = reply[1:33], reply[33:49]
        shared = key.exchange(X25519PublicKey.from_public_bytes(device_pub))
        session = hkdf(shared, salt_for, info)
        if not hmac.compare_digest(device_tag, tag(session, CONFIRM_DEVICE)):
            raise RuntimeError("device confirm tag mismatch (wrong code?)")
        await self.client.write_gatt_char(PROV_HANDSHAKE, bytes([confirm_opcode]) + tag(session, CONFIRM_CLIENT), True)
        reply = await asyncio.wait_for(self.handshake.get(), 10)
        if reply[0] == 0x7F:
            raise RuntimeError(f"watch refused: {NACK.get(reply[1], reply[1])}")
        self.session = session
        return session

    async def pair(self, pop: str):
        client_id = os.urandom(16)
        session = await self._handshake(0x01, client_id, pop.replace(" ", "").upper().encode(), INFO_PAIR, 0x03)
        ltk = hkdf(session, b"", INFO_LTK)
        STATE_FILE.write_text(json.dumps({"client_id": client_id.hex(), "ltk": ltk.hex()}))
        print(f"Paired; key saved in {STATE_FILE}")

    async def resume(self):
        if not STATE_FILE.exists():
            raise RuntimeError("not paired yet: run 'pair CODE' first")
        state = json.loads(STATE_FILE.read_text())
        await self._handshake(0x05, bytes.fromhex(state["client_id"]), bytes.fromhex(state["ltk"]), INFO_RESUME, 0x07)

    def _encrypt(self, plaintext: bytes) -> bytes:
        counter = self.tx_counter
        self.tx_counter += 1
        return struct.pack("<I", counter) + AESGCM(self.session).encrypt(nonce(0x00, counter), plaintext, None)

    def _decrypt(self, wire: bytes) -> bytes:
        counter = struct.unpack("<I", wire[:4])[0]
        return AESGCM(self.session).decrypt(nonce(0x01, counter), wire[4:], None)

    async def command(self, plaintext: bytes):
        await self.client.write_gatt_char(CMD, self._encrypt(plaintext), True)

    async def reply(self, opcode: int, timeout=10) -> bytes:
        """Next decrypted reply with this opcode (progress notifications are skipped)."""
        while True:
            msg = self._decrypt(await asyncio.wait_for(self.replies.get(), timeout))
            if msg[0] == opcode:
                return msg[1:]
            if msg[0] == 0x80 and opcode != 0x80:
                raise RuntimeError(f"command 0x{msg[1]:02x} failed: {STATUS.get(msg[2], msg[2])}")

    async def result(self, request_opcode: int, timeout=10):
        payload = await self.reply(0x80, timeout)
        if payload[0] != request_opcode or payload[1] != 0:
            raise RuntimeError(f"command 0x{payload[0]:02x}: {STATUS.get(payload[1], payload[1])}")

    async def set_time(self, tz: str):
        await self.command(bytes([0x01]) + struct.pack("<q", int(time.time())) + tz.encode())
        await self.result(0x01)
        print("Time set" + (f" (TZ {tz})" if tz else ""))

    async def info(self):
        print("Device info:", (await self.client.read_gatt_char(DEVICE_INFO)).decode())
        await self.command(bytes([0x02]))
        total, used, photos, music = struct.unpack("<IIHH", await self.reply(0x81))
        print(f"Storage: {used // 1024} of {total // 1024} KB used; {photos} photos, {music} tracks")

    async def list(self, kind: str):
        start, entries = 0, []
        while True:
            await self.command(bytes([0x03, KINDS[kind]]) + struct.pack("<H", start))
            payload = await self.reply(0x82)
            _, page_start, total, count = struct.unpack("<BHHB", payload[:6])
            pos = 6
            for _ in range(count):
                n = payload[pos]; ident = payload[pos + 1:pos + 1 + n].decode(); pos += 1 + n
                size = struct.unpack("<I", payload[pos:pos + 4])[0]; pos += 4
                n = payload[pos]; name = payload[pos + 1:pos + 1 + n].decode(); pos += 1 + n
                entries.append((ident, size, name))
            start = page_start + count
            if count == 0 or start >= total:
                break
        for ident, size, name in entries:
            print(f"  {ident:32} {size:8} {name}")
        print(f"{len(entries)} {kind} file(s)")

    async def upload(self, kind: str, path: Path, ident: str, name: str):
        data = path.read_bytes()
        crc = binascii.crc32(data) & 0xFFFFFFFF
        await self.command(bytes([0x04, KINDS[kind]]) + struct.pack("<II", len(data), crc) +
                           bytes([len(ident)]) + ident.encode() + name.encode())
        await self.result(0x04)

        # Plaintext per DATA write: offset(4) + bytes; the write is MTU - 3 bytes incl. the 20-byte envelope
        chunk = self.client.mtu_size - 3 - 20 - 4
        started = time.monotonic()
        # Flow control: at most UPLOAD_WINDOW bytes unacknowledged by Progress (sent every 4 KB and for the last
        # byte). The OS silently drops writes without response when its queue overflows (bleak doesn't wait for
        # CoreBluetooth's "ready to send"), and a write with response (the commit) can overtake queued ones
        acked = 0
        for offset in range(0, len(data), chunk):
            end = min(offset + chunk, len(data))
            while end - acked > UPLOAD_WINDOW:
                acked = struct.unpack("<I", await self.reply(0x83, timeout=10))[0]
            await self.client.write_gatt_char(DATA, self._encrypt(struct.pack("<I", offset) + data[offset:end]), False)
        while acked < len(data):
            acked = struct.unpack("<I", await self.reply(0x83, timeout=10))[0]
        await self.command(bytes([0x05]))
        await self.result(0x05, timeout=30)
        elapsed = time.monotonic() - started
        print(f"Uploaded {path.name} as {kind}/{ident}: {len(data)} bytes in {elapsed:.1f} s "
              f"({len(data) / 1024 / elapsed:.0f} KB/s, {chunk}-byte chunks)")

    async def set_name(self, name: str):
        await self.command(bytes([0x08]) + name.encode())
        await self.result(0x08)
        print(f"Name set to {name}")

    async def get_name(self):
        await self.command(bytes([0x09]))
        print("Name:", (await self.reply(0x84)).decode())

    async def faces(self):
        await self.command(bytes([0x0B]))
        payload = await self.reply(0x85)
        active, count, i, order = payload[0], payload[1], 2, []
        for _ in range(count):
            n = payload[i]
            order.append(payload[i + 1:i + 1 + n].decode())
            i += 1 + n
        builtins = []
        for _ in range(payload[i]):
            n = payload[i + 1]
            builtins.append(payload[i + 2:i + 2 + n].decode())
            i += 1 + n
        for index, ident in enumerate(order):
            print(("* " if index == active else "  ") + ident)
        print("Builtin:", ", ".join(builtins))

    async def set_face_order(self, ids: list, active: int):
        payload = bytes([active, len(ids)]) + b"".join(bytes([len(i)]) + i.encode() for i in ids)
        await self.command(bytes([0x0A]) + payload)
        await self.result(0x0A)
        print("Face order set")

    async def read(self, kind: str, ident: str, out: Path):
        data, offset = b"", 0
        while True:
            await self.command(bytes([0x0C, KINDS[kind]]) + struct.pack("<IH", offset, 400) + ident.encode())
            reply = await self.reply(0x86)
            status, at, total = reply[0], *struct.unpack("<II", reply[1:9])
            if status != 0:
                raise RuntimeError(f"read failed: {STATUS.get(status, status)}")
            chunk = reply[9:]
            data += chunk
            offset += len(chunk)
            if offset >= total or not chunk:
                break
        out.write_bytes(data)
        print(f"Read {kind}/{ident}: {len(data)} bytes -> {out}")

    async def set_birthday(self, date: str):
        month, day = (0, 0) if date == "none" else map(int, date.split("-"))
        await self.command(bytes([0x0D, month, day]))
        await self.result(0x0D)
        print("Birthday cleared" if month == 0 else f"Birthday set to {day}/{month}")

    async def delete(self, kind: str, ident: str):
        await self.command(bytes([0x07, KINDS[kind]]) + ident.encode())
        await self.result(0x07)
        print(f"Deleted {kind}/{ident}")


async def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("pair").add_argument("pop")
    sub.add_parser("time").add_argument("--tz", default="")
    sub.add_parser("info")
    sub.add_parser("list").add_argument("kind", choices=KINDS)
    up = sub.add_parser("upload")
    up.add_argument("kind", choices=KINDS)
    up.add_argument("file", type=Path)
    up.add_argument("id")
    up.add_argument("--name", default="")
    rm = sub.add_parser("delete")
    rm.add_argument("kind", choices=KINDS)
    rm.add_argument("id")
    sub.add_parser("name").add_argument("name", nargs="?")
    rd = sub.add_parser("read")
    rd.add_argument("kind", choices=KINDS)
    rd.add_argument("id")
    rd.add_argument("out", type=Path)
    sub.add_parser("birthday").add_argument("date")
    sub.add_parser("faces")
    fo = sub.add_parser("face-order")
    fo.add_argument("ids", nargs="+")
    fo.add_argument("--active", type=int, default=0)
    args = parser.parse_args()

    print("Scanning (open Synk on the watch)...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: SERVICE in [u.lower() for u in ad.service_uuids], timeout=15)
    if device is None:
        sys.exit("Watch not found")
    print(f"Found {device.name}")

    async with BleakClient(device) as client:
        watch = Watch(client)
        await watch.start_notifications()
        if args.cmd == "pair":
            await watch.pair(args.pop)
            return
        await watch.resume()
        if args.cmd == "time":
            await watch.set_time(args.tz)
        elif args.cmd == "info":
            await watch.info()
        elif args.cmd == "list":
            await watch.list(args.kind)
        elif args.cmd == "upload":
            await watch.upload(args.kind, args.file, args.id, args.name)
        elif args.cmd == "delete":
            await watch.delete(args.kind, args.id)
        elif args.cmd == "read":
            await watch.read(args.kind, args.id, args.out)
        elif args.cmd == "birthday":
            await watch.set_birthday(args.date)
        elif args.cmd == "faces":
            await watch.faces()
        elif args.cmd == "face-order":
            await watch.set_face_order(args.ids, args.active)
        elif args.cmd == "name":
            if args.name:
                await watch.set_name(args.name)
            else:
                await watch.get_name()


if __name__ == "__main__":
    asyncio.run(main())
