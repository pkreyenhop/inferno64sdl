implement WmSheet;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image, Font, Point, Rect: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "zip.m";
	zip: Zip;
	CDFhdr: import zip;
include "xml.m";
	xml: Xml;
	Item, Parser, Attributes: import xml;
include "string.m";
	str: String;
include "math.m";
	math: Math;
include "keyboard.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;

WmSheet: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

DEFAULT_DIR: con "/usr/inferno";
DEFAULT_ODS: con "/usr/inferno/Financial_Planning_as_at_06Oct26_Sell_WLG_FIRE_in_Apr27.ods";

VEMPTY, VNUM, VSTR, VNA, VERR: con iota;

Val: adt {
	kind: int;
	num:  real;
	s:    string;
};

Cell: adt {
	formula:    string;
	vtype:      string;   # "", "float", "percentage", "string"
	raw_num:    real;
	raw_str:    string;
	cached_num: real;
	cached_str: string;
	has_cached: int;
	val:        Val;
	disp:       string;   # pre-formatted display string
	state:      int;      # 0=uncomputed, 1=visiting, 2=done
};

Sheet: adt {
	name:   string;
	nrows:  int;
	ncols:  int;
	rows:   array of array of ref Cell;
	cur_r:  int;
	cur_c:  int;
	top_r:  int;
	left_c: int;
};

NamedRange: adt {
	name:      string;
	sheetname: string;
	sheetidx:  int;
	row:       int;
	col:       int;
};

Book: adt {
	filename: string;
	sheets:   array of ref Sheet;
	names:    list of ref NamedRange;
};

# ---------------------------------------------------------------------------
# String & cell-coordinate helpers
# ---------------------------------------------------------------------------

tolower(s: string): string
{
	out := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c = c - 'A' + 'a';
		out[len out] = c;
	}
	return out;
}

trim(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	return s[i:j];
}

colname(c: int): string
{
	s := "";
	n := c + 1;
	while(n > 0){
		n--;
		ch := 'A' + (n % 26);
		ns := "";
		ns[0] = ch;
		s = ns + s;
		n /= 26;
	}
	return s;
}

celladdr(r, c: int): string
{
	return colname(c) + string (r + 1);
}

# Parse A1-style ref (with optional $ signs), returns (row0, col0, ok)
parse_a1(s: string): (int, int, int)
{
	i := 0;
	n := len s;
	if(i < n && s[i] == '$')
		i++;
	col := 0;
	gotcol := 0;
	while(i < n){
		ch := s[i];
		if(ch >= 'A' && ch <= 'Z'){
			col = col * 26 + (ch - 'A' + 1);
			gotcol = 1;
			i++;
		}else if(ch >= 'a' && ch <= 'z'){
			col = col * 26 + (ch - 'a' + 1);
			gotcol = 1;
			i++;
		}else
			break;
	}
	if(!gotcol)
		return (0, 0, 0);
	if(i < n && s[i] == '$')
		i++;
	row := 0;
	gotrow := 0;
	while(i < n && s[i] >= '0' && s[i] <= '9'){
		row = row * 10 + (s[i] - '0');
		gotrow = 1;
		i++;
	}
	if(!gotrow || i != n || row <= 0)
		return (0, 0, 0);
	return (row - 1, col - 1, 1);
}

findsheet(b: ref Book, name: string): int
{
	ln := tolower(name);
	for(i := 0; i < len b.sheets; i++)
		if(tolower(b.sheets[i].name) == ln)
			return i;
	return -1;
}

# Parse an ODF address like "$'Inputs and quick look outputs'.$C$15" or "$Playground.$B4" or ".E4"
parse_odf_addr(b: ref Book, defsheet: int, s: string): (int, int, int, int)
{
	s = trim(s);
	if(len s == 0)
		return (-1, 0, 0, 0);
	# Find the dot separating sheet name and cell ref
	dot := -1;
	inquote := 0;
	for(i := 0; i < len s; i++){
		if(s[i] == '\'')
			inquote = !inquote;
		else if(s[i] == '.' && !inquote){
			dot = i;
			break;
		}
	}
	sidx := defsheet;
	cellpart := s;
	if(dot >= 0){
		shpart := s[0:dot];
		cellpart = s[dot+1:];
		if(len shpart > 0){
			if(shpart[0] == '$')
				shpart = shpart[1:];
			if(len shpart >= 2 && shpart[0] == '\'' && shpart[len shpart - 1] == '\'')
				shpart = shpart[1:len shpart - 1];
			sidx = findsheet(b, shpart);
			if(sidx < 0)
				return (-1, 0, 0, 0);
		}
	}
	(r, c, ok) := parse_a1(cellpart);
	if(!ok)
		return (-1, 0, 0, 0);
	return (sidx, r, c, 1);
}

getcell(b: ref Book, sidx, r, c: int): ref Cell
{
	if(sidx < 0 || sidx >= len b.sheets)
		return nil;
	sh := b.sheets[sidx];
	if(r < 0 || r >= sh.nrows || c < 0 || c >= sh.ncols)
		return nil;
	if(sh.rows[r] == nil || c >= len sh.rows[r])
		return nil;
	return sh.rows[r][c];
}

ensurecell(sh: ref Sheet, r, c: int): ref Cell
{
	if(r >= sh.nrows){
		nr := array[r + 1] of array of ref Cell;
		nr[0:] = sh.rows;
		sh.rows = nr;
		sh.nrows = r + 1;
	}
	if(c >= sh.ncols)
		sh.ncols = c + 1;
	if(sh.rows[r] == nil || c >= len sh.rows[r]){
		nc := array[c + 1] of ref Cell;
		if(sh.rows[r] != nil)
			nc[0:] = sh.rows[r];
		sh.rows[r] = nc;
	}
	if(sh.rows[r][c] == nil)
		sh.rows[r][c] = ref Cell("", "", 0.0, "", 0.0, "", 0, Val(VEMPTY, 0.0, ""), "", 0);
	return sh.rows[r][c];
}

# ---------------------------------------------------------------------------
# ODS Reader (ZIP + XML)
# ---------------------------------------------------------------------------

load_ods(path: string): (ref Book, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", path));

	(nil, cdirs, zerr) := zip->open(fd);
	if(zerr != nil)
		return (nil, "zip open: " + zerr);

	var_cdf: ref CDFhdr;
	for(i := 0; i < len cdirs; i++){
		if(cdirs[i].filename == "content.xml"){
			var_cdf = cdirs[i];
			break;
		}
	}
	if(var_cdf == nil)
		return (nil, "content.xml not found in ODS");

	(cfd, nil, oerr) := zip->openfile(fd, var_cdf);
	if(oerr != nil)
		return (nil, "zip openfile content.xml: " + oerr);

	tmp := sys->sprint("/tmp/sheet_%d.xml", sys->pctl(0, nil));
	tfd := sys->create(tmp, Sys->OWRITE, 8r600);
	if(tfd == nil)
		return (nil, sys->sprint("cannot create %s: %r", tmp));
	buf := array[16384] of byte;
	for(;;){
		n := sys->read(cfd, buf, len buf);
		if(n <= 0)
			break;
		sys->write(tfd, buf, n);
	}
	cfd = nil;
	tfd = nil;

	(p, xerr) := xml->open(tmp, nil, nil);
	if(p == nil || (xerr != nil && len xerr > 0)){
		sys->remove(tmp);
		return (nil, "xml->open: " + xerr);
	}

	book := ref Book(path, nil, nil);
	sheets_rev: list of ref Sheet;

	# Walk XML using tag depth
	for(;;){
		it := p.next();
		if(it == nil){
			if(p.readdepth > 0){
				p.up();
				continue;
			}
			break;
		}
		pick t := it {
		Tag =>
			if(t.name == "table:table"){
				sh := parse_table(p, t.attrs.get("table:name"));
				sheets_rev = sh :: sheets_rev;
			}else if(t.name == "table:named-expressions"){
				parse_named_exprs(p, book);
			}else{
				p.down();
			}
		}
	}

	# Reverse sheets list into array
	ns := len sheets_rev;
	book.sheets = array[ns] of ref Sheet;
	idx := ns - 1;
	for(l := sheets_rev; l != nil; l = tl l){
		book.sheets[idx--] = hd l;
	}

	# Resolve named ranges now that all sheets are loaded
	for(nl := book.names; nl != nil; nl = tl nl){
		nr := hd nl;
		(sidx, r, c, ok) := parse_odf_addr(book, 0, nr.sheetname);
		if(ok){
			nr.sheetidx = sidx;
			nr.row = r;
			nr.col = c;
		}
	}

	sys->remove(tmp);
	return (book, nil);
}

parse_named_exprs(p: ref Parser, book: ref Book)
{
	p.down();
	for(;;){
		it := p.next();
		if(it == nil)
			break;
		pick t := it {
		Tag =>
			if(t.name == "table:named-range"){
				nm := t.attrs.get("table:name");
				addr := t.attrs.get("table:cell-range-address");
				if(nm != nil && addr != nil){
					nr := ref NamedRange(nm, addr, -1, 0, 0);
					book.names = nr :: book.names;
				}
			}
		}
	}
	p.up();
}

parse_table(p: ref Parser, name: string): ref Sheet
{
	sh := ref Sheet(name, 0, 0, array[0] of array of ref Cell, 0, 0, 0, 0);
	rows_rev: list of (int, array of ref Cell);
	cur_row := 0;
	max_row := 0;
	max_col := 0;

	p.down();
	for(;;){
		it := p.next();
		if(it == nil)
			break;
		pick t := it {
		Tag =>
			if(t.name == "table:table-row"){
				rrep_s := t.attrs.get("table:number-rows-repeated");
				rrep := 1;
				if(rrep_s != nil && int rrep_s > 0)
					rrep = int rrep_s;
				(rowcells, rowmaxcol, hasdata) := parse_row(p);
				if(hasdata){
					# Cap repeated data rows safely
					cnt := rrep;
					if(cnt > 200)
						cnt = 200;
					for(k := 0; k < cnt; k++){
						rows_rev = (cur_row + k, rowcells) :: rows_rev;
					}
					if(cur_row + cnt > max_row)
						max_row = cur_row + cnt;
					if(rowmaxcol > max_col)
						max_col = rowmaxcol;
				}
				cur_row += rrep;
			}
		}
	}
	p.up();

	if(max_row < 1) max_row = 1;
	if(max_col < 1) max_col = 1;
	sh.nrows = max_row;
	sh.ncols = max_col;
	sh.rows = array[max_row] of array of ref Cell;
	for(l := rows_rev; l != nil; l = tl l){
		(ridx, rc) := hd l;
		if(ridx >= 0 && ridx < max_row)
			sh.rows[ridx] = rc;
	}
	return sh;
}

parse_row(p: ref Parser): (array of ref Cell, int, int)
{
	cells_rev: list of (int, ref Cell);
	col := 0;
	max_col := 0;
	hasdata := 0;

	p.down();
	for(;;){
		it := p.next();
		if(it == nil)
			break;
		pick t := it {
		Tag =>
			if(t.name == "table:table-cell" || t.name == "table:covered-table-cell"){
				crep_s := t.attrs.get("table:number-columns-repeated");
				crep := 1;
				if(crep_s != nil && int crep_s > 0)
					crep = int crep_s;

				vt := t.attrs.get("office:value-type");
				f := t.attrs.get("table:formula");
				v := t.attrs.get("office:value");
				txt := read_cell_text(p);

				if(vt != nil || f != nil || len txt > 0){
					hasdata = 1;
					cnt := crep;
					if(cnt > 100)
						cnt = 100;
					for(k := 0; k < cnt; k++){
						c := ref Cell("", "", 0.0, "", 0.0, "", 0, Val(VEMPTY, 0.0, ""), "", 0);
						if(vt != nil)
							c.vtype = vt;
						if(f != nil)
							c.formula = f;
						if(v != nil){
							c.raw_num = real v;
							c.cached_num = c.raw_num;
							c.has_cached = 1;
						}
						if(len txt > 0){
							c.raw_str = txt;
							c.cached_str = txt;
						}
						cells_rev = (col + k, c) :: cells_rev;
					}
					if(col + cnt > max_col)
						max_col = col + cnt;
				}
				col += crep;
			}
		}
	}
	p.up();

	if(!hasdata || max_col == 0)
		return (nil, 0, 0);

	arr := array[max_col] of ref Cell;
	for(l := cells_rev; l != nil; l = tl l){
		(cidx, cell) := hd l;
		if(cidx >= 0 && cidx < max_col)
			arr[cidx] = cell;
	}
	return (arr, max_col, 1);
}

read_cell_text(p: ref Parser): string
{
	txt := "";
	p.down();
	for(;;){
		it := p.next();
		if(it == nil)
			break;
		pick t := it {
		Tag =>
			if(t.name == "text:p"){
				if(len txt > 0)
					txt += " ";
				txt += read_p_text(p);
			}
		}
	}
	p.up();
	return txt;
}

read_p_text(p: ref Parser): string
{
	s := "";
	p.down();
	for(;;){
		it := p.next();
		if(it == nil)
			break;
		pick t := it {
		Text =>
			s += t.ch;
		Tag =>
			if(t.name == "text:s"){
				cnt := 1;
				cs := t.attrs.get("text:c");
				if(cs != nil && int cs > 0)
					cnt = int cs;
				for(k := 0; k < cnt; k++)
					s += " ";
			}else{
				s += read_p_text(p);
			}
		}
	}
	p.up();
	return s;
}

# ---------------------------------------------------------------------------
# Formula Evaluator (OpenFormula subset needed by this ODS)
# ---------------------------------------------------------------------------

Expr: adt {
	book:  ref Book;
	sidx:  int;
	src:   string;
	pos:   int;
};

