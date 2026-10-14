#!/usr/bin/env bash
# Complete Linux/WSL setup; only system packages require elevation.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
skip_sdk=0
skip_system=0
usage() {
    echo "Usage: $0 [--workspace PATH] [--skip-sdk] [--skip-system]"
    echo "Ubuntu/Debian, Arch/CachyOS, Fedora and WSL2; installs host tools, uv and OTA tooling."
}
while (($#)); do
    case "$1" in
        --workspace) workspace="${2:?missing workspace path}"; shift 2 ;;
        --skip-system) skip_system=1; shift ;;
        --skip-sdk) skip_sdk=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
[[ "$(uname -s)" == Linux ]] || { echo "Run on Linux or inside WSL2." >&2; exit 1; }
# Reject foreign workspaces before installing or modifying anything.
if [[ -d "$workspace/.west" || -f "$workspace/manifest/west.yml" ]]; then
    if [[ ! -f "$workspace/manifest/west.yml" ]] ||
        ! cmp -s "$project_dir/west.yml" "$workspace/manifest/west.yml"; then
        echo "Workspace manifest differs; use a new --workspace path." >&2; exit 1;
    fi
fi
# shellcheck source=/dev/null
source "$project_dir/scripts/linux-prerequisites.sh"
if (( ! skip_system )); then install_linux_prerequisites; fi
for tool in git ninja make gcc curl xz wget file go; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; rerun without --skip-system." >&2; exit 1; }
done
bootstrap_uv
mkdir -p "$workspace/manifest"
workspace="$(cd "$workspace" && pwd)"
cp "$project_dir/west.yml" "$workspace/manifest/west.yml"
if [[ ! -x "$workspace/.venv/bin/python" ]]; then
    uv venv --python 3.12 "$workspace/.venv"
fi
uv pip install --python "$workspace/.venv/bin/python" 'west==1.4.0' 'cmake==3.31.6' pip
export PATH="$workspace/.venv/bin:$PATH"
cd "$workspace"
if [[ ! -d .west ]]; then
    west init -l manifest
fi
west update --narrow --fetch-opt=--depth=1
uv pip install --python "$workspace/.venv/bin/python" \
    -r zephyr/scripts/requirements-base.txt -r bootloader/mcuboot/scripts/requirements.txt
west config --local build.board nucleo_h755zi_q/stm32h755xx/m7
if (( ! skip_sdk )); then
    west sdk install --version 0.17.2 --toolchains arm-zephyr-eabi --install-dir "$workspace/sdk"
fi
ZEPHYR_WORKSPACE="$workspace" "$project_dir/scripts/install-ota-tools.sh"
printf '\nReady. Activate with: source %q\n' "$workspace/.venv/bin/activate"
