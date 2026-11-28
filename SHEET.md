# `wm/sheet` — Native Limbo ODS Spreadsheet for Inferno

`wm/sheet` (`appl/wm/sheet.b` -> `dis/wm/sheet.dis`) is a lightweight, native **Limbo** spreadsheet application for **inferno64sdl** that reads, evaluates, and interactively edits **OpenDocument Spreadsheet (`.ods`)** workbooks directly inside Inferno's window manager (`wm/wm`) using only standard Inferno modules (`sys`, `draw`, `wmclient`, `zip`, `xml`, `bufio`, `string`, `math`).

It was built with a strict minimalist philosophy: implement all the ODS parsing, formula evaluation, recalculation, formatting, and interactive UI performance required for real-world multi-sheet financial planning workbooks, and nothing more.

---

## Launching & Usage

### From the Desktop
- **Start Menu**: Click the Inferno start button -> **Sheet** (configured in `lib/wmsetup` via `menu Sheet {wmapp /Apps/!Sheet}`).
- **Apps Filer**: Open **Apps** -> double-click `!Sheet` (`Apps/!Sheet/`).

### From the Inferno Shell
```sh
wm/sheet                            # Opens the default workbook & mounts /mnt/sheet
wm/sheet /path/to/file.ods          # Opens a specific .ods or .s9 file & mounts /mnt/sheet
wm/sheet -m /mnt/mysh file.ods      # Mounts the synthetic filesystem at a custom path
wm/sheet -s [file.ods|file.s9]      # Headless server mode (mounts /mnt/sheet without GUI)
wm/sheet -t [file.ods]              # Headless CLI formula verification
```

### From macOS Host Terminal
```sh
./start-inferno.sh --shell /dis/sh.dis -c "wm/sheet -t; echo halt > /dev/sysctl"
```

---

## Interactive Controls

| Action | Control |
| :--- | :--- |
| **Select cell** | Left-click any grid cell, or use `Up` / `Down` / `Left` / `Right` / `Tab` |
| **Page / jump** | `Page Up` / `Page Down` (15 rows), `Home` (top-left `A1`) |
| **Vertical scroll** | Mouse wheel / two-finger trackpad scroll, or click/drag the right scrollbar |
| **Horizontal scroll** | Click/drag the bottom scrollbar, or move right/left with arrow keys |
| **Switch sheet** | Left-click any sheet tab along the bottom bar |
| **Edit selected cell** | Click the formula bar, press `Enter`, or start typing any printable character |
| **Commit edit** | Press `Enter` (evaluates & recalculates the entire workbook immediately) |
| **Cancel edit** | Press `Esc` |
| **Clear cell** | Press `Delete` or `Backspace` (outside edit mode) |

### Input Value Parsing on Edit
When committing an edit:
- Leading `=` -> stored as a formula (e.g. `=SUM(A1:A10)`, `=B2*1.05`).
- Trailing `%` -> stored as a `percentage` value (e.g. `7.5%` -> `0.075`).
- Numeric literal (`-`, digits, `.`) -> stored as a `float`.
- Empty input -> clears the cell.
- Anything else -> stored as a `string`.

---

## Architecture & Data Model

The entire application lives in `appl/wm/sheet.b` and is structured into five clean layers:

### 1. Core Data Structures
- **`Book`**: holds `filename`, `sheets: array of ref Sheet`, and `names: list of ref NamedRange`.
- **`Sheet`**: holds `name`, dimensions (`nrows`, `ncols`), sparse `rows: array of array of ref Cell`, and per-sheet viewport/selection state (`cur_r`, `cur_c`, `top_r`, `left_c`).
- **`Cell`**: stores raw inputs (`formula`, `vtype`, `raw_num`, `raw_str`), ODS cached values (`cached_num`, `cached_str`, `has_cached` for `-t` verification), computed `val: Val`, pre-formatted display string `disp`, and memoization `state` (`0` uncomputed, `1` visiting, `2` done).
- **`Val`**: tagged value (`VEMPTY`, `VNUM`, `VSTR`, `VNA`, `VERR`).
- **`NamedRange`**: maps a workbook-level name (e.g. `annual_spend`, `inflation`) to its resolved `(sheetidx, row, col)`.

