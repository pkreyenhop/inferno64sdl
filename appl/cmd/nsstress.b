implement NsStress;

include "sys.m";
	sys: Sys;
include "draw.m";
include "netsurf.m";
	ns: NetSurf;

NsStress: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

pump(fb: array of byte, steps: int, label: string)
{
	frames := 0;
	for(i := 0; i < steps; i++){
		(dirty, nil, nil) := ns->step(fb);
		if(dirty != 0)
			frames++;
		sys->sleep(33);
	}
	sys->print("  [%s] %d steps, %d frames rendered\n", label, steps, frames);
}

click(x, y: int)
{
	ns->mouse(x, y, 0);
	ns->mouse(x, y, 1);
	ns->mouse(x, y, 0);
}

scroll(x, y, times, btn: int)
{
	for(i := 0; i < times; i++){
		ns->mouse(x, y, btn);
		ns->mouse(x, y, 0);
	}
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	ns = load NetSurf NetSurf->PATH;
	if(ns == nil){
		sys->fprint(sys->fildes(2), "nsstress: cannot load $NetSurf: %r\n");
		raise "fail:load";
	}

	w := 1024;
	h := 768;
	fb := array[w * h * 4] of byte;

	sys->print("1. Starting NetSurf on Hacker News...\n");
	if(ns->start(w, h, "https://news.ycombinator.com/") < 0){
		sys->fprint(sys->fildes(2), "nsstress: ns->start failed\n");
		raise "fail:start";
	}
	pump(fb, 60, "HN front");

	sys->print("2. Scrolling Hacker News...\n");
	scroll(400, 300, 8, 16); # scroll down
	pump(fb, 20, "HN scroll down");
	scroll(400, 300, 8, 8);  # scroll up
	pump(fb, 20, "HN scroll up");

	sys->print("3. Navigating Hacker News sections...\n");
	urls := array[] of {
		"https://news.ycombinator.com/newest",
		"https://news.ycombinator.com/ask",
		"https://news.ycombinator.com/show",
		"https://news.ycombinator.com/news",
	};
	for(i := 0; i < len urls; i++){
		ns->navigate(urls[i]);
		pump(fb, 50, urls[i]);
	}

	sys->print("4. Clicking top story & resizing while loading...\n");
	click(220, 105);
	pump(fb, 25, "HN click story");
	w = 900;
	h = 650;
	fb = array[w * h * 4] of byte;
	ns->resize(w, h);
	pump(fb, 40, "HN after resize");

	sys->print("5. Back to HN & rapid navigation...\n");
	ns->navigate("https://news.ycombinator.com/");
	pump(fb, 15, "HN rapid 1");
	ns->navigate("https://lite.duckduckgo.com/lite/");
	pump(fb, 40, "DDG Lite");
	ns->navigate("https://en.wikipedia.org/wiki/Inferno_(operating_system)");
	pump(fb, 60, "Wikipedia");

	sys->print("STRESS_OK\n");
}
