#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${ZEPHYR_WORKSPACE:-$project_dir/.zephyr}"
workspace="$(cd "$workspace" && pwd)"
mcuboot="$workspace/bootloader/mcuboot"
git -C "$mcuboot" submodule update --init --depth 1 ext/mbedtls
# MCUboot's pinned Mbed TLS has an unused temporary flagged by recent GCC.
# Keep other warnings as errors; this changes no simulator behavior.
export CFLAGS="${CFLAGS:-} -Wno-error=unused-but-set-variable"
cargo test --manifest-path "$mcuboot/sim/Cargo.toml" --features sig-rsa,swap-offset
