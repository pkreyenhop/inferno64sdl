# Sample Applications in `inferno64sdl`

`inferno64sdl` ships with both **custom applications built for this fork** (ODS spreadsheet + 9P/Styx filesystem, FIRE Scenario Explorer, embedded NetSurf 3.11, DOOM, and graphical/CLI Limbo examples) and the full suite of **Inferno desktop applications** packaged as RISC OS-style `!App` bundles in `Apps/`.

---

## How to Launch Applications

1. **Start Menu**: Click the **Inferno** button in the bottom-left taskbar.
2. **Apps Filer**: Click **Inferno → Apps** (opens `wm/filer /Apps`) and double-click any `!App` folder.
3. **Inferno Shell**:
   - Launch a `!App` bundle (sets up `$approot`, `!Boot` namespace, and session tracking):
     ```sh
     wmapp /Apps/!Sheet
     ```
   - Or run a command directly:
     ```sh
     wm/netsurf https://news.ycombinator.com
     wm/mandelbrot
     fib 20
     ```
4. **Session Persistence**: Any app launched from the Start menu or `wmapp` / `wmrun` is automatically saved to `/usr/inferno/lib/wmsession` and restored at its exact position and size across **Restart** and **Exit / reopen**.

---

## Custom `inferno64sdl` Applications

| App | Launch | Source | Description |
| :--- | :--- | :--- | :--- |
| **Led (`wm/led`)** | Start → **Led**, `wmapp /Apps/!Led`, or `wm/led [file\|dir]` | `appl/wm/led.b` | Lightweight Zed-inspired Limbo IDE with directory tree sidebar, multi-tab editing, Limbo syntax highlighting, auto-indent, clipboard (`Cmd/Alt+C/V/X`), and integrated `/dis/limbo.dis` compilation (`Ctrl+B`) with clickable error diagnostics. |
| **Sheet (`wm/sheet`)** | Start → **Sheet**, `wmapp /Apps/!Sheet`, or `wm/sheet [file.ods\|file.s9]` | `appl/wm/sheet.b` | Native Limbo OpenDocument Spreadsheet (`.ods`) and `.s9` viewer/evaluator with multi-sheet tabs, formula engine, incremental scroll blitting, and a live **9P/Styx filesystem at `/mnt/sheet`** (`-s` headless server, `-t` CLI self-test). See [SHEET.md](SHEET.md). |
| **FIRE Scenario Explorer (`wm/fire`)** | Start → **FIRE**, `wmapp /Apps/!Fire`, or `wm/fire` | `appl/wm/fire.b` | Interactive Limbo/Tk client that drives `wm/sheet` live over 9P/Styx (`/tmp/sheet.addr` → `/mnt/sheet`) with real-time sliders (Stock Growth, Inflation, Withdrawal Rate, Annual Spending), presets, live outcome readouts, and spending/growth/withdrawal sensitivity sweeps. |
| **NetSurf 3.11 (`wm/netsurf`)** | Start → **NetSurf**, or `wm/netsurf [url]` | `appl/wm/netsurf.b`, `libinterp/netsurf.c` | Embedded NetSurf 3.11 web browser (`$NetSurf` builtin) supporting HTML5, CSS, Duktape JavaScript, PNG/JPEG/GIF/BMP/SVG, and native HTTPS via `libcurl`. |
| **DOOM (`wm/doom`)** | Start → **Games → Doom**, or `wm/doom [wad_path]` | `appl/wm/doom.b`, `libinterp/doom.c` | Embedded `doomgeneric` engine (`$Doom` builtin) playable with **Freedoom: Phase 1** (`lib/doom/freedoom1.wad`) or any compatible IWAD. Controls: Arrows / `W`/`S` move, `A`/`D` strafe, `F` / left-click fire, `E` / `Space` / right-click use, `1`–`7` weapons, `Esc` menu. |
| **Mandelbrot (`wm/mandelbrot`)** | `wm/mandelbrot` | `appl/wm/mandelbrot.b` | Interactive graphical Mandelbrot fractal explorer with left-click zoom in, right-click zoom out, `+`/`-` iteration control, `r` reset, and live window resize. |
| **Fibonacci (`fib`)** | `fib <n>` | `appl/cmd/fib.b` | Minimal CLI Limbo recursive Fibonacci benchmark/example (e.g. `fib 20`). |
| **NetSurf Stress (`nsstress`)** | `nsstress` | `appl/cmd/nsstress.b` | Automated headless stress test exercising `$NetSurf` against Hacker News, DuckDuckGo Lite, and Wikipedia. |

---

## Core Desktop & Productivity