# Range descriptor for SUM, MAX, MATCH, INDEX
Range: adt {
	ok:    int;
	sidx:  int;
	r0:    int;
	c0:    int;
	r1:    int;
	c1:    int;
};

eval_cell(b: ref Book, sidx, r, c: int): Val
{
	cell := getcell(b, sidx, r, c);
	if(cell == nil)
		return Val(VEMPTY, 0.0, "");
	if(cell.state == 2)
		return cell.val;
	if(cell.state == 1)
		return Val(VERR, 0.0, "#CYCLE");

	cell.state = 1;
	if(len cell.formula > 0){
		f := cell.formula;
		if(len f >= 4 && f[0:4] == "of:=")
			f = f[4:];
		else if(len f >= 1 && f[0] == '=')
			f = f[1:];
		e := ref Expr(b, sidx, f, 0);
		cell.val = parse_cmp(e);
	}else if(cell.vtype == "float" || cell.vtype == "percentage"){
		cell.val = Val(VNUM, cell.raw_num, "");
	}else if(len cell.raw_str > 0){
		cell.val = Val(VSTR, 0.0, cell.raw_str);
	}else{
		cell.val = Val(VEMPTY, 0.0, "");
	}
	cell.state = 2;
	cell.disp = format_cell(cell);
	return cell.val;
}

recalc(b: ref Book)
{
	for(si := 0; si < len b.sheets; si++){
		sh := b.sheets[si];
		for(r := 0; r < sh.nrows; r++){
			row := sh.rows[r];
			if(row == nil) continue;
			for(c := 0; c < len row; c++){
				if(row[c] != nil)
					row[c].state = 0;
			}
		}
	}
	for(si = 0; si < len b.sheets; si++){
		sh := b.sheets[si];
		for(r := 0; r < sh.nrows; r++){
			row := sh.rows[r];
			if(row == nil) continue;
			for(c := 0; c < len row; c++){
				if(row[c] != nil && row[c].state == 0)
					eval_cell(b, si, r, c);
			}
		}
	}
}

skipws(e: ref Expr)
{
	while(e.pos < len e.src){
		ch := e.src[e.pos];
		if(ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r')
			e.pos++;
		else
			break;
	}
}

valnum(v: Val): real
{
	if(v.kind == VNUM)
		return v.num;
	if(v.kind == VSTR)
		return real v.s;
	return 0.0;
}

valtruthy(v: Val): int
{
	if(v.kind == VNUM)
		return v.num != 0.0;
	if(v.kind == VSTR)
		return len v.s > 0;
	return 0;
}

# Try to parse an ODF bracketed ref/range `[...]` or bare range `A1:B2`
try_parse_range(e: ref Expr): Range
{
	skipws(e);
	save := e.pos;
	if(e.pos < len e.src && e.src[e.pos] == '['){
		e.pos++;
		start := e.pos;
		while(e.pos < len e.src && e.src[e.pos] != ']')
			e.pos++;
		if(e.pos >= len e.src){
			e.pos = save;
			return Range(0, 0, 0, 0, 0, 0);
		}
		inside := e.src[start:e.pos];
		e.pos++; # consume ']'
		# Split on ':' if range
		colon := -1;
		inquote := 0;
		for(i := 0; i < len inside; i++){
			if(inside[i] == '\'') inquote = !inquote;
			else if(inside[i] == ':' && !inquote){ colon = i; break; }
		}
		if(colon >= 0){
			(s0, r0, c0, ok0) := parse_odf_addr(e.book, e.sidx, inside[0:colon]);
			(s1, r1, c1, ok1) := parse_odf_addr(e.book, s0, inside[colon+1:]);
			if(ok0 && ok1){
				if(r0 > r1){ t := r0; r0 = r1; r1 = t; }
				if(c0 > c1){ t := c0; c0 = c1; c1 = t; }
				return Range(1, s0, r0, c0, r1, c1);
			}
		}else{
			(s0, r0, c0, ok0) := parse_odf_addr(e.book, e.sidx, inside);
			if(ok0)
				return Range(1, s0, r0, c0, r0, c0);
		}
		e.pos = save;
		return Range(0, 0, 0, 0, 0, 0);
	}
	# Bare A1 or A1:B2 (for user-edited formulas)
	start := e.pos;
	while(e.pos < len e.src){
		ch := e.src[e.pos];
		if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '$' || ch == ':')
			e.pos++;
		else
			break;
	}
	tok := e.src[start:e.pos];
	if(len tok > 0){
		colon := -1;
		for(i := 0; i < len tok; i++)
			if(tok[i] == ':'){ colon = i; break; }
		if(colon >= 0){
			(r0, c0, ok0) := parse_a1(tok[0:colon]);
			(r1, c1, ok1) := parse_a1(tok[colon+1:]);
			if(ok0 && ok1){
				if(r0 > r1){ t := r0; r0 = r1; r1 = t; }
				if(c0 > c1){ t := c0; c0 = c1; c1 = t; }
				return Range(1, e.sidx, r0, c0, r1, c1);
			}
		}
	}
	e.pos = save;
	return Range(0, 0, 0, 0, 0, 0);
}

cmp_vals(a, b: Val, op: string): int
{
	if(a.kind == VSTR || b.kind == VSTR){
		sa := a.s;
		sb := b.s;
		if(a.kind == VNUM) sa = string a.num;
		if(b.kind == VNUM) sb = string b.num;
		case op {
		"="  => return sa == sb;
		"<>" => return sa != sb;
		"<"  => return sa < sb;
		"<=" => return sa <= sb;
		">"  => return sa > sb;
		">=" => return sa >= sb;
		}
		return 0;
	}
	na := valnum(a);
	nb := valnum(b);
	case op {
	"="  => return na == nb;
	"<>" => return na != nb;
	"<"  => return na < nb;
	"<=" => return na <= nb;
	">"  => return na > nb;
	">=" => return na >= nb;
	}
	return 0;
}

parse_cmp(e: ref Expr): Val
{
	v := parse_add(e);
	if(v.kind == VNA || v.kind == VERR)
		return v;
	for(;;){
		skipws(e);
		if(e.pos >= len e.src)
			break;
		op := "";
		if(e.pos + 1 < len e.src){
			two := e.src[e.pos:e.pos+2];
			if(two == "<=" || two == ">=" || two == "<>"){
				op = two;
				e.pos += 2;
			}
		}
		if(op == ""){
			ch := e.src[e.pos];
			if(ch == '<' || ch == '>' || ch == '='){
				op[0] = ch;
				e.pos++;
			}
		}
		if(op == "")
			break;
		r := parse_add(e);
		if(r.kind == VNA || r.kind == VERR)
			return r;
		if(cmp_vals(v, r, op))
			v = Val(VNUM, 1.0, "");
		else
			v = Val(VNUM, 0.0, "");
	}
	return v;
}

parse_add(e: ref Expr): Val
{
	v := parse_mul(e);
	if(v.kind == VNA || v.kind == VERR)
		return v;
	for(;;){
		skipws(e);
		if(e.pos >= len e.src)
			break;
		ch := e.src[e.pos];
		if(ch != '+' && ch != '-')
			break;
		e.pos++;
		r := parse_mul(e);
		if(r.kind == VNA || r.kind == VERR)
			return r;
		if(ch == '+')
			v = Val(VNUM, valnum(v) + valnum(r), "");
		else
			v = Val(VNUM, valnum(v) - valnum(r), "");
	}
	return v;
}

parse_mul(e: ref Expr): Val
{
	v := parse_unary(e);
	if(v.kind == VNA || v.kind == VERR)
		return v;
	for(;;){
		skipws(e);
		if(e.pos >= len e.src)
			break;
		ch := e.src[e.pos];
		if(ch != '*' && ch != '/')
			break;
		e.pos++;
		r := parse_unary(e);
		if(r.kind == VNA || r.kind == VERR)
			return r;
		if(ch == '*')
			v = Val(VNUM, valnum(v) * valnum(r), "");
		else{
			d := valnum(r);
			if(d == 0.0)
				return Val(VERR, 0.0, "#DIV/0!");
			v = Val(VNUM, valnum(v) / d, "");
		}
	}
	return v;
}

parse_unary(e: ref Expr): Val
{
	skipws(e);
	if(e.pos < len e.src){
		if(e.src[e.pos] == '+'){
			e.pos++;
			return parse_unary(e);
		}
		if(e.src[e.pos] == '-'){
			e.pos++;
			v := parse_unary(e);
			if(v.kind == VNA || v.kind == VERR)
				return v;
			return Val(VNUM, -valnum(v), "");
		}
	}
	return parse_primary(e);
}

# Skip an unevaluated expression argument (up to matching ';' or ',' or ')')
skip_arg(e: ref Expr)
{
	depth := 0;
	inquote := 0;
	while(e.pos < len e.src){
		ch := e.src[e.pos];
		if(ch == '"')
			inquote = !inquote;
		else if(!inquote){
			if(ch == '(') depth++;
			else if(ch == ')'){
				if(depth == 0) return;
				depth--;
			}else if((ch == ';' || ch == ',') && depth == 0)
				return;
		}
		e.pos++;
	}
}

consume_sep(e: ref Expr): int
{
	skipws(e);
	if(e.pos < len e.src && (e.src[e.pos] == ';' || e.src[e.pos] == ',')){
		e.pos++;
		return 1;
	}
	return 0;
}

consume_rparen(e: ref Expr)
{
	skipws(e);
	if(e.pos < len e.src && e.src[e.pos] == ')')
		e.pos++;
}

parse_primary(e: ref Expr): Val
{
	skipws(e);
	if(e.pos >= len e.src)
		return Val(VEMPTY, 0.0, "");

	ch := e.src[e.pos];

	# Parenthesized expression
	if(ch == '('){
		e.pos++;
		v := parse_cmp(e);
		consume_rparen(e);
		return v;
	}

	# String literal
	if(ch == '"'){
		e.pos++;
		s := "";
		while(e.pos < len e.src){
			if(e.src[e.pos] == '"'){
				if(e.pos + 1 < len e.src && e.src[e.pos+1] == '"'){
					s[len s] = '"';
					e.pos += 2;
				}else{
					e.pos++;
					break;
				}
			}else{
				s[len s] = e.src[e.pos++];
			}
		}
		return Val(VSTR, 0.0, s);
	}

	# Number literal
	if((ch >= '0' && ch <= '9') || ch == '.'){
		start := e.pos;
		while(e.pos < len e.src && ((e.src[e.pos] >= '0' && e.src[e.pos] <= '9') || e.src[e.pos] == '.'))
			e.pos++;
		if(e.pos < len e.src && (e.src[e.pos] == 'e' || e.src[e.pos] == 'E')){
			e.pos++;
			if(e.pos < len e.src && (e.src[e.pos] == '+' || e.src[e.pos] == '-'))
				e.pos++;
			while(e.pos < len e.src && e.src[e.pos] >= '0' && e.src[e.pos] <= '9')
				e.pos++;
		}
		num := real e.src[start:e.pos];
		if(e.pos < len e.src && e.src[e.pos] == '%'){
			e.pos++;
			num /= 100.0;
		}
		return Val(VNUM, num, "");
	}

	# ODF cell reference [...]
	if(ch == '['){
		rng := try_parse_range(e);
		if(rng.ok)
			return eval_cell(e.book, rng.sidx, rng.r0, rng.c0);
		return Val(VERR, 0.0, "#REF!");
	}

	# Identifier: function call, named range, or bare A1 cell ref
	if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '$'){
		start := e.pos;
		while(e.pos < len e.src){
			c := e.src[e.pos];
			if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '$' || c == '.')
				e.pos++;
			else
				break;
		}
		ident := e.src[start:e.pos];
		skipws(e);
		if(e.pos < len e.src && e.src[e.pos] == '('){
			e.pos++; # consume '('
			return eval_func(e, tolower(ident));
		}

		# Named range lookup
		li := tolower(ident);
		for(nl := e.book.names; nl != nil; nl = tl nl){
			nr := hd nl;
			if(tolower(nr.name) == li && nr.sheetidx >= 0)
				return eval_cell(e.book, nr.sheetidx, nr.row, nr.col);
		}

		# Bare A1 cell reference (for user-edited formulas)
		(r, col, ok) := parse_a1(ident);
		if(ok)
			return eval_cell(e.book, e.sidx, r, col);

		if(li == "true")
			return Val(VNUM, 1.0, "");
		if(li == "false")
			return Val(VNUM, 0.0, "");

		return Val(VERR, 0.0, "#NAME?");
	}

	return Val(VERR, 0.0, "#ERR!");
}

