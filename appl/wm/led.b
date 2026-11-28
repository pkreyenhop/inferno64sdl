implement Led;

#
# Led — lightweight Zed-inspired Limbo IDE for Inferno
#   - Directory tree sidebar with .b/.m indicators
#   - Multi-tab editor with Limbo syntax highlighting & line numbers
#   - Integrated /dis/limbo.dis compiler with clickable error diagnostics
#   - Auto-indent, selection, mouse-wheel & scrollbar drag, Cmd/Alt+C/V/X
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;
include "keyboard.m";
include "readdir.m";
	readdir: Readdir;
include "string.m";
	str: String;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sh.m";

Led: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# Layout constants
SIDEBAR_W: con 236;
TAB_H:     con 40;
STAT_H:    con 28;
OUT_H:     con 164;
OUT_HDR_H: con 28;
GUTTER_W:  con 54;
SB_W:      con 14;
LINE_H:    con 24;
SIDE_ROW:  con 26;
TAB_W:     con 4;	# spaces per tab stop

# Palette (Zed Light — Neutral Modern)
C_BG:        con int 16rffffffff;
C_SIDEBG:    con int 16rf4f4f5ff;
C_TABBG:     con int 16rf4f4f5ff;
C_GUTTERBG:  con int 16rf8fafcff;
C_CURLINE:   con int 16rf1f5f9ff;
C_ERRLINE:   con int 16rfef2f2ff;
C_SELBG:     con int 16rbfdbfeff;
C_BORDER:    con int 16rd4d4d8ff;
C_SUBBDR:    con int 16re4e4e7ff;
C_INK:       con int 16r09090bff;
C_MUTED:     con int 16r71717aff;
C_GUTTERFG:  con int 16r94a3b8ff;
C_ACCENT:    con int 16r2563ebff;
C_ACCENTBG:  con int 16rdbeafeff;
C_ACCENTFG:  con int 16r1d4ed8ff;
C_DIRTY:     con int 16rea580cff;
C_OK:        con int 16r15803dff;
C_OKBG:      con int 16rdcfce7ff;
C_ERR:       con int 16rdc2626ff;
C_ERRBG:     con int 16rfee2e2ff;
C_SBTK:      con int 16re4e4e7ff;
C_SBTH:      con int 16ra1a1aaff;

# Limbo syntax colors
S_TEXT:      con int 16r18181bff;
S_KW:        con int 16r7c3aedff;	# purple — keywords
S_TYPE:      con int 16r0d9488ff;	# teal — builtin types
S_MOD:       con int 16r1d4ed8ff;	# cobalt — Capitalized types/modules
S_STR:       con int 16r15803dff;	# emerald — strings & chars
S_NUM:       con int 16rb45309ff;	# amber — numbers
S_CMT:       con int 16r64748bff;	# slate — # comments
S_OP:        con int 16r475569ff;	# dark slate — operators

# Token kinds
TK_TEXT, TK_KW, TK_TYPE, TK_MOD, TK_STR, TK_NUM, TK_CMT, TK_OP: con iota;

DirEntry: adt {
	name: string;
	path: string;
	isdir: int;
};

Diag: adt {
	file: string;
	line: int;	# 0-based, -1 if none
	text: string;
	iserr: int;
};

Buffer: adt {
	path: string;
	name: string;
	lines: array of string;
	dirty: int;
	cur_l: int;
	cur_c: int;
	sel_on: int;
	sel_l: int;
	sel_c: int;
	top_l: int;
	left_c: int;
};

# Global resources
display: ref Display;
f_mono: ref Font;
f_monobd: ref Font;
f_ui: ref Font;
f_uibd: ref Font;
charw := 10;

# Cached color images
c_bg, c_sidebg, c_tabbg, c_gutterbg, c_curline, c_errline, c_selbg: ref Image;
c_border, c_subbdr, c_ink, c_muted, c_gutterfg: ref Image;
c_accent, c_accentbg, c_accentfg, c_dirty, c_ok, c_okbg, c_err, c_errbg: ref Image;
c_sbtk, c_sbth: ref Image;
s_cols: array of ref Image;

# Offscreen double buffer
bufimg: ref Image;
bufw := 0;
bufh := 0;

# Workspace state
curdir := "/appl/wm";
entries: array of ref DirEntry;
side_top := 0;

tabs: array of ref Buffer;
curtab := -1;

show_out := 1;
compiling := 0;
build_ok := -1;	# -1 = idle, 1 = ok, 0 = fail
build_msg := "Ready";
diags: array of ref Diag;
out_top := 0;

# Clickable button hit rects (updated on each draw)
r_btn_save, r_btn_comp, r_btn_out: Rect;
r_tabs: array of Rect;
r_tab_xs: array of Rect;

# Mouse drag state
drag_mode := 0;	# 0=none, 1=editor sel, 2=vscroll
drag_off := 0;
last_click_ms := 0;
last_click_l := -1;
last_click_c := -1;

# Limbo keyword & builtin type tables
kw_list := array[] of {
	"adt", "alt", "array", "break", "case", "chan", "con", "continue",
	"cyclic", "do", "else", "exception", "exit", "fixed", "fn", "for",
	"hd", "if", "implement", "import", "in", "include", "iota", "len",
	"list", "load", "module", "nil", "of", "or", "pick", "raise",
	"raises", "ref", "return", "self", "spawn", "tagof", "tl", "to",
	"type", "while"
};

type_list := array[] of {
	"big", "byte", "int", "real", "string"
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	readdir = load Readdir Readdir->PATH;
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;

	if(draw == nil || wmclient == nil || readdir == nil || str == nil || bufio == nil){
		sys->fprint(sys->fildes(2), "led: failed to load required modules\n");
		raise "fail:load";
	}
	wmclient->init();
	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "led: no draw context\n");
		raise "fail:nodraw";
	}
	display = ctxt.display;
	init_resources();

	win := wmclient->window(ctxt, "Led", Wmclient->Appl);
	sz := win.displayr.size();
	ww := sz.x * 78 / 100;
	wh := sz.y * 82 / 100;
	if(ww < 860) ww = 860;
	if(wh < 580) wh = 580;
	if(ww > sz.x - 40) ww = sz.x - 40;
	if(wh > sz.y - 80) wh = sz.y - 80;
	win.reshape(((0, 0), (ww, wh)));
	win.onscreen("place");
	win.startinput("kbd" :: "ptr" :: nil);

	# Determine initial dir & file from argv
	startfile := "";
	if(argv != nil && tl argv != nil){
		arg := hd tl argv;
		(ok, d) := sys->stat(arg);
		if(ok >= 0){
			if((d.mode & Sys->DMDIR) != 0)
				curdir = cleanpath(arg);
			else {
				startfile = cleanpath(arg);
				curdir = dirname(startfile);
			}
		}
	}
	load_dir(curdir);
	if(startfile != "")
		open_file(startfile);
	else {
		# Open first .b file in curdir (prefer led.b if in /appl/wm)
		if(curdir == "/appl/wm" && sys->stat("/appl/wm/led.b").t0 >= 0)
			open_file("/appl/wm/led.b");
		else {
			for(i := 0; i < len entries; i++){
				if(!entries[i].isdir && has_suffix(entries[i].name, ".b")){
					open_file(entries[i].path);
					break;
				}
			}
		}
	}
	if(curtab < 0)
		new_untitled();

	update_title(win);
	redraw(win);

	compc := chan of (int, string, array of ref Diag);
	prev_b := 0;

	for(;;) alt {
	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		if(ctl == "exit")
			exit;
		oldimg := win.image;
		win.wmctl(ctl);
		if(win.image != nil && (win.image != oldimg || win.image.r.dx() != bufw || win.image.r.dy() != bufh))
			redraw(win);

	(ok, msg, darr) := <-compc =>
		compiling = 0;
		build_ok = ok;
		build_msg = msg;
		diags = darr;
		out_top = 0;
		show_out = 1;
		redraw(win);

	p := <-win.ctxt.ptr =>
		if(win.pointer(*p))
			break;
		if(win.image == nil)
			break;
		# Coalesce rapid drag motions
		if(p.buttons != 0 && prev_b == p.buttons){
		DrainP:
			for(;;){
				alt {
				p2 := <-win.ctxt.ptr =>
					if(p2.buttons == p.buttons)
						p = p2;
					else {
						handle_ptr(win, p, prev_b, compc);
						prev_b = p.buttons;
						p = p2;
						break DrainP;
					}
				* =>
					break DrainP;
				}
			}
		}
		handle_ptr(win, p, prev_b, compc);
		prev_b = p.buttons;

	k := <-win.ctxt.kbd =>
		handle_key(win, k, compc);
	}
}

