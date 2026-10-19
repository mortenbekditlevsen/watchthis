#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""
Prints test vectors for docs/watch-ble-protocol.md, computed with the reference client's own functions
(tools/ble_test_client.py), so another implementation (the iPhone app) can unit-test its key derivation, confirm tags
and frame encryption without a watch. Fixed keys, so the output never changes:

    tools/.venv/bin/python tools/protocol_test_vectors.py
"""
import struct
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

sys.path.insert(0, str(Path(__file__).parent))
import ble_test_client as c  # noqa: E402

CLIENT_PRIV = bytes(range(0x01, 0x21))          # 01 02 .. 20
DEVICE_PRIV = bytes(range(0x41, 0x61))          # 41 42 .. 60
CLIENT_ID = bytes(range(0xA0, 0xB0))            # A0 .. AF
POP = b"7K2M9XAB"
UTC = 1_760_000_000                             # 2025-10-09 08:53:20 UTC
TZ = b"CET-1CEST,M3.5.0,M10.5.0/3"


def show(label: str, value: bytes):
    print(f"{label:28} {value.hex()}")


def main():
    client = X25519PrivateKey.from_private_bytes(CLIENT_PRIV)
    device = X25519PrivateKey.from_private_bytes(DEVICE_PRIV)
    shared = client.exchange(X25519PublicKey.from_public_bytes(c.raw_pub(device)))

    print("Inputs")
    show("client private key", CLIENT_PRIV)
    show("client public key", c.raw_pub(client))
    show("device private key", DEVICE_PRIV)
    show("device public key", c.raw_pub(device))
    show("client id", CLIENT_ID)
    print(f"{'POP':28} {POP.decode()}")

    print("\nPairing")
    show("X25519 shared secret", shared)
    session = c.hkdf(shared, POP, c.INFO_PAIR)
    show("session key", session)
    show("device confirm tag", c.tag(session, c.CONFIRM_DEVICE))
    show("client confirm tag", c.tag(session, c.CONFIRM_CLIENT))
    ltk = c.hkdf(session, b"", c.INFO_LTK)
    show("LTK", ltk)
    show("ClientHello", bytes([0x01]) + CLIENT_ID + c.raw_pub(client))
    show("DeviceHello", bytes([0x02]) + c.raw_pub(device) + c.tag(session, c.CONFIRM_DEVICE))
    show("ClientConfirm", bytes([0x03]) + c.tag(session, c.CONFIRM_CLIENT))

    print("\nResume (same ephemeral keys, for brevity)")
    resume = c.hkdf(shared, ltk, c.INFO_RESUME)
    show("session key", resume)
    show("device confirm tag", c.tag(resume, c.CONFIRM_DEVICE))
    show("client confirm tag", c.tag(resume, c.CONFIRM_CLIENT))

    print("\nFrames (pairing session key)")
    set_time = bytes([0x01]) + struct.pack("<q", UTC) + TZ
    show("SetTime plaintext", set_time)
    show("nonce app->watch, ctr 0", c.nonce(0x00, 0))
    show("wire app->watch, ctr 0", struct.pack("<I", 0) + AESGCM(session).encrypt(c.nonce(0x00, 0), set_time, None))
    result = bytes([0x80, 0x01, 0x00])
    show("Result(SetTime, ok)", result)
    show("nonce watch->app, ctr 0", c.nonce(0x01, 0))
    show("wire watch->app, ctr 0", struct.pack("<I", 0) + AESGCM(session).encrypt(c.nonce(0x01, 0), result, None))
    data = struct.pack("<I", 0) + b"\xff\xd8\xff\xe0"
    show("DATA plaintext (offset 0)", data)
    show("wire app->watch, ctr 1", struct.pack("<I", 1) + AESGCM(session).encrypt(c.nonce(0x00, 1), data, None))


if __name__ == "__main__":
    main()
