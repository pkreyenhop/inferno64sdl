implement Mandelbrot;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect: import draw;

include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

Mandelbrot: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

MAXITER := 128;

# Palette of 256 RGB triplets (768 bytes)
palette: array of byte;

makepalette()
{
	palette = array[256 * 3] of byte;
	for(i := 0; i < 256; i++){
		t := real i / 255.0;
		# Smooth polynomial RGB gradient (deep blue -> cyan -> gold -> white)
		r := int (9.0 * (1.0 - t) * t * t * t * 255.0);
		g := int (15.0 * (1.0 - t) * (1.0 - t) * t * t * 255.0);
		b := int (8.5 * (1.0 - t) * (1.0 - t) * (1.0 - t) * t * 255.0);
		if(r > 255) r = 255;
		if(g > 255) g = 255;
		if(b > 255) b = 255;
		palette[i*3 + 0] = byte b;
		palette[i*3 + 1] = byte g;
		palette[i*3 + 2] = byte r;
	}
}

render(win: ref Window, cx, cy, span: real, maxiter: int)
{
	img := win.image;
	if(img == nil)
		return;

	r := win.image.r;
	w := r.dx();
	h := r.dy();
	if(w <= 0 || h <= 0)
		return;

	tmp := win.display.newimage(Rect((0, 0), (w, h)), Draw->RGB24, 0, Draw->Black);
	if(tmp == nil)
		return;

	row := array[w * 3] of byte;
	aspect := real h / real w;
	xmin := cx - span / 2.0;
	ymin := cy - (span * aspect) / 2.0;
	dx := span / real w;
	dy := (span * aspect) / real h;

	for(py := 0; py < h; py++){
		ci := ymin + real py * dy;
		off := 0;
		for(px := 0; px < w; px++){
			cr := xmin + real px * dx;
			zr := 0.0;
			zi := 0.0;
			iter := 0;
			while(iter < maxiter){
				zr2 := zr * zr;
				zi2 := zi * zi;
				if(zr2 + zi2 > 4.0)
					break;
				zi = 2.0 * zr * zi + ci;
				zr = zr2 - zi2 + cr;
				iter++;
			}
			if(iter == maxiter){
				row[off++] = byte 0;
				row[off++] = byte 0;
				row[off++] = byte 0;
			}else{
				ci3 := ((iter * 255) / maxiter) * 3;
				row[off++] = palette[ci3 + 0];
				row[off++] = palette[ci3 + 1];
				row[off++] = palette[ci3 + 2];
			}
		}
		tmp.writepixels(Rect((0, py), (w, py + 1)), row);
	}

	img.draw(r, tmp, nil, (0, 0));
	win.display.image.flush(Draw->Flushnow);
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "mandelbrot: cannot make draw context: %r\n");
		raise "fail:no context";
	}

	makepalette();

	win := wmclient->window(ctxt, "Mandelbrot", Wmclient->Appl);
	win.reshape(Rect((0, 0), (640, 480)));
	win.onscreen("place");
	win.startinput("kbd" :: "ptr" :: nil);

	cx := -0.5;
	cy := 0.0;
	span := 3.2;
	maxiter := MAXITER;
	lastb := 0;

	render(win, cx, cy, span, maxiter);

	for(;;) alt{
	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		win.wmctl(ctl);
		if(ctl != nil && (ctl[0] == '!' || (len ctl >= 4 && ctl[0:4] == "size")))
			render(win, cx, cy, span, maxiter);

	p := <-win.ctxt.ptr =>
		if(!win.pointer(*p)){
			if(p.buttons != 0 && lastb == 0){
				r := win.image.r;
				w := r.dx();
				h := r.dy();
				if(w > 0 && h > 0){
					aspect := real h / real w;
					mx := real (p.xy.x - r.min.x) / real w;
					my := real (p.xy.y - r.min.y) / real h;
					cx = (cx - span / 2.0) + mx * span;
					cy = (cy - (span * aspect) / 2.0) + my * (span * aspect);
					if(p.buttons & 1)
						span /= 2.0;
					else if(p.buttons & 4)
						span *= 2.0;
					render(win, cx, cy, span, maxiter);
				}
			}
			lastb = p.buttons;
		}

	c := <-win.ctxt.kbd =>
		case c {
		'q' or 'Q' =>
			exit;
		'r' or 'R' =>
			cx = -0.5;
			cy = 0.0;
			span = 3.2;
			maxiter = MAXITER;
			render(win, cx, cy, span, maxiter);
		'+' or '=' =>
			maxiter *= 2;
			if(maxiter > 4096) maxiter = 4096;
			render(win, cx, cy, span, maxiter);
		'-' =>
			maxiter /= 2;
			if(maxiter < 32) maxiter = 32;
			render(win, cx, cy, span, maxiter);
		}
	}
}
