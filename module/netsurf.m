NetSurf: module
{
	PATH: con "$NetSurf";

	start:    fn(w: int, h: int, url: string): int;
	step:     fn(fb: array of byte): (int, int, int);
	mouse:    fn(x: int, y: int, buttons: int);
	key:      fn(ch: int);
	navigate: fn(url: string);
	resize:   fn(w: int, h: int);
};
