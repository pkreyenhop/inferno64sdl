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

run_wm() {
    FS="$1"
    shift
    RESTART_FLAG="$ROOT/tmp/restart"
    mkdir -p "$ROOT/tmp"
    while :; do
        rm -f "$RESTART_FLAG"
        if INFERNO_FULLSCREEN="$FS" "$EMU" -pimage=256m -r "$ROOT" "$@" /dis/wm/wm.dis; then
            rc=0
        else
            rc=$?
        fi
        if [ -f "$RESTART_FLAG" ]; then
            rm -f "$RESTART_FLAG"
            continue
        fi
        exit "$rc"
    done
}

case "${1:-}" in
    --shell|-s)
        shift
        exec "$EMU" -r "$ROOT" "$@"
        ;;
    --windowed|-w)
        shift
        run_wm 0 "$@"
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
            run_wm 0 "$@"
        else
            run_wm 1 "$@"
        fi
        ;;
esac
