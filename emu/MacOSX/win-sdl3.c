#include "dat.h"
#include "fns.h"
#include "cursor.h"
#include "keyboard.h"
#include <draw.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/*
 * Avoid macro collisions between Inferno's lib9.h and SDL3 headers
 */
#undef malloc
#undef free
#undef realloc
#undef calloc

#include <SDL3/SDL.h>

enum {
	CursorSize = 32,
	CursorBytes = CursorSize * CursorSize / 8,
};

extern int Xsize;
extern int Ysize;
extern ulong displaychan;

/* Main-thread / kproc synchronization */
static pthread_mutex_t sdl_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  sdl_cv = PTHREAD_COND_INITIALIZER;

static int screen_requested = 0;
static int screen_ready = 0;
static int screen_failed = 0;
static int want_fullscreen = 0;

/* Framebuffer (XRGB32: 4 bytes per pixel, little-endian [B, G, R, X] == SDL_PIXELFORMAT_XRGB8888) */
static uchar *fbdata = nil;
static int fbw = 0;
static int fbh = 0;

/* Dirty rectangle tracking */
static pthread_mutex_t dirty_mu = PTHREAD_MUTEX_INITIALIZER;
static int dirty_flag = 0;
static Rectangle dirty_rect;

/* Cursor state */
static pthread_mutex_t curs_mu = PTHREAD_MUTEX_INITIALIZER;
static int curs_changed = 0;
static int curs_custom = 0;
static int curs_w = 0;
static int curs_h = 0;
static int curs_hotx = 0;
static int curs_hoty = 0;
static uchar curs_data[CursorBytes];
static uchar curs_mask[CursorBytes];

/* Pointer warp state */
static pthread_mutex_t warp_mu = PTHREAD_MUTEX_INITIALIZER;
static int warp_pending = 0;
static int warp_x = 0;
static int warp_y = 0;

/* Clipboard request/response state */
static pthread_mutex_t clip_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  clip_cv = PTHREAD_COND_INITIALIZER;
static int clip_op = 0; /* 0=none, 1=read, 2=write */
static char *clip_in = nil;
static char *clip_out = nil;
static int clip_done = 0;

/* SDL3 objects (owned strictly by main thread) */
static SDL_Window   *sdl_win = nil;
static SDL_Renderer *sdl_ren = nil;
static SDL_Texture  *sdl_tex = nil;
static SDL_Cursor   *sdl_cur = nil;
static Uint32        sdl_ev_wakeup = 0;

/* Pointer button state */
static int mouse_buttons = 0;
static int mouse_x = 0;
static int mouse_y = 0;

static void
push_wakeup(void)
{
	if(sdl_ev_wakeup != 0){
		SDL_Event ev;
		memset(&ev, 0, sizeof(ev));
		ev.type = sdl_ev_wakeup;
		SDL_PushEvent(&ev);
	}
}

static void
present_framebuffer(void)
{
	Rectangle r;
	int do_update = 0;

	pthread_mutex_lock(&dirty_mu);
	if(dirty_flag){
		r = dirty_rect;
		dirty_flag = 0;
		do_update = 1;
	}
	pthread_mutex_unlock(&dirty_mu);

	if(do_update && fbdata != nil && sdl_tex != nil){
		if(r.min.x < 0) r.min.x = 0;
		if(r.min.y < 0) r.min.y = 0;
		if(r.max.x > fbw) r.max.x = fbw;
		if(r.max.y > fbh) r.max.y = fbh;
		if(r.min.x < r.max.x && r.min.y < r.max.y){
			SDL_Rect sr;
			sr.x = r.min.x;
			sr.y = r.min.y;
			sr.w = r.max.x - r.min.x;
			sr.h = r.max.y - r.min.y;
			SDL_UpdateTexture(sdl_tex, &sr,
				fbdata + (size_t)r.min.y * (size_t)fbw * 4 + (size_t)r.min.x * 4,
				fbw * 4);
		}
	}

	if(sdl_ren != nil && sdl_tex != nil){
		SDL_RenderClear(sdl_ren);
		SDL_RenderTexture(sdl_ren, sdl_tex, NULL, NULL);
		SDL_RenderPresent(sdl_ren);
	}
}