### 2. ODS Reader (`load_ods`)
1. Opens the `.ods` ZIP archive using Inferno's `zip` module (`appl/lib/zip.b` was fixed to handle ZIP bit-3 data descriptors, `Flocaldatadescr`, by falling back to Central Directory sizes when local header sizes are zero).
2. Binds `#s` onto `/chan` (required by `zip->openfile`) and extracts `content.xml` to a temporary file `/tmp/sheet_<pid>.xml` (removed after parsing).
3. Streams `content.xml` with Inferno's `xml` pull-parser (`p.next()`, `p.down()`, `p.up()`), extracting:
   - `<table:table>` sheets and names
   - `<table:table-row>` with `table:number-rows-repeated`
   - `<table:table-cell>` / `<table:covered-table-cell>` with `table:number-columns-repeated`, `office:value-type`, `table:formula`, `office:value`, and nested `<text:p>` / `<text:s text:c="...">` text content
   - `<table:named-expressions>` / `<table:named-range>` definitions
4. Resolves all named range addresses once all sheets are loaded.

### 3. Formula Engine (`eval_cell`, `recalc`)
Implements a recursive-descent parser and evaluator supporting both OpenFormula (`of:=...`) and standard (`=...`) syntax:
- **Operators & Precedence**:
  1. Comparisons: `=`, `<>`, `<`, `<=`, `>`, `>=` (including string and numeric comparisons)
  2. Addition / subtraction: `+`, `-`
  3. Multiplication / division: `*`, `/`
  4. Exponentiation: `^`
  5. Unary `+` / `-` and parenthesized subexpressions `(...)`
- **References**:
  - ODF bracketed references: `[.E4]`, `[.$B$2]`, `[$'Inputs and quick look outputs'.$C$15]`, `[.A1:.Z10]`
  - Bare A1-style references and ranges: `A1`, `$C$15`, `B2:B20`
  - Workbook named ranges (case-insensitive)
- **Built-in Functions**:
  - `SUM(...)` — sums ranges and scalar arguments (ignores empty/string cells)
  - `MAX(...)` — maximum across ranges and scalar expressions (e.g. `MAX([.Z4]-[.AB4];0)`)
  - `IF(cond; then_expr [; else_expr])` — short-circuit conditional evaluation
  - `ISBLANK(ref)` — true when the referenced cell evaluates to `VEMPTY`
  - `TRUE()` — boolean `1.0`
  - `IFNA(expr; fallback)` — returns `fallback` when `expr` evaluates to `#N/A` (`VNA`)
  - `MATCH(lookup; range [op rhs]; match_type)` — 1-based exact lookup supporting both standard range matching and array-comparison predicates such as `MATCH(TRUE(); [.D4:.D64]<0; 0)`
  - `INDEX(range; row_num [; col_num])` — 1-based indexed cell lookup
- **Evaluation & Cycle Safety**:
  - `recalc(book)` resets all cell states to `0` and evaluates every cell lazily with memoization (`state == 2`), returning `#CYCLE` if a circular dependency (`state == 1`) is encountered.
  - Pre-formats `cell.disp` immediately after evaluation so rendering never runs floating-point formatting in the draw loop.

### 4. Display Formatting (`format_cell`)
- **`percentage`**: displays whole percentages as `10%`, fractional percentages as `7.5%`.
- **Whole numbers**: formatted with thousands separators (`120,000`), except 4-digit years (`1900`–`2200`) which display without commas (`2026`).
- **Decimals**: formatted to 2 decimal places (`%.2f`).
- **Errors**: `#N/A`, `#CYCLE`, `#NAME?`, `#DIV/0!`.

### 5. Rendering & Performance Architecture
Designed to stay smooth even on large maximized displays (e.g. 2560×1440 with 1,000+ visible cells):
- **Typography & Layout**: Uses bold Bitstream Vera Sans (`/fonts/vera/verabd/verabd.18.font`) with generous row height (`ROW_H=30`), header/formula/tab bars, crisp `#d4d4d8` grid lines, `#2563eb` active cell highlight, and right-aligned numeric columns via `font.width()`.
- **Offscreen Double-Buffering**: Renders into a window-sized offscreen `bufimg` (explicitly released before reallocation on resize) and flushes to `win.image` in one blit.
- **Incremental Scroll Blitting**:
  - **Vertical scroll**: blits the overlapping rows inside `bufimg` with a single `img.draw()` and renders only the newly exposed row band (`draw_row_band`).
  - **Horizontal scroll**: blits overlapping columns (headers + all visible rows) in a single `img.draw()` and renders only the newly exposed column band (`draw_col_band`).
  - **Selection-only moves**: redraws only the old and new cell (`draw_single_cell`) plus the formula bar, copying just those dirty sub-rectangles (`blit_subrect`) to the window.
