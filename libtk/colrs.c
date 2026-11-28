#include "lib9.h"
#include "draw.h"
#include "tk.h"

#define RGB(R,G,B) ((R<<24)|(G<<16)|(B<<8)|(0xff))

enum
{
	/* Neutral Modern Light palette (zinc/neutral whites + crisp blue accent) */
	tkBackR		= 0xf4,		/* Chrome / surface (#f4f4f5) */
	tkBackG 	= 0xf4,
	tkBackB 	= 0xf5,

	tkSelectR	= 0x25,		/* Check box / radio selected (#2563eb) */
	tkSelectG	= 0x63,
	tkSelectB	= 0xeb,

	tkSelectbgndR	= 0x25,		/* Selected item / menu highlight (#2563eb) */
	tkSelectbgndG	= 0x63,
	tkSelectbgndB	= 0xeb
};

typedef struct Coltab Coltab;
struct Coltab {
	int	c;
	ulong rgba;
	int shade;
};

static Coltab coltab[] =
{
	TkCbackgnd,
		RGB(tkBackR, tkBackG, tkBackB),
		TkSameshade,
	TkCbackgndlght,
		RGB(0xc4, 0xc4, 0xcc),
		TkSameshade,
	TkCbackgnddark,
		RGB(0xa1, 0xa1, 0xaa),
		TkSameshade,
	TkCactivebgnd,
		RGB(0xdc, 0xdc, 0xe2),
		TkSameshade,
	TkCactivebgndlght,
		RGB(0xb4, 0xb4, 0xbc),
		TkSameshade,
	TkCactivebgnddark,
		RGB(0x71, 0x71, 0x7a),
		TkSameshade,
	TkCactivefgnd,
		RGB(0x09, 0x09, 0x0b),
		TkSameshade,
	TkCforegnd,
		RGB(0x09, 0x09, 0x0b),
		TkSameshade,
	TkCselect,
		RGB(tkSelectR, tkSelectG, tkSelectB),
		TkSameshade,
	TkCselectbgnd,
		RGB(tkSelectbgndR, tkSelectbgndG, tkSelectbgndB),
		TkSameshade,
	TkCselectbgndlght,
		RGB(0x3b, 0x82, 0xf6),
		TkSameshade,
	TkCselectbgnddark,
		RGB(0x1d, 0x4e, 0xd8),
		TkSameshade,
	TkCselectfgnd,
		RGB(0xff, 0xff, 0xff),
		TkSameshade,
	TkCdisablefgnd,
		RGB(0xa1, 0xa1, 0xaa),
		TkSameshade,
	TkChighlightfgnd,
		RGB(0x25, 0x63, 0xeb),
		TkSameshade,
	TkCtransparent,
		DTransparent,
		TkSameshade,
	-1,
};

void
tksetenvcolours(TkEnv *env)
{
	Coltab *c;

	c = &coltab[0];
	while(c->c != -1) {
		env->colors[c->c] = tkrgbashade(c->rgba, c->shade);
		env->set |= (1<<c->c);
		c++;
	}
}