static void
apply_cursor(void)
{
	int custom, w, h, hx, hy;
	uchar data[CursorBytes], mask[CursorBytes];

	pthread_mutex_lock(&curs_mu);
	if(!curs_changed){
		pthread_mutex_unlock(&curs_mu);
		return;
	}
	curs_changed = 0;
	custom = curs_custom;
	w = curs_w;
	h = curs_h;
	hx = curs_hotx;
	hy = curs_hoty;
	if(custom){
		memcpy(data, curs_data, sizeof(data));
		memcpy(mask, curs_mask, sizeof(mask));
	}
	pthread_mutex_unlock(&curs_mu);

	if(sdl_cur != nil){
		SDL_DestroyCursor(sdl_cur);
		sdl_cur = nil;
	}

	if(!custom || w <= 0 || h <= 0){
		SDL_SetCursor(SDL_GetDefaultCursor());
		return;
	}

	if(hx < 0) hx = 0;
	if(hy < 0) hy = 0;
	if(hx >= w) hx = w - 1;
	if(hy >= h) hy = h - 1;

	sdl_cur = SDL_CreateCursor(data, mask, w, h, hx, hy);
	if(sdl_cur != nil)
		SDL_SetCursor(sdl_cur);
	else
		SDL_SetCursor(SDL_GetDefaultCursor());
}

static void
apply_warp(void)
{
	int do_warp = 0, x = 0, y = 0;

	pthread_mutex_lock(&warp_mu);
	if(warp_pending){
		warp_pending = 0;
		do_warp = 1;
		x = warp_x;
		y = warp_y;
	}
	pthread_mutex_unlock(&warp_mu);

	if(do_warp && sdl_win != nil)
		SDL_WarpMouseInWindow(sdl_win, (float)x, (float)y);
}

static void
apply_clipboard(void)
{
	pthread_mutex_lock(&clip_mu);
	if(clip_op == 1){
		char *s = SDL_GetClipboardText();
		if(s != nil){
			clip_out = kmalloc(strlen(s) + 1);
			if(clip_out != nil)
				strcpy(clip_out, s);
			SDL_free(s);
		}else{
			clip_out = nil;
		}
		clip_op = 0;
		clip_done = 1;
		pthread_cond_signal(&clip_cv);
	}else if(clip_op == 2){
		if(clip_in != nil)
			SDL_SetClipboardText(clip_in);
		clip_op = 0;
		clip_done = 1;
		pthread_cond_signal(&clip_cv);
	}
	pthread_mutex_unlock(&clip_mu);
}

static void
map_mouse_coords(float fx, float fy, int *ox, int *oy)
{
	int ww = fbw, wh = fbh;
	if(sdl_win != nil)
		SDL_GetWindowSize(sdl_win, &ww, &wh);
	if(ww > 0 && wh > 0 && (ww != fbw || wh != fbh)){
		*ox = (int)(fx * (float)fbw / (float)ww);
		*oy = (int)(fy * (float)fbh / (float)wh);
	}else{
		*ox = (int)fx;
		*oy = (int)fy;
	}
	if(*ox < 0) *ox = 0;
	if(*oy < 0) *oy = 0;
	if(*ox >= fbw) *ox = fbw - 1;
	if(*oy >= fbh) *oy = fbh - 1;
}

static int
sdl_button_mask(Uint8 button, SDL_Keymod mod)
{
	switch(button){
	case SDL_BUTTON_LEFT:
		if(mod & SDL_KMOD_ALT)
			return 2;
		if(mod & (SDL_KMOD_GUI | SDL_KMOD_CTRL))
			return 4;
		return 1;
	case SDL_BUTTON_MIDDLE:
		return 2;
	case SDL_BUTTON_RIGHT:
		return 4;
	default:
		return 0;
	}
}

