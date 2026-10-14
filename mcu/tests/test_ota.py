"""Updater failure cases plus the real MCUmgr CLI against a UDP SMP test peer."""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ota.py"
spec = importlib.util.spec_from_file_location("ota", SCRIPT)
ota = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ota)


def signed_fixture():
    # Structurally signed fixture; crypto validity is checked by MCUboot, not the updater.
    header = struct.pack("<IIHHII", 0x96F3B83D, 0, 32, 0, 8192, 0) + bytes(12)
    payload = header + bytes(range(256)) * 32
    digest = hashlib.sha256(payload).digest()
    tlvs = struct.pack("<HH", 0x10, 32) + digest + struct.pack("<HH", 0x20, 256) + bytes(256)
    return payload + struct.pack("<HH", 0x6907, len(tlvs) + 4) + tlvs


class FakeClient:
    def __init__(self, digest, wrong_hash=False, rollback=False, reset_error=False):
        self.digest = digest
        self.wrong_hash = wrong_hash
        self.rollback = rollback
        self.reset_error = reset_error
        self.uploaded = self.pending = self.reset = False
        self.calls = []

    def states(self):
        old = {"image": 0, "slot": 0, "hash": "aa" * 32, "flags": {"active", "confirmed"}}
        if self.reset and not self.rollback:
            return [{"image": 0, "slot": 0, "hash": self.digest, "flags": {"active", "confirmed"}}]
        if self.uploaded:
            return [old, {"image": 0, "slot": 1,
                          "hash": "bb" * 32 if self.wrong_hash else self.digest,
                          "flags": {"pending"} if self.pending else set()}]
        return [old]

    def run(self, *args):
        self.calls.append(args)
        if args[:2] == ("image", "upload"):
            self.uploaded = True
        elif args[:2] == ("image", "test"):
            self.pending = True
        elif args == ("reset",):
            self.reset = True
            if self.reset_error:
                raise ota.subprocess.CalledProcessError(1, "reset")
        return ""


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.image = Path(self.directory.name) / "signed.bin"
        self.image.write_bytes(signed_fixture())
        self.digest = ota.image_hash(self.image)

    def test_wrong_slot_hash_refuses_test_and_reset(self):
        client = FakeClient(self.digest, wrong_hash=True)
        with self.assertRaisesRegex(RuntimeError, "hash is absent"):
            ota.update(client, self.image)
        self.assertEqual(len(client.calls), 1)

    def test_corruption_refuses_upload(self):
        data = bytearray(self.image.read_bytes())
        data[50] ^= 1
        self.image.write_bytes(data)
        client = FakeClient(self.digest)
        with self.assertRaisesRegex(ValueError, "SHA256"):
            ota.update(client, self.image)
        self.assertEqual(client.calls, [])

    def test_no_reset_and_missing_reset_ack(self):
        client = FakeClient(self.digest)
        ota.update(client, self.image, no_reset=True)
        self.assertTrue(client.pending)
        self.assertFalse(client.reset)
        client = FakeClient(self.digest, reset_error=True)
        ota.update(client, self.image)
        self.assertTrue(client.reset)

    def test_old_confirmed_image_is_not_success(self):
        client = FakeClient(self.digest, rollback=True)
        with patch.object(ota.time, "monotonic", side_effect=[0, 0, 2]), \
                patch.object(ota.time, "sleep"), self.assertRaisesRegex(RuntimeError, "did not become"):
            ota.update(client, self.image, wait=1)

    def test_parser_preserves_image_and_flags(self):
        states = ota.image_states(f"Images:\n image=0 slot=1\n flags: pending\n hash: {self.digest}\nSplit status: N/A\n")
        self.assertTrue(ota.has_image(states, self.digest, ("pending",), slot=1))
        states[0]["image"] = 1
        self.assertFalse(ota.has_image(states, self.digest))

    def test_truncated_images(self):
        for size in (0, 20, 32, 97, len(signed_fixture()) - 1):
            self.image.write_bytes(signed_fixture()[:size])
            with self.assertRaises(ValueError):
                ota.image_hash(self.image)

    def test_real_cli_udp_upload_test_reset(self):
        executable = Path(os.environ.get("MCUMGR", SCRIPT.parents[1] / (".zephyr/.venv/Scripts/mcumgr.exe" if os.name == "nt" else ".zephyr/.venv/bin/mcumgr")))
        if not executable.is_file():
            self.skipTest("Install OTA tools to exercise the real CLI")
        import cbor2
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", 0))
        sock.settimeout(0.1)
        stop = threading.Event()
        errors = []
        received = bytearray()
        upload_requests = set()
        state = {"pending": False, "reset": False, "dropped": False, "retried": False}

        def serve():
            while not stop.is_set():
                try:
                    packet, address = sock.recvfrom(2048)
                except socket.timeout:
                    continue
                except OSError:
                    return
                try:
                    op, flags, length, group, sequence, command = struct.unpack("!BBHHBB", packet[:8])
                    request = cbor2.loads(packet[8:8 + length])
                    response = {"rc": 0}
                    if group == 1 and command == 1:
                        offset = request["off"]
                        fingerprint = (offset, request["data"])
                        if fingerprint in upload_requests:
                            state["retried"] = True
                        upload_requests.add(fingerprint)
                        if not state["dropped"]:
                            state["dropped"] = True
                            continue
                        if offset == len(received):
                            received.extend(request["data"])
                        else:
                            state["retried"] = True
                        response["off"] = len(received)
                    elif group == 1 and command == 0:
                        if op & 3 == 2:
                            self.assertEqual(request["hash"].hex(), self.digest)
                            self.assertFalse(request.get("confirm", False))
                            state["pending"] = True
                        old = {"image": 0, "slot": 0, "version": "0.0.0", "hash": bytes.fromhex("aa" * 32),
                               "bootable": True, "active": True, "confirmed": True}
                        new = {"image": 0, "slot": 1, "version": "0.1.0", "hash": bytes.fromhex(self.digest),
                               "bootable": True, "pending": state["pending"], "active": False, "confirmed": False}
                        if state["reset"]:
                            new.update(slot=0, pending=False, active=True, confirmed=True)
                            response["images"] = [new]
                        else:
                            response["images"] = [old] + ([new] if received else [])
                    elif group == 0 and command == 5:
                        self.assertTrue(state["pending"])
                        state["reset"] = True
                    else:
                        raise AssertionError((group, command, request))
                    body = cbor2.dumps(response)
                    sock.sendto(struct.pack("!BBHHBB", op + 1, flags, len(body), group, sequence, command) + body, address)
                except Exception as error:
                    errors.append(error)
                    return

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            ota.update(ota.Client(executable, "127.0.0.1", sock.getsockname()[1]), self.image)
            self.assertEqual(received, self.image.read_bytes())
            self.assertTrue(state["reset"])
            self.assertTrue(state["retried"])
            self.assertFalse(errors, errors)
        finally:
            stop.set()
            thread.join(timeout=2)
            sock.close()


if __name__ == "__main__":
    with contextlib.redirect_stdout(io.StringIO()):
        unittest.main()