eval_func(e: ref Expr, fnname: string): Val
{
	case fnname {
	"true" =>
		consume_rparen(e);
		return Val(VNUM, 1.0, "");

	"false" =>
		consume_rparen(e);
		return Val(VNUM, 0.0, "");

	"sum" =>
		total := 0.0;
		skipws(e);
		if(e.pos < len e.src && e.src[e.pos] != ')'){
			for(;;){
				save := e.pos;
				rng := try_parse_range(e);
				skipws(e);
				if(rng.ok && (e.pos >= len e.src || e.src[e.pos] == ';' || e.src[e.pos] == ',' || e.src[e.pos] == ')')){
					for(r := rng.r0; r <= rng.r1; r++){
						for(c := rng.c0; c <= rng.c1; c++){
							v := eval_cell(e.book, rng.sidx, r, c);
							if(v.kind == VNUM)
								total += v.num;
						}
					}
				}else{
					e.pos = save;
					v := parse_cmp(e);
					if(v.kind == VNUM)
						total += v.num;
				}
				if(!consume_sep(e))
					break;
			}
		}
		consume_rparen(e);
		return Val(VNUM, total, "");

	"max" =>
		has := 0;
		best := 0.0;
		skipws(e);
		if(e.pos < len e.src && e.src[e.pos] != ')'){
			for(;;){
				save := e.pos;
				rng := try_parse_range(e);
				skipws(e);
				if(rng.ok && (e.pos >= len e.src || e.src[e.pos] == ';' || e.src[e.pos] == ',' || e.src[e.pos] == ')')){
					for(r := rng.r0; r <= rng.r1; r++){
						for(c := rng.c0; c <= rng.c1; c++){
							v := eval_cell(e.book, rng.sidx, r, c);
							if(v.kind == VNUM){
								if(!has || v.num > best){ best = v.num; has = 1; }
							}
						}
					}
				}else{
					e.pos = save;
					v := parse_cmp(e);
					if(v.kind == VNUM){
						if(!has || v.num > best){ best = v.num; has = 1; }
					}
				}
				if(!consume_sep(e))
					break;
			}
		}
		consume_rparen(e);
		return Val(VNUM, best, "");

	"isblank" =>
		rng := try_parse_range(e);
		blank := 0;
		if(rng.ok){
			cell := getcell(e.book, rng.sidx, rng.r0, rng.c0);
			if(cell == nil)
				blank = 1;
			else if(len cell.formula == 0 && cell.vtype == "" && len cell.raw_str == 0)
				blank = 1;
			else{
				v := eval_cell(e.book, rng.sidx, rng.r0, rng.c0);
				if(v.kind == VEMPTY)
					blank = 1;
			}
		}else{
			v := parse_cmp(e);
			if(v.kind == VEMPTY)
				blank = 1;
		}
		consume_rparen(e);
		if(blank)
			return Val(VNUM, 1.0, "");
		return Val(VNUM, 0.0, "");

	"if" =>
		cond := parse_cmp(e);
		if(cond.kind == VNA || cond.kind == VERR){
			skip_arg(e);
			if(consume_sep(e)) skip_arg(e);
			if(consume_sep(e)) skip_arg(e);
			consume_rparen(e);
			return cond;
		}
		res := Val(VEMPTY, 0.0, "");
		if(valtruthy(cond)){
			if(consume_sep(e))
				res = parse_cmp(e);
			if(consume_sep(e))
				skip_arg(e);
		}else{
			if(consume_sep(e))
				skip_arg(e);
			if(consume_sep(e))
				res = parse_cmp(e);
		}
		consume_rparen(e);
		return res;

	"ifna" =>
		v := parse_cmp(e);
		if(v.kind == VNA){
			if(consume_sep(e))
				v = parse_cmp(e);
		}else{
			if(consume_sep(e))
				skip_arg(e);
		}
		consume_rparen(e);
		return v;

	"match" =>
		# MATCH(lookup; range [op rhs]; match_type)
		lookup := parse_cmp(e);
		if(!consume_sep(e)){
			consume_rparen(e);
			return Val(VNA, 0.0, "#N/A");
		}
		rng := try_parse_range(e);
		if(!rng.ok){
			skip_arg(e);
			if(consume_sep(e)) skip_arg(e);
			consume_rparen(e);
			return Val(VNA, 0.0, "#N/A");
		}
		# Optional array comparison operator (e.g., [$Playground.$E4:.$E164] < 0)
		skipws(e);
		arrop := "";
		arrrhs := Val(VEMPTY, 0.0, "");
		if(e.pos < len e.src){
			if(e.pos + 1 < len e.src){
				two := e.src[e.pos:e.pos+2];
				if(two == "<=" || two == ">=" || two == "<>"){
					arrop = two;
					e.pos += 2;
				}
			}
			if(arrop == ""){
				c := e.src[e.pos];
				if(c == '<' || c == '>' || c == '='){
					arrop[0] = c;
					e.pos++;
				}
			}
			if(arrop != "")
				arrrhs = parse_add(e);
		}
		if(consume_sep(e))
			parse_cmp(e); # match_type (0 = exact)
		consume_rparen(e);

		# Scan range (1-based index)
		idx := 0;
		for(r := rng.r0; r <= rng.r1; r++){
			for(c := rng.c0; c <= rng.c1; c++){
				idx++;
				cv := eval_cell(e.book, rng.sidx, r, c);
				elem: Val;
				if(arrop != ""){
					if(cv.kind == VEMPTY)
						elem = Val(VNUM, 0.0, "");
					else if(cmp_vals(cv, arrrhs, arrop))
						elem = Val(VNUM, 1.0, "");
					else
						elem = Val(VNUM, 0.0, "");
				}else{
					elem = cv;
				}
				if(cmp_vals(elem, lookup, "="))
					return Val(VNUM, real idx, "");
			}
		}
		return Val(VNA, 0.0, "#N/A");

	"index" =>
		# INDEX(range; row_num [; col_num])
		rng := try_parse_range(e);
		if(!rng.ok){
			skip_arg(e);
			if(consume_sep(e)) skip_arg(e);
			consume_rparen(e);
			return Val(VNA, 0.0, "#N/A");
		}
		row_v := Val(VNUM, 1.0, "");
		if(consume_sep(e))
			row_v = parse_cmp(e);
		col_v := Val(VNUM, 1.0, "");
		if(consume_sep(e))
			col_v = parse_cmp(e);
		consume_rparen(e);

		if(row_v.kind == VNA || row_v.kind == VERR)
			return row_v;
		if(col_v.kind == VNA || col_v.kind == VERR)
			return col_v;

		ri := int valnum(row_v) - 1;
		ci := int valnum(col_v) - 1;
		rr := rng.r0 + ri;
		cc := rng.c0 + ci;
		if(rr < rng.r0 || rr > rng.r1 || cc < rng.c0 || cc > rng.c1)
			return Val(VNA, 0.0, "#N/A");
		return eval_cell(e.book, rng.sidx, rr, cc);
	}

	# Unknown function: skip args
	skip_arg(e);
	while(consume_sep(e))
		skip_arg(e);
	consume_rparen(e);
	return Val(VERR, 0.0, "#NAME?");
}

# ---------------------------------------------------------------------------
# Display formatting
# ---------------------------------------------------------------------------

format_int_commas(n: big): string
{
	neg := 0;
	if(n < big 0){
		neg = 1;
		n = -n;
	}
	raw := string n;
	out := "";
	l := len raw;
	for(i := 0; i < l; i++){
		if(i > 0 && ((l - i) % 3) == 0)
			out[len out] = ',';
		out[len out] = raw[i];
	}
	if(neg)
		return "-" + out;
	return out;
}

format_cell(cell: ref Cell): string
{
	if(cell == nil)
		return "";
	v := cell.val;
	case v.kind {
	VEMPTY =>
		return "";
	VSTR =>
		return v.s;
	VNA =>
		return "#N/A";
	VERR =>
		return v.s;
	VNUM =>
		if(cell.vtype == "percentage"){
			pct := v.num * 100.0;
			ip := int math->rint(pct);
			if(math->fabs(pct - real ip) < 0.005)
				return sys->sprint("%d%%", ip);
			return sys->sprint("%.1f%%", pct);
		}
		iv := big math->rint(v.num);
		if(math->fabs(v.num - real iv) < 0.005){
			# Avoid commas on 4-digit years like 2026..2100
			if(iv >= big 1900 && iv <= big 2200)
				return string iv;
			return format_int_commas(iv);
		}
		return sys->sprint("%.2f", v.num);
	}
	return "";
}

# ---------------------------------------------------------------------------
# CLI Self-Test (-t)
# ---------------------------------------------------------------------------

run_selftest(b: ref Book)
{
	checked := 0;
	mismatches := 0;
	for(si := 0; si < len b.sheets; si++){
		sh := b.sheets[si];
		for(r := 0; r < sh.nrows; r++){
			row := sh.rows[r];
			if(row == nil) continue;
			for(c := 0; c < len row; c++){
				cell := row[c];
				if(cell == nil || len cell.formula == 0)
					continue;
				if(cell.has_cached && (cell.vtype == "float" || cell.vtype == "percentage")){
					checked++;
					diff := math->fabs(cell.val.num - cell.cached_num);
					tol := 0.01 + math->fabs(cell.cached_num) * 1e-6;
					if(cell.val.kind != VNUM || diff > tol){
						mismatches++;
						if(mismatches <= 15)
							sys->print("MISMATCH [%s %s] got=%g (%d) expected=%g formula=%s\n",
								sh.name, celladdr(r, c), cell.val.num, cell.val.kind, cell.cached_num, cell.formula);
					}
				}
			}
		}
	}
	sys->print("Loaded %d sheets, verified %d numeric formulas: %d mismatches\n",
		len b.sheets, checked, mismatches);

	# Print Quick Look Outputs from 'Inputs and quick look outputs'
	isi := findsheet(b, "Inputs and quick look outputs");
	if(isi >= 0){
		sys->print("\nQuick Look Outputs:\n");
		outrows := array[] of {4, 6, 8, 12, 14, 19, 21};
		for(i := 0; i < len outrows; i++){
			r := outrows[i];
			lbl := format_cell(getcell(b, isi, r, 1));
			v1 := format_cell(getcell(b, isi, r, 2));
			v2 := format_cell(getcell(b, isi, r, 4));
			if(len v2 > 0)
				sys->print("  %-44s | P1: %-14s | P2: %s\n", lbl, v1, v2);
			else
				sys->print("  %-44s | %s\n", lbl, v1);
		}
	}
}

# ---------------------------------------------------------------------------
# Interactive wmclient GUI
# ---------------------------------------------------------------------------

BAR_H:  con 38;
TAB_H:  con 36;
HDR_H:  con 32;
ROW_H:  con 32;
ROWH_W: con 58;
SB_W:   con 16;

c_bg, c_hdr, c_grid, c_text, c_sel, c_selbg, c_tab, c_tabact, c_editbg, c_sb, c_thumb: ref Image;
bufimg: ref Image;
bufw, bufh: int;
prev_sheet, prev_top_r, prev_left_c, prev_cur_r, prev_cur_c: int;
font: ref Font;
charw: int;

initcolors(d: ref Display)
{
	c_bg     = d.white;
	c_hdr    = d.color(int 16rececefff);
	c_grid   = d.color(int 16rc8c8d0ff);
	c_text   = d.color(int 16r09090bff);
	c_sel    = d.color(int 16r2563ebff);
	c_selbg  = d.color(int 16rdbeafeff);
	c_tab    = d.color(int 16re4e4e7ff);
	c_tabact = d.white;
	c_editbg = d.color(int 16rfef3c7ff);
	c_sb     = d.color(int 16rececefff);
	c_thumb  = d.color(int 16ra1a1aaff);
	bufimg   = nil;
	bufw     = 0;
	bufh     = 0;
	prev_sheet = -1;
	prev_top_r = -1;
	prev_left_c = -1;
	prev_cur_r = -1;
	prev_cur_c = -1;
	font     = Font.open(d, "/fonts/vera/vera/vera.18.font");
	if(font == nil)
		font = Font.open(d, "/fonts/vera/verabd/verabd.16.font");
	if(font == nil)
		font = Font.open(d, "*default*");
	charw = 9;
	if(font != nil){
		cw := font.width("0");
		if(cw > 0) charw = cw;
	}
}

colwidth(sh: ref Sheet, c: int): int
{
	if(sh.ncols <= 1)
		return 960;
	if(sh.name == "Inputs and quick look outputs"){
		if(c == 0) return 30;
		if(c == 1) return 380;
		if(c == 5) return 540;
		return 145;
	}
	if(sh.name == "Formula cheat sheet"){
		if(c == 0) return 300;
		if(c == 1) return 380;
		return 220;
	}
	if(c == 41) # Status message column AP on Playground
		return 400;
	return 124;
}

clipstr(s: string, maxw: int): string
{
	if(len s == 0 || maxw <= 0)
		return "";
	maxc := maxw / charw;
	if(maxc <= 0)
		return "";
	if(len s <= maxc)
		return s;
	return s[0:maxc];
}

draw_single_cell(img: ref Image, sh: ref Sheet, ri, ci, rows_y0, grid_y1, grid_x1: int): Rect
{
	empty := Rect((0, 0), (0, 0));
	if(ri < sh.top_r || ci < sh.left_c)
		return empty;
	y := rows_y0 + (ri - sh.top_r) * ROW_H;
	if(y >= grid_y1)
		return empty;
	y1 := y + ROW_H;
	if(y1 > grid_y1) y1 = grid_y1;

	x := ROWH_W;
	for(c := sh.left_c; c < ci && x < grid_x1; c++)
		x += colwidth(sh, c);
	if(x >= grid_x1)
		return empty;
	cw := colwidth(sh, ci);
	x1 := x + cw;
	if(x1 > grid_x1) x1 = grid_x1;

	sel := (ri == sh.cur_r && ci == sh.cur_c);
	if(sel)
		img.draw(Rect((x, y), (x1, y1)), c_selbg, nil, (0, 0));
	else
		img.draw(Rect((x, y), (x1, y1)), c_bg, nil, (0, 0));

	if(ri >= 0 && ri < sh.nrows){
		row := sh.rows[ri];
		if(row != nil && ci < len row && row[ci] != nil){
			cl := row[ci];
			s := cl.disp;
			if(len s > 0){
				cs := clipstr(s, (x1 - x) - 8);
				if(len cs > 0){
					if(cl.val.kind == VNUM){
						tx := x1 - font.width(cs) - 6;
						if(tx < x + 5) tx = x + 5;
						img.text((tx, y + 5), c_text, (0, 0), font, cs);
					}else{
						img.text((x + 5, y + 5), c_text, (0, 0), font, cs);
					}
				}
			}
		}
	}

	img.draw(Rect((x, y), (x + 1, y1)), c_grid, nil, (0, 0));
	img.draw(Rect((x, y1 - 1), (x1, y1)), c_grid, nil, (0, 0));
	if(sel)
		img.border(Rect((x, y), (x1, y1)), 2, c_sel, (0, 0));
	return Rect((x, y), (x1, y1));
}

