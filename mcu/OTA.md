# Ethernet OTA and rollback

The design follows K2: MCUboot, two internal-flash slots, swap using offset,
and MCUmgr SMP over IPv4 UDP port 1337. Blinky stays the only application
function; no K2 thruster or sensor control code is included.

## Build and provision

```sh
./mcu/scripts/build.sh
source mcu/.zephyr/.venv/bin/activate
# First-time provision or recovery: flash BOTH MCUboot and the signed app.
./mcu/scripts/flash.sh
```

The flash script runs west from the project workspace using OpenOCD. The
sysbuild domain list flashes MCUboot plus the application; flashing just
`build-ota/mcu` does not provision the bootloader. `--blinky` produces a
standalone development app at the start of flash, so provision the full OTA
build again when switching back to OTA. Connect ST-LINK, use USART3's 115200
baud serial console, and connect the board's RJ45 Ethernet port. JP6 and JP7
must be ON for the upstream H755 Ethernet pin configuration. Keep the M4 core
unused and retain the board's default flash bank configuration.

Artifacts:

- `build-ota/mcuboot/zephyr/zephyr.bin`: bootloader.
- `build-ota/mcu/zephyr/zephyr.signed.bin`: upload this over Ethernet.
- `build-ota/mcu/zephyr/zephyr.signed.hex`: addressed image for USB flashing.

The default build uses MCUboot's public development RSA key. For a deployed
board, generate a private key outside version control and provision MCUboot
with it; retain the same key for subsequent application releases:

```sh
mkdir -p mcu/keys
python mcu/.zephyr/bootloader/mcuboot/scripts/imgtool.py keygen \
  -t rsa-2048 -k mcu/keys/firmware.pem
./mcu/scripts/build.sh --key mcu/keys/firmware.pem
```

`mcu/keys/` is ignored. Back up the private key securely. MCUboot validates
signatures against its compiled public key. UDP management has no transport
authentication or encryption; use the isolated ROV network. A signing key
protects firmware authenticity, but does not restrict who can request resets
or send management traffic.

## Host networking

The board uses static `10.77.0.2/24`, without DHCP or a default gateway. Give
the host's connected Ethernet interface `10.77.0.1/24`; choose the real
interface name from `ip link`, avoiding any conflicting network:

```sh
# Run these host-administration commands yourself; replace eno1 as needed.
sudo ip addr add 10.77.0.1/24 dev eno1
sudo ip link set eno1 up
ping 10.77.0.2
```

Configure the same static address in NetworkManager for a persistent setup.

In WSL2, configure the **Windows Ethernet adapter** with `10.77.0.1/24` in
Windows network settings. On supported Windows 11 systems, put the following
in `%UserProfile%\.wslconfig`, then run `wsl --shutdown` from PowerShell:

```ini
[wsl2]
networkingMode=mirrored
```

Restart WSL and verify its route with `ip route get 10.77.0.2`. Permit the
required traffic through Windows/Hyper-V firewall policy. With NAT networking,
use a reachable LAN route via Windows instead; do not assume a direct cable is
reachable from WSL. For first flashing, attach ST-LINK using usbipd-win as
linked in the README. After provisioning, updates require only Ethernet.

## Upload, test, reset, confirm

Bump `VERSION` before a release so the new version is visible in logs and
`mcumgr image list`. Use `--key mcu/keys/firmware.pem` for a board provisioned with that key. For
a board provisioned with the development key:

```sh
./mcu/scripts/build.sh
python3 mcu/scripts/ota.py --host 10.77.0.2
# Or select a particular signed artifact:
python3 mcu/scripts/ota.py --host 10.77.0.2 path/to/zephyr.signed.bin
```

The helper validates the local image's SHA256 and signature TLV, uploads via
the pinned Apache MCUmgr CLI, verifies that slot 1 contains that exact image
hash, requests **test** boot, checks the pending flag, resets, and polls for
the exact uploaded hash to become active and confirmed. The board validates
the cryptographic signature. The helper never permanently confirms remotely.
An already active, confirmed copy of the same image is a successful no-op.
`--no-reset` stages a test boot for a later reset; `--wait` changes the default
120-second post-reset observation window. Failures return a nonzero status.

To inspect without updating:

```sh
mcu/.zephyr/.venv/bin/mcumgr --conntype udp \
  '--connstring=[10.77.0.2]:1337' image list
```

## Flash layout and failure handling

| Region | Flash offset | Size |
| --- | --- | --- |
| MCUboot | `0x000000` | 128 KiB |
| Primary application | `0x020000` | 384 KiB |
| Secondary application | `0x100000` | 512 KiB |

Both images share one partition definition. Sectors are 128 KiB. The secondary
slot has one additional sector for offset swapping; MCUboot's trailer and
alignment reserve space as well. In this configuration the application link
region is 261,808 bytes; the signed image must fit the primary slot minus its
reserved footer. Signing, MCUmgr's sysbuild size checks, and `verify-build.py`
enforce the build's limits. The unused flash gaps are left unallocated.

A trial image confirms only after the LED initializes and the main loop runs
with a preferred IPv4 address and the Ethernet interface and carrier up
continuously for five seconds.
Network setup and starting MCUmgr must succeed first. The default static IP
is configured before this check; link readiness does not prove communication
with the topside. Extend the health criteria when application functions grow.

An unconfirmed trial that has not passed health checks within 60 seconds
resets, so MCUboot reverts to the previously confirmed image. Confirmation
write failures also remain subject to that deadline. A confirmed image keeps
running when the Ethernet cable is disconnected.

The independent watchdog starts in MCUboot with an eight-second timeout;
MCUboot feeds it while validating/swapping. The application also configures
that timeout at initialization and feeds only after a successful LED loop.
A stuck main loop or startup failure therefore resets without confirming.
Actual erase timing and watchdog resets must be verified on the board.
Power loss during upload leaves the primary intact; interrupted swaps resume
using MCUboot's swap status. Rollback requires a previously provisioned valid
image and a reset. For a fault before watchdog initialization, recovery may
still require an external reset or power cycle.

## Board acceptance checklist

These are physical acceptance tests, not claims of completed hardware testing:

1. Provision via ST-LINK; verify the version log and green LED, and inspect
   `mcumgr image list` with the Ethernet cable connected.
2. Build a different version, upload it, and verify the new hash is active and
   confirmed. Power-cycle and verify that version remains running.
3. Build a deliberate rollback image with
   `./mcu/scripts/build.sh -DCONFIG_ROV_OTA_CONFIRM=n` (and the same signing key).
   Upload it. It must reboot after 60 seconds and restore the previous image;
   the helper must report failure because the uploaded hash is not confirmed.
4. Test a trial with the cable unplugged immediately after reset. It must revert
   after the trial deadline. Reconnect and inspect the restored version.
5. Interrupt an upload and repeat it. Separately interrupt power during a swap;
   restore power and verify that MCUboot resumes into a valid image.
6. Try an image signed with a different key and an oversized image. Neither
   must replace the active, confirmed application.
7. With a debugger, deliberately stop the application from feeding IWDG;
   verify a hardware reset and rollback for an unconfirmed image. Debugger
   watchdog-freeze settings must be disabled for this test.
8. Repeat initial flashing and Ethernet update from WSL2.

Restore a normal build after deliberate fault tests. Keep serial logs and
before/after image hashes as acceptance evidence.
