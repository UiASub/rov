#!/usr/bin/env bash
# Initial provisioning / recovery. Normal updates use ota.py over Ethernet.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
mode=ota
case "${1:-}" in
    --blinky) mode=blinky; shift ;;
    --help) echo "Usage: $0 [--blinky] [extra west flash arguments]"; exit 0 ;;
esac
[[ -x "$workspace/.venv/bin/west" ]] || { echo "Install Zephyr first." >&2; exit 1; }
workspace="$(cd "$workspace" && pwd)"
export PATH="$workspace/.venv/bin:$PATH"
export ZEPHYR_BASE="$workspace/zephyr"
cd "$workspace"
exec west flash -d "$project_dir/build-$mode" --runner openocd "$@"