draw_row_band(img: ref Image, sh: ref Sheet, ri, y, y1, grid_x1, draw_vlines: int)
{
	# Row header
	img.draw(Rect((0, y), (ROWH_W, y1)), c_hdr, nil, (0, 0));
	img.text((6, y + 4), c_text, (0, 0), font, string (ri + 1));

	# Clear row cells area in one draw call
	img.draw(Rect((ROWH_W, y), (grid_x1, y1)), c_bg, nil, (0, 0));

	row: array of ref Cell;
	if(ri >= 0 && ri < sh.nrows)
		row = sh.rows[ri];

	x := ROWH_W;
	for(c := sh.left_c; c < sh.ncols + 5 && x < grid_x1; c++){
		cw := colwidth(sh, c);
		x1 := x + cw;
		if(x1 > grid_x1) x1 = grid_x1;

		if(ri == sh.cur_r && c == sh.cur_c)
			img.draw(Rect((x + 1, y + 1), (x1, y1)), c_selbg, nil, (0, 0));

		if(row != nil && c < len row && row[c] != nil){
			cl := row[c];
			s := cl.disp;
			if(len s > 0){
				cs := clipstr(s, (x1 - x) - 8);
				if(len cs > 0){
					if(cl.val.kind == VNUM){
						tx := x1 - font.width(cs) - 6;
						if(tx < x + 5) tx = x + 5;
						img.text((tx, y + 5), c_text, (0, 0), font, cs);
					}else{
						img.text((x + 5, y + 5), c_text, (0, 0), font, cs);
					}
				}
			}
		}

		if(draw_vlines)
			img.draw(Rect((x, y), (x + 1, y1)), c_grid, nil, (0, 0));
		if(ri == sh.cur_r && c == sh.cur_c)
			img.border(Rect((x, y), (x1, y1)), 2, c_sel, (0, 0));

		x += cw;
	}
	img.draw(Rect((0, y1 - 1), (grid_x1, y1)), c_grid, nil, (0, 0));
}

draw_col_band(img: ref Image, sh: ref Sheet, c0, c1_excl, x_start, grid_y0, rows_y0, grid_y1, grid_x1, vis_rows: int)
{
	if(x_start >= grid_x1 || c0 >= c1_excl)
		return;
	x_end := x_start;
	for(c := c0; c < c1_excl && x_end < grid_x1; c++)
		x_end += colwidth(sh, c);
	if(x_end > grid_x1) x_end = grid_x1;

	# Clear header & cells area for this column band
	img.draw(Rect((x_start, grid_y0), (x_end, rows_y0)), c_hdr, nil, (0, 0));
	img.draw(Rect((x_start, rows_y0), (x_end, grid_y1)), c_bg, nil, (0, 0));

	# Draw column headers + cell contents
	x := x_start;
	for(c = c0; c < c1_excl && x < grid_x1; c++){
		cw := colwidth(sh, c);
		x1 := x + cw;
		if(x1 > grid_x1) x1 = grid_x1;

		cn := colname(c);
		tx := x + (cw - len cn * charw) / 2;
		if(tx < x + 2) tx = x + 2;
		img.text((tx, grid_y0 + 4), c_text, (0, 0), font, cn);

		for(ri := sh.top_r; ri < sh.top_r + vis_rows; ri++){
			y := rows_y0 + (ri - sh.top_r) * ROW_H;
			if(y >= grid_y1) break;
			y1 := y + ROW_H;
			if(y1 > grid_y1) y1 = grid_y1;

			if(ri == sh.cur_r && c == sh.cur_c)
				img.draw(Rect((x + 1, y + 1), (x1, y1)), c_selbg, nil, (0, 0));

			if(ri >= 0 && ri < sh.nrows){
				row := sh.rows[ri];
				if(row != nil && c < len row && row[c] != nil){
					cl := row[c];
					s := cl.disp;
					if(len s > 0){
						cs := clipstr(s, (x1 - x) - 8);
						if(len cs > 0){
							if(cl.val.kind == VNUM){
								ttx := x1 - font.width(cs) - 6;
								if(ttx < x + 5) ttx = x + 5;
								img.text((ttx, y + 5), c_text, (0, 0), font, cs);
							}else{
								img.text((x + 5, y + 5), c_text, (0, 0), font, cs);
							}
						}
					}
				}
			}

			if(ri == sh.cur_r && c == sh.cur_c)
				img.border(Rect((x, y), (x1, y1)), 2, c_sel, (0, 0));
		}

		img.draw(Rect((x, grid_y0), (x + 1, grid_y1)), c_grid, nil, (0, 0));
		x += cw;
	}

	# Horizontal grid lines across the band
	img.draw(Rect((x_start, rows_y0 - 1), (x_end, rows_y0)), c_grid, nil, (0, 0));
	for(ri := sh.top_r; ri < sh.top_r + vis_rows; ri++){
		y1 := rows_y0 + (ri - sh.top_r + 1) * ROW_H;
		if(y1 > grid_y1) break;
		img.draw(Rect((x_start, y1 - 1), (x_end, y1)), c_grid, nil, (0, 0));
	}
}

draw_scrollbars(img: ref Image, sh: ref Sheet, w, h, grid_y0, grid_y1, grid_x1, vis_rows: int)
{
	# Vertical scrollbar (right edge)
	img.draw(Rect((grid_x1, grid_y0), (w, grid_y1)), c_sb, nil, (0, 0));
	img.draw(Rect((grid_x1, grid_y0), (grid_x1 + 1, grid_y1)), c_grid, nil, (0, 0));
	tot_r := sh.nrows;
	if(tot_r < 1) tot_r = 1;
	vsb_h := grid_y1 - grid_y0;
	if(vsb_h > 20){
		th := (vis_rows * vsb_h) / tot_r;
		if(th < 24) th = 24;
		if(th > vsb_h) th = vsb_h;
		ty := grid_y0 + (sh.top_r * (vsb_h - th)) / tot_r;
		if(ty + th > grid_y1) ty = grid_y1 - th;
		img.draw(Rect((grid_x1 + 2, ty), (w - 2, ty + th)), c_thumb, nil, (0, 0));
	}

	# Horizontal scrollbar (above tab bar)
	img.draw(Rect((0, grid_y1), (w, grid_y1 + SB_W)), c_sb, nil, (0, 0));
	img.draw(Rect((0, grid_y1), (w, grid_y1 + 1)), c_grid, nil, (0, 0));
	tot_c := sh.ncols;
	if(tot_c < 1) tot_c = 1;
	hsb_w := grid_x1;
	if(hsb_w > 20){
		vis_c := (grid_x1 - ROWH_W) / 124;
		if(vis_c < 1) vis_c = 1;
		tw := (vis_c * hsb_w) / tot_c;
		if(tw < 28) tw = 28;
		if(tw > hsb_w) tw = hsb_w;
		tx := (sh.left_c * (hsb_w - tw)) / tot_c;
		if(tx + tw > grid_x1) tx = grid_x1 - tw;
		img.draw(Rect((tx, grid_y1 + 2), (tx + tw, grid_y1 + SB_W - 2)), c_thumb, nil, (0, 0));
	}
}

draw_formulabar(img: ref Image, b: ref Book, cur_sheet, w, editing: int, editbuf: string)
{
	sh := b.sheets[cur_sheet];
	bar_r := Rect((0, 0), (w, BAR_H));
	if(editing)
		img.draw(bar_r, c_editbg, nil, (0, 0));
	else
		img.draw(bar_r, c_hdr, nil, (0, 0));
	img.draw(Rect((0, BAR_H - 1), (w, BAR_H)), c_grid, nil, (0, 0));

	cell := getcell(b, cur_sheet, sh.cur_r, sh.cur_c);
	bartext := "";
	if(editing){
		bartext = celladdr(sh.cur_r, sh.cur_c) + " = " + editbuf + "_";
	}else{
		valshow := "";
		if(cell != nil){
			if(len cell.formula > 0)
				valshow = cell.formula;
			else
				valshow = cell.disp;
		}
		bartext = celladdr(sh.cur_r, sh.cur_c) + ": " + valshow;
	}
	img.text((8, 6), c_text, (0, 0), font, clipstr(bartext, w - 16));
}

blit_subrect(wimg, img: ref Image, wr, sub: Rect)
{
	if(sub.dx() <= 0 || sub.dy() <= 0)
		return;
	dst := Rect((wr.min.x + sub.min.x, wr.min.y + sub.min.y),
	            (wr.min.x + sub.max.x, wr.min.y + sub.max.y));
	wimg.draw(dst, img, nil, sub.min);
}

