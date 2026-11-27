# inferno64sdl

**inferno64sdl** is a fork of [caerwynj/inferno64](https://github.com/caerwynj/inferno64) (the 64-bit fork of Bell Labs' [Inferno](https://www.vitanuova.com/inferno/) distributed operating system) focused on running Inferno natively on **macOS Apple Silicon (`arm64`)** with a native **SDL3** GUI backend—no XQuartz required—alongside embedded **NetSurf 3.11** and **DOOM** builtin modules.

---

## What Inferno Is

Inferno represents services, devices, network interfaces, and application state as a per-process hierarchy of files (a *name space*) accessed uniformly with `open`, `read`, `write`, and `close`. Applications are written in **Limbo**, a concurrent, memory-safe language compiled to portable 64-bit **Dis** bytecode, and can import or export resources across a network using the **9P (Styx)** protocol.

---

## What `inferno64sdl` Provides

### Native macOS Apple Silicon (`MacOSX/arm64`) & SDL3 GUI
- **Native `MacOSX/arm64` target**: platform headers (`MacOSX/arm64/include/`), `mkfiles/mkfile-MacOSX-arm64`, arm64 floating-point control (`lib9/setfcr-MacOSX-arm64.c`), atomic `_tas`, and 64-bit pthreads.
- **Native SDL3 display backend** (`emu/port/win-sdl3.c`): runs natively on macOS (Metal) and Linux (Wayland/X11) without XQuartz, supporting native fullscreen, high-DPI scaling, UTF-8 text input, custom cursors, scroll wheel, coalesced mouse-motion/frame presentation for smooth dragging, host clipboard integration (`Cmd/Alt+C` copy and `Cmd/Alt+V` paste in Shell, Acme, and Sheet), Option/Cmd click emulation for 3-button mouse, and `Cmd+Q` to quit.
- **Startup launcher (`./start-inferno.sh`)**: auto-detects OS/architecture, sets `ROOT`, `PATH`, and a 256 MB image pool (`-pimage=256m`) for high-resolution displays, supports in-place **Restart** from the Start menu, and launches `wm/wm` in native SDL3 fullscreen by default (with `--windowed` and `--shell` modes).

### Desktop & Core 64-Bit Inferno Environment
- **Hosted `emu` runtime** and **Limbo compiler (`limbo`)**, `mk`, `iyacc`, `ndate`, and full Dis userland (`appl/` -> `dis/`).
- **Modern cryptography & TLS 1.3** (`tls.m`, `keyring.m`) and **SQLite** builtin bindings (`$Sqlite`).
- **Pre-configured desktop (`lib/wmsetup`)**:
  - **Acme** editor (opens automatically at 72% × 85% of the display)
  - **Shell (`wm/sh`)** (rc-style Inferno shell, opens automatically on startup)
  - **Charon** browser (with TLS 1.3, HTML 4.01, and Gemini protocol support)
  - **Filer**, **Brutus** markdown editor, **Pinboard**, and RISC OS-style `!App` bundles in `Apps/`
  - **Restart** and **Exit** options in the starter menu for in-place restarts and clean shutdown (`echo halt > /dev/sysctl`)

### Builtin Modules & Included Applications
- **NetSurf 3.11 Web Browser (`$NetSurf` / `wm/netsurf`)**:
  - Embedded NetSurf 3.11 framebuffer engine (`libnetsurf.a`) with HTML5, CSS, Duktape JavaScript, PNG/JPEG/GIF/BMP/SVG, and native HTTPS via `libcurl`.
  - Accessible from the starter menu (**NetSurf**) or via `wm/netsurf [url]`.
  - Includes `nsstress` (`appl/cmd/nsstress.b`) for automated Hacker News / DuckDuckGo Lite / Wikipedia navigation stress testing.
- **DOOM (`$Doom` / `wm/doom`)**:
  - Embedded `doomgeneric` engine (`libdoom.a`) playable with the free **Freedoom: Phase 1** WAD (`lib/doom/freedoom1.wad`) or any compatible IWAD.
  - Accessible from **Games -> Doom** or via `wm/doom [wad_path]`.
  - Controls: Arrows or `W`/`S` move/turn, `A`/`D` strafe, `F` or left-click fire, `E`/`Space`/right-click use, `1`–`7` weapons, `Esc` menu.
- **Limbo Apps**:
  - **ODS Spreadsheet (`wm/sheet` / `Apps/!Sheet`)**: native Limbo OpenDocument Spreadsheet (`.ods`) and `.s9` viewer/evaluator (`appl/wm/sheet.b`, see [SHEET.md](SHEET.md)) with multi-sheet tabs, named ranges, formula evaluation (`SUM`, `MAX`, `IF`, `ISBLANK`, `TRUE`, `MATCH`, `INDEX`, `IFNA`, arithmetic/array comparisons), interactive editing, incremental scroll blitting, a live **9P/Styx filesystem at `/mnt/sheet`** (plus `tcp!127.0.0.1!19900`) for scripting/automation, headless server mode (`wm/sheet -s`), and CLI verification (`wm/sheet -t`). Accessible from the starter menu (**Sheet**) or `/Apps/!Sheet`.
  - **FIRE Scenario Explorer (`wm/fire` / `Apps/!Fire`)**: interactive Limbo/Tk GUI (`appl/wm/fire.b`) that drives `wm/sheet` live over 9P/Styx (`/mnt/sheet`) with real-time sliders (Stock Growth, Inflation, Withdrawal Rate, Annual Spending), one-click presets, live outcome readouts, and spending/growth/withdrawal sensitivity sweeps. Accessible from the starter menu (**FIRE**) or `/Apps/!Fire`.
  - **Mandelbrot Viewer (`wm/mandelbrot`)**: interactive graphical fractal explorer (`appl/wm/mandelbrot.b`) with left/right-click zoom, `+`/`-` iteration control, `r` reset, and live resize.
  - **Recursive Fibonacci (`fib`)**: CLI Limbo example (`appl/cmd/fib.b`).

---

## Quick Start (macOS arm64)

```sh
git clone https://github.com/pkreyenhop/inferno64sdl.git
cd inferno64sdl

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

> **Note on third-party static libraries**: `libdoom.a` (from [ozkl/doomgeneric](https://github.com/ozkl/doomgeneric)), `libnetsurf.a` (from `netsurf-all-3.11`), and `lib/doom/freedoom1.wad` (from [Freedoom](https://github.com/freedoom/freedoom/releases)) are excluded from git via `.gitignore` and should be built/placed in `MacOSX/arm64/lib/` and `lib/doom/` when building from a fresh clone (or remove `doom` / `netsurf` from `emu/MacOSX/emu` and `emu/MacOSX/mkfile` for a minimal build).

### Linux (amd64 / arm64 — Native SDL3 / Wayland & X11)

Install dependencies:
```sh
# Arch / Omarchy Linux:
sudo pacman -S --needed base-devel git sdl3 libpulse

# Debian / Ubuntu:
sudo apt-get install -y build-essential git libsdl3-dev libpulse-dev
```

Set `SYSHOST=Linux` in `mkconfig`, then build and launch:
```sh
sed -i 's/^SYSHOST=MacOSX/SYSHOST=Linux/' mkconfig
export ROOT="$(pwd)"
export objtype=amd64   # or arm64
export PATH="$ROOT/Linux/$objtype/bin:$PATH"
./makemk.sh
mk mkdirs
mk install
./start-inferno.sh
```

> **Hyprland / Wayland tip**: SDL3 runs natively on Wayland. Use `Alt+C` / `Alt+V` for host <-> Inferno copy/paste (since `Super` is usually bound by Hyprland).

---

## Key Paths

| Path | Description |
| :--- | :--- |
| `start-inferno.sh` | Startup script (defaults to native SDL3 fullscreen `wm/wm`) |
| `emu/port/win-sdl3.c` | Shared native SDL3 display, input, cursor, and clipboard backend (macOS & Linux) |
| `libinterp/netsurf.c`, `module/netsurf.m`, `appl/wm/netsurf.b` | `$NetSurf` builtin module and `wm/netsurf` browser |
| `libinterp/doom.c`, `module/doom.m`, `appl/wm/doom.b` | `$Doom` builtin module and `wm/doom` frontend |
| `appl/wm/sheet.b`, `Apps/!Sheet/` | Native Limbo ODS spreadsheet app (`wm/sheet`) and `!App` bundle |
| `appl/wm/fire.b`, `Apps/!Fire/` | FIRE Scenario Explorer GUI driving `wm/sheet` over 9P/Styx |
| `appl/wm/mandelbrot.b` | Interactive graphical Mandelbrot viewer |
| `appl/cmd/fib.b`, `appl/cmd/nsstress.b` | Recursive Fibonacci CLI and NetSurf Hacker News stress test |
| `lib/wmsetup` | Desktop startup layout (Acme, Shell, Pinboard) and starter menu |
