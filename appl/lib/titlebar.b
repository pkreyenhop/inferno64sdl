implement Titlebar;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "titlebar.m";

TB_FONT: con "/fonts/vera/verabd/verabd.16.font";

title_cfg := array[] of {
	"frame .Wm_t -bg #e2e8f0 -borderwidth 0",
	"label .Wm_t.title -anchor w -bg #e2e8f0 -fg #64748b -font " + TB_FONT + " -padx 10 -pady 5",
	"button .Wm_t.e -text {x} -font " + TB_FONT + " -bg #fee2e2 -fg #b91c1c -activebackground #fecaca -activeforeground #991b1b -relief flat -bd 0 -width 26 -height 22 -command {send wm_title exit} -takefocus 0",
	"pack .Wm_t.e -side right -padx 4 -pady 3",
	"bind .Wm_t <Button-1> {send wm_title move %X %Y}",
	"bind .Wm_t <Double-Button-1> {send wm_title lower .}",
	"bind .Wm_t <Motion-Button-1> {}",
	"bind .Wm_t <Motion> {}",
	"bind .Wm_t.title <Button-1> {send wm_title move %X %Y}",
	"bind .Wm_t.title <Double-Button-1> {send wm_title lower .}",
	"bind .Wm_t.title <Motion-Button-1> {}",
	"bind .Wm_t.title <Motion> {}",
	"bind . <FocusIn> {.Wm_t configure -bg #f1f5f9;"+
		".Wm_t.title configure -bg #f1f5f9 -fg #0f172a;update}",
	"bind . <FocusOut> {.Wm_t configure -bg #e2e8f0;"+
		".Wm_t.title configure -bg #e2e8f0 -fg #64748b;update}",
};

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

new(top: ref Tk->Toplevel, buts: int): chan of string
{
	ctl := chan of string;
	tk->namechan(top, ctl, "wm_title");

	if(buts & Plain)
		return ctl;

	for(i := 0; i < len title_cfg; i++)
		cmd(top, title_cfg[i]);

	bstyle := " -font " + TB_FONT + " -bg #e2e8f0 -fg #334155 -activebackground #cbd5e1 -activeforeground #0f172a -relief flat -bd 0 -width 26 -height 22 -takefocus 0";

	if(buts & OK)
		cmd(top, "button .Wm_t.ok -text {OK}" + bstyle +
			" -command {send wm_title ok}; pack .Wm_t.ok -side right -padx 2 -pady 3");

	if(buts & Hide)
		cmd(top, "button .Wm_t.top -text {-}" + bstyle +
			" -command {send wm_title task}; pack .Wm_t.top -side right -padx 2 -pady 3");

	if(buts & Resize)
		cmd(top, "button .Wm_t.m -text {+}" + bstyle +
			" -command {send wm_title size}; pack .Wm_t.m -side right -padx 2 -pady 3");

	if(buts & Help)
		cmd(top, "button .Wm_t.h -text {?}" + bstyle +
			" -command {send wm_title help}; pack .Wm_t.h -side right -padx 2 -pady 3");

	# pack the title last so it gets clipped first
	cmd(top, "pack .Wm_t.title -side left -fill x");
	cmd(top, "pack .Wm_t -fill x");

	return ctl;
}

title(top: ref Tk->Toplevel): string
{
	if(tk->cmd(top, "winfo class .Wm_t.title")[0] != '!')
		return cmd(top, ".Wm_t.title cget -text");
	return nil;
}
	
settitle(top: ref Tk->Toplevel, t: string): string
{
	s := title(top);
	tk->cmd(top, ".Wm_t.title configure -text '" + t);
	return s;
}

sendctl(top: ref Tk->Toplevel, c: string)
{
	cmd(top, "send wm_title " + c);
}

minsize(top: ref Tk->Toplevel): Point
{
	buts := array[] of {"e", "ok", "top", "m", "h"};
	r := tk->rect(top, ".", Tk->Border);
	r.min.x = r.max.x;
	r.max.y = r.min.y;
	for(i := 0; i < len  buts; i++){
		br := tk->rect(top, ".Wm_t." + buts[i], Tk->Border);
		if(br.dx() > 0)
			r = r.combine(br);
	}
	r.max.x += tk->rect(top, ".Wm_t." + buts[0], Tk->Border).dx();
	return r.size();
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "wmclient: tk error %s on '%s'\n", e, s);
	return e;
}
