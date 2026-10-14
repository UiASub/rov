#!/usr/bin/env bash
# User-owned workspace; never installs system packages or replaces other workspaces.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
skip_sdk=0
usage() {
    echo "Usage: $0 [--workspace PATH] [--skip-sdk]"
    echo "Linux and WSL2; requires uv, git, ninja, make, gcc, xz, wget and file."
}
while (($#)); do
    case "$1" in
        --workspace) workspace="${2:?missing workspace path}"; shift 2 ;;
        --skip-sdk) skip_sdk=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
[[ "$(uname -s)" == Linux ]] || { echo "Run on Linux or inside WSL2." >&2; exit 1; }
for tool in uv git ninja make gcc xz wget file; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; see mcu/README.md for host packages." >&2; exit 1; }
done
mkdir -p "$workspace"
workspace="$(cd "$workspace" && pwd)"
# Check ownership before changing an existing west workspace.
if [[ -d "$workspace/.west" ]]; then
    if [[ ! -f "$workspace/manifest/west.yml" ]] ||
        ! cmp -s "$project_dir/west.yml" "$workspace/manifest/west.yml"; then
        echo "Workspace manifest differs; use a new --workspace path." >&2; exit 1;
    fi
else
    mkdir -p "$workspace/manifest"
    cp "$project_dir/west.yml" "$workspace/manifest/west.yml"
fi
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
printf '\nReady. Activate with: source %q\n' "$workspace/.venv/bin/activate"
