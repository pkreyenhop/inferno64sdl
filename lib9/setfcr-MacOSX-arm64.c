#include "lib9.h"

void
setfcr(u32 fcr)
{
	u64 v = fcr;
	__asm__ __volatile__("msr fpcr, %0" : : "r"(v));
}

u32
getfcr(void)
{
	u64 v;
	__asm__ __volatile__("mrs %0, fpcr" : "=r"(v));
	return (u32)v;
}

u32
getfsr(void)
{
	u64 v;
	__asm__ __volatile__("mrs %0, fpsr" : "=r"(v));
	return (u32)v;
}

void
setfsr(u32 fsr)
{
	u64 v = fsr;
	__asm__ __volatile__("msr fpsr, %0" : : "r"(v));
}