static void
handle_keydown(SDL_KeyboardEvent *kev)
{
	SDL_Keycode sym = kev->key;
	SDL_Keymod mod = kev->mod;
	int r = -1;

	/* Cmd+Q quits cleanly on macOS */
	if((mod & SDL_KMOD_GUI) && sym == SDLK_Q){
		cleanexit(0);
		return;
	}

	/* Control key combinations (Ctrl+A .. Ctrl+Z, etc.) */
	if((mod & SDL_KMOD_CTRL) && sym >= 'a' && sym <= 'z'){
		gkbdputc(gkbdq, (sym - 'a') + 1);
		return;
	}
	if((mod & SDL_KMOD_CTRL) && sym >= '[' && sym <= '_'){
		gkbdputc(gkbdq, sym & 0x1f);
		return;
	}

	switch(sym){
	case SDLK_BACKSPACE:	r = '\b'; break;
	case SDLK_TAB:		r = (mod & SDL_KMOD_SHIFT) ? BackTab : '\t'; break;
	case SDLK_RETURN:
	case SDLK_KP_ENTER:	r = '\n'; break;
	case SDLK_ESCAPE:	r = Esc; break;
	case SDLK_DELETE:	r = Del; break;
	case SDLK_INSERT:	r = Ins; break;
	case SDLK_HOME:		r = Home; break;
	case SDLK_END:		r = End; break;
	case SDLK_UP:		r = Up; break;
	case SDLK_DOWN:		r = Down; break;
	case SDLK_LEFT:		r = Left; break;
	case SDLK_RIGHT:	r = Right; break;
	case SDLK_PAGEUP:	r = Pgup; break;
	case SDLK_PAGEDOWN:	r = Pgdown; break;
	case SDLK_F1:		r = KF|1; break;
	case SDLK_F2:		r = KF|2; break;
	case SDLK_F3:		r = KF|3; break;
	case SDLK_F4:		r = KF|4; break;
	case SDLK_F5:		r = KF|5; break;
	case SDLK_F6:		r = KF|6; break;
	case SDLK_F7:		r = KF|7; break;
	case SDLK_F8:		r = KF|8; break;
	case SDLK_F9:		r = KF|9; break;
	case SDLK_F10:		r = KF|10; break;
	case SDLK_F11:		r = KF|11; break;
	case SDLK_F12:		r = KF|12; break;
	default:
		break;
	}

	if(r >= 0)
		gkbdputc(gkbdq, r);
}

static void
handle_textinput(const char *text)
{
	const char *p = text;
	Rune r;

	while(*p != '\0'){
		p += chartorune(&r, (char*)p);
		if(r != 0)
			gkbdputc(gkbdq, r);
	}
}

/*
 * Called on the macOS main thread from os.c:libinit().
 * Blocks silently on a condvar until attachscreen() is invoked, so headless/CLI
 * emu runs never initialize SDL3 or create a window.
 */
