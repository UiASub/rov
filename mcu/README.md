# ROV microcontroller

Based on [K2-Zephyr](https://github.com/UiASub/K2-Zephyr), inspected at
`38535e1c8b751f06aa49094dfef5e4613c30eedb`. Target: NUCLEO-H755ZI-Q,
STM32H755 M7 (`nucleo_h755zi_q/stm32h755xx/m7`), matching K2's current board.
The M4 core is not used. Zephyr 4.2.0 and SDK 0.17.2 match K2.

## Install on Linux or WSL2

Run one command from the repo root as your normal user:

```sh
./mcu/scripts/install-zephyr.sh
```

Supported: Ubuntu/Debian, Arch and Arch derivatives (including CachyOS), Fedora,
and those distributions inside WSL2. The installer selects apt, pacman or dnf
and requests sudo only if host packages are missing. It installs the compiler,
Ninja, Git, download/archive tools, gperf, dtc, OpenOCD and Go; bootstraps
[uv](https://docs.astral.sh/uv/getting-started/installation/) if missing; creates
a uv-managed Python 3.12 venv; installs pinned west and CMake in that venv;
fetches Zephyr and the board's modules; installs the ARM SDK; and installs the
pinned Apache MCUmgr CLI for Ethernet updates. You do not need a system Python
or CMake installation, or a separate OTA tools setup step.

The script can be rerun after an interrupted install. It installs required
packages without a general OS upgrade and never deletes workspaces. Arch
systems should have up-to-date package databases from their normal system
updates. Use `--skip-system` when host tools are already managed for you,
`--skip-sdk` for an existing toolchain, or `--workspace PATH` for an external
workspace (set `ZEPHYR_WORKSPACE=PATH` for subsequent commands). A different
manifest is rejected before any installations or workspace changes. Generated
dependencies, SDK, virtual environment and builds are ignored by git.

Activation is optional for the build and flash wrappers:

```sh
source mcu/.zephyr/.venv/bin/activate
```

On WSL2, keep the checkout in the Linux filesystem (e.g. `~/dev/rov`). Use
[usbipd-win](https://learn.microsoft.com/windows/wsl/connect-usb) to attach the
ST-LINK USB device to WSL for initial flashing; give your user access to
ST-LINK using the distro's udev rules. Ethernet updates need a route from WSL
to the board; see [OTA.md](OTA.md) for mirrored networking or a LAN route.

## Blinky

```sh
./mcu/scripts/build.sh --blinky
./mcu/scripts/flash.sh --blinky
```

The green user LED (LD1/PA5, upstream `led0` alias) toggles every 500 ms.
USART3 logs appear through ST-LINK at 115200 baud. The upstream board definition
provides clocks and pins; `boards/` holds application-specific configuration.
The build script finds its workspace without requiring shell activation and
accepts extra CMake arguments after the script name.


## Ethernet updates

`./mcu/scripts/build.sh` now defaults to a signed MCUboot sysbuild with Ethernet
OTA. Plain blinky remains available with `--blinky`. See [OTA.md](OTA.md) for
initial USB provisioning, signing keys, Linux/WSL networking, normal updates,
rollback behavior and the board acceptance checklist.

```sh
./mcu/scripts/build.sh
python3 mcu/scripts/ota.py --host 10.77.0.2
```

## Local verification

```sh
./mcu/scripts/test.sh
# Optional: Rust-based upstream MCUboot power-loss / rollback simulator.
./mcu/scripts/test-mcuboot.sh
```

The first command checks installer safety/reruns, updater failure paths and the
real MCUmgr CLI over loopback UDP (including a dropped upload packet), the trial
confirmation policy, both target builds, generated partitions and watchdog
settings, image size and RSA signature. The simulator runs MCUboot's RSA and
swap-offset tests across its supported simulated flash geometries. Neither
suite exercises the physical H755 flash controller, PHY, ST-LINK or WSL host.
