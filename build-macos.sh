#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

case "$(uname -s)" in
    Darwin) ;;
    *)
        echo "Error: build-macos.sh is intended to run on macOS (detected $(uname -s))" >&2
        exit 1
        ;;
esac

case "$(uname -m)" in
    arm64|aarch64) objtype="arm64" ;;
    x86_64|amd64)  objtype="amd64" ;;
    *)
        echo "Error: unsupported macOS architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
export objtype

INSTALL_DEPS=0
DIS_ONLY=0
EMU_ONLY=0
FORCE_MK=0

for arg in "$@"; do
    case "$arg" in
        --deps)     INSTALL_DEPS=1 ;;
        --dis-only) DIS_ONLY=1 ;;
        --emu-only) EMU_ONLY=1 ;;
        --clean-mk) FORCE_MK=1 ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [options]

Automates building inferno64sdl on macOS (Apple Silicon / Intel) with native SDL3.

Options:
  --deps      Install required Homebrew packages before building
  --dis-only  Rebuild only Limbo/Dis apps (appl/lib, appl/cmd, appl/wm, appl/acme)
  --emu-only  Rebuild only emu/MacOSX
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
    if ! command -v brew >/dev/null 2>&1; then
        echo "Error: Homebrew (brew) not found. Install it from https://brew.sh first." >&2
        exit 1
    fi
    echo "==> Installing dependencies via Homebrew..."
    brew install sdl3 libpng jpeg-turbo pkg-config bison
fi

# Ensure mkconfig targets MacOSX
if grep -q '^SYSHOST=Linux' "$ROOT/mkconfig"; then
    echo "==> Setting SYSHOST=MacOSX in mkconfig..."
    sed -i '' 's/^SYSHOST=Linux/SYSHOST=MacOSX/' "$ROOT/mkconfig"
fi

BIN_DIR="$ROOT/MacOSX/$objtype/bin"
export PATH="$BIN_DIR:$PATH"

mkdir -p "$ROOT/mnt/sheet" "$ROOT/tmp"

if [ "$FORCE_MK" -eq 1 ] || [ ! -x "$BIN_DIR/mk" ]; then
    echo "==> Bootstrapping mk for MacOSX/$objtype..."
    (cd "$ROOT" && ./makemk.sh)
fi

if [ "$DIS_ONLY" -eq 1 ]; then
    echo "==> Rebuilding Limbo/Dis targets..."
    (cd "$ROOT/appl/lib" && mk ROOT="$ROOT" SYSHOST=MacOSX OBJTYPE="$objtype" install)
    (cd "$ROOT/appl/cmd" && mk ROOT="$ROOT" SYSHOST=MacOSX OBJTYPE="$objtype" install)
    (cd "$ROOT/appl/wm" && mk ROOT="$ROOT" SYSHOST=MacOSX OBJTYPE="$objtype" install)
    (cd "$ROOT/appl/acme" && mk ROOT="$ROOT" SYSHOST=MacOSX OBJTYPE="$objtype" install)
elif [ "$EMU_ONLY" -eq 1 ]; then
    echo "==> Rebuilding emu/MacOSX..."
    (cd "$ROOT/emu/MacOSX" && mk ROOT="$ROOT" SYSHOST=MacOSX OBJTYPE="$objtype" install)
else
    echo "==> Creating build directories and building full Inferno tree (MacOSX/$objtype)..."
    (cd "$ROOT" && mk mkdirs && mk install)
fi

echo "==> Build complete! Launch with: ./start-inferno.sh"