| App | Bundle | Command | Description |
| :--- | :--- | :--- | :--- |
| **Shell** | `Apps/!Shell` | `wm/sh` | Interactive Inferno `sh` terminal with host clipboard (`Cmd/Alt+C` / `Cmd/Alt+V`) and automatic `/mnt/sheet` mounting when Sheet is running. |
| **Acme** | `Apps/!Acme` | `acme` | Plan 9 / Inferno programmer's editor & shell environment with mouse chording, host clipboard (`Cmd/Alt+C` / `Cmd/Alt+V`), and automatic `/mnt/sheet` mounting. |
| **Edit** | `Apps/!Edit` | `wm/edit` | Lightweight GUI text editor. |
| **Vixen** | `Apps/!Vixen` | `wm/vixen` | Vi-style modal text editor inside `wm`. |
| **Charon** | `Apps/!Web` | `charon` | Native Limbo web browser with TLS 1.3, HTML 4.01, and Gemini protocol support. |
| **Filer** | `Apps/!Filer` | `wm/dir` / `wm/filer` | Graphical file & directory browser with `!App` bundle launching. |
| **Manual** | `Apps/!Manual` | `wm/man` | Graphical Inferno manual page browser. |
| **Mail** | `Apps/!Mail` | `wm/readmail` | Inferno email reader. |
| **EPub** | `Apps/!EPub` | `ebook/ebook` | E-book reader (opens books from `/lib/ebook`). |
| **View** | `Apps/!View` | `wm/view` | Image viewer (`.bit`, PNG, JPEG, GIF). |
| **Pinboard** | *(desktop)* | `wm/pinboard` | RISC OS-style desktop backdrop & icon surface serving `/chan/pinboard`. |

---

## System & Development Tools

| App | Bundle | Command | Description |
| :--- | :--- | :--- | :--- |
| **Debugger** | `Apps/!Debugger` | `wm/deb` | Graphical Limbo / Dis source-level debugger. |
| **Dis Manager** | `Apps/!DisManager` | `wm/rt` | Runtime Dis module & compilation manager (JIT / interpreter toggle). |
| **Task Manager** | `Apps/!TaskManager` | `wm/task` | Live process monitor & killer for running Dis threads. |
| **Memory Monitor** | `Apps/!Memory` | `wm/memory` | Real-time visualization of Inferno memory pools (`main`, `heap`, `image`). |
| **Chars** | `Apps/!Chars` | `wm/unibrowse` | Unicode character & font glyph browser. |
| **About** | `Apps/!About` | `wm/about` | System information dialog. |

---

## Utilities & Graphics Demos

| App | Bundle | Command | Description |
| :--- | :--- | :--- | :--- |
| **Calculator** | `Apps/!Calc` | `wm/tkcalc` | Desktop calculator. |
| **Calendar** | `Apps/!Calendar` | `wm/calendar` | Monthly calendar & schedule viewer. |
| **Clock** | `Apps/!Clock` | `wm/clock` | Analog desktop clock. |
| **Date** | `Apps/!Date` | `wm/date` | Digital date & time display. |
| **Stopwatch** | `Apps/!Stopwatch` | `wm/stopwatch` | Lap timer / stopwatch. |
| **Coffee** | `Apps/!Coffee` | `wm/coffee` | Classic animated coffee cup demo. |
| **Colours** | `Apps/!Colours` | `wm/colors` | Interactive RGB / Inferno colour palette explorer. |
| **Keyboard** | `Apps/!Keyboard` | `wm/keyboard` | On-screen virtual keyboard. |
| **Pen** | `Apps/!Pen` | `wm/pen` | Freehand drawing / scribble pad. |
| **Polyhedra** | `Apps/!Polyhedra` | `wm/polyhedra` | Interactive 3D rotating polyhedra viewer. |
| **Collide** | `Apps/!Collide` | `wm/collide` | 2D elastic particle collision physics demo. |
| **Mandelbrot (Classic)** | `Apps/!Mandelbrot` | `wm/mand` | Classic Inferno Mandelbrot fractal viewer. |

---

## Games

| App | Bundle | Command | Description |
| :--- | :--- | :--- | :--- |
| **DOOM** | *(Start → Games)* | `wm/doom` | Embedded `doomgeneric` engine with Freedoom Phase 1. |
| **Tetris** | `Apps/!Tetris` | `wm/tetris` | Classic falling-blocks puzzle game. |
| **Snake** | `Apps/!Snake` | `wm/snake` | Classic arcade snake game. |
| **Mines** | `Apps/!Mines` | `wm/sweeper` | Minesweeper puzzle game. |
| **Reversi** | `Apps/!Reversi` | `wm/reversi` | Reversi / Othello board game. |
| **Connect 4** | `Apps/!Connect4` | `wm/c4` | Four-in-a-row strategy game. |
| **Cards** | `Apps/!Cards` | `wm/cards` | Solitaire / card games suite. |
| **Bounce** | `Apps/!Bounce` | `wm/bounce` | Bouncing ball physics toy. |

---

## Structure of a `!App` Bundle

Each directory under `Apps/!<Name>/` follows the RISC OS application-folder convention invoked by `/lib/wmapp`:

```text
Apps/!MyApp/
├── !Boot                 # Optional Inferno namespace rules (nsbuild)
├── !Run                  # Executable #!/dis/sh.dis launch script
└── icons/
    ├── !MyApp.bit        # 28×28 icon bitmap
    └── !MyApp.mask       # 28×28 1-bit transparency mask
```
