# inferno64sdl

**inferno64sdl** is a fork of [caerwynj/inferno64](https://github.com/caerwynj/inferno64) (the 64-bit fork of Bell Labs' [Inferno](https://www.vitanuova.com/inferno/) distributed operating system) focused on running Inferno natively on **macOS Apple Silicon (`arm64`)** and **Omarchy / Arch Linux (`amd64` / `arm64`)** with a shared native **SDL3** GUI backend (Metal on macOS, Wayland/X11 on Linux—no XQuartz or XWayland required)—alongside a native Limbo ODS spreadsheet (`wm/sheet` + `/mnt/sheet` 9P/Styx FS), **FIRE Scenario Explorer** (`wm/fire`), and embedded **NetSurf 3.11** and **DOOM** builtin modules.

---

## What Inferno Is

Inferno represents services, devices, network interfaces, and application state as a per-process hierarchy of files (a *name space*) accessed uniformly with `open`, `read`, `write`, and `close`. Applications are written in **Limbo**, a concurrent, memory-safe language compiled to portable 64-bit **Dis** bytecode, and can import or export resources across a network using the **9P (Styx)** protocol.

---

## What `inferno64sdl` Provides

### Native macOS Apple Silicon (`MacOSX/arm64`) & SDL3 GUI
- **Native `MacOSX/arm64` target**: platform headers (`MacOSX/arm64/include/`), `mkfiles/mkfile-MacOSX-arm64`, arm64 floating-point control (`lib9/setfcr-MacOSX-arm64.c`), atomic `_tas`, and 64-bit pthreads.
- **Native SDL3 display backend** (`emu/port/win-sdl3.c`): runs natively on macOS (Metal) and Linux (Wayland/X11) without XQuartz, supporting native fullscreen, high-DPI scaling, UTF-8 text input, custom cursors, scroll wheel, coalesced mouse-motion/frame presentation for smooth dragging, host clipboard integration (`Cmd/Alt+C` copy and `Cmd/Alt+V` paste in Shell, Acme, and Sheet), Option/Cmd click emulation for 3-button mouse, and `Cmd+Q` to quit.
- **Startup launcher (`./start-inferno.sh`)**: auto-detects OS/architecture, sets `ROOT`, `PATH`, and a 256 MB image pool (`-pimage=256m`) for high-resolution displays, supports in-place **Restart** from the Start menu, and launches `wm/wm` in native SDL3 fullscreen by default (with `--windowed` and `--shell` modes).

### Desktop, Modernized GUI & Window Manager (`wm/wm`)
- **Hosted `emu` runtime** and **Limbo compiler (`limbo`)**, `mk`, `iyacc`, `ndate`, and full Dis userland (`appl/` -> `dis/`).
- **Modern cryptography & TLS 1.3** (`tls.m`, `keyring.m`) and **SQLite** builtin bindings (`$Sqlite`).
- **Neutral Modern Light GUI theme** (`libtk/colrs.c`, `libtk/utils.c`, `libtk/scale.c`, `appl/lib/titlebar.b`, `appl/wm/toolbar.b`, `appl/wm/pinboard.b`):
  - Clean 18 pt Bitstream Vera typography across widgets, menus, Shell, Acme, Sheet, and FIRE.
  - Flat 1 px hairline borders, high-contrast dark charcoal focused (`#27272a`) / slate unfocused (`#52525b`) title bars, slim `#2563eb` accent sliders, and crisp neutral white/grey surfaces.
  - Single-line taskbar buttons for minimized windows (`-`) with clean restore redraws.
- **Modern window management (`appl/wm/wm.b`)**:
  - **Direct corner & edge resizing**: grab any window corner or edge to sweep-resize directly.
  - **Maximize / restore toggle (`+`)**: remembers the window's bounds and expands to fill the screen above the taskbar; clicking `+` again restores the previous size and position.
  - **Automatic session persistence (`/usr/inferno/lib/wmsession`)**: automatically remembers open apps, exact window positions/sizes, and z-order across **Restart** and **Exit / reopen**.
- **Pre-configured desktop (`lib/wmsetup`)**:
  - Restores your last session from `/usr/inferno/lib/wmsession` (or opens **Acme** and **Shell** on first boot)
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

Clone and run the automated build script (`--deps` installs `sdl3 libpng jpeg-turbo pkg-config bison` via Homebrew):
```sh
git clone https://github.com/pkreyenhop/inferno64sdl.git
cd inferno64sdl

./build-macos.sh --deps            # Install Homebrew deps + full build
./start-inferno.sh                 # Native SDL3 fullscreen
```

After a `git pull`, rebuild quickly with `./build-macos.sh` (or `--dis-only` / `--emu-only`).

> **Note on third-party static libraries**: `libdoom.a` (from [ozkl/doomgeneric](https://github.com/ozkl/doomgeneric)), `libnetsurf.a` (from `netsurf-all-3.11`), and `lib/doom/freedoom1.wad` (from [Freedoom](https://github.com/freedoom/freedoom/releases)) are excluded from git via `.gitignore` and should be built/placed in `MacOSX/arm64/lib/` and `lib/doom/` when building from a fresh clone (or remove `doom` / `netsurf` from `emu/MacOSX/emu` and `emu/MacOSX/mkfile` for a minimal build).

### Omarchy Linux / Arch Linux (`amd64` / `arm64` — Native SDL3 / Wayland)

Clone and run the automated build script (`--deps` installs `base-devel git sdl3 libpulse` via `pacman`, or `build-essential git libsdl3-dev libpulse-dev` on Debian/Ubuntu):
```sh
git clone https://github.com/pkreyenhop/inferno64sdl.git
cd inferno64sdl

./build-linux.sh --deps            # Install dependencies + full build
./start-inferno.sh                 # Native SDL3/Wayland fullscreen
./start-inferno.sh -w -g1280x800   # Windowed mode
```

After a `git pull`, rebuild quickly with `./build-linux.sh` (or `./build-linux.sh --dis-only` for Limbo-only updates).

> **Omarchy / Hyprland notes**:
> - SDL3 runs natively on Wayland (crisp HiDPI scaling, no XWayland needed).
> - Use `Alt+C` / `Alt+V` for host <-> Inferno copy/paste (since Hyprland typically binds `Super`).
> - Place any personal `.ods` workbooks in `usr/inferno/` (gitignored) to open them with `wm/sheet`.

### Debian / Ubuntu Linux (`amd64` / `arm64`)

```sh
./build-linux.sh --deps
./start-inferno.sh
```

---

## Key Paths

| Path | Description |
| :--- | :--- |
| `start-inferno.sh` | Startup script (defaults to native SDL3 fullscreen `wm/wm`, `-pimage=256m`, restart loop) |
| `build-macos.sh`, `build-linux.sh` | Automated build scripts for macOS (`arm64`) and Linux (`amd64`/`arm64`) |
| `emu/port/win-sdl3.c` | Shared native SDL3 display, input, cursor, and clipboard backend (macOS & Linux) |
| `appl/wm/wm.b`, `appl/lib/titlebar.b`, `appl/wm/toolbar.b` | Window manager (corner/edge resize, `+` maximize toggle, session persistence), dark title bars, and taskbar |
| `libtk/colrs.c`, `libtk/utils.c`, `libtk/scale.c` | Neutral Modern Light Tk theme, 1 px hairline reliefs, 18 pt default font, and slim sliders |
| `libinterp/netsurf.c`, `module/netsurf.m`, `appl/wm/netsurf.b` | `$NetSurf` builtin module and `wm/netsurf` browser |
| `libinterp/doom.c`, `module/doom.m`, `appl/wm/doom.b` | `$Doom` builtin module and `wm/doom` frontend |
| `appl/wm/sheet.b`, `Apps/!Sheet/` | Native Limbo ODS spreadsheet app (`wm/sheet`) and `!App` bundle |
| `appl/wm/fire.b`, `Apps/!Fire/` | FIRE Scenario Explorer GUI driving `wm/sheet` over 9P/Styx |
| `appl/wm/mandelbrot.b` | Interactive graphical Mandelbrot viewer |
| `appl/cmd/fib.b`, `appl/cmd/nsstress.b` | Recursive Fibonacci CLI and NetSurf Hacker News stress test |
| `lib/wmsetup`, `lib/wmapp` | Desktop startup, session restore (`/usr/inferno/lib/wmsession`), `!App` launcher, and Start menu |
