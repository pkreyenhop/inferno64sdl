implement WmFire;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "math.m";
	math: Math;

WmFire: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

MNT: con "/mnt/sheet";
ADDR_FILE: con "/tmp/sheet.addr";
DEF_ADDR: con "tcp!127.0.0.1!19900";

FONT_UI:   con "/fonts/vera/verabd/verabd.14.font";
FONT_BIG:  con "/fonts/vera/verabd/verabd.18.font";
FONT_MONO: con "/fonts/vera/veramono/veramono.14.font";

# Original values captured on connect for Reset
orig_growth := 10.0;
orig_infl   := 3.0;
orig_wr     := 4.0;
orig_spend  := 120000;

cur_growth  := 10.0;
cur_infl    := 3.0;
cur_wr      := 4.0;
cur_spend   := 120000;
connected   := 0;

trim(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	return s[i:j];
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return trim(string buf[0:n]);
}

writefile(path: string, s: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte (s + "\n");
	if(sys->write(fd, b, len b) != len b)
		return -1;
	return 0;
}

parse_pct(s: string, defv: real): real
{
	s = trim(s);
	if(len s == 0)
		return defv;
	if(s[len s - 1] == '%')
		return real s[0:len s - 1];
	v := real s;
	if(v > 0.0 && v < 1.0)
		return v * 100.0;
	return v;
}

fmt_commas(n: int): string
{
	neg := 0;
	if(n < 0){ neg = 1; n = -n; }
	raw := string n;
	out := "";
	l := len raw;
	for(i := 0; i < l; i++){
		if(i > 0 && ((l - i) % 3) == 0)
			out[len out] = ',';
		out[len out] = raw[i];
	}
	if(neg) return "-" + out;
	return out;
}

fmt_pct(v: real): string
{
	iv := int math->rint(v);
	if(math->fabs(v - real iv) < 0.01)
		return sys->sprint("%d%%", iv);
	iv2 := int math->rint(v * 10.0);
	if(math->fabs(v * 10.0 - real iv2) < 0.05)
		return sys->sprint("%.1f%%", v);
	return sys->sprint("%.2f%%", v);
}

connecting  := 0;
last_err    := "";

get_sheet_addr(): string
{
	a := readfile(ADDR_FILE);
	if(len a > 0)
		return a;
	return DEF_ADDR;
}

connect_worker(force: int, donec: chan of (int, string))
{
	if(!force && readfile(MNT + "/index") != nil){
		donec <-= (1, nil);
		return;
	}
	sys->unmount(nil, MNT);
	addr := get_sheet_addr();
	(ok, c) := sys->dial(addr, nil);
	if(ok < 0){
		donec <-= (0, sys->sprint("dial %s: %r", addr));
		return;
	}
	if(sys->mount(c.dfd, nil, MNT, Sys->MREPL, nil) < 0){
		donec <-= (0, sys->sprint("mount %s: %r", MNT));
		return;
	}
	if(readfile(MNT + "/index") != nil)
		donec <-= (1, nil);
	else
		donec <-= (0, "sheet index unreadable");
}

timeout_worker(ms: int, toutc: chan of int)
{
	sys->sleep(ms);
	toutc <-= 1;
}

start_connect(top: ref Tk->Toplevel, force: int, connc: chan of (int, string))
{
	if(connecting)
		return;
	connecting = 1;
	cmd(top, ".st configure -text {Connecting to /mnt/sheet...} -fg #1e40af");
	cmd(top, "update");
	spawn connect_timed(force, connc);
}

connect_timed(force: int, connc: chan of (int, string))
{
	donec := chan of (int, string);
	toutc := chan of int;
	spawn connect_worker(force, donec);
	spawn timeout_worker(1500, toutc);
	alt{
	res := <-donec =>
		connc <-= res;
	<-toutc =>
		connc <-= (0, "timed out waiting for Sheet");
	}
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if(e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "wm/fire: tk err on '%s': %s\n", s, e);
	return e;
}