init_resources()
{
	f_mono = Font.open(display, "/fonts/vera/veramono/veramono.16.font");
	if(f_mono == nil)
		f_mono = Font.open(display, "/fonts/pelm/unicode.8.font");
	f_monobd = Font.open(display, "/fonts/vera/veramobd/veramobd.16.font");
	if(f_monobd == nil)
		f_monobd = f_mono;
	f_ui = Font.open(display, "/fonts/vera/vera/vera.14.font");
	if(f_ui == nil)
		f_ui = f_mono;
	f_uibd = Font.open(display, "/fonts/vera/verabd/verabd.14.font");
	if(f_uibd == nil)
		f_uibd = f_ui;

	charw = f_mono.width("M");
	if(charw < 6)
		charw = 10;

	c_bg       = display.color(C_BG);
	c_sidebg   = display.color(C_SIDEBG);
	c_tabbg    = display.color(C_TABBG);
	c_gutterbg = display.color(C_GUTTERBG);
	c_curline  = display.color(C_CURLINE);
	c_errline  = display.color(C_ERRLINE);
	c_selbg    = display.color(C_SELBG);
	c_border   = display.color(C_BORDER);
	c_subbdr   = display.color(C_SUBBDR);
	c_ink      = display.color(C_INK);
	c_muted    = display.color(C_MUTED);
	c_gutterfg = display.color(C_GUTTERFG);
	c_accent   = display.color(C_ACCENT);
	c_accentbg = display.color(C_ACCENTBG);
	c_accentfg = display.color(C_ACCENTFG);
	c_dirty    = display.color(C_DIRTY);
	c_ok       = display.color(C_OK);
	c_okbg     = display.color(C_OKBG);
	c_err      = display.color(C_ERR);
	c_errbg    = display.color(C_ERRBG);
	c_sbtk     = display.color(C_SBTK);
	c_sbth     = display.color(C_SBTH);

	s_cols = array[8] of ref Image;
	s_cols[TK_TEXT] = display.color(S_TEXT);
	s_cols[TK_KW]   = display.color(S_KW);
	s_cols[TK_TYPE] = display.color(S_TYPE);
	s_cols[TK_MOD]  = display.color(S_MOD);
	s_cols[TK_STR]  = display.color(S_STR);
	s_cols[TK_NUM]  = display.color(S_NUM);
	s_cols[TK_CMT]  = display.color(S_CMT);
	s_cols[TK_OP]   = display.color(S_OP);
}

# --- Path & Directory Helpers ---

cleanpath(p: string): string
{
	if(p == nil || p == "")
		return "/";
	while(len p > 1 && p[len p - 1] == '/')
		p = p[0:len p - 1];
	return p;
}

dirname(p: string): string
{
	p = cleanpath(p);
	for(i := len p - 1; i >= 0; i--){
		if(p[i] == '/'){
			if(i == 0)
				return "/";
			return p[0:i];
		}
	}
	return ".";
}

basename(p: string): string
{
	p = cleanpath(p);
	for(i := len p - 1; i >= 0; i--)
		if(p[i] == '/')
			return p[i+1:];
	return p;
}

joinpath(d, name: string): string
{
	if(d == "/")
		return "/" + name;
	return d + "/" + name;
}

has_suffix(s, suf: string): int
{
	if(len s < len suf)
		return 0;
	return s[len s - len suf:] == suf;
}

has_prefix(s, pre: string): int
{
	if(len s < len pre)
		return 0;
	return s[0:len pre] == pre;
}

load_dir(dir: string)
{
	dir = cleanpath(dir);
	(dirs, n) := readdir->init(dir, Readdir->NAME | Readdir->COMPACT);
	if(n < 0){
		entries = array[0] of ref DirEntry;
		return;
	}
	curdir = dir;
	side_top = 0;

	# Count visible entries (skip hidden .git/.savegame etc. and .dis/.sbl build clutter)
	dlist: list of ref DirEntry;
	flist: list of ref DirEntry;
	for(i := 0; i < n; i++){
		nm := dirs[i].name;
		if(len nm == 0 || nm[0] == '.')
			continue;
		if((dirs[i].mode & Sys->DMDIR) != 0)
			dlist = ref DirEntry(nm, joinpath(dir, nm), 1) :: dlist;
		else {
			if(has_suffix(nm, ".dis") || has_suffix(nm, ".sbl"))
				continue;
			flist = ref DirEntry(nm, joinpath(dir, nm), 0) :: flist;
		}
	}

	# Reverse lists (readdir already sorted ascending by name)
	dlist = rev_entries(dlist);
	flist = rev_entries(flist);

	cnt := len dlist + len flist;
	if(dir != "/")
		cnt++;
	entries = array[cnt] of ref DirEntry;
	k := 0;
	if(dir != "/")
		entries[k++] = ref DirEntry("..", dirname(dir), 1);
	for(; dlist != nil; dlist = tl dlist)
		entries[k++] = hd dlist;
	for(; flist != nil; flist = tl flist)
		entries[k++] = hd flist;
}

