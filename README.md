# Inferno64

**Inferno64** is a 64-bit fork of the [Inferno](https://www.vitanuova.com/inferno/) distributed operating system originally created at Bell Labs. It focuses on running Inferno's **Limbo** language, **Dis** virtual machine, and **9P (Styx)** file-oriented environment on modern 64-bit hosts (`arm64`, `amd64`, `riscv64`), with native **macOS Apple Silicon (arm64)** support, an **SDL3** GUI, and embedded C libraries exposed as Limbo builtin modules.

---

## What Inferno Is

Inferno represents services, devices, network interfaces, and application state as a per-process hierarchy of files (a *name space*) accessed uniformly with `open`, `read`, `write`, and `close`. Applications are written in **Limbo**, a concurrent, memory-safe language compiled to portable **Dis** bytecode, and can import or export resources across a network using the **9P** protocol.

---

## What This Project Provides

### Core 64-Bit Inferno Environment
- **Hosted `emu` runtime** and **Limbo compiler (`limbo`)**, `mk`, `iyacc`, `ndate`, and full Dis userland (`appl/` -> `dis/`).
- **Modern cryptography & TLS 1.3** (`tls.m`, `keyring.m`) and **SQLite** builtin bindings (`$Sqlite`).
- **Desktop & Apps (`wm/wm`)**:
  - **Acme** editor (configured to open large at 72% × 85% of the display on startup)
  - **Shell (`wm/sh`)** (rc-style Inferno shell, opened automatically on startup)
  - **Charon** browser (with TLS 1.3, HTML 4.01, and Gemini protocol support)
  - **Filer**, **Brutus** markdown editor, **Pinboard**, and RISC OS-style `!App` bundles in `Apps/`
  - **Exit** option in the starter menu (`echo halt > /dev/sysctl`) for clean shutdown

### Native macOS Apple Silicon (`MacOSX/arm64`) & SDL3 GUI
- **Native `MacOSX/arm64` target**: platform headers (`MacOSX/arm64/include/`), `mkfiles/mkfile-MacOSX-arm64`, arm64 floating-point control (`lib9/setfcr-MacOSX-arm64.c`), atomic `_tas`, and 64-bit pthreads.
- **Native SDL3 display backend** (`emu/MacOSX/win-sdl3.c`): runs directly on macOS without XQuartz, supporting native fullscreen, high-DPI scaling, UTF-8 text input, custom cursors, scroll wheel, macOS clipboard integration, Option/Cmd click emulation for 3-button mouse, and `Cmd+Q` to quit.
- **Startup launcher (`./start-inferno.sh`)**: auto-detects OS/architecture, sets `ROOT` and `PATH`, and launches `wm/wm` in native SDL3 fullscreen by default (with `--windowed` and `--shell` modes).

### Builtin Modules & Included Applications
- **NetSurf 3.11 Web Browser (`$NetSurf` / `wm/netsurf`)**:
  - Embedded NetSurf 3.11 framebuffer engine (`libnetsurf.a`) with HTML5, CSS, Duktape JavaScript, PNG/JPEG/GIF/BMP/SVG, and native HTTPS via `libcurl`.
  - Accessible from the starter menu (**NetSurf**) or via `wm/netsurf [url]`.
  - Includes `nsstress` (`appl/cmd/nsstress.b`) for automated Hacker News / DDG Lite / Wikipedia navigation stress testing.
- **DOOM (`$Doom` / `wm/doom`)**:
  - Embedded `doomgeneric` engine (`libdoom.a`) bundled with the free **Freedoom: Phase 1** WAD (`lib/doom/freedoom1.wad`).
  - Accessible from **Games -> Doom** or via `wm/doom [wad_path]`.
  - Controls: Arrows or `W`/`S` move/turn, `A`/`D` strafe, `F` or left-click fire, `E`/`Space`/right-click use, `1`–`7` weapons, `Esc` menu.
- **Example Limbo Programs**:
  - **Mandelbrot Viewer (`wm/mandelbrot`)**: interactive graphical fractal explorer (`appl/wm/mandelbrot.b`) with left/right-click zoom, `+`/`-` iteration control, `r` reset, and live resize.
  - **Recursive Fibonacci (`fib`)**: CLI Limbo example (`appl/cmd/fib.b`).

---

## Quick Start (macOS arm64)

```sh
./start-inferno.sh                 # Launch wm/wm in native SDL3 fullscreen (with Acme & Shell)
./start-inferno.sh -w -g1280x800   # Launch wm/wm in a 1280x800 window
./start-inferno.sh --shell         # Start interactive Inferno shell (headless)
./start-inferno.sh --shell /dis/sh.dis -c 'fib 20'
```

---

## Building from Source

### macOS (Apple Silicon)

Install dependencies via Homebrew:
```sh
brew install sdl3 libpng jpeg-turbo pkg-config bison
```

Bootstrap `mk` and build Inferno:
```sh
export ROOT="$(pwd)"
export objtype=arm64
export PATH="$ROOT/MacOSX/$objtype/bin:$PATH"
./makemk.sh
mk mkdirs
mk install
```

### Linux (amd64 / arm64)

Install dependencies:
```sh
sudo apt-get install -y libx11-dev libxext-dev linux-libc-dev libpulse-dev
```

Set `SYSHOST=Linux` in `mkconfig`, then build:
```sh
export ROOT="$(pwd)"
export objtype=amd64   # or arm64
export PATH="$ROOT/Linux/$objtype/bin:$PATH"
./makemk.sh
mk mkdirs
mk install
```

---

## Key Paths

| Path | Description |
| :--- | :--- |
| `start-inferno.sh` | Cross-platform startup script (defaults to native SDL3 fullscreen `wm/wm`) |
| `emu/MacOSX/win-sdl3.c` | Native SDL3 display, input, cursor, and clipboard backend |
| `libinterp/netsurf.c`, `module/netsurf.m`, `appl/wm/netsurf.b` | `$NetSurf` builtin module and `wm/netsurf` browser |
| `libinterp/doom.c`, `module/doom.m`, `appl/wm/doom.b` | `$Doom` builtin module and `wm/doom` frontend |
| `appl/wm/mandelbrot.b` | Interactive graphical Mandelbrot viewer |
| `appl/cmd/fib.b`, `appl/cmd/nsstress.b` | Recursive Fibonacci CLI and NetSurf Hacker News stress test |
| `lib/wmsetup` | Desktop startup layout (Acme, Shell, Pinboard) and starter menu |