- **Fast Grid Lines**: Uses 1-pixel `img.draw()` rectangles instead of `img.line()` polygon rasterization, and draws vertical grid lines once per column across full grid height during full redraws.
- **Input Coalescing & Drag Capture**:
  - Coalesces mouse-wheel bursts (`DrainW`), scrollbar drag pointer streams (`DrainD`), and held keyboard repeats (`KbdLoop`).
  - Captures scrollbar drag mode (`vscroll` / `hscroll`) on button press so dragging continues smoothly even if the pointer drifts outside the 16 px scrollbar track.
  - Works in tandem with `emu/port/win-sdl3.c`'s bounded SDL3 event-drain loop (32 events max per frame + motion coalescing) and `start-inferno.sh`'s 256 MB image pool (`-pimage=256m`).

---

## Plan 9 / Inferno Integration: `/mnt/sheet` & `.s9` Format

`wm/sheet` exposes the live workbook as a **9P/Styx synthetic filesystem** mounted at `/mnt/sheet` (using `styx(2)` and `styxservers(2)`), serialized with the GUI event loop over Limbo channels (`navc` and `reqc`). Any Inferno shell script, Acme command, or external program can read and modify cells, named ranges, and sheets with standard file operations, and every write immediately recalculates and updates the live GUI window.

### 1. Live Filesystem Layout (`/mnt/sheet`)

- **New shells** opened from the Start menu after `wm/sheet` is running (or the shell that ran `wm/sheet &`) inherit `/mnt/sheet` automatically.
- **Already-open shells / Acme windows** have their own forked namespaces (`FORKNS`). Attach them to the running `wm/sheet` instance at any time via its loopback Styx listener (dynamically bound to `tcp!127.0.0.1!19900..19919` and published to `/tmp/sheet.addr`, auto-mounted by `Apps/!Shell/!Run` and `Apps/!Acme/!Run`):
  ```sh
  mount -A `{cat /tmp/sheet.addr} /mnt/sheet
  ```

```text
/mnt/sheet/
├── ctl                       # Control commands (read status, write commands)
├── event                     # Blocking change-notification stream (set / recalc / load)
├── index                     # Sheet list: "<id>\t<nrows>\t<ncols>\t<name>\n"
├── apply                     # Write .s9 patch lines atomically (write-only)
├── names/                    # Workbook named ranges (read = value, write = set + recalc)
│   ├── annual_spend
│   ├── inflation
│   ├── real_growth
│   ├── stock_growth
│   └── Withdrawal_rate
└── sheets/
    └── <id>/
        ├── name              # Sheet title
        ├── tsv               # Evaluated sheet as tab-separated values
        ├── raw               # Sheet cells in .s9 format
        ├── val/<A1>          # Read-only evaluated value (e.g. 120000, 10%, 67)
        └── cell/<A1>         # Read/write raw input or formula (write triggers recalc)
```

### 2. Control Commands (`/mnt/sheet/ctl`)
- `recalc` — force full recalculation and GUI redraw.
- `batch on` / `batch off` — defer recalculation during multi-cell writes, then recalculate and redraw once on `batch off`.
- `sheet <id-or-name>` — switch the active sheet tab in the GUI.
- `save <path>` — export the workbook in plain-text `.s9` format.
- `load <path>` — load a `.s9` or `.ods` workbook (auto-detected by ZIP `PK` magic vs text).

### 3. Shell Scripting Examples

```sh
# Read current spending, withdrawal rate, and FIRE outputs
cat /mnt/sheet/names/annual_spend
cat /mnt/sheet/names/Withdrawal_rate
cat /mnt/sheet/sheets/1/val/C20    # P1: Age when 1st batch runs out
cat /mnt/sheet/sheets/1/val/E20    # P2: Age when 1st batch runs out
cat /mnt/sheet/sheets/1/val/C22    # P1: Age when all investments run out
cat /mnt/sheet/sheets/1/val/E22    # P2: Age when all investments run out

# Change the withdrawal rate (GUI updates live; also writable via sheets/1/cell/C13)
echo 3.5% > /mnt/sheet/names/Withdrawal_rate

# Update spending, growth, or an individual age/investment cell live
echo 140000 > /mnt/sheet/names/annual_spend
echo 8% > /mnt/sheet/names/stock_growth
echo 45 > /mnt/sheet/sheets/2/cell/B4

# Batch-update multiple cells with one recalculation
echo 'batch on' > /mnt/sheet/ctl
echo 110000 > /mnt/sheet/names/annual_spend
echo 3.5% > /mnt/sheet/names/inflation
echo 'batch off' > /mnt/sheet/ctl

# Sensitivity sweep across withdrawal rates
for rate in 3% 3.5% 4% 4.5% 5% {
    echo $rate > /mnt/sheet/names/Withdrawal_rate
    echo $rate '->' P1:`{cat /mnt/sheet/sheets/1/val/C20} P2:`{cat /mnt/sheet/sheets/1/val/E20}
}