sync_sliders(top: ref Tk->Toplevel)
{
	cmd(top, sys->sprint(".in.g.s set %d", int math->rint(cur_growth * 2.0)));
	cmd(top, sys->sprint(".in.i.s set %d", int math->rint(cur_infl * 2.0)));
	cmd(top, sys->sprint(".in.w.s set %d", int math->rint(cur_wr * 4.0)));
	cmd(top, sys->sprint(".in.sp.s set %d", cur_spend / 5000));
	cmd(top, ".in.g.v configure -text {" + fmt_pct(cur_growth) + "}");
	cmd(top, ".in.i.v configure -text {" + fmt_pct(cur_infl) + "}");
	cmd(top, ".in.w.v configure -text {" + fmt_pct(cur_wr) + "}");
	cmd(top, ".in.sp.v configure -text {$" + fmt_commas(cur_spend) + "}");
}

color_for_outcome(s: string): string
{
	if(s == "Never run out")
		return "#0a7a2f";
	return "#b3261e";
}

refresh_outputs(top: ref Tk->Toplevel)
{
	if(!connected){
		msg := "Not connected to /mnt/sheet — launch Sheet, then click Connect";
		if(len last_err > 0)
			msg = "Not connected (" + last_err + ") — click Connect";
		cmd(top, ".st configure -text {" + msg + "} -fg #b3261e");
		cmd(top, "update");
		return;
	}
	rg := readfile(MNT + "/names/real_growth");
	p1_1 := readfile(MNT + "/sheets/1/val/C20");
	p2_1 := readfile(MNT + "/sheets/1/val/E20");
	p1_all := readfile(MNT + "/sheets/1/val/C22");
	p2_all := readfile(MNT + "/sheets/1/val/E22");
	if(rg == nil){
		connected = 0;
		cmd(top, ".st configure -text {Lost connection to /mnt/sheet — click Connect} -fg #b3261e");
		cmd(top, "update");
		return;
	}

	cmd(top, ".st configure -text {Connected to /mnt/sheet (live 9P/Styx)} -fg #0a7a2f");
	cmd(top, ".out.rg.v configure -text {" + rg + "}");
	cmd(top, ".out.b1.p1 configure -text {P1: " + p1_1 + "} -fg " + color_for_outcome(p1_1));
	cmd(top, ".out.b1.p2 configure -text {P2: " + p2_1 + "} -fg " + color_for_outcome(p2_1));
	cmd(top, ".out.ba.p1 configure -text {P1: " + p1_all + "} -fg " + color_for_outcome(p1_all));
	cmd(top, ".out.ba.p2 configure -text {P2: " + p2_all + "} -fg " + color_for_outcome(p2_all));
	cmd(top, "update");
}

load_from_sheet(top: ref Tk->Toplevel, save_orig: int)
{
	if(!connected)
		return;
	cur_growth = parse_pct(readfile(MNT + "/names/stock_growth"), 10.0);
	cur_infl   = parse_pct(readfile(MNT + "/names/inflation"), 3.0);
	cur_wr     = parse_pct(readfile(MNT + "/names/Withdrawal_rate"), 4.0);
	sp := readfile(MNT + "/names/annual_spend");
	if(len sp > 0)
		cur_spend = int real sp;
	if(save_orig){
		orig_growth = cur_growth;
		orig_infl   = cur_infl;
		orig_wr     = cur_wr;
		orig_spend  = cur_spend;
	}
	sync_sliders(top);
	refresh_outputs(top);
}