redraw(win: ref Window, b: ref Book, cur_sheet: int, editing: int, editbuf: string, force_full: int)
{
	wimg := win.image;
	if(wimg == nil)
		return;

	wr := wimg.r;
	w := wr.dx();
	h := wr.dy();
	if(w < 100 || h < 100)
		return;

	full := force_full;
	if(bufimg == nil || bufw != w || bufh != h){
		bufimg = nil;
		bufimg = win.display.newimage(Rect((0, 0), (w, h)), wimg.chans, 0, Draw->White);
		bufw = w;
		bufh = h;
		full = 1;
	}
	img := bufimg;
	if(img == nil)
		return;

	sh := b.sheets[cur_sheet];
	grid_y0 := BAR_H;
	grid_y1 := h - TAB_H - SB_W;
	grid_x1 := w - SB_W;
	rows_y0 := grid_y0 + HDR_H;
	vis_rows := (grid_y1 - rows_y0 + ROW_H - 1) / ROW_H;
	if(vis_rows < 1) vis_rows = 1;

	# Fast paths on same sheet: selection-only, vertical scroll, or horizontal scroll!
	if(!full && prev_sheet == cur_sheet){
		dr := sh.top_r - prev_top_r;
		dc := sh.left_c - prev_left_c;

		if(dr == 0 && dc == 0){
			# Only selection moved or formula bar changed: redraw at most 2 cells + formula bar!
			draw_formulabar(img, b, cur_sheet, w, editing, editbuf);
			blit_subrect(wimg, img, wr, Rect((0, 0), (w, BAR_H)));
			if(prev_cur_r != sh.cur_r || prev_cur_c != sh.cur_c){
				r1 := draw_single_cell(img, sh, prev_cur_r, prev_cur_c, rows_y0, grid_y1, grid_x1);
				r2 := draw_single_cell(img, sh, sh.cur_r, sh.cur_c, rows_y0, grid_y1, grid_x1);
				blit_subrect(wimg, img, wr, r1);
				blit_subrect(wimg, img, wr, r2);
			}
			prev_cur_r = sh.cur_r;
			prev_cur_c = sh.cur_c;
			win.display.image.flush(Draw->Flushnow);
			return;
		}else if(dc == 0 && dr > 0 && dr < vis_rows - 1){
			# Scrolled down by dr rows: blit overlapping rows UP, draw only bottom rows!
			draw_formulabar(img, b, cur_sheet, w, editing, editbuf);
			shift := dr * ROW_H;
			keep_h := (grid_y1 - rows_y0) - shift;
			if(keep_h > 0)
				img.draw(Rect((0, rows_y0), (grid_x1, rows_y0 + keep_h)), img, nil, (0, rows_y0 + shift));
			if(prev_cur_r != sh.cur_r || prev_cur_c != sh.cur_c)
				draw_single_cell(img, sh, prev_cur_r, prev_cur_c, rows_y0, grid_y1, grid_x1);
			first_new := sh.top_r + (keep_h / ROW_H);
			for(ri := first_new; ri < sh.top_r + vis_rows; ri++){
				y := rows_y0 + (ri - sh.top_r) * ROW_H;
				if(y >= grid_y1) break;
				y1 := y + ROW_H; if(y1 > grid_y1) y1 = grid_y1;
				draw_row_band(img, sh, ri, y, y1, grid_x1, 1);
			}
			draw_scrollbars(img, sh, w, h, grid_y0, grid_y1, grid_x1, vis_rows);
			prev_top_r = sh.top_r;
			prev_cur_r = sh.cur_r;
			prev_cur_c = sh.cur_c;
			blit_subrect(wimg, img, wr, Rect((0, 0), (w, grid_y1 + SB_W)));
			win.display.image.flush(Draw->Flushnow);
			return;
		}else if(dc == 0 && dr < 0 && -dr < vis_rows - 1){
			# Scrolled up by -dr rows: blit overlapping rows DOWN, draw only top rows!
			draw_formulabar(img, b, cur_sheet, w, editing, editbuf);
			shift := (-dr) * ROW_H;
			keep_h := (grid_y1 - rows_y0) - shift;
			if(keep_h > 0)
				img.draw(Rect((0, rows_y0 + shift), (grid_x1, rows_y0 + shift + keep_h)), img, nil, (0, rows_y0));
			if(prev_cur_r != sh.cur_r || prev_cur_c != sh.cur_c)
				draw_single_cell(img, sh, prev_cur_r, prev_cur_c, rows_y0, grid_y1, grid_x1);
			for(ri := sh.top_r; ri < sh.top_r + (-dr) && ri < sh.top_r + vis_rows; ri++){
				y := rows_y0 + (ri - sh.top_r) * ROW_H;
				if(y >= grid_y1) break;
				y1 := y + ROW_H; if(y1 > grid_y1) y1 = grid_y1;
				draw_row_band(img, sh, ri, y, y1, grid_x1, 1);
			}
			draw_scrollbars(img, sh, w, h, grid_y0, grid_y1, grid_x1, vis_rows);
			prev_top_r = sh.top_r;
			prev_cur_r = sh.cur_r;
			prev_cur_c = sh.cur_c;
			blit_subrect(wimg, img, wr, Rect((0, 0), (w, grid_y1 + SB_W)));
			win.display.image.flush(Draw->Flushnow);
			return;
		}else if(dr == 0 && dc > 0){
			# Scrolled right by dc columns: blit overlapping columns LEFT, draw only rightmost columns!
			shift := 0;
			for(c := prev_left_c; c < sh.left_c; c++)
				shift += colwidth(sh, c);
			avail_w := grid_x1 - ROWH_W;
			if(shift > 0 && shift < avail_w){
				draw_formulabar(img, b, cur_sheet, w, editing, editbuf);
				keep_w := avail_w - shift;
				img.draw(Rect((ROWH_W, grid_y0), (ROWH_W + keep_w, grid_y1)), img, nil, (ROWH_W + shift, grid_y0));
				if(prev_cur_r != sh.cur_r || prev_cur_c != sh.cur_c)
					draw_single_cell(img, sh, prev_cur_r, prev_cur_c, rows_y0, grid_y1, grid_x1);
				# Find first column that starts at or overlaps ROWH_W + keep_w
				x := ROWH_W;
				c_new := sh.left_c;
				while(c_new < sh.ncols + 5 && x + colwidth(sh, c_new) <= ROWH_W + keep_w){
					x += colwidth(sh, c_new);
					c_new++;
				}
				draw_col_band(img, sh, c_new, sh.ncols + 5, x, grid_y0, rows_y0, grid_y1, grid_x1, vis_rows);
				draw_scrollbars(img, sh, w, h, grid_y0, grid_y1, grid_x1, vis_rows);
				prev_left_c = sh.left_c;
				prev_cur_r = sh.cur_r;
				prev_cur_c = sh.cur_c;
				blit_subrect(wimg, img, wr, Rect((0, 0), (w, grid_y1 + SB_W)));
				win.display.image.flush(Draw->Flushnow);
				return;
			}
		}else if(dr == 0 && dc < 0){
			# Scrolled left by -dc columns: blit overlapping columns RIGHT, draw only leftmost columns!
			shift := 0;
			for(c := sh.left_c; c < prev_left_c; c++)
				shift += colwidth(sh, c);
			avail_w := grid_x1 - ROWH_W;
			if(shift > 0 && shift < avail_w){
				draw_formulabar(img, b, cur_sheet, w, editing, editbuf);
				keep_w := avail_w - shift;
				img.draw(Rect((ROWH_W + shift, grid_y0), (ROWH_W + shift + keep_w, grid_y1)), img, nil, (ROWH_W, grid_y0));
				if(prev_cur_r != sh.cur_r || prev_cur_c != sh.cur_c)
					draw_single_cell(img, sh, prev_cur_r, prev_cur_c, rows_y0, grid_y1, grid_x1);
				draw_col_band(img, sh, sh.left_c, prev_left_c, ROWH_W, grid_y0, rows_y0, grid_y1, grid_x1, vis_rows);
				draw_scrollbars(img, sh, w, h, grid_y0, grid_y1, grid_x1, vis_rows);
				prev_left_c = sh.left_c;
				prev_cur_r = sh.cur_r;
				prev_cur_c = sh.cur_c;
				blit_subrect(wimg, img, wr, Rect((0, 0), (w, grid_y1 + SB_W)));
				win.display.image.flush(Draw->Flushnow);
				return;
			}
		}
	}

	# Full redraw path
	img.draw(Rect((0, 0), (w, h)), c_bg, nil, (0, 0));
	draw_formulabar(img, b, cur_sheet, w, editing, editbuf);

	# Corner + column headers
	img.draw(Rect((0, grid_y0), (grid_x1, rows_y0)), c_hdr, nil, (0, 0));
	x := ROWH_W;
	for(c := sh.left_c; c < sh.ncols + 5 && x < grid_x1; c++){
		cw := colwidth(sh, c);
		x1 := x + cw;
		if(x1 > grid_x1) x1 = grid_x1;
		cn := colname(c);
		tx := x + (cw - len cn * charw) / 2;
		if(tx < x + 2) tx = x + 2;
		img.text((tx, grid_y0 + 4), c_text, (0, 0), font, cn);
		x += cw;
	}
	img.draw(Rect((0, rows_y0 - 1), (grid_x1, rows_y0)), c_grid, nil, (0, 0));

	# Visible rows (without per-cell vertical lines)
	y := rows_y0;
	for(ri := sh.top_r; ri < sh.nrows + 10 && y < grid_y1; ri++){
		y1 := y + ROW_H;
		if(y1 > grid_y1) y1 = grid_y1;
		draw_row_band(img, sh, ri, y, y1, grid_x1, 0);
		y += ROW_H;
	}

	# Draw vertical column grid lines once per column across full grid height
	x = ROWH_W;
	for(c = sh.left_c; c < sh.ncols + 5 && x < grid_x1; c++){
		img.draw(Rect((x, grid_y0), (x + 1, grid_y1)), c_grid, nil, (0, 0));
		x += colwidth(sh, c);
	}
	# Re-draw selection border on top of vertical grid lines if visible
	draw_single_cell(img, sh, sh.cur_r, sh.cur_c, rows_y0, grid_y1, grid_x1);

	draw_scrollbars(img, sh, w, h, grid_y0, grid_y1, grid_x1, vis_rows);

	# Sheet tabs at bottom
	tab_y0 := h - TAB_H;
	img.draw(Rect((0, tab_y0), (w, h)), c_tab, nil, (0, 0));
	img.draw(Rect((0, tab_y0), (w, tab_y0 + 1)), c_grid, nil, (0, 0));
	tx := 4;
	for(si := 0; si < len b.sheets; si++){
		sn := b.sheets[si].name;
		tw := font.width(sn) + 18;
		tr := Rect((tx, tab_y0 + 2), (tx + tw, h - 1));
		if(si == cur_sheet)
			img.draw(tr, c_tabact, nil, (0, 0));
		img.border(tr, 1, c_grid, (0, 0));
		img.text((tx + 9, tab_y0 + 6), c_text, (0, 0), font, sn);
		tx += tw + 3;
	}

	prev_sheet = cur_sheet;
	prev_top_r = sh.top_r;
	prev_left_c = sh.left_c;
	prev_cur_r = sh.cur_r;
	prev_cur_c = sh.cur_c;

	wimg.draw(wr, img, nil, (0, 0));
	win.display.image.flush(Draw->Flushnow);
}

commit_cell(b: ref Book, sidx, r, c: int, text: string, do_recalc: int)
{
	if(sidx < 0 || sidx >= len b.sheets)
		return;
	sh := b.sheets[sidx];
	cell := ensurecell(sh, r, c);
	t := trim(text);
	cell.formula = "";
	cell.raw_str = "";
	cell.raw_num = 0.0;
	cell.has_cached = 0;

	if(len t == 0){
		cell.vtype = "";
	}else if(t[0] == '='){
		cell.formula = t;
		if(cell.vtype != "percentage")
			cell.vtype = "float";
	}else if(t[len t - 1] == '%'){
		cell.vtype = "percentage";
		cell.raw_num = real t[0:len t - 1] / 100.0;
	}else{
		# Check if numeric (allow commas like 120,000)
		isnum := 1;
		hasdig := 0;
		clean := "";
		for(i := 0; i < len t; i++){
			ch := t[i];
			if(ch >= '0' && ch <= '9'){
				hasdig = 1;
				clean[len clean] = ch;
			}else if(ch == '-' && i == 0){
				clean[len clean] = ch;
			}else if(ch == '.'){
				clean[len clean] = ch;
			}else if(ch == ','){
				;
			}else{
				isnum = 0;
			}
		}
		if(isnum && hasdig){
			cell.vtype = "float";
			cell.raw_num = real clean;
		}else{
			cell.vtype = "string";
			cell.raw_str = t;
		}
	}
	if(do_recalc)
		recalc(b);
}

commit_edit(b: ref Book, cur_sheet: int, text: string)
{
	sh := b.sheets[cur_sheet];
	commit_cell(b, cur_sheet, sh.cur_r, sh.cur_c, text, 1);
}

# ---------------------------------------------------------------------------
# Plain-text .s9 interchange format & clean value formatters
# ---------------------------------------------------------------------------

format_plain(cell: ref Cell): string
{
	if(cell == nil)
		return "";
	v := cell.val;
	case v.kind {
	VEMPTY =>
		return "";
	VSTR =>
		return v.s;
	VNA =>
		return "#N/A";
	VERR =>
		return v.s;
	VNUM =>
		if(cell.vtype == "percentage"){
			pct := v.num * 100.0;
			ip := int math->rint(pct);
			if(math->fabs(pct - real ip) < 0.005)
				return sys->sprint("%d%%", ip);
			return sys->sprint("%.4g%%", pct);
		}
		iv := big math->rint(v.num);
		if(math->fabs(v.num - real iv) < 0.005)
			return string iv;
		return sys->sprint("%.6g", v.num);
	}
	return "";
}

format_raw(cell: ref Cell): string
{
	if(cell == nil)
		return "";
	if(len cell.formula > 0){
		f := cell.formula;
		if(len f >= 4 && f[0:4] == "of:=")
			return "=" + f[4:];
		return f;
	}
	if(cell.vtype == "percentage")
		return format_plain(cell);
	if(cell.vtype == "float")
		return format_plain(cell);
	return cell.raw_str;
}

sheet_tsv(sh: ref Sheet): string
{
	out := "";
	for(r := 0; r < sh.nrows; r++){
		row := sh.rows[r];
		if(row != nil){
			line := "";
			last_nonempty := -1;
			for(c := 0; c < len row; c++){
				if(row[c] != nil && len format_plain(row[c]) > 0)
					last_nonempty = c;
			}
			for(c = 0; c <= last_nonempty; c++){
				if(c > 0)
					line += "\t";
				if(row[c] != nil)
					line += format_plain(row[c]);
			}
			out += line;
		}
		out += "\n";
	}
	return out;
}

sheet_raw_s9(b: ref Book, sidx: int): string
{
	if(sidx < 0 || sidx >= len b.sheets)
		return "";
	sh := b.sheets[sidx];
	out := "";
	for(r := 0; r < sh.nrows; r++){
		row := sh.rows[r];
		if(row == nil) continue;
		for(c := 0; c < len row; c++){
			cl := row[c];
			if(cl == nil) continue;
			kind := "";
			val := "";
			if(len cl.formula > 0){
				kind = "fml";
				val = format_raw(cl);
			}else if(cl.vtype == "percentage"){
				kind = "pct";
				val = sys->sprint("%.10g", cl.raw_num);
			}else if(cl.vtype == "float"){
				kind = "num";
				val = sys->sprint("%.10g", cl.raw_num);
			}else if(len cl.raw_str > 0){
				kind = "str";
				val = cl.raw_str;
			}else{
				continue;
			}
			out += sys->sprint("cell\t%d!%s\t%s\t%s\n", sidx, celladdr(r, c), kind, val);
		}
	}
	return out;
}

book_to_s9(b: ref Book): string
{
	out := "# Inferno sheet format v1\n";
	for(si := 0; si < len b.sheets; si++)
		out += sys->sprint("sheet\t%d\t%s\n", si, b.sheets[si].name);
	out += "\n";
	for(nl := b.names; nl != nil; nl = tl nl){
		nr := hd nl;
		if(nr.sheetidx >= 0)
			out += sys->sprint("name\t%s\t%d!%s\n", nr.name, nr.sheetidx, celladdr(nr.row, nr.col));
	}
	out += "\n";
	for(si = 0; si < len b.sheets; si++)
		out += sheet_raw_s9(b, si);
	return out;
}

save_s9(b: ref Book, path: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r664);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	data := array of byte book_to_s9(b);
	if(sys->write(fd, data, len data) != len data)
		return sys->sprint("write %s: %r", path);
	return nil;
}

split_tabs(s: string): array of string
{
	parts: list of string;
	start := 0;
	for(i := 0; i <= len s; i++){
		if(i == len s || s[i] == '\t'){
			parts = s[start:i] :: parts;
			start = i + 1;
		}
	}
	n := len parts;
	arr := array[n] of string;
	for(k := n - 1; k >= 0; k--){
		arr[k] = hd parts;
		parts = tl parts;
	}
	return arr;
}

parse_s9_addr(b: ref Book, s: string): (int, int, int, int)
{
	bang := -1;
	for(i := 0; i < len s; i++){
		if(s[i] == '!'){
			bang = i;
			break;
		}
	}
	if(bang <= 0 || bang >= len s - 1)
		return (-1, 0, 0, 0);
	sp := s[0:bang];
	ap := s[bang + 1:];
	sidx := -1;
	isdigits := 1;
	for(i = 0; i < len sp; i++)
		if(sp[i] < '0' || sp[i] > '9')
			isdigits = 0;
	if(isdigits)
		sidx = int sp;
	else
		sidx = findsheet(b, sp);
	if(sidx < 0 || sidx >= len b.sheets)
		return (-1, 0, 0, 0);
	(r, c, ok) := parse_a1(ap);
	if(!ok)
		return (-1, 0, 0, 0);
	return (sidx, r, c, 1);
}

