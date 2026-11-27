implement WmNetSurf;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect: import draw;

include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "netsurf.m";
	ns: NetSurf;

WmNetSurf: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

ticker(ch: chan of int, stop: chan of int)
{
	for(;;){
		sys->sleep(33);
		alt{
		<-stop =>
			return;
		ch <-= 1 =>
			;
		* =>
			;
		}
	}
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	ns = load NetSurf NetSurf->PATH;

	if(ns == nil){
		sys->fprint(sys->fildes(2), "wm/netsurf: cannot load $NetSurf: %r\n");
		raise "fail:load";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wm/netsurf: cannot make draw context: %r\n");
		raise "fail:no context";
	}

	url := "https://lite.duckduckgo.com/lite/";
	if(argv != nil && tl argv != nil)
		url = hd tl argv;

	w := 1024;
	h := 768;

	if(ns->start(w, h, url) < 0){
		sys->fprint(sys->fildes(2), "wm/netsurf: failed to start NetSurf\n");
		raise "fail:start";
	}

	win := wmclient->window(ctxt, "NetSurf", Wmclient->Appl);
	win.reshape(Rect((0, 0), (w, h)));
	win.onscreen("place");
	win.startinput("kbd" :: "ptr" :: nil);

	frame := win.display.newimage(Rect((0, 0), (w, h)), Draw->XRGB32, 0, Draw->White);
	fb := array[w * h * 4] of byte;

	tickch := chan of int;
	stopch := chan of int;
	spawn ticker(tickch, stopch);

	for(;;) alt{
	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		if(ctl == "exit"){
			alt{ stopch <-= 1 => ; * => ; }
			exit;
		}
		win.wmctl(ctl);
		if(win.image != nil){
			nw := win.image.r.dx();
			nh := win.image.r.dy();
			if(nw >= 300 && nh >= 200 && (nw != w || nh != h)){
				w = nw;
				h = nh;
				frame = win.display.newimage(Rect((0, 0), (w, h)), Draw->XRGB32, 0, Draw->White);
				fb = array[w * h * 4] of byte;
				ns->resize(w, h);
			}
		}

	p := <-win.ctxt.ptr =>
		if(!win.pointer(*p) && win.image != nil){
			mx := p.xy.x - win.image.r.min.x;
			my := p.xy.y - win.image.r.min.y;
			ns->mouse(mx, my, p.buttons);
		}

	c := <-win.ctxt.kbd =>
		ns->key(c);

	<-tickch =>
		(dirty, fw, fh) := ns->step(fb);
		if(dirty != 0 && win.image != nil && fw > 0 && fh > 0){
			if(fw != w || fh != h){
				w = fw;
				h = fh;
				frame = win.display.newimage(Rect((0, 0), (w, h)), Draw->XRGB32, 0, Draw->White);
				fb = array[w * h * 4] of byte;
			}else{
				frame.writepixels(Rect((0, 0), (fw, fh)), fb);
				win.image.draw(win.image.r, frame, nil, (0, 0));
				win.display.image.flush(Draw->Flushnow);
			}
		}
	}
}