apply_all(top: ref Tk->Toplevel)
{
	if(!connected)
		return;
	if(writefile(MNT + "/ctl", "batch on") < 0){
		connected = 0;
		refresh_outputs(top);
		return;
	}
	writefile(MNT + "/names/stock_growth", fmt_pct(cur_growth));
	writefile(MNT + "/names/inflation", fmt_pct(cur_infl));
	writefile(MNT + "/names/Withdrawal_rate", fmt_pct(cur_wr));
	writefile(MNT + "/names/annual_spend", string cur_spend);
	writefile(MNT + "/ctl", "batch off");
	sync_sliders(top);
	refresh_outputs(top);
}

run_sweep_spend(top: ref Tk->Toplevel)
{
	if(!connected)
		return;
	saved := cur_spend;
	txt := "Annual Spend   | 1st Batch (P1 / P2) | All Investments (P1 / P2)\n";
	txt += "---------------+---------------------+------------------------------\n";
	for(sp := 80000; sp <= 200000; sp += 15000){
		if(writefile(MNT + "/names/annual_spend", string sp) < 0){
			connected = 0;
			refresh_outputs(top);
			return;
		}
		p1_1 := readfile(MNT + "/sheets/1/val/C20");
		p2_1 := readfile(MNT + "/sheets/1/val/E20");
		p1_a := readfile(MNT + "/sheets/1/val/C22");
		p2_a := readfile(MNT + "/sheets/1/val/E22");
		mark := " ";
		if(sp == saved) mark = "*";
		txt += sys->sprint("%s$%-12s | %-7s / %-9s | %-13s / %s\n",
			mark, fmt_commas(sp), p1_1, p2_1, p1_a, p2_a);
	}
	writefile(MNT + "/names/annual_spend", string saved);
	cmd(top, ".sw.t delete 1.0 end");
	cmd(top, ".sw.t insert end {" + txt + "}");
	refresh_outputs(top);
}

run_sweep_growth(top: ref Tk->Toplevel)
{
	if(!connected)
		return;
	saved := cur_growth;
	txt := "Stock Growth   | Real  | 1st Batch (P1/P2) | All Investments (P1 / P2)\n";
	txt += "---------------+-------+-------------------+------------------------------\n";
	for(g := 5; g <= 12; g++){
		if(writefile(MNT + "/names/stock_growth", sys->sprint("%d%%", g)) < 0){
			connected = 0;
			refresh_outputs(top);
			return;
		}
		rg   := readfile(MNT + "/names/real_growth");
		p1_1 := readfile(MNT + "/sheets/1/val/C20");
		p2_1 := readfile(MNT + "/sheets/1/val/E20");
		p1_a := readfile(MNT + "/sheets/1/val/C22");
		p2_a := readfile(MNT + "/sheets/1/val/E22");
		txt += sys->sprint(" %-13s | %-5s | %-7s / %-7s | %-13s / %s\n",
			sys->sprint("%d%%", g), rg, p1_1, p2_1, p1_a, p2_a);
	}
	writefile(MNT + "/names/stock_growth", fmt_pct(saved));
	cmd(top, ".sw.t delete 1.0 end");
	cmd(top, ".sw.t insert end {" + txt + "}");
	refresh_outputs(top);
}

run_sweep_wr(top: ref Tk->Toplevel)
{
	if(!connected)
		return;
	saved := cur_wr;
	txt := "Withdrawal     | 1st Batch (P1 / P2) | All Investments (P1 / P2)\n";
	txt += "---------------+---------------------+------------------------------\n";
	rates := array[] of {2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0};
	for(i := 0; i < len rates; i++){
		rs := fmt_pct(rates[i]);
		if(writefile(MNT + "/names/Withdrawal_rate", rs) < 0){
			connected = 0;
			refresh_outputs(top);
			return;
		}
		p1_1 := readfile(MNT + "/sheets/1/val/C20");
		p2_1 := readfile(MNT + "/sheets/1/val/E20");
		p1_a := readfile(MNT + "/sheets/1/val/C22");
		p2_a := readfile(MNT + "/sheets/1/val/E22");
		txt += sys->sprint(" %-13s | %-7s / %-9s | %-13s / %s\n",
			rs, p1_1, p2_1, p1_a, p2_a);
	}
	writefile(MNT + "/names/Withdrawal_rate", fmt_pct(saved));
	cmd(top, ".sw.t delete 1.0 end");
	cmd(top, ".sw.t insert end {" + txt + "}");
	refresh_outputs(top);
}

