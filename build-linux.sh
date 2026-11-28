#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

case "$(uname -s)" in
    Linux) ;;
    *)
        echo "Error: build-linux.sh is intended to run on Linux (detected $(uname -s))" >&2
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64|amd64)  objtype="amd64" ;;
    aarch64|arm64) objtype="arm64" ;;
    *)
        echo "Error: unsupported Linux architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
export objtype

INSTALL_DEPS=0
DIS_ONLY=0
FORCE_MK=0

for arg in "$@"; do
    case "$arg" in
        --deps)     INSTALL_DEPS=1 ;;
        --dis-only) DIS_ONLY=1 ;;
        --clean-mk) FORCE_MK=1 ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [options]

Automates building inferno64sdl on Linux (Omarchy/Arch, Debian/Ubuntu) with native SDL3.

Options:
  --deps      Install required system packages (pacman or apt-get) before building
  --dis-only  Rebuild only Limbo/Dis apps (appl/wm, appl/cmd, appl/lib, appl/acme)
  --clean-mk  Force re-bootstrapping mk via ./makemk.sh
  -h, --help  Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (use --help)" >&2
            exit 1
            ;;
    esac
done

if [ "$INSTALL_DEPS" -eq 1 ]; then
    if command -v pacman >/dev/null 2>&1; then
        echo "==> Installing dependencies via pacman..."
        sudo pacman -S --needed base-devel git sdl3 libpulse
    elif command -v apt-get >/dev/null 2>&1; then
        echo "==> Installing dependencies via apt-get..."
        sudo apt-get update
        sudo apt-get install -y build-essential git libsdl3-dev libpulse-dev
    else
        echo "Error: unsupported package manager; install gcc, make, SDL3, and libpulse manually." >&2
        exit 1
    fi
fi

# Ensure mkconfig targets Linux
if grep -q '^SYSHOST=MacOSX' "$ROOT/mkconfig"; then
    echo "==> Setting SYSHOST=Linux in mkconfig..."
    sed -i 's/^SYSHOST=MacOSX/SYSHOST=Linux/' "$ROOT/mkconfig"
fi

BIN_DIR="$ROOT/Linux/$objtype/bin"
export PATH="$BIN_DIR:$PATH"

mkdir -p "$ROOT/mnt/sheet" "$ROOT/tmp"

if [ "$FORCE_MK" -eq 1 ] || [ ! -x "$BIN_DIR/mk" ]; then
    echo "==> Bootstrapping mk for Linux/$objtype..."
    (cd "$ROOT" && ./makemk.sh)
fi

if [ "$DIS_ONLY" -eq 1 ]; then
    echo "==> Rebuilding Limbo/Dis targets..."
    (cd "$ROOT/appl/lib" && mk install)
    (cd "$ROOT/appl/cmd" && mk install)
    (cd "$ROOT/appl/wm" && mk install)
    (cd "$ROOT/appl/acme" && mk install)
else
    echo "==> Creating build directories and building full Inferno tree (Linux/$objtype)..."
    rm -f "$ROOT/emu/Linux/o.emu"
    (cd "$ROOT" && mk mkdirs && mk install)
fi

echo "==> Build complete! Launch with: ./start-inferno.sh"
