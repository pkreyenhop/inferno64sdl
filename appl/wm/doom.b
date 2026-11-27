implement WmDoom;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect: import draw;

include "keyboard.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "doom.m";
	doom: Doom;

WmDoom: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# DOOM key codes (from doomkeys.h)
KEY_STRAFE_L:	con 16ra0;
KEY_STRAFE_R:	con 16ra1;
KEY_USE:	con 16ra2;
KEY_FIRE:	con 16ra3;
KEY_LEFTARROW:	con 16rac;
KEY_UPARROW:	con 16rad;
KEY_RIGHTARROW:	con 16rae;
KEY_DOWNARROW:	con 16raf;
KEY_TAB:	con 9;
KEY_ENTER:	con 13;
KEY_ESCAPE:	con 27;

HOLD_MS:	con 180;

heldkeys: array of int;
helduntil: array of int;
nheld := 0;

presskey(k: int)
{
	now := sys->millisec();
	for(i := 0; i < nheld; i++){
		if(heldkeys[i] == k){
			helduntil[i] = now + HOLD_MS;
			return;
		}
	}
	if(nheld < len heldkeys){
		heldkeys[nheld] = k;
		helduntil[nheld] = now + HOLD_MS;
		nheld++;
	}
	doom->key(1, k);
}

releaseexpired()
{
	now := sys->millisec();
	i := 0;
	while(i < nheld){
		if(now >= helduntil[i]){
			doom->key(0, heldkeys[i]);
			nheld--;
			heldkeys[i] = heldkeys[nheld];
			helduntil[i] = helduntil[nheld];
		}else{
			i++;
		}
	}
}

mapkey(c: int): int
{
	case c {
	Keyboard->Up or 'w' or 'W' =>
		return KEY_UPARROW;
	Keyboard->Down or 's' or 'S' =>
		return KEY_DOWNARROW;
	Keyboard->Left =>
		return KEY_LEFTARROW;
	Keyboard->Right =>
		return KEY_RIGHTARROW;
	'a' or 'A' =>
		return KEY_STRAFE_L;
	'd' or 'D' =>
		return KEY_STRAFE_R;
	'e' or 'E' or ' ' =>
		return KEY_USE;
	'f' or 'F' =>
		return KEY_FIRE;
	'\n' or '\r' =>
		return KEY_ENTER;
	Keyboard->Esc =>
		return KEY_ESCAPE;
	'\t' =>
		return KEY_TAB;
	* =>
		if(c >= 32 && c < 127)
			return c;
		return 0;
	}
}

ticker(ch: chan of int, stop: chan of int)
{
	for(;;){
		sys->sleep(25);
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
	doom = load Doom Doom->PATH;

	if(doom == nil){
		sys->fprint(sys->fildes(2), "wm/doom: cannot load $Doom: %r\n");
		raise "fail:load";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wm/doom: cannot make draw context: %r\n");
		raise "fail:no context";
	}

	wad := "/lib/doom/freedoom1.wad";
	if(argv != nil && tl argv != nil)
		wad = hd tl argv;

	(dw, dh) := doom->start(wad);
	if(dw <= 0 || dh <= 0){
		sys->fprint(sys->fildes(2), "wm/doom: failed to load WAD %s\n", wad);
		raise "fail:wad";
	}

	win := wmclient->window(ctxt, "Doom", Wmclient->Appl);
	win.reshape(Rect((0, 0), (dw, dh)));
	win.onscreen("place");
	win.startinput("kbd" :: "ptr" :: nil);

	frame := win.display.newimage(Rect((0, 0), (dw, dh)), Draw->XRGB32, 0, Draw->Black);
	fb := array[dw * dh * 4] of byte;

	heldkeys = array[16] of int;
	helduntil = array[16] of int;
	nheld = 0;

	tickch := chan of int;
	stopch := chan of int;
	spawn ticker(tickch, stopch);

	lastb := 0;

	for(;;) alt{
	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		if(ctl == "exit"){
			alt{ stopch <-= 1 => ; * => ; }
			exit;
		}
		win.wmctl(ctl);

	p := <-win.ctxt.ptr =>
		if(!win.pointer(*p)){
			if((p.buttons & 1) && !(lastb & 1))
				doom->key(1, KEY_FIRE);
			else if(!(p.buttons & 1) && (lastb & 1))
				doom->key(0, KEY_FIRE);

			if((p.buttons & 4) && !(lastb & 4))
				doom->key(1, KEY_USE);
			else if(!(p.buttons & 4) && (lastb & 4))
				doom->key(0, KEY_USE);

			lastb = p.buttons;
		}

	c := <-win.ctxt.kbd =>
		k := mapkey(c);
		if(k != 0)
			presskey(k);

	<-tickch =>
		releaseexpired();
		if(doom->tick(fb) != 0 && win.image != nil){
			frame.writepixels(Rect((0, 0), (dw, dh)), fb);
			win.image.draw(win.image.r, frame, nil, (0, 0));
			win.display.image.flush(Draw->Flushnow);
		}
	}
}