tkcfg := array[] of {
	"frame .hdr -bg #1e293b -bd 6",
	"label .hdr.t -text {FIRE Scenario Explorer} -bg #1e293b -fg white -font " + FONT_BIG,
	"pack .hdr.t -side left -padx 6",
	"button .hdr.conn -text {Connect} -font " + FONT_UI + " -command {send cmd connect}",
	"pack .hdr.conn -side right -padx 4",
	"pack .hdr -fill x",

	"label .st -text {Connecting to /mnt/sheet...} -anchor w -font " + FONT_UI + " -bg #f1f5f9 -padx 8 -pady 4",
	"pack .st -fill x",

	# Presets bar
	"frame .pre -bg #e2e8f0 -bd 4",
	"label .pre.l -text {Presets:} -bg #e2e8f0 -font " + FONT_UI,
	"button .pre.b1 -text {Base} -font " + FONT_UI + " -command {send cmd pre_base}",
	"button .pre.b2 -text {Conservative} -font " + FONT_UI + " -command {send cmd pre_cons}",
	"button .pre.b3 -text {High Infl} -font " + FONT_UI + " -command {send cmd pre_infl}",
	"button .pre.b4 -text {Fat FIRE} -font " + FONT_UI + " -command {send cmd pre_fat}",
	"button .pre.b5 -text {Lean FIRE} -font " + FONT_UI + " -command {send cmd pre_lean}",
	"button .pre.rst -text {Reset} -font " + FONT_UI + " -command {send cmd reset}",
	"pack .pre.l .pre.b1 .pre.b2 .pre.b3 .pre.b4 .pre.b5 .pre.rst -side left -padx 3 -pady 2",
	"pack .pre -fill x",

	# Inputs frame
	"frame .in -bg white -bd 6",

	"frame .in.g -bg white",
	"label .in.g.l -text {Stock Growth} -width 155 -anchor w -bg white -font " + FONT_UI,
	"scale .in.g.s -orient horizontal -from 8 -to 28 -showvalue 0 -length 340 -command {send cmd sg}",
	"label .in.g.v -text {10%} -width 95 -anchor e -bg white -font " + FONT_UI,
	"pack .in.g.l .in.g.s .in.g.v -side left -padx 6 -pady 4",
	"pack .in.g -fill x",

	"frame .in.i -bg white",
	"label .in.i.l -text {Inflation} -width 155 -anchor w -bg white -font " + FONT_UI,
	"scale .in.i.s -orient horizontal -from 2 -to 14 -showvalue 0 -length 340 -command {send cmd si}",
	"label .in.i.v -text {3%} -width 95 -anchor e -bg white -font " + FONT_UI,
	"pack .in.i.l .in.i.s .in.i.v -side left -padx 6 -pady 4",
	"pack .in.i -fill x",

	"frame .in.w -bg white",
	"label .in.w.l -text {Withdrawal Rate} -width 155 -anchor w -bg white -font " + FONT_UI,
	"scale .in.w.s -orient horizontal -from 10 -to 24 -showvalue 0 -length 340 -command {send cmd sw}",
	"label .in.w.v -text {4%} -width 95 -anchor e -bg white -font " + FONT_UI,
	"pack .in.w.l .in.w.s .in.w.v -side left -padx 6 -pady 4",
	"pack .in.w -fill x",

	"frame .in.sp -bg white",
	"label .in.sp.l -text {Annual Spending} -width 155 -anchor w -bg white -font " + FONT_UI,
	"scale .in.sp.s -orient horizontal -from 12 -to 44 -showvalue 0 -length 340 -command {send cmd ssp}",
	"label .in.sp.v -text {$120,000} -width 95 -anchor e -bg white -font " + FONT_UI,
	"pack .in.sp.l .in.sp.s .in.sp.v -side left -padx 6 -pady 4",
	"pack .in.sp -fill x",

	"pack .in -fill x",

	# Live outputs card
	"frame .out -bg #f8fafc -bd 2 -relief groove",
	"frame .out.rg -bg #f8fafc",
	"label .out.rg.l -text {Real Stock Market Growth:} -width 230 -anchor w -bg #f8fafc -font " + FONT_UI,
	"label .out.rg.v -text {-} -width 175 -anchor w -bg #f8fafc -fg #1e40af -font " + FONT_UI,
	"pack .out.rg.l .out.rg.v -side left -padx 8 -pady 4",
	"pack .out.rg -fill x",

	"frame .out.b1 -bg #f8fafc",
	"label .out.b1.l -text {1st Batch Runs Out:} -width 230 -anchor w -bg #f8fafc -font " + FONT_UI,
	"label .out.b1.p1 -text {P1: -} -width 185 -anchor w -bg #f8fafc -font " + FONT_UI,
	"label .out.b1.p2 -text {P2: -} -width 185 -anchor w -bg #f8fafc -font " + FONT_UI,
	"pack .out.b1.l .out.b1.p1 .out.b1.p2 -side left -padx 8 -pady 4",
	"pack .out.b1 -fill x",

	"frame .out.ba -bg #f8fafc",
	"label .out.ba.l -text {All Investments Run Out:} -width 230 -anchor w -bg #f8fafc -font " + FONT_UI,
	"label .out.ba.p1 -text {P1: -} -width 185 -anchor w -bg #f8fafc -font " + FONT_UI,
	"label .out.ba.p2 -text {P2: -} -width 185 -anchor w -bg #f8fafc -font " + FONT_UI,
	"pack .out.ba.l .out.ba.p1 .out.ba.p2 -side left -padx 8 -pady 4",
	"pack .out.ba -fill x",
	"pack .out -fill x -padx 6 -pady 6",

	# Sweep buttons + output table
	"frame .swb -bg #e2e8f0 -bd 4",
	"label .swb.l -text {Sensitivity Sweep:} -bg #e2e8f0 -font " + FONT_UI,
	"button .swb.sp -text {Sweep Spending} -font " + FONT_UI + " -command {send cmd sweep_spend}",
	"button .swb.gr -text {Sweep Growth} -font " + FONT_UI + " -command {send cmd sweep_growth}",
	"button .swb.wr -text {Sweep Withdrawal} -font " + FONT_UI + " -command {send cmd sweep_wr}",
	"pack .swb.l .swb.sp .swb.gr .swb.wr -side left -padx 4 -pady 2",
	"pack .swb -fill x",

	"frame .sw -bg white",
	"text .sw.t -width 680 -height 220 -bg white -fg #0f172a -font " + FONT_MONO,
	"pack .sw.t -fill both -expand 1 -padx 6 -pady 6",
	"pack .sw -fill both -expand 1",
	"update",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	math = load Math Math->PATH;

	sys->pctl(Sys->NEWPGRP | Sys->FORKNS, nil);
	tkclient->init();
	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wm/fire: no draw context\n");
		raise "fail:no context";
	}

	(top, titlectl) := tkclient->toplevel(ctxt, "", "FIRE Explorer", Tkclient->Appl);
	cmdc := chan of string;
	tk->namechan(top, cmdc, "cmd");

	for(i := 0; i < len tkcfg; i++)
		cmd(top, tkcfg[i]);

	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd" :: "ptr" :: nil);

	connc := chan of (int, string);
	start_connect(top, 0, connc);

	for(;;) alt{
	(ok, cerr) := <-connc =>
		connecting = 0;
		connected = ok;
		last_err = cerr;
		if(connected){
			load_from_sheet(top, 1);
			run_sweep_spend(top);
		}else{
			refresh_outputs(top);
		}
	s := <-top.ctxt.kbd =>
		tk->keyboard(top, s);
	s := <-top.ctxt.ptr =>
		tk->pointer(top, *s);
	s := <-top.ctxt.ctl or
	s = <-top.wreq or
	s = <-titlectl =>
		if(s == "exit")
			sys->unmount(nil, MNT);
		tkclient->wmctl(top, s);

	msg := <-cmdc =>
		# Coalesce rapid slider drags so only the latest value hits /mnt/sheet
	Drain:
		for(;;){
			alt{
			m2 := <-cmdc =>
				msg = m2;
			* =>
				break Drain;
			}
		}
		(n, flds) := sys->tokenize(msg, " \t");
		if(n == 0)
			continue;
		op := hd flds;
		case op {
		"connect" =>
			start_connect(top, 1, connc);
		"sg" =>
			if(tl flds != nil){
				nv := real (int hd tl flds) / 2.0;
				if(math->fabs(nv - cur_growth) > 0.01){
					cur_growth = nv;
					cmd(top, ".in.g.v configure -text {" + fmt_pct(cur_growth) + "}");
					if(connected){
						writefile(MNT + "/names/stock_growth", fmt_pct(cur_growth));
						refresh_outputs(top);
					}
				}
			}
		"si" =>
			if(tl flds != nil){
				nv := real (int hd tl flds) / 2.0;
				if(math->fabs(nv - cur_infl) > 0.01){
					cur_infl = nv;
					cmd(top, ".in.i.v configure -text {" + fmt_pct(cur_infl) + "}");
					if(connected){
						writefile(MNT + "/names/inflation", fmt_pct(cur_infl));
						refresh_outputs(top);
					}
				}
			}
		"sw" =>
			if(tl flds != nil){
				nv := real (int hd tl flds) / 4.0;
				if(math->fabs(nv - cur_wr) > 0.01){
					cur_wr = nv;
					cmd(top, ".in.w.v configure -text {" + fmt_pct(cur_wr) + "}");
					if(connected){
						writefile(MNT + "/names/Withdrawal_rate", fmt_pct(cur_wr));
						refresh_outputs(top);
					}
				}
			}
		"ssp" =>
			if(tl flds != nil){
				nv := int hd tl flds * 5000;
				if(nv != cur_spend){
					cur_spend = nv;
					cmd(top, ".in.sp.v configure -text {$" + fmt_commas(cur_spend) + "}");
					if(connected){
						writefile(MNT + "/names/annual_spend", string cur_spend);
						refresh_outputs(top);
					}
				}
			}
		"pre_base" =>
			cur_growth = 10.0; cur_infl = 3.0; cur_wr = 4.0; cur_spend = 120000;
			apply_all(top);
		"pre_cons" =>
			cur_growth = 7.0; cur_infl = 3.5; cur_wr = 3.5; cur_spend = 120000;
			apply_all(top);
		"pre_infl" =>
			cur_growth = 8.0; cur_infl = 5.0; cur_wr = 4.0; cur_spend = 130000;
			apply_all(top);
		"pre_fat" =>
			cur_growth = 10.0; cur_infl = 3.0; cur_wr = 4.0; cur_spend = 160000;
			apply_all(top);
		"pre_lean" =>
			cur_growth = 9.0; cur_infl = 3.0; cur_wr = 3.5; cur_spend = 90000;
			apply_all(top);
		"reset" =>
			cur_growth = orig_growth; cur_infl = orig_infl;
			cur_wr = orig_wr; cur_spend = orig_spend;
			apply_all(top);
		"sweep_spend" =>
			run_sweep_spend(top);
		"sweep_growth" =>
			run_sweep_growth(top);
		"sweep_wr" =>
			run_sweep_wr(top);
		}
	}
}
