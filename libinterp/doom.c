#include "lib9.h"
#include "kernel.h"
#include <isa.h>
#include "interp.h"
#include "runt.h"
#include "pool.h"
#include "raise.h"
#include "doommod.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../libdoom/doomgeneric/doomgeneric.h"

enum {
	KeyQSize = 64,
};

static long dg_start_ms = 0;
static int dg_started = 0;
static int dg_frame_ready = 0;

static unsigned short keyq[KeyQSize];
static int keyq_rd = 0;
static int keyq_wr = 0;

extern long osmillisec(void);
extern int osmillisleep(ulong);

void
DG_Init(void)
{
	dg_start_ms = osmillisec();
}

void
DG_DrawFrame(void)
{
	dg_frame_ready = 1;
}

void
DG_SleepMs(uint32_t ms)
{
	osmillisleep(ms);
}

uint32_t
DG_GetTicksMs(void)
{
	return (uint32_t)(osmillisec() - dg_start_ms);
}

int
DG_GetKey(int *pressed, unsigned char *key)
{
	unsigned short v;

	if(keyq_rd == keyq_wr)
		return 0;

	v = keyq[keyq_rd];
	keyq_rd = (keyq_rd + 1) % KeyQSize;
	*pressed = (v >> 8) & 1;
	*key = v & 0xff;
	return 1;
}

void
DG_SetWindowTitle(const char *title)
{
	USED(title);
}

void
doommodinit(void)
{
	builtinmod("$Doom", Doommodtab, Doommodlen);
}

static char doom_wad_buf[1024];

void
Doom_start(void *fp)
{
	F_Doom_start *f = fp;
	char *wad;
	const char *root;
	char *argv[4];

	if(!dg_started){
		wad = string2c(f->wad);
		if(wad != nil && wad[0] != '\0'){
			if(access(wad, R_OK) == 0){
				snprint(doom_wad_buf, sizeof(doom_wad_buf), "%s", wad);
			}else{
				root = getenv("ROOT");
				if(root != nil && root[0] != '\0')
					snprint(doom_wad_buf, sizeof(doom_wad_buf), "%s/%s", root, wad);
				else
					snprint(doom_wad_buf, sizeof(doom_wad_buf), "%s", wad);
			}
		}else{
			root = getenv("ROOT");
			if(root != nil && root[0] != '\0')
				snprint(doom_wad_buf, sizeof(doom_wad_buf), "%s/lib/doom/freedoom1.wad", root);
			else
				snprint(doom_wad_buf, sizeof(doom_wad_buf), "lib/doom/freedoom1.wad");
		}

		if(access(doom_wad_buf, R_OK) != 0){
			f->ret->t0 = 0;
			f->ret->t1 = 0;
			return;
		}

		argv[0] = "doom";
		argv[1] = "-iwad";
		argv[2] = doom_wad_buf;
		argv[3] = nil;

		dg_start_ms = osmillisec();
		release();
		doomgeneric_Create(3, argv);
		acquire();
		dg_started = 1;
	}

	f->ret->t0 = DOOMGENERIC_RESX;
	f->ret->t1 = DOOMGENERIC_RESY;
}

void
Doom_tick(void *fp)
{
	F_Doom_tick *f = fp;
	int need = DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4;

	if(!dg_started){
		*f->ret = 0;
		return;
	}

	release();
	doomgeneric_Tick();
	acquire();

	if(dg_frame_ready && DG_ScreenBuffer != nil && f->fb != H && f->fb->len >= need){
		memmove(f->fb->data, DG_ScreenBuffer, need);
		dg_frame_ready = 0;
		*f->ret = 1;
		return;
	}

	*f->ret = 0;
}

void
Doom_key(void *fp)
{
	F_Doom_key *f = fp;
	int next = (keyq_wr + 1) % KeyQSize;

	if(next != keyq_rd){
		keyq[keyq_wr] = (unsigned short)(((f->pressed ? 1 : 0) << 8) | (f->key & 0xff));
		keyq_wr = next;
	}
}