apply_s9_text(b: ref Book, text: string): (int, string)
{
	applied := 0;
	start := 0;
	for(i := 0; i <= len text; i++){
		if(i < len text && text[i] != '\n')
			continue;
		line := text[start:i];
		start = i + 1;
		if(len line > 0 && line[len line - 1] == '\r')
			line = line[0:len line - 1];
		tline := trim(line);
		if(len tline == 0 || tline[0] == '#')
			continue;
		f := split_tabs(line);
		if(len f < 3)
			continue;
		case f[0] {
		"sheet" =>
			idx := int f[1];
			nm := f[2];
			if(idx >= len b.sheets){
				ns := array[idx + 1] of ref Sheet;
				if(b.sheets != nil)
					ns[0:] = b.sheets;
				for(k := len b.sheets; k <= idx; k++)
					ns[k] = ref Sheet(sys->sprint("Sheet%d", k + 1), 1, 1, array[1] of array of ref Cell, 0, 0, 0, 0);
				b.sheets = ns;
			}
			b.sheets[idx].name = nm;
			applied++;
		"name" =>
			(sidx, r, c, ok) := parse_s9_addr(b, f[2]);
			if(ok){
				found := 0;
				for(nl := b.names; nl != nil; nl = tl nl){
					nr := hd nl;
					if(tolower(nr.name) == tolower(f[1])){
						nr.sheetidx = sidx; nr.row = r; nr.col = c;
						found = 1;
						break;
					}
				}
				if(!found)
					b.names = ref NamedRange(f[1], f[2], sidx, r, c) :: b.names;
				applied++;
			}
		"cell" =>
			if(len f < 4)
				continue;
			(sidx, r, c, ok) := parse_s9_addr(b, f[1]);
			if(!ok)
				continue;
			sh := b.sheets[sidx];
			cl := ensurecell(sh, r, c);
			cl.formula = "";
			cl.raw_str = "";
			cl.raw_num = 0.0;
			cl.has_cached = 0;
			case f[2] {
			"num" =>
				cl.vtype = "float";
				cl.raw_num = real f[3];
			"pct" =>
				cl.vtype = "percentage";
				cl.raw_num = real f[3];
			"str" =>
				cl.vtype = "string";
				cl.raw_str = f[3];
			"fml" =>
				cl.formula = f[3];
				if(cl.vtype != "percentage")
					cl.vtype = "float";
			"empty" =>
				cl.vtype = "";
			* =>
				commit_cell(b, sidx, r, c, f[3], 0);
			}
			applied++;
		}
	}
	return (applied, nil);
}

load_s9(path: string): (ref Book, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", path));
	data := "";
	buf := array[16384] of byte;
	for(;;){
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		data += string buf[0:n];
	}
	book := ref Book(path, array[0] of ref Sheet, nil);
	(napp, err) := apply_s9_text(book, data);
	if(err != nil)
		return (nil, err);
	if(len book.sheets == 0)
		return (nil, "no sheets found in " + path);
	return (book, nil);
}

load_book(path: string): (ref Book, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", path));
	hdr := array[4] of byte;
	n := sys->read(fd, hdr, len hdr);
	fd = nil;
	if(n >= 2 && hdr[0] == byte 'P' && hdr[1] == byte 'K')
		return load_ods(path);
	return load_s9(path);
}

# ---------------------------------------------------------------------------
# Live Synthetic 9P/Styx Filesystem (/mnt/sheet)
# ---------------------------------------------------------------------------

QKROOT:   con 0;
QKTOP:    con 1;  # 1=ctl, 2=event, 3=index, 4=apply
QKNAMES:  con 2;
QKNAME:   con 3;  # payload = index in book.names
QKSHEETS: con 4;
QKSHEET:  con 5;  # payload = sidx
QKSSUB:   con 6;  # payload = (sidx << 8) | sub (1=name, 2=tsv, 3=raw)
QKSVALD:  con 7;  # payload = sidx
QKSCELLD: con 8;  # payload = sidx
QKSVAL:   con 9;  # payload = (sidx << 36) | (r << 16) | c
QKSCELL:  con 10; # payload = (sidx << 36) | (r << 16) | c

QTOP_CTL:   con 1;
QTOP_EVENT: con 2;
QTOP_INDEX: con 3;
QTOP_APPLY: con 4;

QSUB_NAME:  con 1;
QSUB_TSV:   con 2;
QSUB_RAW:   con 3;

FsReq: adt {
	q:       big;
	offset:  big;
	count:   int;
	data:    array of byte;
	iswrite: int;
	evmsg:   ref Tmsg.Read;
	rreply:  chan of (array of byte, string);
	wreply:  chan of (int, string);
};

mkqid(kind: int, payload: big): big
{
	return (big kind << 56) | (payload & ((big 1 << 56) - big 1));
}

qkind(q: big): int
{
	return int (q >> 56);
}

qpay(q: big): big
{
	return q & ((big 1 << 56) - big 1);
}

mkcellq(kind, sidx, r, c: int): big
{
	p := (big sidx << 36) | (big (r & 16rfffff) << 16) | big (c & 16rffff);
	return mkqid(kind, p);
}

decode_cellq(q: big): (int, int, int)
{
	p := qpay(q);
	sidx := int (p >> 36);
	r := int ((p >> 16) & big 16rfffff);
	c := int (p & big 16rffff);
	return (sidx, r, c);
}

mkdirent(q: big, name: string, mode: int, length: big): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.name = name;
	d.uid = "inferno";
	d.gid = "inferno";
	d.muid = "inferno";
	qtype := Sys->QTFILE;
	if(mode & Sys->DMDIR)
		qtype = Sys->QTDIR;
	d.qid = Sys->Qid(q, 0, qtype);
	d.mode = mode;
	d.length = length;
	return d;
}

get_named_by_idx(b: ref Book, idx: int): ref NamedRange
{
	i := 0;
	for(nl := b.names; nl != nil; nl = tl nl){
		if(i == idx)
			return hd nl;
		i++;
	}
	return nil;
}

stat_q(b: ref Book, q: big): (ref Sys->Dir, string)
{
	k := qkind(q);
	p := qpay(q);
	case k {
	QKROOT =>
		return (mkdirent(q, "/", Sys->DMDIR | 8r555, big 0), nil);
	QKTOP =>
		case int p {
		QTOP_CTL =>   return (mkdirent(q, "ctl",   8r666, big 0), nil);
		QTOP_EVENT => return (mkdirent(q, "event", 8r444, big 0), nil);
		QTOP_INDEX => return (mkdirent(q, "index", 8r444, big 0), nil);
		QTOP_APPLY => return (mkdirent(q, "apply", 8r222, big 0), nil);
		}
	QKNAMES =>
		return (mkdirent(q, "names", Sys->DMDIR | 8r555, big 0), nil);
	QKNAME =>
		nr := get_named_by_idx(b, int p);
		if(nr != nil)
			return (mkdirent(q, nr.name, 8r666, big 0), nil);
	QKSHEETS =>
		return (mkdirent(q, "sheets", Sys->DMDIR | 8r555, big 0), nil);
	QKSHEET =>
		si := int p;
		if(si >= 0 && si < len b.sheets)
			return (mkdirent(q, string si, Sys->DMDIR | 8r555, big 0), nil);
	QKSSUB =>
		si := int (p >> 8);
		sub := int (p & big 16rff);
		if(si >= 0 && si < len b.sheets){
			case sub {
			QSUB_NAME => return (mkdirent(q, "name", 8r444, big 0), nil);
			QSUB_TSV  => return (mkdirent(q, "tsv",  8r444, big 0), nil);
			QSUB_RAW  => return (mkdirent(q, "raw",  8r444, big 0), nil);
			}
		}
	QKSVALD =>
		si := int p;
		if(si >= 0 && si < len b.sheets)
			return (mkdirent(q, "val", Sys->DMDIR | 8r555, big 0), nil);
	QKSCELLD =>
		si := int p;
		if(si >= 0 && si < len b.sheets)
			return (mkdirent(q, "cell", Sys->DMDIR | 8r555, big 0), nil);
	QKSVAL =>
		(si, r, c) := decode_cellq(q);
		if(si >= 0 && si < len b.sheets)
			return (mkdirent(q, celladdr(r, c), 8r444, big 0), nil);
	QKSCELL =>
		(si, r, c) := decode_cellq(q);
		if(si >= 0 && si < len b.sheets)
			return (mkdirent(q, celladdr(r, c), 8r666, big 0), nil);
	}
	return (nil, Styxservers->Enotfound);
}

walk_q(b: ref Book, pq: big, name: string): (ref Sys->Dir, string)
{
	if(name == ".."){
		k := qkind(pq);
		p := qpay(pq);
		case k {
		QKROOT =>   return stat_q(b, pq);
		QKTOP or QKNAMES or QKSHEETS =>
			return stat_q(b, mkqid(QKROOT, big 0));
		QKNAME =>
			return stat_q(b, mkqid(QKNAMES, big 0));
		QKSHEET =>
			return stat_q(b, mkqid(QKSHEETS, big 0));
		QKSSUB =>
			return stat_q(b, mkqid(QKSHEET, p >> 8));
		QKSVALD or QKSCELLD =>
			return stat_q(b, mkqid(QKSHEET, p));
		QKSVAL =>
			(si, nil, nil) := decode_cellq(pq);
			return stat_q(b, mkqid(QKSVALD, big si));
		QKSCELL =>
			(si, nil, nil) := decode_cellq(pq);
			return stat_q(b, mkqid(QKSCELLD, big si));
		}
		return stat_q(b, mkqid(QKROOT, big 0));
	}

	k := qkind(pq);
	p := qpay(pq);
	case k {
	QKROOT =>
		case name {
		"ctl"    => return stat_q(b, mkqid(QKTOP, big QTOP_CTL));
		"event"  => return stat_q(b, mkqid(QKTOP, big QTOP_EVENT));
		"index"  => return stat_q(b, mkqid(QKTOP, big QTOP_INDEX));
		"apply"  => return stat_q(b, mkqid(QKTOP, big QTOP_APPLY));
		"names"  => return stat_q(b, mkqid(QKNAMES, big 0));
		"sheets" => return stat_q(b, mkqid(QKSHEETS, big 0));
		}
	QKNAMES =>
		i := 0;
		for(nl := b.names; nl != nil; nl = tl nl){
			nr := hd nl;
			if(nr.name == name || tolower(nr.name) == tolower(name))
				return stat_q(b, mkqid(QKNAME, big i));
			i++;
		}
	QKSHEETS =>
		isd := len name > 0;
		for(i := 0; i < len name; i++)
			if(name[i] < '0' || name[i] > '9')
				isd = 0;
		if(isd){
			si := int name;
			if(si >= 0 && si < len b.sheets)
				return stat_q(b, mkqid(QKSHEET, big si));
		}
	QKSHEET =>
		si := int p;
		if(si >= 0 && si < len b.sheets){
			case name {
			"name" => return stat_q(b, mkqid(QKSSUB, (big si << 8) | big QSUB_NAME));
			"tsv"  => return stat_q(b, mkqid(QKSSUB, (big si << 8) | big QSUB_TSV));
			"raw"  => return stat_q(b, mkqid(QKSSUB, (big si << 8) | big QSUB_RAW));
			"val"  => return stat_q(b, mkqid(QKSVALD, big si));
			"cell" => return stat_q(b, mkqid(QKSCELLD, big si));
			}
		}
	QKSVALD =>
		si := int p;
		(r, c, ok) := parse_a1(name);
		if(ok && si >= 0 && si < len b.sheets)
			return stat_q(b, mkcellq(QKSVAL, si, r, c));
	QKSCELLD =>
		si := int p;
		(r, c, ok) := parse_a1(name);
		if(ok && si >= 0 && si < len b.sheets)
			return stat_q(b, mkcellq(QKSCELL, si, r, c));
	}
	return (nil, Styxservers->Enotfound);
}

readdir_q(b: ref Book, q: big, offset, count: int, reply: chan of (ref Sys->Dir, string))
{
	k := qkind(q);
	p := qpay(q);
	ents: list of ref Sys->Dir;

	case k {
	QKROOT =>
		ents = mkdirent(mkqid(QKSHEETS, big 0), "sheets", Sys->DMDIR | 8r555, big 0) ::
		       mkdirent(mkqid(QKNAMES, big 0),  "names",  Sys->DMDIR | 8r555, big 0) ::
		       mkdirent(mkqid(QKTOP, big QTOP_APPLY), "apply", 8r222, big 0) ::
		       mkdirent(mkqid(QKTOP, big QTOP_INDEX), "index", 8r444, big 0) ::
		       mkdirent(mkqid(QKTOP, big QTOP_EVENT), "event", 8r444, big 0) ::
		       mkdirent(mkqid(QKTOP, big QTOP_CTL),   "ctl",   8r666, big 0) :: nil;
	QKNAMES =>
		i := 0;
		for(nl := b.names; nl != nil; nl = tl nl){
			nr := hd nl;
			ents = mkdirent(mkqid(QKNAME, big i), nr.name, 8r666, big 0) :: ents;
			i++;
		}
	QKSHEETS =>
		for(si := len b.sheets - 1; si >= 0; si--)
			ents = mkdirent(mkqid(QKSHEET, big si), string si, Sys->DMDIR | 8r555, big 0) :: ents;
	QKSHEET =>
		si := int p;
		if(si >= 0 && si < len b.sheets){
			ents = mkdirent(mkqid(QKSCELLD, big si), "cell", Sys->DMDIR | 8r555, big 0) ::
			       mkdirent(mkqid(QKSVALD,  big si), "val",  Sys->DMDIR | 8r555, big 0) ::
			       mkdirent(mkqid(QKSSUB, (big si << 8) | big QSUB_RAW),  "raw",  8r444, big 0) ::
			       mkdirent(mkqid(QKSSUB, (big si << 8) | big QSUB_TSV),  "tsv",  8r444, big 0) ::
			       mkdirent(mkqid(QKSSUB, (big si << 8) | big QSUB_NAME), "name", 8r444, big 0) :: nil;
		}
	QKSVALD or QKSCELLD =>
		si := int p;
		if(si >= 0 && si < len b.sheets){
			sh := b.sheets[si];
			ck := QKSVAL;
			mode := 8r444;
			if(k == QKSCELLD){
				ck = QKSCELL;
				mode = 8r666;
			}
			idx := 0;
			sent := 0;
			for(r := 0; r < sh.nrows && sent < count; r++){
				row := sh.rows[r];
				if(row == nil) continue;
				for(c := 0; c < len row && sent < count; c++){
					if(row[c] == nil) continue;
					if(len row[c].formula == 0 && len row[c].disp == 0) continue;
					if(idx >= offset){
						reply <-= (mkdirent(mkcellq(ck, si, r, c), celladdr(r, c), mode, big 0), nil);
						sent++;
					}
					idx++;
				}
			}
			reply <-= (nil, nil);
			return;
		}
	}

	# Reverse non-cell list so order is natural, then skip offset and emit count
	rev: list of ref Sys->Dir;
	for(l := ents; l != nil; l = tl l)
		rev = hd l :: rev;
	idx := 0;
	sent := 0;
	for(l = rev; l != nil && sent < count; l = tl l){
		if(idx >= offset){
			reply <-= (hd l, nil);
			sent++;
		}
		idx++;
	}
	reply <-= (nil, nil);
}

