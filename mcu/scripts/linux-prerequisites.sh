#!/usr/bin/env bash
# Sourced by install-zephyr.sh. No actions occur merely by sourcing this file.
linux_family() {
    local distro="${1:-}" related="${2:-}"
    case " $distro $related " in
        *' ubuntu '*|*' debian '*) echo apt ;;
        *' arch '*|*' cachyos '*) echo pacman ;;
        *' fedora '*) echo dnf ;;
        *) echo "Unsupported Linux distribution: $distro ($related)." >&2; return 1 ;;
    esac
}

read_linux_release() {
    # shellcheck source=/dev/null
    source /etc/os-release
}

install_linux_prerequisites() {
    local family tool missing=0
    read_linux_release
    family="$(linux_family "$ID" "${ID_LIKE:-}")"
    for tool in git ninja make gcc g++ curl wget xz file gperf dtc openocd go; do
        if ! command -v "$tool" >/dev/null; then missing=1; fi
    done
    if (( ! missing )); then return; fi
    local privilege=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || { echo "System packages need root; install sudo or use --skip-system with preinstalled tools." >&2; return 1; }
        privilege=(sudo)
    fi
    case "$family" in
        apt)
            "${privilege[@]}" apt-get update
            "${privilege[@]}" apt-get install -y --no-install-recommends \
                ca-certificates git ninja-build make gcc g++ curl wget xz-utils file \
                gperf device-tree-compiler openocd golang-go
            ;;
        pacman)
            "${privilege[@]}" pacman -S --needed --noconfirm \
                ca-certificates git ninja make gcc curl wget xz file gperf dtc openocd go
            ;;
        dnf)
            "${privilege[@]}" dnf install -y \
                ca-certificates git ninja-build make gcc gcc-c++ curl wget xz file gperf dtc openocd golang
            ;;
    esac
}

bootstrap_uv() {
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv >/dev/null; then return; fi
    local installer
    installer="$(mktemp)"
    if ! curl --fail --location --silent --show-error \
        https://astral.sh/uv/install.sh --output "$installer"; then
        rm -f "$installer"; return 1
    fi
    local result=0
    UV_NO_MODIFY_PATH=1 sh "$installer" || result=$?
    rm -f "$installer"
    if (( result != 0 )); then return "$result"; fi
    command -v uv >/dev/null || { echo "uv installation did not provide uv on PATH." >&2; return 1; }
}
