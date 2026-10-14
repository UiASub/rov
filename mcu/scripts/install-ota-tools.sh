#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
[[ -d "$workspace/.venv/bin" ]] || { echo "Install Zephyr first." >&2; exit 1; }
command -v go >/dev/null || { echo "Install Go with your distro package manager first." >&2; exit 1; }
workspace="$(cd "$workspace" && pwd)"
export GOBIN="$workspace/.venv/bin"
go install github.com/apache/mynewt-mcumgr-cli/mcumgr@5c56bd24066c780aad5836429bfa2ecc4f9a944c