# Sensitivity sweep across annual spending
for spend in 90000 100000 110000 120000 130000 140000 150000 {
    echo $spend > /mnt/sheet/names/annual_spend
    echo $spend '->' P1:`{cat /mnt/sheet/sheets/1/val/C20} P2:`{cat /mnt/sheet/sheets/1/val/E20}
}

# Save & reload plain-text .s9 snapshot
echo 'save /tmp/plan.s9' > /mnt/sheet/ctl
echo 'load /tmp/plan.s9' > /mnt/sheet/ctl
```

### 4. Plain-Text Interchange Format (`.s9`)

Line-oriented UTF-8 tab-separated records (`#` comments ignored) for saving, `diff`ing, version control, and patching via `/mnt/sheet/apply`:

```text
# Inferno sheet format v1
sheet	0	Instructions
sheet	1	Inputs and quick look outputs
sheet	2	Playground

name	annual_spend	1!C15
name	stock_growth	1!C5

cell	1!B5	str	Stock market growth
cell	1!C5	pct	0.1
cell	1!C15	num	120000
cell	1!C9	fml	=(1+stock_growth)/(1+inflation)-1
```

Supported cell types in `.s9`: `num`, `pct`, `str`, `fml`, and `empty` (to clear a cell). `wm/sheet` can open `.s9` files directly (`wm/sheet /tmp/plan.s9`) as well as `.ods` files.

### 5. Companion GUI: FIRE Scenario Explorer (`wm/fire` / `Apps/!Fire`)

`wm/fire` (`appl/wm/fire.b`) is a standalone Limbo/Tk client that demonstrates driving `wm/sheet` purely over 9P/Styx (`/tmp/sheet.addr` -> `/mnt/sheet`) with zero duplicated spreadsheet math, non-blocking timed reconnects, and clean unmount on exit:
- Launch from the Start menu (**FIRE**) or `/Apps/!Fire` while `Sheet` is open (or click **Connect** after opening `Sheet`).
- Adjust **Stock Growth**, **Inflation**, **Withdrawal Rate**, and **Annual Spending** with live sliders or presets (`Base`, `Conservative`, `High Infl`, `Fat FIRE`, `Lean FIRE`, `Reset`) and watch both `FIRE Explorer` and `Sheet` update in real time.
- Run one-click **Sweep Spending**, **Sweep Growth**, and **Sweep Withdrawal** sensitivity tables directly against `/mnt/sheet`.

---

## Building & Self-Testing

### Compile
```sh
MacOSX/arm64/bin/limbo -I module -g -o dis/wm/sheet.dis appl/wm/sheet.b
```

### Formula Self-Test (`-t`)
Running `wm/sheet -t [file.ods]` evaluates every formula cell from scratch and compares its computed result against the cached `office:value` stored in the `.ods` file:

```sh
./start-inferno.sh --shell /dis/sh.dis -c "wm/sheet -t; echo halt > /dev/sysctl"
```

On the reference 5-sheet financial planning workbook, this verifies **1,157 numeric formulas with 0 mismatches**.

---

## Related Files

| Path | Role |
| :--- | :--- |
| `appl/wm/sheet.b` | Full Limbo source for `wm/sheet` |
| `dis/wm/sheet.dis` | Compiled Dis bytecode |
| `appl/wm/fire.b`, `Apps/!Fire/` | FIRE Scenario Explorer GUI client driving `/mnt/sheet` over Styx |
| `Apps/!Sheet/!Run`, `!Boot`, `icons/!Sheet.{bit,mask}` | RISC OS-style `!App` bundle and toolbar icon |
| `Apps/!Shell/!Run`, `Apps/!Acme/!Run` | Auto-mount `tcp!127.0.0.1!19900` onto `/mnt/sheet` when `Sheet` is running |
| `appl/lib/zip.b` | Inferno ZIP library (patched for `Flocaldatadescr` data descriptors) |
| `lib/wmsetup` | Start menu entry (`menu Sheet {wmapp /Apps/!Sheet}`) |
| `emu/port/win-sdl3.c` | Shared native SDL3 backend (macOS & Linux) with coalesced drag/present loop |
| `start-inferno.sh` | Launcher configured with `-pimage=256m` |

---

## Scope & Limitations
- **Persistence**: Saves and loads native plain-text `.s9` workbooks via `/mnt/sheet/ctl` (`save`/`load`) and CLI; `.ods` write-back is not implemented.
- **Focused function set**: Only the OpenFormula functions listed above are implemented (unknown functions return `#NAME?`).
- **Minimal styling**: Uses clean uniform typography, grid lines, and column widths tuned for readability rather than full ODF style/chart rendering.