void
sdl3_mainloop(void)
{
	SDL_Event ev;
	SDL_WindowFlags flags;

	pthread_mutex_lock(&sdl_mu);
	while(!screen_requested)
		pthread_cond_wait(&sdl_cv, &sdl_mu);
	pthread_mutex_unlock(&sdl_mu);

	if(!SDL_Init(SDL_INIT_VIDEO)){
		fprint(2, "emu: SDL_Init failed: %s\n", SDL_GetError());
		pthread_mutex_lock(&sdl_mu);
		screen_failed = 1;
		screen_ready = 1;
		pthread_cond_broadcast(&sdl_cv);
		pthread_mutex_unlock(&sdl_mu);
		for(;;)
			pause();
	}

	sdl_ev_wakeup = SDL_RegisterEvents(1);

	if(want_fullscreen){
		SDL_DisplayID disp = SDL_GetPrimaryDisplay();
		const SDL_DisplayMode *dm = SDL_GetDesktopDisplayMode(disp);
		if(dm != nil && dm->w > 0 && dm->h > 0){
			Xsize = dm->w & ~0x3;
			Ysize = dm->h;
		}
	}

	fbw = Xsize & ~0x3;
	fbh = Ysize;
	fbdata = calloc((size_t)fbw * (size_t)fbh, 4);

	flags = SDL_WINDOW_HIGH_PIXEL_DENSITY;
	if(want_fullscreen)
		flags |= SDL_WINDOW_FULLSCREEN;

	sdl_win = SDL_CreateWindow("Inferno", fbw, fbh, flags);
	if(sdl_win == nil){
		fprint(2, "emu: SDL_CreateWindow failed: %s\n", SDL_GetError());
		pthread_mutex_lock(&sdl_mu);
		screen_failed = 1;
		screen_ready = 1;
		pthread_cond_broadcast(&sdl_cv);
		pthread_mutex_unlock(&sdl_mu);
		for(;;)
			pause();
	}

	sdl_ren = SDL_CreateRenderer(sdl_win, NULL);
	if(sdl_ren == nil){
		fprint(2, "emu: SDL_CreateRenderer failed: %s\n", SDL_GetError());
		pthread_mutex_lock(&sdl_mu);
		screen_failed = 1;
		screen_ready = 1;
		pthread_cond_broadcast(&sdl_cv);
		pthread_mutex_unlock(&sdl_mu);
		for(;;)
			pause();
	}

	SDL_SetRenderLogicalPresentation(sdl_ren, fbw, fbh, SDL_LOGICAL_PRESENTATION_STRETCH);

	sdl_tex = SDL_CreateTexture(sdl_ren, SDL_PIXELFORMAT_XRGB8888,
		SDL_TEXTUREACCESS_STREAMING, fbw, fbh);
	if(sdl_tex == nil){
		fprint(2, "emu: SDL_CreateTexture failed: %s\n", SDL_GetError());
		pthread_mutex_lock(&sdl_mu);
		screen_failed = 1;
		screen_ready = 1;
		pthread_cond_broadcast(&sdl_cv);
		pthread_mutex_unlock(&sdl_mu);
		for(;;)
			pause();
	}

	SDL_StartTextInput(sdl_win);

	pthread_mutex_lock(&sdl_mu);
	screen_ready = 1;
	pthread_cond_broadcast(&sdl_cv);
	pthread_mutex_unlock(&sdl_mu);

	for(;;){
		int force_present = 0;
		int have_motion = 0;
		int nevents = 0;

		if(!SDL_WaitEvent(&ev))
			continue;

		do {
			if(ev.type == sdl_ev_wakeup){
				continue;
			}

			switch(ev.type){
			case SDL_EVENT_QUIT:
			case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
				cleanexit(0);
				break;

			case SDL_EVENT_WINDOW_EXPOSED:
			case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
			case SDL_EVENT_WINDOW_RESIZED:
				force_present = 1;
				break;

			case SDL_EVENT_MOUSE_MOTION:
				map_mouse_coords(ev.motion.x, ev.motion.y, &mouse_x, &mouse_y);
				have_motion = 1;
				break;

			case SDL_EVENT_MOUSE_BUTTON_DOWN:
				map_mouse_coords(ev.button.x, ev.button.y, &mouse_x, &mouse_y);
				mouse_buttons |= sdl_button_mask(ev.button.button, SDL_GetModState());
				have_motion = 0;
				mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
				break;

			case SDL_EVENT_MOUSE_BUTTON_UP:
				map_mouse_coords(ev.button.x, ev.button.y, &mouse_x, &mouse_y);
				if(ev.button.button == SDL_BUTTON_LEFT)
					mouse_buttons &= ~(1 | 2 | 4);
				else
					mouse_buttons &= ~sdl_button_mask(ev.button.button, 0);
				have_motion = 0;
				mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
				break;

			case SDL_EVENT_MOUSE_WHEEL:
				if(have_motion){
					have_motion = 0;
					mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
				}
				if(ev.wheel.y > 0){
					mousetrack(mouse_buttons | 8, mouse_x, mouse_y, 0);
					mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
				}else if(ev.wheel.y < 0){
					mousetrack(mouse_buttons | 16, mouse_x, mouse_y, 0);
					mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
				}
				break;

			case SDL_EVENT_KEY_DOWN:
				handle_keydown(&ev.key);
				break;

			case SDL_EVENT_TEXT_INPUT:
				handle_textinput(ev.text.text);
				break;
			}
		} while(++nevents < 32 && SDL_PollEvent(&ev));

		if(have_motion)
			mousetrack(mouse_buttons, mouse_x, mouse_y, 0);

		/* Coalesce all pending flush/cursor/clipboard updates into one present */
		apply_clipboard();
		apply_cursor();
		apply_warp();
		pthread_mutex_lock(&dirty_mu);
		if(dirty_flag || force_present){
			pthread_mutex_unlock(&dirty_mu);
			present_framebuffer();
		}else{
			pthread_mutex_unlock(&dirty_mu);
		}
	}
}

