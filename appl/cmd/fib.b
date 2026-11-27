implement Fib;

include "sys.m";
	sys: Sys;
include "draw.m";

Fib: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

fib(n: int): big
{
	if(n <= 1)
		return big n;
	return fib(n - 1) + fib(n - 2);
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	n := 10;
	if(argv != nil && tl argv != nil)
		n = int hd tl argv;

	if(n < 0){
		sys->fprint(sys->fildes(2), "usage: fib [n>=0]\n");
		raise "fail:usage";
	}

	sys->print("fib(%d) = %bd\n", n, fib(n));
}
