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
wm/sheet                        # Opens the default workbook
wm/sheet /path/to/file.ods      # Opens a specific .ods file
wm/sheet -t                     # Headless CLI formula verification on the default workbook
wm/sheet -t /path/to/file.ods   # Headless CLI formula verification on a specific .ods file
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
- **Typography & Layout**: Uses bold Bitstream Vera Sans (`/fonts/vera/verabd/verabd.16.font`, 19 px) with generous row height (`ROW_H=28`), header/formula/tab bars, crisp `#b8b8b8` grid lines, and right-aligned numeric columns via `font.width()`.
- **Offscreen Double-Buffering**: Renders into a window-sized offscreen `bufimg` (explicitly released before reallocation on resize) and flushes to `win.image` in one blit.
- **Incremental Scroll Blitting**:
  - **Vertical scroll**: blits the overlapping rows inside `bufimg` with a single `img.draw()` and renders only the newly exposed row band (`draw_row_band`).
  - **Horizontal scroll**: blits overlapping columns (headers + all visible rows) in a single `img.draw()` and renders only the newly exposed column band (`draw_col_band`).
  - **Selection-only moves**: redraws only the old and new cell (`draw_single_cell`) plus the formula bar, copying just those dirty sub-rectangles (`blit_subrect`) to the window.
- **Fast Grid Lines**: Uses 1-pixel `img.draw()` rectangles instead of `img.line()` polygon rasterization, and draws vertical grid lines once per column across full grid height during full redraws.
- **Input Coalescing & Drag Capture**:
  - Coalesces mouse-wheel bursts (`DrainW`), scrollbar drag pointer streams (`DrainD`), and held keyboard repeats (`KbdLoop`).
  - Captures scrollbar drag mode (`vscroll` / `hscroll`) on button press so dragging continues smoothly even if the pointer drifts outside the 16 px scrollbar track.
  - Works in tandem with `emu/MacOSX/win-sdl3.c`'s bounded SDL3 event-drain loop (32 events max per frame + motion coalescing) and `start-inferno.sh`'s 256 MB image pool (`-pimage=256m`).

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
| `Apps/!Sheet/!Run`, `!Boot`, `icons/!Sheet.{bit,mask}` | RISC OS-style `!App` bundle and toolbar icon |
| `appl/lib/zip.b` | Inferno ZIP library (patched for `Flocaldatadescr` data descriptors) |
| `lib/wmsetup` | Start menu entry (`menu Sheet {wmapp /Apps/!Sheet}`) |
| `emu/MacOSX/win-sdl3.c` | Native SDL3 backend with coalesced drag/present loop |
| `start-inferno.sh` | Launcher configured with `-pimage=256m` |

---

## Scope & Limitations
- **In-memory editing**: Cell edits recalculate live across all sheets, but `.ods` write-back/saving is not implemented.
- **Focused function set**: Only the OpenFormula functions listed above are implemented (unknown functions return `#NAME?`).
- **Minimal styling**: Uses clean uniform typography, grid lines, and column widths tuned for readability rather than full ODF style/chart rendering.
