#!/usr/bin/env sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

case "$(uname -s)" in
    Darwin) SYSHOST="MacOSX" ;;
    Linux)  SYSHOST="Linux" ;;
    *)      SYSHOST="$(uname -s)" ;;
esac

case "$(uname -m)" in
    arm64|aarch64) objtype="arm64" ;;
    x86_64|amd64)  objtype="amd64" ;;
    *)             objtype="$(uname -m)" ;;
esac
export objtype

BIN_DIR="$ROOT/$SYSHOST/$objtype/bin"
EMU="$BIN_DIR/emu"

if [ ! -x "$EMU" ]; then
    echo "Error: Inferno emu binary not found at $EMU" >&2
    exit 1
fi

export PATH="$BIN_DIR:$PATH"

case "${1:-}" in
    --shell|-s)
        shift
        exec "$EMU" -r "$ROOT" "$@"
        ;;
    --windowed|-w)
        shift
        INFERNO_FULLSCREEN=0 exec "$EMU" -pimage=256m -r "$ROOT" "$@" /dis/wm/wm.dis
        ;;
    --help|-h)
        cat <<EOF
Usage: $(basename "$0") [options] [emu args...]

By default, launches the Inferno window manager (wm/wm) in native SDL3 fullscreen.

Options:
  -w, --windowed  Launch wm/wm in a window instead of fullscreen
  -s, --shell     Start the interactive Inferno shell instead of wm/wm
  -h, --help      Show this help message

Examples:
  $(basename "$0")                                # Launch wm/wm in fullscreen
  $(basename "$0") -w -g1280x800                  # Launch wm/wm in a 1280x800 window
  $(basename "$0") --shell                        # Start Inferno interactive shell
  $(basename "$0") --shell /dis/sh.dis -c 'ls'    # Run a command inside Inferno
EOF
        exit 0
        ;;
    *)
        HAS_GEOM=0
        for arg in "$@"; do
            case "$arg" in
                -g*) HAS_GEOM=1 ;;
            esac
        done

        if [ "$HAS_GEOM" -eq 1 ]; then
            INFERNO_FULLSCREEN=0 exec "$EMU" -pimage=256m -r "$ROOT" "$@" /dis/wm/wm.dis
        else
            INFERNO_FULLSCREEN=1 exec "$EMU" -pimage=256m -r "$ROOT" "$@" /dis/wm/wm.dis
        fi
        ;;
esac
