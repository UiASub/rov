#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
if [[ "${1:-}" == --help ]]; then
    echo "Usage: $0 [extra CMake arguments]"; exit 0
fi
[[ -x "$workspace/.venv/bin/west" ]] || {
    echo "Run $project_dir/scripts/install-zephyr.sh first." >&2; exit 1;
}
export PATH="$workspace/.venv/bin:$PATH"
export ZEPHYR_BASE="$workspace/zephyr"
if [[ -d "$workspace/sdk" ]]; then
    export ZEPHYR_SDK_INSTALL_DIR="$workspace/sdk"
fi
cd "$workspace"
exec west build -p always -b nucleo_h755zi_q/stm32h755xx/m7 \
    -d "$project_dir/build-blinky" "$project_dir" -- "$@"