handle_navop(b: ref Book, op: ref Navop)
{
	pick m := op {
	Stat =>
		m.reply <-= stat_q(b, m.path);
	Walk =>
		m.reply <-= walk_q(b, m.path, m.name);
	Readdir =>
		readdir_q(b, m.path, m.offset, m.count, m.reply);
	}
}

styx_loop(tchan: chan of ref Tmsg, srv: ref Styxserver, reqc: chan of ref FsReq)
{
	while((gm := <-tchan) != nil){
		pick m := gm {
		Readerror =>
			return;
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				continue;
			}
			if(c.qtype & Sys->QTDIR){
				srv.read(m);
				continue;
			}
			if(qkind(c.path) == QKTOP && int qpay(c.path) == QTOP_EVENT){
				reqc <-= ref FsReq(c.path, m.offset, m.count, nil, 0, m, nil, nil);
				continue;
			}
			rc := chan of (array of byte, string);
			reqc <-= ref FsReq(c.path, m.offset, m.count, nil, 0, nil, rc, nil);
			(data, rerr) := <-rc;
			if(rerr != nil)
				srv.reply(ref Rmsg.Error(m.tag, rerr));
			else
				srv.reply(styxservers->readbytes(m, data));
		Write =>
			(c, err) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				continue;
			}
			wc := chan of (int, string);
			reqc <-= ref FsReq(c.path, m.offset, len m.data, m.data, 1, nil, nil, wc);
			(nw, werr) := <-wc;
			if(werr != nil)
				srv.reply(ref Rmsg.Error(m.tag, werr));
			else
				srv.reply(ref Rmsg.Write(m.tag, nw));
		* =>
			srv.default(gm);
		}
	}
}

evwaiters: list of ref Tmsg.Read;
evqueue: list of string;
batch_mode := 0;

emit_event(srv: ref Styxserver, line: string)
{
	if(srv == nil)
		return;
	if(evwaiters != nil){
		data := array of byte line;
		for(l := evwaiters; l != nil; l = tl l){
			m := hd l;
			d := data;
			if(len d > m.count)
				d = d[0:m.count];
			srv.reply(ref Rmsg.Read(m.tag, d));
		}
		evwaiters = nil;
		return;
	}
	if(len evqueue < 32)
		evqueue = line :: evqueue;
}

pop_evqueue(): string
{
	if(evqueue == nil)
		return nil;
	# FIFO: reverse, pop head, reverse back
	rev: list of string;
	for(l := evqueue; l != nil; l = tl l)
		rev = hd l :: rev;
	out := hd rev;
	evqueue = nil;
	for(l = tl rev; l != nil; l = tl l)
		evqueue = hd l :: evqueue;
	return out;
}

handle_fsreq(srv: ref Styxserver, b: ref Book, cur_sheet: int, req: ref FsReq): (ref Book, int, int)
{
	# Async /mnt/sheet/event reader
	if(req.evmsg != nil){
		ev := pop_evqueue();
		if(ev != nil){
			d := array of byte ev;
			if(len d > req.evmsg.count)
				d = d[0:req.evmsg.count];
			srv.reply(ref Rmsg.Read(req.evmsg.tag, d));
		}else{
			evwaiters = req.evmsg :: evwaiters;
		}
		return (b, cur_sheet, 0);
	}

	k := qkind(req.q);
	p := qpay(req.q);

	if(!req.iswrite){
		s := "";
		case k {
		QKTOP =>
			case int p {
			QTOP_CTL =>
				s = sys->sprint("batch %d\nsheet %d\n", batch_mode, cur_sheet);
			QTOP_INDEX =>
				for(si := 0; si < len b.sheets; si++){
					sh := b.sheets[si];
					s += sys->sprint("%d\t%d\t%d\t%s\n", si, sh.nrows, sh.ncols, sh.name);
				}
			}
		QKNAME =>
			nr := get_named_by_idx(b, int p);
			if(nr == nil){
				req.rreply <-= (nil, Styxservers->Enotfound);
				return (b, cur_sheet, 0);
			}
			s = format_plain(getcell(b, nr.sheetidx, nr.row, nr.col)) + "\n";
		QKSSUB =>
			si := int (p >> 8);
			sub := int (p & big 16rff);
			if(si < 0 || si >= len b.sheets){
				req.rreply <-= (nil, Styxservers->Enotfound);
				return (b, cur_sheet, 0);
			}
			case sub {
			QSUB_NAME => s = b.sheets[si].name + "\n";
			QSUB_TSV  => s = sheet_tsv(b.sheets[si]);
			QSUB_RAW  => s = sheet_raw_s9(b, si);
			}
		QKSVAL =>
			(si, r, c) := decode_cellq(req.q);
			s = format_plain(getcell(b, si, r, c)) + "\n";
		QKSCELL =>
			(si, r, c) := decode_cellq(req.q);
			s = format_raw(getcell(b, si, r, c)) + "\n";
		* =>
			req.rreply <-= (nil, Styxservers->Enotfound);
			return (b, cur_sheet, 0);
		}
		req.rreply <-= (array of byte s, nil);
		return (b, cur_sheet, 0);
	}

	# Write request
	txt := string req.data;
	nw := len req.data;
	dirty := 0;

	case k {
	QKTOP =>
		case int p {
		QTOP_CTL =>
			cmd := trim(txt);
			(nargs, args) := sys->tokenize(cmd, " \t\n\r");
			if(nargs == 0){
				req.wreply <-= (nw, nil);
				return (b, cur_sheet, 0);
			}
			op := hd args;
			case op {
			"recalc" =>
				recalc(b);
				emit_event(srv, "recalc\n");
				dirty = 1;
			"batch" =>
				if(tl args != nil && hd tl args == "on"){
					batch_mode = 1;
				}else{
					batch_mode = 0;
					recalc(b);
					emit_event(srv, "recalc\n");
					dirty = 1;
				}
			"sheet" =>
				if(tl args != nil){
					targ := trim(cmd[len "sheet":]);
					si := findsheet(b, targ);
					if(si < 0){
						isd := len targ > 0;
						for(i := 0; i < len targ; i++)
							if(targ[i] < '0' || targ[i] > '9') isd = 0;
						if(isd && int targ >= 0 && int targ < len b.sheets)
							si = int targ;
					}
					if(si >= 0){
						cur_sheet = si;
						dirty = 1;
					}else{
						req.wreply <-= (0, "unknown sheet");
						return (b, cur_sheet, 0);
					}
				}
			"save" =>
				if(tl args == nil){
					req.wreply <-= (0, "usage: save path");
					return (b, cur_sheet, 0);
				}
				serr := save_s9(b, trim(cmd[len "save":]));
				if(serr != nil){
					req.wreply <-= (0, serr);
					return (b, cur_sheet, 0);
				}
			"load" =>
				if(tl args == nil){
					req.wreply <-= (0, "usage: load path");
					return (b, cur_sheet, 0);
				}
				(nb, lerr) := load_book(trim(cmd[len "load":]));
				if(lerr != nil){
					req.wreply <-= (0, lerr);
					return (b, cur_sheet, 0);
				}
				b = nb;
				recalc(b);
				if(cur_sheet >= len b.sheets)
					cur_sheet = 0;
				emit_event(srv, "load\n");
				dirty = 1;
			* =>
				req.wreply <-= (0, "unknown ctl command");
				return (b, cur_sheet, 0);
			}
			req.wreply <-= (nw, nil);
			return (b, cur_sheet, dirty);
		QTOP_APPLY =>
			(nil, aerr) := apply_s9_text(b, txt);
			if(aerr != nil){
				req.wreply <-= (0, aerr);
				return (b, cur_sheet, 0);
			}
			if(!batch_mode){
				recalc(b);
				emit_event(srv, "recalc\n");
				dirty = 1;
			}
			req.wreply <-= (nw, nil);
			return (b, cur_sheet, dirty);
		* =>
			req.wreply <-= (0, Styxservers->Eperm);
			return (b, cur_sheet, 0);
		}
	QKNAME =>
		nr := get_named_by_idx(b, int p);
		if(nr == nil || nr.sheetidx < 0){
			req.wreply <-= (0, Styxservers->Enotfound);
			return (b, cur_sheet, 0);
		}
		commit_cell(b, nr.sheetidx, nr.row, nr.col, txt, !batch_mode);
		if(!batch_mode){
			cl := getcell(b, nr.sheetidx, nr.row, nr.col);
			emit_event(srv, sys->sprint("set %d %s %s\n", nr.sheetidx, celladdr(nr.row, nr.col), format_plain(cl)));
			dirty = 1;
		}
		req.wreply <-= (nw, nil);
		return (b, cur_sheet, dirty);
	QKSCELL =>
		(si, r, c) := decode_cellq(req.q);
		if(si < 0 || si >= len b.sheets){
			req.wreply <-= (0, Styxservers->Enotfound);
			return (b, cur_sheet, 0);
		}
		commit_cell(b, si, r, c, txt, !batch_mode);
		if(!batch_mode){
			cl := getcell(b, si, r, c);
			emit_event(srv, sys->sprint("set %d %s %s\n", si, celladdr(r, c), format_plain(cl)));
			dirty = 1;
		}
		req.wreply <-= (nw, nil);
		return (b, cur_sheet, dirty);
	}

	req.wreply <-= (0, Styxservers->Eperm);
	return (b, cur_sheet, 0);
}

SHEET_ADDR_FILE: con "/tmp/sheet.addr";

listen_cfd: ref Sys->FD;
tcp_cfds: list of ref Sys->FD;
fs_closing := 0;

listen_sheetfs(navc: chan of ref Navop, reqc: chan of ref FsReq)
{
	ok := -1;
	c: Sys->Connection;
	bound_addr := "";
	for(port := 19900; port < 19920; port++){
		addr := sys->sprint("tcp!127.0.0.1!%d", port);
		(ok, c) = sys->announce(addr);
		if(ok >= 0){
			bound_addr = addr;
			break;
		}
	}
	if(ok < 0)
		return;
	afd := sys->create(SHEET_ADDR_FILE, Sys->OWRITE, 8r664);
	if(afd != nil)
		sys->fprint(afd, "%s\n", bound_addr);
	listen_cfd = c.cfd;
	for(;;){
		(lok, nc) := sys->listen(c);
		if(lok < 0 || fs_closing)
			return;
		dfd := sys->open(nc.dir + "/data", Sys->ORDWR);
		if(dfd == nil)
			continue;
		if(fs_closing){
			if(nc.cfd != nil)
				sys->fprint(nc.cfd, "hangup");
			dfd = nil;
			return;
		}
		if(nc.cfd != nil)
			tcp_cfds = nc.cfd :: tcp_cfds;
		(tchan, srv) := Styxserver.new(dfd, Navigator.new(navc), mkqid(QKROOT, big 0));
		dfd = nil;
		spawn styx_loop(tchan, srv, reqc);
	}
}

shutdown_sheetfs(mountpt: string)
{
	fs_closing = 1;
	sys->remove(SHEET_ADDR_FILE);
	if(listen_cfd != nil){
		sys->fprint(listen_cfd, "hangup");
		listen_cfd = nil;
	}
	for(l := tcp_cfds; l != nil; l = tl l){
		cfd := hd l;
		if(cfd != nil)
			sys->fprint(cfd, "hangup");
	}
	tcp_cfds = nil;
	sys->unmount(nil, mountpt);
}

mount_sheetfs(fd: ref Sys->FD, mountpt: string)
{
	if(sys->mount(fd, nil, mountpt, Sys->MREPL, nil) < 0)
		sys->fprint(sys->fildes(2), "wm/sheet: mount %s failed: %r\n", mountpt);
}

start_sheetfs(mountpt: string): (ref Styxserver, chan of ref Navop, chan of ref FsReq)
{
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	if(styx == nil || styxservers == nil)
		return (nil, nil, nil);
	styx->init();
	styxservers->init(styx);

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return (nil, nil, nil);

	navc := chan of ref Navop;
	reqc := chan of ref FsReq;
	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navc), mkqid(QKROOT, big 0));
	fds[0] = nil;
	spawn styx_loop(tchan, srv, reqc);
	# Mount asynchronously so the main alt loop can service Tattach's Navop.Stat
	spawn mount_sheetfs(fds[1], mountpt);
	# Also listen on loopback TCP (19900..19919) and publish address in /tmp/sheet.addr
	spawn listen_sheetfs(navc, reqc);
	return (srv, navc, reqc);
}

