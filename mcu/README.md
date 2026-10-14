# ROV microcontroller

Based on [K2-Zephyr](https://github.com/UiASub/K2-Zephyr), inspected at
`38535e1c8b751f06aa49094dfef5e4613c30eedb`. Target: NUCLEO-H755ZI-Q,
STM32H755 M7 (`nucleo_h755zi_q/stm32h755xx/m7`), matching K2's current board.
The M4 core is not used. Zephyr 4.2.0 and SDK 0.17.2 match K2.

## Install on Linux or WSL2

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) and host
packages first. Run the appropriate command yourself:

```sh
# Debian/Ubuntu (including Ubuntu in WSL2)
sudo apt-get install --no-install-recommends \
  git ninja-build make gcc g++ xz-utils wget file gperf device-tree-compiler openocd
# Fedora
sudo dnf install git ninja-build make gcc gcc-c++ xz wget file gperf dtc openocd
# Arch/CachyOS
sudo pacman -S --needed git ninja make gcc xz wget file gperf dtc openocd
```

From the repo root:

```sh
./mcu/scripts/install-zephyr.sh
source mcu/.zephyr/.venv/bin/activate
```

The script uses uv-managed Python 3.12, pins west and CMake, fetches only the
modules needed for this board, and installs the ARM SDK. It can be rerun after
an interrupted install. It does not upgrade OS packages or delete workspaces.
Use `--workspace PATH` (and `ZEPHYR_WORKSPACE=PATH` for subsequent builds) for
an external workspace, or `--skip-sdk` for an existing toolchain. A different
manifest is rejected rather than overwriting another project's workspace.
Generated dependencies, SDK, virtual environment and builds are ignored by git.

On WSL2, keep the checkout in the Linux filesystem (e.g. `~/dev/rov`). Use
[usbipd-win](https://learn.microsoft.com/windows/wsl/connect-usb) to attach the
ST-LINK USB device to WSL for initial flashing; install Linux OpenOCD and give
your user access to ST-LINK using the distro's udev rules. Ethernet updates
need a route from WSL to the board; mirrored networking on supported Windows
11 systems is the easiest direct-link setup. Native Windows is not required.

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
# Requires Go; installs a pinned Apache MCUmgr CLI in the workspace venv.
./mcu/scripts/install-ota-tools.sh
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
