int
_tas(int *p)
{
	return __atomic_exchange_n(p, 1, __ATOMIC_ACQ_REL);
}