ensure_visible(win: ref Window, sh: ref Sheet)
{
	if(win.image == nil)
		return;
	vis_rows := (win.image.r.dy() - BAR_H - TAB_H - SB_W - HDR_H) / ROW_H;
	if(vis_rows < 1) vis_rows = 1;
	if(sh.cur_r < sh.top_r)
		sh.top_r = sh.cur_r;
	else if(sh.cur_r >= sh.top_r + vis_rows)
		sh.top_r = sh.cur_r - vis_rows + 1;

	if(sh.cur_c < sh.left_c)
		sh.left_c = sh.cur_c;
	else{
		# Ensure cur_c fits in visible width
		avail := win.image.r.dx() - ROWH_W - SB_W;
		wsum := 0;
		for(c := sh.left_c; c <= sh.cur_c; c++)
			wsum += colwidth(sh, c);
		while(wsum > avail && sh.left_c < sh.cur_c){
			wsum -= colwidth(sh, sh.left_c);
			sh.left_c++;
		}
	}
}

endswith(s, suf: string): int
{
	if(len s < len suf)
		return 0;
	return tolower(s[len s - len suf:]) == suf;
}

find_default_ods(): string
{
	(ok, nil) := sys->stat(DEFAULT_ODS);
	if(ok == 0)
		return DEFAULT_ODS;
	fd := sys->open(DEFAULT_DIR, Sys->OREAD);
	if(fd == nil)
		return DEFAULT_ODS;
	best := "";
	best_mtime := 0;
	for(;;){
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++){
			if((dirs[i].mode & Sys->DMDIR) != 0)
				continue;
			name := dirs[i].name;
			if(!endswith(name, ".ods"))
				continue;
			if(best == "" || dirs[i].mtime > best_mtime || (dirs[i].mtime == best_mtime && name < best)){
				best = name;
				best_mtime = dirs[i].mtime;
			}
		}
	}
	if(best != "")
		return DEFAULT_DIR + "/" + best;
	return DEFAULT_ODS;
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	zip = load Zip Zip->PATH;
	xml = load Xml Xml->PATH;
	str = load String String->PATH;
	math = load Math Math->PATH;
	wmclient = load Wmclient Wmclient->PATH;

	if(bufio == nil) { sys->fprint(sys->fildes(2), "wm/sheet: cannot load bufio: %r\n"); raise "fail:load"; }
	if(zip == nil) { sys->fprint(sys->fildes(2), "wm/sheet: cannot load zip: %r\n"); raise "fail:load"; }
	if(xml == nil) { sys->fprint(sys->fildes(2), "wm/sheet: cannot load xml: %r\n"); raise "fail:load"; }
	if(math == nil) { sys->fprint(sys->fildes(2), "wm/sheet: cannot load math: %r\n"); raise "fail:load"; }

	zinit := zip->init();
	if(zinit != nil) { sys->fprint(sys->fildes(2), "wm/sheet: zip->init: %s\n", zinit); raise "fail:load"; }
	xinit := xml->init();
	if(xinit != nil) { sys->fprint(sys->fildes(2), "wm/sheet: xml->init: %s\n", xinit); raise "fail:load"; }
	sys->bind("#s", "/chan", Sys->MBEFORE);

	testmode := 0;
	servemode := 0;
	mountpt := "/mnt/sheet";
	path := "";
	if(argv != nil){
		for(a := tl argv; a != nil; a = tl a){
			arg := hd a;
			if(arg == "-t")
				testmode = 1;
			else if(arg == "-s")
				servemode = 1;
			else if(arg == "-m" && tl a != nil){
				a = tl a;
				mountpt = hd a;
			}else
				path = arg;
		}
	}
	if(path == "")
		path = find_default_ods();

	(book, err) := load_book(path);
	if(err != nil){
		sys->fprint(sys->fildes(2), "wm/sheet: %s\n", err);
		raise "fail:load";
	}
	recalc(book);

	if(testmode){
		run_selftest(book);
		return;
	}

	sys->pctl(Sys->NEWPGRP, nil);

	# Start on 'Inputs and quick look outputs' if present, else sheet 0
	cur_sheet := findsheet(book, "Inputs and quick look outputs");
	if(cur_sheet < 0)
		cur_sheet = 0;

	(srv, navc, reqc) := start_sheetfs(mountpt);
	if(navc == nil)
		navc = chan of ref Navop;
	if(reqc == nil)
		reqc = chan of ref FsReq;

	if(servemode){
		if(srv == nil){
			sys->fprint(sys->fildes(2), "wm/sheet: failed to mount %s\n", mountpt);
			raise "fail:mount";
		}
		for(;;) alt{
		op := <-navc =>
			handle_navop(book, op);
		req := <-reqc =>
			(book, cur_sheet, nil) = handle_fsreq(srv, book, cur_sheet, req);
		}
	}

	wmclient->init();
	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wm/sheet: cannot make draw context: %r\n");
		raise "fail:no context";
	}

	win := wmclient->window(ctxt, "Sheet - " + path, Wmclient->Appl);
	initcolors(win.display);
	win.reshape(Rect((0, 0), (1100, 720)));
	win.onscreen("place");
	win.startinput("kbd" :: "ptr" :: nil);

	editing := 0;
	editbuf := "";
	lastb := 0;
	drag_mode := 0; # 0=none, 1=vscroll, 2=hscroll

	redraw(win, book, cur_sheet, editing, editbuf, 1);

	for(;;) alt{
	op := <-navc =>
		handle_navop(book, op);

	req := <-reqc =>
		dirty := 0;
		(book, cur_sheet, dirty) = handle_fsreq(srv, book, cur_sheet, req);
		if(dirty)
			redraw(win, book, cur_sheet, editing, editbuf, 1);

	ctl := <-win.ctl or
	ctl = <-win.ctxt.ctl =>
		if(ctl == "exit"){
			shutdown_sheetfs(mountpt);
			exit;
		}
		oldimg := win.image;
		win.wmctl(ctl);
		if(win.image != nil && (win.image != oldimg || win.image.r.dx() != bufw || win.image.r.dy() != bufh))
			redraw(win, book, cur_sheet, editing, editbuf, 1);

	p := <-win.ctxt.ptr =>
		if(!win.pointer(*p) && win.image != nil){
			r := win.image.r;
			sh := book.sheets[cur_sheet];
			mx := p.xy.x;
			my := p.xy.y;
			grid_y0 := r.min.y + BAR_H;
			grid_y1 := r.max.y - TAB_H - SB_W;
			grid_x1 := r.max.x - SB_W;
			tab_y0  := r.max.y - TAB_H;

			# Coalesce rapid mouse-wheel bursts into a single redraw
			if(((p.buttons & 8) && !(lastb & 8)) || ((p.buttons & 16) && !(lastb & 16))){
				delta := 0;
				if(p.buttons & 8) delta -= 3;
				if(p.buttons & 16) delta += 3;
				lastb = p.buttons;
			DrainW:
				for(;;){
					alt{
					p2 := <-win.ctxt.ptr =>
						if((p2.buttons & 8) && !(lastb & 8)) delta -= 3;
						else if((p2.buttons & 16) && !(lastb & 16)) delta += 3;
						lastb = p2.buttons;
					* =>
						break DrainW;
					}
				}
				sh.top_r += delta;
				if(sh.top_r < 0) sh.top_r = 0;
				if(sh.top_r >= sh.nrows) sh.top_r = sh.nrows - 1;
				redraw(win, book, cur_sheet, editing, editbuf, 0);
			}else if(p.buttons & 1){
				# Capture scrollbar drag on initial button press
				if(!(lastb & 1)){
					if(my >= grid_y0 && my < grid_y1 && mx >= grid_x1)
						drag_mode = 1;
					else if(my >= grid_y1 && my < tab_y0 && mx < grid_x1)
						drag_mode = 2;
					else
						drag_mode = 0;
				}
				# Coalesce drag pointer events to the latest position
				released := 0;
			DrainD:
				for(;;){
					alt{
					p2 := <-win.ctxt.ptr =>
						if(p2.buttons & 1){
							mx = p2.xy.x;
							my = p2.xy.y;
							p = p2;
						}else{
							released = 1;
							lastb = p2.buttons;
							break DrainD;
						}
					* =>
						break DrainD;
					}
				}
				if(drag_mode == 1){
					frac := (my - grid_y0) * sh.nrows / (grid_y1 - grid_y0);
					if(frac < 0) frac = 0;
					if(frac >= sh.nrows) frac = sh.nrows - 1;
					if(frac != sh.top_r){
						sh.top_r = frac;
						redraw(win, book, cur_sheet, editing, editbuf, 0);
					}
				}else if(drag_mode == 2){
					frac := (mx - r.min.x) * sh.ncols / (grid_x1 - r.min.x);
					if(frac < 0) frac = 0;
					if(frac >= sh.ncols) frac = sh.ncols - 1;
					if(frac != sh.left_c){
						sh.left_c = frac;
						redraw(win, book, cur_sheet, editing, editbuf, 0);
					}
				}else if(!(lastb & 1)){
					if(my >= tab_y0){
						tx := r.min.x + 4;
						for(si := 0; si < len book.sheets; si++){
							tw := font.width(book.sheets[si].name) + 18;
							if(mx >= tx && mx < tx + tw){
								if(editing){
									commit_edit(book, cur_sheet, editbuf);
									editing = 0;
								}
								cur_sheet = si;
								redraw(win, book, cur_sheet, editing, editbuf, 1);
								break;
							}
							tx += tw + 3;
						}
					}else if(my >= grid_y0 + HDR_H && mx >= r.min.x + ROWH_W){
						if(editing){
							commit_edit(book, cur_sheet, editbuf);
							editing = 0;
						}
						nr := sh.top_r + (my - (grid_y0 + HDR_H)) / ROW_H;
						x := r.min.x + ROWH_W;
						nc := sh.left_c;
						while(nc < sh.ncols + 5){
							cw := colwidth(sh, nc);
							if(mx < x + cw)
								break;
							x += cw;
							nc++;
						}
						if(nr >= 0) sh.cur_r = nr;
						if(nc >= 0) sh.cur_c = nc;
						redraw(win, book, cur_sheet, editing, editbuf, 0);
					}else if(my < grid_y0){
						if(!editing){
							editing = 1;
							cl := getcell(book, cur_sheet, sh.cur_r, sh.cur_c);
							if(cl != nil && len cl.formula > 0){
								f := cl.formula;
								if(len f >= 4 && f[0:4] == "of:=")
									f = "=" + f[4:];
								editbuf = f;
							}else if(cl != nil)
								editbuf = cl.disp;
							else
								editbuf = "";
							redraw(win, book, cur_sheet, editing, editbuf, 0);
						}
					}
				}
				if(released)
					drag_mode = 0;
				else
					lastb = p.buttons;
			}else{
				drag_mode = 0;
				lastb = p.buttons;
			}
		}

	c := <-win.ctxt.kbd =>
		sh := book.sheets[cur_sheet];
		if(editing){
			force := 0;
			case c {
			'\n' or '\r' =>
				commit_edit(book, cur_sheet, editbuf);
				editing = 0;
				sh.cur_r++;
				ensure_visible(win, sh);
				force = 1;
			Keyboard->Esc =>
				editing = 0;
			'\b' =>
				if(len editbuf > 0)
					editbuf = editbuf[0:len editbuf - 1];
			Keyboard->APP | 'c' =>
				wmclient->snarfput(editbuf);
			Keyboard->APP | 'v' =>
				sn := trim(wmclient->snarfget());
				if(len sn > 0)
					editbuf += sn;
			* =>
				if(c >= 32 && c < 127)
					editbuf[len editbuf] = c;
			}
			redraw(win, book, cur_sheet, editing, editbuf, force);
		}else{
			force := 0;
			# Process this key plus any immediately queued navigation repeats
		KbdLoop:
			for(;;){
				case c {
				Keyboard->Up =>
					if(sh.cur_r > 0) sh.cur_r--;
					ensure_visible(win, sh);
				Keyboard->Down =>
					sh.cur_r++;
					ensure_visible(win, sh);
				Keyboard->Left =>
					if(sh.cur_c > 0) sh.cur_c--;
					ensure_visible(win, sh);
				Keyboard->Right or '\t' =>
					sh.cur_c++;
					ensure_visible(win, sh);
				Keyboard->Pgup =>
					sh.cur_r -= 15;
					if(sh.cur_r < 0) sh.cur_r = 0;
					ensure_visible(win, sh);
				Keyboard->Pgdown =>
					sh.cur_r += 15;
					ensure_visible(win, sh);
				Keyboard->Home =>
					sh.cur_r = 0; sh.cur_c = 0; sh.top_r = 0; sh.left_c = 0;
				'\n' or '\r' =>
					editing = 1;
					cl := getcell(book, cur_sheet, sh.cur_r, sh.cur_c);
					if(cl != nil && len cl.formula > 0){
						f := cl.formula;
						if(len f >= 4 && f[0:4] == "of:=")
							f = "=" + f[4:];
						editbuf = f;
					}else if(cl != nil)
						editbuf = cl.disp;
					else
						editbuf = "";
					break KbdLoop;
				Keyboard->Del or '\b' =>
					commit_edit(book, cur_sheet, "");
					force = 1;
					break KbdLoop;
				Keyboard->APP | 'c' =>
					cl := getcell(book, cur_sheet, sh.cur_r, sh.cur_c);
					if(cl != nil)
						wmclient->snarfput(format_plain(cl));
					break KbdLoop;
				Keyboard->APP | 'v' =>
					sn := trim(wmclient->snarfget());
					if(len sn > 0){
						commit_edit(book, cur_sheet, sn);
						force = 1;
					}
					break KbdLoop;
				* =>
					if(c >= 32 && c < 127){
						editing = 1;
						editbuf = "";
						editbuf[0] = c;
					}
					break KbdLoop;
				}
				alt{
				c = <-win.ctxt.kbd =>
					;
				* =>
					break KbdLoop;
				}
			}
			redraw(win, book, cur_sheet, editing, editbuf, force);
		}
	}
}