uchar*
attachscreen(Rectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	const char *fs;

	pthread_mutex_lock(&sdl_mu);
	if(!screen_requested){
		fs = getenv("INFERNO_FULLSCREEN");
		want_fullscreen = (fs != nil && fs[0] != '\0' && strcmp(fs, "0") != 0);
		screen_requested = 1;
		pthread_cond_broadcast(&sdl_cv);
	}
	while(!screen_ready)
		pthread_cond_wait(&sdl_cv, &sdl_mu);
	pthread_mutex_unlock(&sdl_mu);

	if(screen_failed || fbdata == nil)
		return nil;

	Xsize = fbw;
	Ysize = fbh;

	r->min.x = 0;
	r->min.y = 0;
	r->max.x = fbw;
	r->max.y = fbh;

	*chan = XRGB32;
	*d = 32;
	*width = (fbw / 4) * (*d / 8);
	*softscreen = 1;
	displaychan = *chan;

	return fbdata;
}

void
flushmemscreen(Rectangle r)
{
	if(fbdata == nil)
		return;
	if(r.min.x >= r.max.x || r.min.y >= r.max.y)
		return;

	int need_wake = 0;

	pthread_mutex_lock(&dirty_mu);
	if(!dirty_flag){
		dirty_rect = r;
		dirty_flag = 1;
		need_wake = 1;
	}else{
		if(r.min.x < dirty_rect.min.x) dirty_rect.min.x = r.min.x;
		if(r.min.y < dirty_rect.min.y) dirty_rect.min.y = r.min.y;
		if(r.max.x > dirty_rect.max.x) dirty_rect.max.x = r.max.x;
		if(r.max.y > dirty_rect.max.y) dirty_rect.max.y = r.max.y;
	}
	pthread_mutex_unlock(&dirty_mu);

	if(need_wake)
		push_wakeup();
}

void
setpointer(int x, int y)
{
	pthread_mutex_lock(&warp_mu);
	warp_x = x;
	warp_y = y;
	warp_pending = 1;
	pthread_mutex_unlock(&warp_mu);
	push_wakeup();
}

void
drawcursor(Drawcursor *c)
{
	int i, j, w, h, bpl;
	uchar *bc, *bs, *ps, *pm;

	pthread_mutex_lock(&curs_mu);
	if(c == nil || c->data == nil){
		curs_custom = 0;
		curs_w = 0;
		curs_h = 0;
		curs_changed = 1;
		pthread_mutex_unlock(&curs_mu);
		push_wakeup();
		return;
	}

	h = (c->maxy - c->miny) / 2;
	if(h > CursorSize)
		h = CursorSize;
	bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 1);
	w = bpl;
	if(w > CursorSize / 8)
		w = CursorSize / 8;

	memset(curs_data, 0, sizeof(curs_data));
	memset(curs_mask, 0, sizeof(curs_mask));
	ps = curs_data;
	pm = curs_mask;
	bc = c->data;
	bs = c->data + h * bpl;
	for(i = 0; i < h; i++){
		for(j = 0; j < bpl && j < w; j++){
			*ps++ = bs[j];
			*pm++ = bs[j] | bc[j];
		}
		bs += bpl;
		bc += bpl;
	}
	curs_custom = 1;
	curs_w = w * 8;
	curs_h = h;
	curs_hotx = -c->hotx;
	curs_hoty = -c->hoty;
	curs_changed = 1;
	pthread_mutex_unlock(&curs_mu);

	push_wakeup();
}

char*
clipread(void)
{
	char *res;

	if(!screen_ready || screen_failed)
		return nil;

	pthread_mutex_lock(&clip_mu);
	clip_op = 1;
	clip_out = nil;
	clip_done = 0;
	push_wakeup();
	while(!clip_done)
		pthread_cond_wait(&clip_cv, &clip_mu);
	res = clip_out;
	clip_out = nil;
	pthread_mutex_unlock(&clip_mu);

	return res;
}

int
clipwrite(char *buf)
{
	if(!screen_ready || screen_failed || buf == nil)
		return 0;

	pthread_mutex_lock(&clip_mu);
	clip_op = 2;
	clip_in = buf;
	clip_done = 0;
	push_wakeup();
	while(!clip_done)
		pthread_cond_wait(&clip_cv, &clip_mu);
	clip_in = nil;
	pthread_mutex_unlock(&clip_mu);

	return 0;
}
