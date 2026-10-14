#!/usr/bin/env python3
"""Upload a signed image with the Apache MCUmgr CLI; require its exact hash."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time

PROJECT = Path(__file__).resolve().parents[1]


def image_hash(path):
    data = Path(path).read_bytes()
    if len(data) < 32:
        raise ValueError("Image is too short")
    magic, _, header_size, protected_size, body_size = struct.unpack_from("<IIHHI", data)
    if magic != 0x96F3B83D or header_size < 32:
        raise ValueError("Not an MCUboot image")
    offset = header_size + body_size
    if protected_size:
        if offset + 4 > len(data):
            raise ValueError("Truncated protected TLVs")
        if struct.unpack_from("<HH", data, offset) != (0x6908, protected_size):
            raise ValueError("Invalid protected TLVs")
        offset += protected_size
    digest = hashlib.sha256(data[:offset]).digest()
    if offset + 4 > len(data):
        raise ValueError("Image has no TLVs")
    magic, size = struct.unpack_from("<HH", data, offset)
    end = offset + size
    if magic != 0x6907 or size < 4 or end > len(data):
        raise ValueError("Invalid image TLVs")
    offset += 4
    found_hash = False
    signed = False
    while offset < end:
        if offset + 4 > end:
            raise ValueError("Truncated TLV header")
        kind, length = struct.unpack_from("<HH", data, offset)
        offset += 4
        if offset + length > end:
            raise ValueError("Truncated TLV data")
        if kind == 0x10:
            if data[offset:offset + length] != digest:
                raise ValueError("Image SHA256 does not match its contents")
            found_hash = True
        if kind in (0x20, 0x22, 0x23, 0x24) and length:
            signed = True
        offset += length
    if not found_hash or not signed:
        raise ValueError("Expected a signed SHA256 MCUboot image")
    return digest.hex()


def image_states(output):
    states = []
    current = None
    for line in output.splitlines():
        match = re.fullmatch(r"\s*image=(\d+) slot=(\d+)\s*", line)
        if match:
            current = {"image": int(match[1]), "slot": int(match[2]), "flags": set()}
            states.append(current)
        elif current is not None:
            key, separator, value = line.strip().partition(":")
            if separator and key == "hash":
                current["hash"] = value.strip().lower()
            elif separator and key == "flags":
                current["flags"] = set(value.split())
    return states


class Client:
    def __init__(self, executable, host, port):
        self.command = [str(executable), "--conntype", "udp",
                        f"--connstring=[{host}]:{port}", "--timeout", "2", "--tries", "2"]

    def run(self, *arguments):
        result = subprocess.run(self.command + list(arguments), check=True,
                                capture_output=True, text=True, timeout=1200)
        return result.stdout

    def states(self):
        return image_states(self.run("image", "list"))


def has_image(states, digest, flags=(), slot=None):
    return any(state.get("hash") == digest and state["image"] == 0
               and set(flags) <= state["flags"] and (slot is None or state["slot"] == slot)
               for state in states)


def update(client, image, no_reset=False, wait=120):
    digest = image_hash(image)
    if has_image(client.states(), digest, ("active", "confirmed")):
        print("This image is already active and confirmed.")
        return
    print(f"Uploading {image} (image hash {digest})", flush=True)
    client.run("image", "upload", str(image))
    if not has_image(client.states(), digest, slot=1):
        raise RuntimeError("Uploaded image hash is absent from slot 1; refusing test/reset")
    client.run("image", "test", digest)
    if not has_image(client.states(), digest, ("pending",), slot=1):
        raise RuntimeError("Image was not marked pending; refusing reset")
    if no_reset:
        print("Image marked for test boot. Reset the board to start the trial.")
        return
    try:
        client.run("reset")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        # A reset can happen before its UDP acknowledgment arrives. State polling
        # still must prove that this specific image became active and confirmed.
        print(f"Reset acknowledgment unavailable: {error}", file=sys.stderr)
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        try:
            if has_image(client.states(), digest, ("active", "confirmed")):
                print("Uploaded image is active and confirmed.")
                return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pass
        time.sleep(1)
    raise RuntimeError("Uploaded image did not become active and confirmed; check rollback and serial logs")


def main():
    workspace = Path(os.environ.get("ZEPHYR_WORKSPACE", PROJECT / ".zephyr")).resolve()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", nargs="?", type=Path,
                        default=PROJECT / "build-ota/mcu/zephyr/zephyr.signed.bin")
    parser.add_argument("--host", default="10.77.0.2")
    parser.add_argument("--port", type=int, default=1337)
    parser.add_argument("--wait", type=int, default=120)
    parser.add_argument("--no-reset", action="store_true")
    mcumgr_path = ".venv/Scripts/mcumgr.exe" if os.name == "nt" else ".venv/bin/mcumgr"
    parser.add_argument("--mcumgr", default=os.environ.get("MCUMGR", str(workspace / mcumgr_path)))
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or args.wait <= 0:
        parser.error("port must be 1..65535 and wait must be positive")
    try:
        update(Client(args.mcumgr, args.host, args.port), args.image, args.no_reset, args.wait)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"OTA failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
