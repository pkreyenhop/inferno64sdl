#include "lib9.h"
#include "kernel.h"
#include <isa.h>
#include "interp.h"
#include "runt.h"
#include "pool.h"
#include "raise.h"
#include "keyboard.h"
#include "netsurfmod.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../libnetsurf/inst-framebuffer/include/libnsfb.h"
#include "../libnetsurf/inst-framebuffer/include/libnsfb_event.h"

extern int netsurf_inferno_start(int width, int height, const char *start_url);
extern void netsurf_inferno_step(void);
extern void netsurf_inferno_navigate(const char *url_str);
extern void netsurf_inferno_resize(int width, int height);

extern uint8_t *nsfb_inferno_get_fb(int *w, int *h);
extern int nsfb_inferno_consume_dirty(void);
extern void nsfb_inferno_push_event(const nsfb_event_t *ev);

static pthread_mutex_t ns_mu = PTHREAD_MUTEX_INITIALIZER;
static int ns_last_buttons = 0;
static char ns_start_url[2048];

void
netsurfmodinit(void)
{
	builtinmod("$NetSurf", NetSurfmodtab, NetSurfmodlen);
}

void
NetSurf_start(void *fp)
{
	F_NetSurf_start *f = fp;
	const char *root;
	char resdir[1024];
	int w, h, rc;

	w = f->w;
	h = f->h;
	snprint(ns_start_url, sizeof(ns_start_url), "%s", string2c(f->url));

	root = getenv("ROOT");
	if(root != nil && root[0] != '\0'){
		snprint(resdir, sizeof(resdir), "%s/lib/netsurf", root);
		setenv("NETSURFRES", resdir, 0);
	}

	release();
	pthread_mutex_lock(&ns_mu);
	rc = netsurf_inferno_start(w, h, ns_start_url);
	pthread_mutex_unlock(&ns_mu);
	acquire();

	*f->ret = rc;
}

void
NetSurf_step(void *fp)
{
	F_NetSurf_step *f = fp;
	uint8_t *ptr;
	int w = 0, h = 0, dirty = 0, copied = 0;

	release();
	pthread_mutex_lock(&ns_mu);
	netsurf_inferno_step();
	dirty = nsfb_inferno_consume_dirty();
	pthread_mutex_unlock(&ns_mu);
	acquire();

	if(dirty){
		pthread_mutex_lock(&ns_mu);
		ptr = nsfb_inferno_get_fb(&w, &h);
		if(ptr != nil && w > 0 && h > 0 && f->fb != H && f->fb->len >= w * h * 4){
			memmove(f->fb->data, ptr, (size_t)w * (size_t)h * 4);
			copied = 1;
		}
		pthread_mutex_unlock(&ns_mu);
	}

	f->ret->t0 = copied;
	f->ret->t1 = w;
	f->ret->t2 = h;
}

static void
push_key_ev(enum nsfb_event_type_e type, enum nsfb_key_code_e code)
{
	nsfb_event_t ev;
	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.value.keycode = code;
	nsfb_inferno_push_event(&ev);
}

void
NetSurf_mouse(void *fp)
{
	F_NetSurf_mouse *f = fp;
	nsfb_event_t ev;
	int b = f->buttons;
	int diff = b ^ ns_last_buttons;

	memset(&ev, 0, sizeof(ev));
	ev.type = NSFB_EVENT_MOVE_ABSOLUTE;
	ev.value.vector.x = f->x;
	ev.value.vector.y = f->y;
	ev.value.vector.z = 0;
	nsfb_inferno_push_event(&ev);

	if(diff & 1)
		push_key_ev((b & 1) ? NSFB_EVENT_KEY_DOWN : NSFB_EVENT_KEY_UP, NSFB_KEY_MOUSE_1);
	if(diff & 2)
		push_key_ev((b & 2) ? NSFB_EVENT_KEY_DOWN : NSFB_EVENT_KEY_UP, NSFB_KEY_MOUSE_2);
	if(diff & 4)
		push_key_ev((b & 4) ? NSFB_EVENT_KEY_DOWN : NSFB_EVENT_KEY_UP, NSFB_KEY_MOUSE_3);
	if(diff & 8)
		push_key_ev((b & 8) ? NSFB_EVENT_KEY_DOWN : NSFB_EVENT_KEY_UP, NSFB_KEY_MOUSE_4);
	if(diff & 16)
		push_key_ev((b & 16) ? NSFB_EVENT_KEY_DOWN : NSFB_EVENT_KEY_UP, NSFB_KEY_MOUSE_5);

	ns_last_buttons = b;
}

void
NetSurf_key(void *fp)
{
	F_NetSurf_key *f = fp;
	int c = f->ch;
	enum nsfb_key_code_e code = NSFB_KEY_UNKNOWN;
	int shift = 0;

	switch(c){
	case '\b':	code = NSFB_KEY_BACKSPACE; break;
	case '\t':	code = NSFB_KEY_TAB; break;
	case '\n':
	case '\r':	code = NSFB_KEY_RETURN; break;
	case Esc:	code = NSFB_KEY_ESCAPE; break;
	case Del:	code = NSFB_KEY_DELETE; break;
	case Up:	code = NSFB_KEY_UP; break;
	case Down:	code = NSFB_KEY_DOWN; break;
	case Left:	code = NSFB_KEY_LEFT; break;
	case Right:	code = NSFB_KEY_RIGHT; break;
	case Home:	code = NSFB_KEY_HOME; break;
	case End:	code = NSFB_KEY_END; break;
	case Pgup:	code = NSFB_KEY_PAGEUP; break;
	case Pgdown:	code = NSFB_KEY_PAGEDOWN; break;
	default:
		if(c >= 'A' && c <= 'Z'){
			shift = 1;
			code = (enum nsfb_key_code_e)(c - 'A' + 'a');
		}else if(c >= 32 && c < 127){
			code = (enum nsfb_key_code_e)c;
		}
		break;
	}

	if(code == NSFB_KEY_UNKNOWN)
		return;

	if(shift)
		push_key_ev(NSFB_EVENT_KEY_DOWN, NSFB_KEY_LSHIFT);
	push_key_ev(NSFB_EVENT_KEY_DOWN, code);
	push_key_ev(NSFB_EVENT_KEY_UP, code);
	if(shift)
		push_key_ev(NSFB_EVENT_KEY_UP, NSFB_KEY_LSHIFT);
}

void
NetSurf_navigate(void *fp)
{
	F_NetSurf_navigate *f = fp;
	char urlbuf[2048];

	snprint(urlbuf, sizeof(urlbuf), "%s", string2c(f->url));

	release();
	pthread_mutex_lock(&ns_mu);
	netsurf_inferno_navigate(urlbuf);
	pthread_mutex_unlock(&ns_mu);
	acquire();
}

void
NetSurf_resize(void *fp)
{
	F_NetSurf_resize *f = fp;
	int w = f->w;
	int h = f->h;

	release();
	pthread_mutex_lock(&ns_mu);
	netsurf_inferno_resize(w, h);
	pthread_mutex_unlock(&ns_mu);
	acquire();
}
