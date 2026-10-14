#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
workspace="$(cd "$workspace" && pwd)"
export ZEPHYR_WORKSPACE="$workspace"
export MCUMGR="$workspace/.venv/bin/mcumgr"
[[ -x "$MCUMGR" ]] || { echo "Run scripts/install-ota-tools.sh first." >&2; exit 1; }
export PATH="$workspace/.venv/bin:$PATH"
if command -v shellcheck >/dev/null; then
    shellcheck "$project_dir"/scripts/*.sh
fi
for script in "$project_dir"/scripts/*.sh; do bash -n "$script"; done
python "$project_dir/scripts/test_install.py"
python "$project_dir/tests/test_ota.py"
test_binary="$(mktemp)"
trap 'rm -f "$test_binary"' EXIT
cc -std=c11 -Wall -Wextra -Werror -I "$project_dir/src" \
    "$project_dir/tests/ota_policy.c" -o "$test_binary"
"$test_binary"
"$project_dir/scripts/build.sh" --blinky
"$project_dir/scripts/build.sh" --ota
python "$project_dir/scripts/verify-build.py"