rev_entries(l: list of ref DirEntry): list of ref DirEntry
{
	r: list of ref DirEntry;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

# --- Buffer & File Management ---

new_untitled()
{
	lines := array[] of {
		"implement Untitled;",
		"",
		"include \"sys.m\";",
		"\tsys: Sys;",
		"include \"draw.m\";",
		"",
		"Untitled: module {",
		"\tinit: fn(ctxt: ref Draw->Context, argv: list of string);",
		"};",
		"",
		"init(nil: ref Draw->Context, nil: list of string)",
		"{",
		"\tsys = load Sys Sys->PATH;",
		"\tsys->print(\"hello from Limbo!\\n\");",
		"}"
	};
	b := ref Buffer(joinpath(curdir, "untitled.b"), "untitled.b", lines, 1, 0, 0, 0, 0, 0, 0, 0);
	add_tab(b);
}

open_file(path: string): int
{
	path = cleanpath(path);
	for(i := 0; i < len tabs; i++){
		if(tabs[i].path == path){
			curtab = i;
			return 1;
		}
	}
	io := bufio->open(path, Bufio->OREAD);
	if(io == nil)
		return 0;
	ll: list of string;
	cnt := 0;
	while((s := io.gets('\n')) != nil){
		if(len s > 0 && s[len s - 1] == '\n')
			s = s[0:len s - 1];
		if(len s > 0 && s[len s - 1] == '\r')
			s = s[0:len s - 1];
		ll = s :: ll;
		cnt++;
	}
	io.close();

	lines: array of string;
	if(cnt == 0){
		lines = array[1] of {""};
	} else {
		lines = array[cnt] of string;
		for(j := cnt - 1; j >= 0; j--){
			lines[j] = hd ll;
			ll = tl ll;
		}
	}
	b := ref Buffer(path, basename(path), lines, 0, 0, 0, 0, 0, 0, 0, 0);
	add_tab(b);
	return 1;
}

add_tab(b: ref Buffer)
{
	n := len tabs;
	nt := array[n + 1] of ref Buffer;
	if(n > 0)
		nt[0:] = tabs;
	nt[n] = b;
	tabs = nt;
	curtab = n;
}

close_tab(idx: int)
{
	if(idx < 0 || idx >= len tabs)
		return;
	n := len tabs;
	if(n == 1){
		tabs = array[0] of ref Buffer;
		curtab = -1;
		new_untitled();
		return;
	}
	nt := array[n - 1] of ref Buffer;
	k := 0;
	for(i := 0; i < n; i++)
		if(i != idx)
			nt[k++] = tabs[i];
	tabs = nt;
	if(curtab >= len tabs)
		curtab = len tabs - 1;
}

save_current(): int
{
	if(curtab < 0)
		return 0;
	b := tabs[curtab];
	fd := sys->create(b.path, Sys->OWRITE, 8r644);
	if(fd == nil){
		build_ok = 0;
		build_msg = sys->sprint("Save failed: %r");
		return 0;
	}
	io := bufio->fopen(fd, Bufio->OWRITE);
	if(io == nil){
		build_ok = 0;
		build_msg = "Save failed: bufio";
		return 0;
	}
	for(i := 0; i < len b.lines; i++){
		io.puts(b.lines[i]);
		if(i + 1 < len b.lines)
			io.putc('\n');
	}
	io.putc('\n');
	io.flush();
	io.close();
	b.dirty = 0;
	build_msg = "Saved " + b.name;
	return 1;
}

update_title(win: ref Window)
{
	if(curtab >= 0){
		b := tabs[curtab];
		m := "";
		if(b.dirty)
			m = " *";
		win.settitle("Led - " + b.path + m);
	} else
		win.settitle("Led");
}

# --- Limbo Compiler Integration ---

compute_dis_out(src: string): string
{
	if(!has_suffix(src, ".b"))
		return "";
	stem := src[0:len src - 2];
	if(has_prefix(src, "/appl/wm/"))
		return "/dis/wm/" + basename(stem) + ".dis";
	if(has_prefix(src, "/appl/cmd/"))
		return "/dis/" + basename(stem) + ".dis";
	if(has_prefix(src, "/appl/lib/"))
		return "/dis/lib/" + basename(stem) + ".dis";
	if(has_prefix(src, "/appl/acme/"))
		return "/dis/acme/" + basename(stem) + ".dis";
	return stem + ".dis";
}

start_compile(win: ref Window, compc: chan of (int, string, array of ref Diag))
{
	if(curtab < 0 || compiling)
		return;
	b := tabs[curtab];
	if(!save_current()){
		redraw(win);
		return;
	}
	if(!has_suffix(b.path, ".b")){
		build_ok = 1;
		build_msg = "Saved " + b.name + " (open a .b file to compile)";
		diags = array[1] of { ref Diag(b.path, -1, build_msg, 0) };
		show_out = 1;
		redraw(win);
		return;
	}
	outpath := compute_dis_out(b.path);
	compiling = 1;
	build_ok = -1;
	build_msg = "Compiling " + b.name + "...";
	show_out = 1;
	redraw(win);
	spawn compile_worker(b.path, outpath, compc);
}

compile_worker(src, outpath: string, compc: chan of (int, string, array of ref Diag))
{
	sys->pctl(Sys->NEWFD | Sys->FORKNS, list of {0, 1, 2});
	pfd := array[2] of ref Sys->FD;
	if(sys->pipe(pfd) < 0){
		d := array[1] of { ref Diag(src, -1, "pipe failed", 1) };
		compc <-= (0, "Compile failed", d);
		return;
	}

	donec := chan of int;
	spawn run_limbo_proc(pfd[1], src, outpath, donec);
	pfd[1] = nil;

	# Read all output from limbo
	buf := array[4096] of byte;
	raw := "";
	while((n := sys->read(pfd[0], buf, len buf)) > 0)
		raw += string buf[0:n];
	pfd[0] = nil;
	ok := <-donec;

	# Parse diagnostic lines
	(nil, lines) := sys->tokenize(raw, "\n");
	dl: list of ref Diag;
	errs := 0;
	for(; lines != nil; lines = tl lines){
		ln := hd lines;
		if(len ln > 0 && ln[len ln - 1] == '\r')
			ln = ln[0:len ln - 1];
		if(len ln == 0)
			continue;
		dg := parse_diag(ln, src);
		if(dg.iserr)
			errs++;
		dl = dg :: dl;
	}
	if(ok && errs == 0){
		msg := "Compiled -> " + outpath;
		d := array[1] of { ref Diag(src, -1, "OK: " + src + " -> " + outpath, 0) };
		compc <-= (1, msg, d);
	} else {
		cnt := len dl;
		if(cnt == 0){
			d := array[1] of { ref Diag(src, -1, "limbo exited with error", 1) };
			compc <-= (0, "Compile failed", d);
		} else {
			d := array[cnt] of ref Diag;
			for(i := cnt - 1; i >= 0; i--){
				d[i] = hd dl;
				dl = tl dl;
			}
			msg := sys->sprint("%d diagnostic(s)", cnt);
			compc <-= (0, msg, d);
		}
	}
}

run_limbo_proc(wfd: ref Sys->FD, src, outpath: string, donec: chan of int)
{
	sys->pctl(Sys->NEWFD, list of {0, wfd.fd});
	sys->dup(wfd.fd, 1);
	sys->dup(wfd.fd, 2);
	wfd = nil;

	cmd := load Command "/dis/limbo.dis";
	if(cmd == nil){
		sys->fprint(sys->fildes(2), "led: cannot load /dis/limbo.dis: %r\n");
		donec <-= 0;
		return;
	}
	args := "limbo" :: "-I" :: "/module" :: "-g" :: "-o" :: outpath :: src :: nil;
	ok := 1;
	{
		cmd->init(nil, args);
	} exception e {
	"fail:*" =>
		ok = 0;
	}
	donec <-= ok;
}

parse_diag(ln, fallback: string): ref Diag
{
	# Typical limbo format: /appl/wm/foo.b:42: syntax error
	c1 := -1;
	for(i := 0; i < len ln; i++){
		if(ln[i] == ':'){
			c1 = i;
			break;
		}
	}
	if(c1 > 0 && c1 + 1 < len ln){
		file := ln[0:c1];
		# Read digits after first colon
		j := c1 + 1;
		while(j < len ln && ln[j] >= '0' && ln[j] <= '9')
			j++;
		if(j > c1 + 1 && j < len ln && (ln[j] == ':' || ln[j] == ',' || ln[j] == '.')){
			lno := int ln[c1+1:j];
			if(lno > 0){
				if(file[0] != '/')
					file = joinpath(dirname(fallback), file);
				return ref Diag(cleanpath(file), lno - 1, ln, 1);
			}
		}
	}
	return ref Diag(fallback, -1, ln, 1);
}

# --- Syntax Highlighting (Limbo) ---

is_id_start(c: int): int
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

is_id_char(c: int): int
{
	return is_id_start(c) || (c >= '0' && c <= '9');
}

is_digit(c: int): int
{
	return c >= '0' && c <= '9';
}

is_kw(w: string): int
{
	for(i := 0; i < len kw_list; i++)
		if(kw_list[i] == w)
			return 1;
	return 0;
}

is_type(w: string): int
{
	for(i := 0; i < len type_list; i++)
		if(type_list[i] == w)
			return 1;
	return 0;
}

# Expand tabs in a line to visual column positions & return visual width of prefix
vis_col(line: string, col: int): int
{
	if(col > len line)
		col = len line;
	vc := 0;
	for(i := 0; i < col; i++){
		if(line[i] == '\t')
			vc += TAB_W - (vc % TAB_W);
		else
			vc++;
	}
	return vc;
}

col_from_vis(line: string, target_vc: int): int
{
	vc := 0;
	for(i := 0; i < len line; i++){
		step := 1;
		if(line[i] == '\t')
			step = TAB_W - (vc % TAB_W);
		if(vc + step / 2 >= target_vc)
			return i;
		vc += step;
	}
	return len line;
}

# Draw a single syntax-highlighted Limbo line at (x0, y) clipped to [x0, xmax)
draw_code_line(img: ref Image, line: string, x0, y, xmax, left_vc: int)
{
	n := len line;
	i := 0;
	vc := 0;
	while(i < n){
		c := line[i];
		# Whitespace
		if(c == ' ' || c == '\t'){
			if(c == '\t')
				vc += TAB_W - (vc % TAB_W);
			else
				vc++;
			i++;
			continue;
		}
		# Comment to end of line
		if(c == '#'){
			seg := line[i:];
			draw_seg(img, seg, TK_CMT, x0, y, xmax, vc, left_vc);
			return;
		}
		# String or char literal
		if(c == '"' || c == '\''){
			q := c;
			j := i + 1;
			while(j < n){
				if(line[j] == '\\' && j + 1 < n)
					j += 2;
				else if(line[j] == q){
					j++;
					break;
				} else
					j++;
			}
			seg := line[i:j];
			vc = draw_seg(img, seg, TK_STR, x0, y, xmax, vc, left_vc);
			i = j;
			continue;
		}
		# Number literal (including 16r..., 8r..., 2r..., floats)
		if(is_digit(c)){
			j := i + 1;
			while(j < n && (is_id_char(line[j]) || line[j] == '.'))
				j++;
			seg := line[i:j];
			vc = draw_seg(img, seg, TK_NUM, x0, y, xmax, vc, left_vc);
			i = j;
			continue;
		}
		# Identifier / keyword / type / module
		if(is_id_start(c)){
			j := i + 1;
			while(j < n && is_id_char(line[j]))
				j++;
			seg := line[i:j];
			kind := TK_TEXT;
			if(is_kw(seg))
				kind = TK_KW;
			else if(is_type(seg))
				kind = TK_TYPE;
			else if(c >= 'A' && c <= 'Z')
				kind = TK_MOD;
			vc = draw_seg(img, seg, kind, x0, y, xmax, vc, left_vc);
			i = j;
			continue;
		}
		# Operator / punctuation run
		j := i + 1;
		while(j < n){
			ch := line[j];
			if(ch == ' ' || ch == '\t' || ch == '#' || ch == '"' || ch == '\'' || is_id_start(ch) || is_digit(ch))
				break;
			j++;
		}
		seg := line[i:j];
		vc = draw_seg(img, seg, TK_OP, x0, y, xmax, vc, left_vc);
		i = j;
	}
}

draw_seg(img: ref Image, seg: string, kind, x0, y, xmax, vc, left_vc: int): int
{
	# Expand any tabs inside strings/comments
	out := "";
	cur_vc := vc;
	for(i := 0; i < len seg; i++){
		if(seg[i] == '\t'){
			sp := TAB_W - (cur_vc % TAB_W);
			for(k := 0; k < sp; k++)
				out[len out] = ' ';
			cur_vc += sp;
		} else {
			out[len out] = seg[i];
			cur_vc++;
		}
	}
	# Clip to horizontal viewport
	start := 0;
	if(vc < left_vc){
		start = left_vc - vc;
		if(start >= len out)
			return cur_vc;
		out = out[start:];
		vc = left_vc;
	}
	px := x0 + (vc - left_vc) * charw;
	if(px >= xmax)
		return cur_vc;
	maxchars := (xmax - px) / charw;
	if(maxchars <= 0)
		return cur_vc;
	if(len out > maxchars)
		out = out[0:maxchars];

	f := f_mono;
	if(kind == TK_KW)
		f = f_monobd;
	img.text((px, y), s_cols[kind], (0, 0), f, out);
	return cur_vc;
}

# --- Layout Geometry Helpers ---

get_ed_rect(w, h: int): Rect
{
	outh := 0;
	if(show_out)
		outh = OUT_H;
	return Rect((SIDEBAR_W, TAB_H), (w - SB_W, h - STAT_H - outh));
}

get_out_rect(w, h: int): Rect
{
	if(!show_out)
		return Rect((0, 0), (0, 0));
	return Rect((SIDEBAR_W, h - STAT_H - OUT_H), (w, h - STAT_H));
}

# --- Rendering ---

redraw(win: ref Window)
{
	if(win.image == nil)
		return;
	wr := win.image.r;
	w := wr.dx();
	h := wr.dy();
	if(w < 200 || h < 120)
		return;

	if(bufimg == nil || bufw != w || bufh != h){
		bufimg = nil;
		bufimg = display.newimage(Rect((0, 0), (w, h)), win.image.chans, 0, Draw->White);
		if(bufimg == nil)
			return;
		bufw = w;
		bufh = h;
	}

	# Clear full canvas
	bufimg.draw(Rect((0, 0), (w, h)), c_bg, nil, (0, 0));

	draw_sidebar(bufimg, w, h);
	draw_tabbar(bufimg, w);
	draw_editor(bufimg, w, h);
	if(show_out)
		draw_output(bufimg, w, h);
	draw_statusbar(bufimg, w, h);

	win.image.draw(wr, bufimg, nil, (0, 0));
	win.image.flush(Draw->Flushnow);
}

draw_sidebar(img: ref Image, nil: int, h: int)
{
	sr := Rect((0, 0), (SIDEBAR_W, h - STAT_H));
	img.draw(sr, c_sidebg, nil, (0, 0));
	# Right divider
	img.draw(Rect((SIDEBAR_W - 1, 0), (SIDEBAR_W, h - STAT_H)), c_border, nil, (0, 0));

	# Header
	img.text((14, 11), c_muted, (0, 0), f_uibd, "PROJECT");
	# Current dir path (truncated from left if long)
	dp := curdir;
	if(len dp > 26)
		dp = "..." + dp[len dp - 23:];
	img.text((14, 34), c_ink, (0, 0), f_ui, dp);
	img.draw(Rect((0, 58), (SIDEBAR_W - 1, 59)), c_subbdr, nil, (0, 0));

	active_path := "";
	if(curtab >= 0)
		active_path = tabs[curtab].path;

	y := 64;
	maxy := h - STAT_H - 4;
	for(i := side_top; i < len entries && y + SIDE_ROW <= maxy; i++){
		e := entries[i];
		isact := (!e.isdir && e.path == active_path);
		if(isact){
			img.draw(Rect((6, y), (SIDEBAR_W - 7, y + SIDE_ROW - 2)), c_accentbg, nil, (0, 0));
			img.draw(Rect((6, y), (9, y + SIDE_ROW - 2)), c_accent, nil, (0, 0));
		}
		if(e.isdir){
			lbl := "> " + e.name + "/";
			if(e.name == "..")
				lbl = "^ ..";
			if(len lbl > 24)
				lbl = lbl[0:22] + "..";
			img.text((14, y + 4), c_ink, (0, 0), f_uibd, lbl);
		} else {
			# Colored language dot (.b blue, .m purple, other muted)
			dotc := c_muted;
			if(has_suffix(e.name, ".b"))
				dotc = c_accent;
			else if(has_suffix(e.name, ".m"))
				dotc = s_cols[TK_KW];
			img.draw(Rect((15, y + 9), (21, y + 15)), dotc, nil, (0, 0));
			lbl := e.name;
			if(len lbl > 22)
				lbl = lbl[0:20] + "..";
			fg := c_ink;
			if(isact)
				fg = c_accentfg;
			img.text((28, y + 4), fg, (0, 0), f_ui, lbl);
		}
		y += SIDE_ROW;
	}
}

draw_tabbar(img: ref Image, w: int)
{
	img.draw(Rect((SIDEBAR_W, 0), (w, TAB_H)), c_tabbg, nil, (0, 0));
	img.draw(Rect((SIDEBAR_W, TAB_H - 1), (w, TAB_H)), c_border, nil, (0, 0));

	# Right-aligned action buttons: [Output] [Compile] [Save]
	bx := w - 10;
	# Output toggle
	ow := 74;
	r_btn_out = Rect((bx - ow, 6), (bx, TAB_H - 6));
	obg := c_subbdr;
	ofg := c_ink;
	if(show_out){
		obg = c_accentbg;
		ofg = c_accentfg;
	}
	img.draw(r_btn_out, obg, nil, (0, 0));
	img.text((r_btn_out.min.x + 12, r_btn_out.min.y + 5), ofg, (0, 0), f_uibd, "Output");
	bx -= ow + 8;

	# Compile button (primary blue)
	cw := 84;
	r_btn_comp = Rect((bx - cw, 6), (bx, TAB_H - 6));
	cbg := c_accent;
	clbl := "Compile";
	if(compiling){
		cbg = c_muted;
		clbl = "Build...";
	}
	img.draw(r_btn_comp, cbg, nil, (0, 0));
	img.text((r_btn_comp.min.x + 12, r_btn_comp.min.y + 5), c_bg, (0, 0), f_uibd, clbl);
	bx -= cw + 8;

	# Save button
	sw := 60;
	r_btn_save = Rect((bx - sw, 6), (bx, TAB_H - 6));
	img.draw(r_btn_save, c_subbdr, nil, (0, 0));
	img.text((r_btn_save.min.x + 12, r_btn_save.min.y + 5), c_ink, (0, 0), f_uibd, "Save");
	bx -= sw + 12;

	# Open tabs
	r_tabs = array[len tabs] of Rect;
	r_tab_xs = array[len tabs] of Rect;
	tx := SIDEBAR_W;
	for(i := 0; i < len tabs; i++){
		b := tabs[i];
		lbl := b.name;
		if(len lbl > 18)
			lbl = lbl[0:15] + "...";
		tw := f_ui.width(lbl) + 46;
		if(tx + tw > bx)
			break;
		tr := Rect((tx, 0), (tx + tw, TAB_H - 1));
		r_tabs[i] = tr;
		if(i == curtab){
			img.draw(tr, c_bg, nil, (0, 0));
			img.draw(Rect((tx, 0), (tx + tw, 2)), c_accent, nil, (0, 0));
		}
		img.draw(Rect((tx + tw - 1, 0), (tx + tw, TAB_H - 1)), c_subbdr, nil, (0, 0));
		lx := tx + 12;
		if(b.dirty){
			img.draw(Rect((lx, 17), (lx + 6, 23)), c_dirty, nil, (0, 0));
			lx += 11;
		}
		fg := c_muted;
		if(i == curtab)
			fg = c_ink;
		img.text((lx, 11), fg, (0, 0), f_ui, lbl);
		# Close x hit area
		xr := Rect((tx + tw - 22, 10), (tx + tw - 6, 28));
		r_tab_xs[i] = xr;
		img.text((xr.min.x + 4, xr.min.y + 1), c_muted, (0, 0), f_ui, "x");
		tx += tw;
	}
}

line_has_err(path: string, lno: int): int
{
	for(i := 0; i < len diags; i++)
		if(diags[i].iserr && diags[i].line == lno && diags[i].file == path)
			return 1;
	return 0;
}

ordered_sel(b: ref Buffer): (int, int, int, int)
{
	l0 := b.sel_l; c0 := b.sel_c;
	l1 := b.cur_l; c1 := b.cur_c;
	if(l0 > l1 || (l0 == l1 && c0 > c1))
		return (l1, c1, l0, c0);
	return (l0, c0, l1, c1);
}

draw_editor(img: ref Image, w, h: int)
{
	er := get_ed_rect(w, h);
	if(er.dx() <= GUTTER_W || er.dy() <= 0)
		return;

	# Gutter background & divider
	img.draw(Rect(er.min, (er.min.x + GUTTER_W, er.max.y)), c_gutterbg, nil, (0, 0));
	img.draw(Rect((er.min.x + GUTTER_W - 1, er.min.y), (er.min.x + GUTTER_W, er.max.y)), c_subbdr, nil, (0, 0));

	# Vertical scrollbar track
	sbr := Rect((w - SB_W, er.min.y), (w, er.max.y));
	img.draw(sbr, c_sbtk, nil, (0, 0));

	if(curtab < 0)
		return;
	b := tabs[curtab];
	nlines := len b.lines;
	vis := er.dy() / LINE_H;
	if(vis < 1) vis = 1;

	# Scrollbar thumb
	if(nlines > vis){
		th := sbr.dy() * vis / nlines;
		if(th < 24) th = 24;
		max_top := nlines - vis;
		ty := sbr.min.y + (sbr.dy() - th) * b.top_l / max_top;
		img.draw(Rect((sbr.min.x + 2, ty), (sbr.max.x - 2, ty + th)), c_sbth, nil, (0, 0));
	}

	code_x0 := er.min.x + GUTTER_W + 10;
	code_xmax := er.max.x - 4;
	(sl0, sc0, sl1, sc1) := ordered_sel(b);

	y := er.min.y + 4;
	for(l := b.top_l; l < nlines && y + LINE_H <= er.max.y + 4; l++){
		iserr := line_has_err(b.path, l);
		if(iserr){
			img.draw(Rect((er.min.x + GUTTER_W, y), (er.max.x, y + LINE_H)), c_errline, nil, (0, 0));
			img.draw(Rect((er.min.x, y), (er.min.x + 3, y + LINE_H)), c_err, nil, (0, 0));
		} else if(l == b.cur_l){
			img.draw(Rect((er.min.x + GUTTER_W, y), (er.max.x, y + LINE_H)), c_curline, nil, (0, 0));
		}

		# Line number (right-aligned in gutter)
		lnum := string (l + 1);
		nw := f_mono.width(lnum);
		gfg := c_gutterfg;
		if(iserr)
			gfg = c_err;
		else if(l == b.cur_l)
			gfg = c_ink;
		img.text((er.min.x + GUTTER_W - nw - 10, y + 3), gfg, (0, 0), f_mono, lnum);

		# Selection highlight
		if(b.sel_on && l >= sl0 && l <= sl1){
			line := b.lines[l];
			a := 0;
			z := len line;
			if(l == sl0) a = sc0;
			if(l == sl1) z = sc1;
			va := vis_col(line, a);
			vz := vis_col(line, z);
			if(l < sl1) vz++;
			sx0 := code_x0 + (va - b.left_c) * charw;
			sx1 := code_x0 + (vz - b.left_c) * charw;
			if(sx0 < code_x0) sx0 = code_x0;
			if(sx1 > code_xmax) sx1 = code_xmax;
			if(sx1 > sx0)
				img.draw(Rect((sx0, y), (sx1, y + LINE_H)), c_selbg, nil, (0, 0));
		}

		# Syntax-highlighted code text
		draw_code_line(img, b.lines[l], code_x0, y + 3, code_xmax, b.left_c);

		# Cursor bar
		if(l == b.cur_l){
			vc := vis_col(b.lines[l], b.cur_c);
			cx := code_x0 + (vc - b.left_c) * charw;
			if(cx >= code_x0 && cx < code_xmax)
				img.draw(Rect((cx, y + 1), (cx + 2, y + LINE_H - 1)), c_accent, nil, (0, 0));
		}

		y += LINE_H;
	}
}

draw_output(img: ref Image, w, h: int)
{
	orr := get_out_rect(w, h);
	img.draw(orr, c_bg, nil, (0, 0));
	# Top border & header bar
	img.draw(Rect(orr.min, (orr.max.x, orr.min.y + 1)), c_border, nil, (0, 0));
	hdr := Rect((orr.min.x, orr.min.y + 1), (orr.max.x, orr.min.y + OUT_HDR_H));
	img.draw(hdr, c_sidebg, nil, (0, 0));
	img.draw(Rect((orr.min.x, orr.min.y + OUT_HDR_H), (orr.max.x, orr.min.y + OUT_HDR_H + 1)), c_subbdr, nil, (0, 0));

	img.text((orr.min.x + 12, orr.min.y + 6), c_muted, (0, 0), f_uibd, "OUTPUT  (limbo -I /module -g)");
	# Status badge
	if(build_ok == 1){
		img.draw(Rect((orr.max.x - 160, orr.min.y + 4), (orr.max.x - 10, orr.min.y + OUT_HDR_H - 4)), c_okbg, nil, (0, 0));
		img.text((orr.max.x - 150, orr.min.y + 6), c_ok, (0, 0), f_uibd, "Build Succeeded");
	} else if(build_ok == 0){
		img.draw(Rect((orr.max.x - 140, orr.min.y + 4), (orr.max.x - 10, orr.min.y + OUT_HDR_H - 4)), c_errbg, nil, (0, 0));
		img.text((orr.max.x - 130, orr.min.y + 6), c_err, (0, 0), f_uibd, "Build Failed");
	}

	y := orr.min.y + OUT_HDR_H + 6;
	maxy := orr.max.y - 4;
	if(len diags == 0){
		img.text((orr.min.x + 14, y), c_muted, (0, 0), f_mono, "Press Compile (Ctrl+B) to compile the active .b file with /dis/limbo.dis.");
		return;
	}
	maxchars := (orr.dx() - 28) / charw;
	if(maxchars < 10) maxchars = 10;
	for(i := out_top; i < len diags && y + 20 <= maxy; i++){
		d := diags[i];
		txt := d.text;
		if(len txt > maxchars)
			txt = txt[0:maxchars - 3] + "...";
		fg := c_ok;
		if(d.iserr)
			fg = c_err;
		img.text((orr.min.x + 14, y), fg, (0, 0), f_mono, txt);
		y += 22;
	}
}

draw_statusbar(img: ref Image, w, h: int)
{
	sr := Rect((0, h - STAT_H), (w, h));
	img.draw(sr, c_sidebg, nil, (0, 0));
	img.draw(Rect((0, h - STAT_H), (w, h - STAT_H + 1)), c_border, nil, (0, 0));

	left := "No file";
	if(curtab >= 0){
		b := tabs[curtab];
		mod := "";
		if(b.dirty)
			mod = "  [modified]";
		left = sys->sprint("%s%s   Ln %d, Col %d   Limbo", b.path, mod, b.cur_l + 1, b.cur_c + 1);
	}
	img.text((14, h - STAT_H + 6), c_ink, (0, 0), f_ui, left);

	right := build_msg + "   |   Ctrl+S Save   Ctrl+B Compile   Ctrl+O Output";
	rw := f_ui.width(right);
	if(rw + 24 < w - f_ui.width(left) - 40)
		img.text((w - rw - 14, h - STAT_H + 6), c_muted, (0, 0), f_ui, right);
}

# --- Cursor & Viewport Helpers ---

ensure_visible(b: ref Buffer, w, h: int)
{
	er := get_ed_rect(w, h);
	vis := er.dy() / LINE_H;
	if(vis < 1) vis = 1;
	if(b.cur_l < b.top_l)
		b.top_l = b.cur_l;
	if(b.cur_l >= b.top_l + vis)
		b.top_l = b.cur_l - vis + 1;
	if(b.top_l < 0)
		b.top_l = 0;

	vcols := (er.dx() - GUTTER_W - 20) / charw;
	if(vcols < 10) vcols = 10;
	vc := vis_col(b.lines[b.cur_l], b.cur_c);
	if(vc < b.left_c)
		b.left_c = vc;
	if(vc >= b.left_c + vcols)
		b.left_c = vc - vcols + 4;
	if(b.left_c < 0)
		b.left_c = 0;
}

clamp_cursor(b: ref Buffer)
{
	if(len b.lines == 0)
		b.lines = array[1] of {""};
	if(b.cur_l < 0) b.cur_l = 0;
	if(b.cur_l >= len b.lines) b.cur_l = len b.lines - 1;
	if(b.cur_c < 0) b.cur_c = 0;
	if(b.cur_c > len b.lines[b.cur_l]) b.cur_c = len b.lines[b.cur_l];
}

# --- Editing Primitives ---

delete_selection(b: ref Buffer): int
{
	if(!b.sel_on)
		return 0;
	(l0, c0, l1, c1) := ordered_sel(b);
	b.sel_on = 0;
	if(l0 == l1 && c0 == c1)
		return 0;
	prefix := b.lines[l0][0:c0];
	suffix := b.lines[l1][c1:];
	removed := l1 - l0;
	n := len b.lines;
	nl := array[n - removed] of string;
	for(i := 0; i < l0; i++)
		nl[i] = b.lines[i];
	nl[l0] = prefix + suffix;
	for(i = l1 + 1; i < n; i++)
		nl[i - removed] = b.lines[i];
	b.lines = nl;
	b.cur_l = l0;
	b.cur_c = c0;
	b.dirty = 1;
	return 1;
}

get_selection_text(b: ref Buffer): string
{
	if(!b.sel_on)
		return "";
	(l0, c0, l1, c1) := ordered_sel(b);
	if(l0 == l1)
		return b.lines[l0][c0:c1];
	out := b.lines[l0][c0:] + "\n";
	for(i := l0 + 1; i < l1; i++)
		out += b.lines[i] + "\n";
	out += b.lines[l1][0:c1];
	return out;
}

insert_text(b: ref Buffer, txt: string)
{
	if(len txt == 0)
		return;
	delete_selection(b);
	for(i := 0; i < len txt; i++){
		c := txt[i];
		if(c == '\r')
			continue;
		if(c == '\n')
			insert_newline(b, 0);
		else
			insert_char(b, c);
	}
}

insert_char(b: ref Buffer, ch: int)
{
	delete_selection(b);
	ln := b.lines[b.cur_l];
	s := "";
	s[0] = ch;
	b.lines[b.cur_l] = ln[0:b.cur_c] + s + ln[b.cur_c:];
	b.cur_c++;
	b.dirty = 1;
}

insert_newline(b: ref Buffer, autoindent: int)
{
	delete_selection(b);
	ln := b.lines[b.cur_l];
	left := ln[0:b.cur_c];
	right := ln[b.cur_c:];
	indent := "";
	if(autoindent){
		for(i := 0; i < len left && (left[i] == '\t' || left[i] == ' '); i++)
			indent[len indent] = left[i];
		# Auto-indent extra tab after opening brace
		t := len left - 1;
		while(t >= 0 && (left[t] == ' ' || left[t] == '\t'))
			t--;
		if(t >= 0 && left[t] == '{')
			indent += "\t";
	}
	n := len b.lines;
	nl := array[n + 1] of string;
	for(i := 0; i < b.cur_l; i++)
		nl[i] = b.lines[i];
	nl[b.cur_l] = left;
	nl[b.cur_l + 1] = indent + right;
	for(i = b.cur_l + 1; i < n; i++)
		nl[i + 1] = b.lines[i];
	b.lines = nl;
	b.cur_l++;
	b.cur_c = len indent;
	b.dirty = 1;
}

do_backspace(b: ref Buffer)
{
	if(delete_selection(b))
		return;
	if(b.cur_c > 0){
		ln := b.lines[b.cur_l];
		b.lines[b.cur_l] = ln[0:b.cur_c - 1] + ln[b.cur_c:];
		b.cur_c--;
		b.dirty = 1;
	} else if(b.cur_l > 0){
		prev := b.lines[b.cur_l - 1];
		cur := b.lines[b.cur_l];
		newc := len prev;
		n := len b.lines;
		nl := array[n - 1] of string;
		for(i := 0; i < b.cur_l - 1; i++)
			nl[i] = b.lines[i];
		nl[b.cur_l - 1] = prev + cur;
		for(i = b.cur_l + 1; i < n; i++)
			nl[i - 1] = b.lines[i];
		b.lines = nl;
		b.cur_l--;
		b.cur_c = newc;
		b.dirty = 1;
	}
}

do_delete(b: ref Buffer)
{
	if(delete_selection(b))
		return;
	ln := b.lines[b.cur_l];
	if(b.cur_c < len ln){
		b.lines[b.cur_l] = ln[0:b.cur_c] + ln[b.cur_c + 1:];
		b.dirty = 1;
	} else if(b.cur_l + 1 < len b.lines){
		nxt := b.lines[b.cur_l + 1];
		n := len b.lines;
		nl := array[n - 1] of string;
		for(i := 0; i < b.cur_l; i++)
			nl[i] = b.lines[i];
		nl[b.cur_l] = ln + nxt;
		for(i = b.cur_l + 2; i < n; i++)
			nl[i - 1] = b.lines[i];
		b.lines = nl;
		b.dirty = 1;
	}
}

# --- Input Handlers ---

pos_from_xy(b: ref Buffer, er: Rect, lx, ly: int): (int, int)
{
	row := b.top_l + (ly - er.min.y - 4) / LINE_H;
	if(row < 0) row = 0;
	if(row >= len b.lines) row = len b.lines - 1;
	code_x0 := er.min.x + GUTTER_W + 10;
	vc := b.left_c + (lx - code_x0 + charw / 2) / charw;
	if(vc < 0) vc = 0;
	col := col_from_vis(b.lines[row], vc);
	return (row, col);
}

handle_ptr(win: ref Window, p: ref Pointer, prev_b: int, compc: chan of (int, string, array of ref Diag))
{
	wr := win.image.r;
	w := wr.dx();
	h := wr.dy();
	lx := p.xy.x - wr.min.x;
	ly := p.xy.y - wr.min.y;
	lp := Point(lx, ly);
	er := get_ed_rect(w, h);
	orr := get_out_rect(w, h);

	# Mouse wheel scroll (buttons 8 = up, 16 = down)
	if((p.buttons & 8) != 0 && (prev_b & 8) == 0){
		if(lx < SIDEBAR_W){
			side_top -= 3;
			if(side_top < 0) side_top = 0;
		} else if(show_out && lp.in(orr)){
			out_top -= 2;
			if(out_top < 0) out_top = 0;
		} else if(curtab >= 0){
			tabs[curtab].top_l -= 4;
			if(tabs[curtab].top_l < 0) tabs[curtab].top_l = 0;
		}
		redraw(win);
		return;
	}
	if((p.buttons & 16) != 0 && (prev_b & 16) == 0){
		if(lx < SIDEBAR_W){
			side_top += 3;
			if(side_top > len entries - 1) side_top = len entries - 1;
			if(side_top < 0) side_top = 0;
		} else if(show_out && lp.in(orr)){
			out_top += 2;
			if(out_top > len diags - 1) out_top = len diags - 1;
			if(out_top < 0) out_top = 0;
		} else if(curtab >= 0){
			b := tabs[curtab];
			b.top_l += 4;
			if(b.top_l >= len b.lines) b.top_l = len b.lines - 1;
			if(b.top_l < 0) b.top_l = 0;
		}
		redraw(win);
		return;
	}

	# Release drag
	if((p.buttons & 1) == 0){
		drag_mode = 0;
		return;
	}

	# Continuing drag
	if((prev_b & 1) != 0){
		if(drag_mode == 1 && curtab >= 0){
			b := tabs[curtab];
			(rl, rc) := pos_from_xy(b, er, lx, ly);
			b.cur_l = rl;
			b.cur_c = rc;
			b.sel_on = (b.cur_l != b.sel_l || b.cur_c != b.sel_c);
			redraw(win);
		} else if(drag_mode == 2 && curtab >= 0){
			b := tabs[curtab];
			vis := er.dy() / LINE_H;
			if(len b.lines > vis){
				max_top := len b.lines - vis;
				frac := (ly - er.min.y) * max_top / er.dy();
				if(frac < 0) frac = 0;
				if(frac > max_top) frac = max_top;
				b.top_l = frac;
				redraw(win);
			}
		}
		return;
	}

	# Fresh Button-1 click
	# 1. Action buttons in tab bar
	if(lp.in(r_btn_save)){
		save_current();
		update_title(win);
		redraw(win);
		return;
	}
	if(lp.in(r_btn_comp)){
		start_compile(win, compc);
		return;
	}
	if(lp.in(r_btn_out)){
		show_out = !show_out;
		redraw(win);
		return;
	}

	# 2. Tabs
	if(ly < TAB_H && lx >= SIDEBAR_W){
		for(i := 0; i < len r_tabs; i++){
			if(lp.in(r_tab_xs[i])){
				close_tab(i);
				update_title(win);
				redraw(win);
				return;
			}
			if(lp.in(r_tabs[i])){
				curtab = i;
				update_title(win);
				redraw(win);
				return;
			}
		}
		return;
	}

	# 3. Sidebar click
	if(lx < SIDEBAR_W && ly >= 64 && ly < h - STAT_H){
		idx := side_top + (ly - 64) / SIDE_ROW;
		if(idx >= 0 && idx < len entries){
			e := entries[idx];
			if(e.isdir)
				load_dir(e.path);
			else {
				open_file(e.path);
				update_title(win);
			}
			redraw(win);
		}
		return;
	}

	# 4. Output panel diagnostic click (jump to file:line)
	if(show_out && lp.in(orr) && ly >= orr.min.y + OUT_HDR_H + 6){
		idx := out_top + (ly - orr.min.y - OUT_HDR_H - 6) / 22;
		if(idx >= 0 && idx < len diags){
			d := diags[idx];
			if(d.line >= 0 && d.file != ""){
				if(open_file(d.file)){
					b := tabs[curtab];
					b.cur_l = d.line;
					b.cur_c = 0;
					b.sel_on = 0;
					clamp_cursor(b);
					ensure_visible(b, w, h);
					update_title(win);
					redraw(win);
				}
			}
		}
		return;
	}

	# 5. Scrollbar click/drag
	if(lx >= w - SB_W && ly >= er.min.y && ly < er.max.y && curtab >= 0){
		drag_mode = 2;
		b := tabs[curtab];
		vis := er.dy() / LINE_H;
		if(len b.lines > vis){
			max_top := len b.lines - vis;
			frac := (ly - er.min.y) * max_top / er.dy();
			if(frac < 0) frac = 0;
			if(frac > max_top) frac = max_top;
			b.top_l = frac;
			redraw(win);
		}
		return;
	}

	# 6. Editor canvas click
	if(lp.in(er) && curtab >= 0){
		b := tabs[curtab];
		(rl, rc) := pos_from_xy(b, er, lx, ly);
		now := sys->millisec();
		if(now - last_click_ms < 350 && rl == last_click_l && rc == last_click_c){
			# Double-click: select word
			ln := b.lines[rl];
			a := rc;
			z := rc;
			while(a > 0 && is_id_char(ln[a - 1])) a--;
			while(z < len ln && is_id_char(ln[z])) z++;
			b.sel_l = rl; b.sel_c = a;
			b.cur_l = rl; b.cur_c = z;
			b.sel_on = (z > a);
			drag_mode = 0;
		} else {
			b.cur_l = rl;
			b.cur_c = rc;
			b.sel_l = rl;
			b.sel_c = rc;
			b.sel_on = 0;
			drag_mode = 1;
		}
		last_click_ms = now;
		last_click_l = rl;
		last_click_c = rc;
		redraw(win);
	}
}

handle_key(win: ref Window, k: int, compc: chan of (int, string, array of ref Diag))
{
	if(curtab < 0 || win.image == nil)
		return;
	b := tabs[curtab];
	wr := win.image.r;
	w := wr.dx();
	h := wr.dy();
	was_dirty := b.dirty;

	case k {
	16r13 =>	# Ctrl+S: Save
		save_current();
		update_title(win);
		redraw(win);
		return;
	16r02 =>	# Ctrl+B: Compile
		start_compile(win, compc);
		return;
	16r0f =>	# Ctrl+O: Toggle Output
		show_out = !show_out;
		redraw(win);
		return;
	16r17 =>	# Ctrl+W: Close tab
		close_tab(curtab);
		update_title(win);
		redraw(win);
		return;
	16r01 =>	# Ctrl+A: Select all
		b.sel_l = 0; b.sel_c = 0;
		b.cur_l = len b.lines - 1;
		b.cur_c = len b.lines[b.cur_l];
		b.sel_on = 1;
		redraw(win);
		return;
	Keyboard->APP | 'c' =>	# Cmd/Alt+C: Copy
		if(b.sel_on)
			wmclient->snarfput(get_selection_text(b));
		else
			wmclient->snarfput(b.lines[b.cur_l] + "\n");
		return;
	Keyboard->APP | 'x' =>	# Cmd/Alt+X: Cut
		if(b.sel_on){
			wmclient->snarfput(get_selection_text(b));
			delete_selection(b);
		}
	Keyboard->APP | 'v' =>	# Cmd/Alt+V: Paste
		sn := wmclient->snarfget();
		if(len sn > 0)
			insert_text(b, sn);
	Keyboard->Up =>
		b.sel_on = 0;
		if(b.cur_l > 0) b.cur_l--;
		clamp_cursor(b);
	Keyboard->Down =>
		b.sel_on = 0;
		if(b.cur_l + 1 < len b.lines) b.cur_l++;
		clamp_cursor(b);
	Keyboard->Left =>
		b.sel_on = 0;
		if(b.cur_c > 0)
			b.cur_c--;
		else if(b.cur_l > 0){
			b.cur_l--;
			b.cur_c = len b.lines[b.cur_l];
		}
	Keyboard->Right =>
		b.sel_on = 0;
		if(b.cur_c < len b.lines[b.cur_l])
			b.cur_c++;
		else if(b.cur_l + 1 < len b.lines){
			b.cur_l++;
			b.cur_c = 0;
		}
	Keyboard->Home =>
		b.sel_on = 0;
		b.cur_c = 0;
	Keyboard->End =>
		b.sel_on = 0;
		b.cur_c = len b.lines[b.cur_l];
	Keyboard->Pgup =>
		b.sel_on = 0;
		er := get_ed_rect(w, h);
		step := er.dy() / LINE_H - 2;
		if(step < 5) step = 5;
		b.cur_l -= step;
		clamp_cursor(b);
	Keyboard->Pgdown =>
		b.sel_on = 0;
		er := get_ed_rect(w, h);
		step := er.dy() / LINE_H - 2;
		if(step < 5) step = 5;
		b.cur_l += step;
		clamp_cursor(b);
	'\n' or '\r' =>
		insert_newline(b, 1);
	'\t' =>
		insert_char(b, '\t');
	'\b' =>
		do_backspace(b);
	Keyboard->Del =>
		do_delete(b);
	Keyboard->Esc =>
		b.sel_on = 0;
	* =>
		if(k >= 32 && k < 127)
			insert_char(b, k);
		else
			return;
	}

	clamp_cursor(b);
	ensure_visible(b, w, h);
	if(b.dirty != was_dirty)
		update_title(win);
	redraw(win);
}
