Doom: module
{
	PATH: con "$Doom";

	start: fn(wad: string): (int, int);
	tick:  fn(fb: array of byte): int;
	key:   fn(pressed: int, key: int);
};
