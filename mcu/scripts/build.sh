#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
mode=ota
key=""
while (($#)); do
    case "$1" in
        --blinky) mode=blinky; shift ;;
        --ota) mode=ota; shift ;;
        --key) key="${2:?missing signing key path}"; shift 2 ;;
        --help) echo "Usage: $0 [--ota|--blinky] [--key PATH] [extra CMake arguments]"; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
signing_args=()
if [[ -n "$key" ]]; then
    [[ "$mode" == ota && -f "$key" ]] || {
        echo "--key requires an existing key file and an OTA build." >&2; exit 1;
    }
    key="$(realpath "$key")"
    signing_args=("-DSB_CONFIG_BOOT_SIGNATURE_KEY_FILE=\"$key\"")
fi
[[ -x "$workspace/.venv/bin/west" ]] || {
    echo "Run $project_dir/scripts/install-zephyr.sh first." >&2; exit 1;
}
workspace="$(cd "$workspace" && pwd)"
export PATH="$workspace/.venv/bin:$PATH"
export ZEPHYR_BASE="$workspace/zephyr"
if [[ -d "$workspace/sdk" ]]; then
    export ZEPHYR_SDK_INSTALL_DIR="$workspace/sdk"
fi
cd "$workspace"
if [[ "$mode" == ota ]]; then
    exec west build --sysbuild -p always -b nucleo_h755zi_q/stm32h755xx/m7 \
        -d "$project_dir/build-ota" "$project_dir" -- \
        -DEXTRA_CONF_FILE=ota.conf -DEXTRA_DTC_OVERLAY_FILE=boards/ota.overlay "${signing_args[@]}" "$@"
else
    exec west build -p always -b nucleo_h755zi_q/stm32h755xx/m7 \
        -d "$project_dir/build-blinky" "$project_dir" -- "$@"
fi
