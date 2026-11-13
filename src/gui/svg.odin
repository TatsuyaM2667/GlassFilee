package main

// A tiny SVG rasterizer for the bundled logo icons (assets/icons): no librsvg needed.
// Supports <path> (all commands, arcs included), <rect rx>, <circle>, <ellipse>,
// <polygon>, nested <g>, fill / fill-rule / opacity / fill-opacity (attributes or
// style=""), transform (matrix / translate / scale / rotate) and gradients (drawn with
// the average of their stop colors). Strokes are ignored: icons are filled shapes.
// Output: premultiplied ARGB, size×size, the viewBox centered and fitted.

import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"

@(private = "file") Mat :: [6]f32 // a b c d e f: x' = a*x + c*y + e, y' = b*x + d*y + f
@(private = "file") IDENT :: Mat{1, 0, 0, 1, 0, 0}

@(private = "file")
mul :: proc(m, n: Mat) -> Mat { // m then n... applied as m ∘ n (n first)
	return {
		m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
		m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
		m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
	}
}

@(private = "file")
apply :: proc(m: Mat, x, y: f32) -> [2]f32 {return {m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]}}

@(private = "file")
Edge :: struct {
	x0, y0, x1, y1: f32,
	dir:            i8,
}

@(private = "file")
Builder :: struct {
	m:          Mat,
	edges:      [dynamic]Edge,
	start, cur: [2]f32, // user space
	first:      [2]f32, // device space, start of subpath
	last:       [2]f32, // device space
	open:       bool,
}

@(private = "file")
line_to :: proc(b: ^Builder, p: [2]f32) { // p: user space
	q := apply(b.m, p.x, p.y)
	if b.last.y != q.y do append(&b.edges, Edge{b.last.x, b.last.y, q.x, q.y, 1 if q.y > b.last.y else -1})
	b.last = q
	b.cur = p
	b.open = true
}

@(private = "file")
move_to :: proc(b: ^Builder, p: [2]f32) {
	close(b)
	b.start, b.cur = p, p
	b.first = apply(b.m, p.x, p.y)
	b.last = b.first
}

@(private = "file")
close :: proc(b: ^Builder) {
	if b.open && b.last != b.first {
		append(&b.edges, Edge{b.last.x, b.last.y, b.first.x, b.first.y, 1 if b.first.y > b.last.y else -1})
	}
	b.open = false
	b.last = b.first
	b.cur = b.start
}

@(private = "file")
segs :: proc(b: ^Builder, pts: ..[2]f32) -> int { // curve flattening steps from its device-space size
	l: f32
	prev := apply(b.m, b.cur.x, b.cur.y)
	for p in pts {
		q := apply(b.m, p.x, p.y)
		l += math.hypot(q.x - prev.x, q.y - prev.y)
		prev = q
	}
	return clamp(int(l / 2), 3, 64)
}

@(private = "file")
cubic :: proc(b: ^Builder, c1, c2, p: [2]f32) {
	p0 := b.cur
	n := segs(b, c1, c2, p)
	for i in 1 ..= n {
		t := f32(i) / f32(n)
		u := 1 - t
		line_to(b, u * u * u * p0 + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * p)
	}
}

@(private = "file")
quad :: proc(b: ^Builder, c, p: [2]f32) {
	p0 := b.cur
	n := segs(b, c, p)
	for i in 1 ..= n {
		t := f32(i) / f32(n)
		u := 1 - t
		line_to(b, u * u * p0 + 2 * u * t * c + t * t * p)
	}
}

// SVG arc, endpoint form → center form (SVG spec F.6.5), then flattened.
@(private = "file")
arc :: proc(b: ^Builder, rx_, ry_, rot: f32, large, sweep: bool, p: [2]f32) {
	p0 := b.cur
	rx, ry := abs(rx_), abs(ry_)
	if rx == 0 || ry == 0 || p0 == p {
		line_to(b, p)
		return
	}
	phi := rot * math.PI / 180
	cs, sn := math.cos(phi), math.sin(phi)
	dx, dy := (p0.x - p.x) / 2, (p0.y - p.y) / 2
	x1 := cs * dx + sn * dy
	y1 := -sn * dx + cs * dy
	lam := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lam > 1 {
		s := math.sqrt(lam)
		rx, ry = rx * s, ry * s
	}
	num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	den := rx * rx * y1 * y1 + ry * ry * x1 * x1
	k := math.sqrt(max(num / den, 0))
	if large == sweep do k = -k
	cxp, cyp := k * rx * y1 / ry, -k * ry * x1 / rx
	cx := cs * cxp - sn * cyp + (p0.x + p.x) / 2
	cy := sn * cxp + cs * cyp + (p0.y + p.y) / 2
	ang :: proc(ux, uy, vx, vy: f32) -> f32 {
		a := math.atan2(vy, vx) - math.atan2(uy, ux)
		return a
	}
	t1 := ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
	dt := ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
	if !sweep && dt > 0 do dt -= 2 * math.PI
	if sweep && dt < 0 do dt += 2 * math.PI
	sc := math.sqrt(abs(b.m[0] * b.m[3] - b.m[1] * b.m[2]))
	n := clamp(int(abs(dt) * max(rx, ry) * sc / 2), 4, 96)
	for i in 1 ..= n {
		t := t1 + dt * f32(i) / f32(n)
		x, y := rx * math.cos(t), ry * math.sin(t)
		line_to(b, {cs * x - sn * y + cx, sn * x + cs * y + cy})
	}
	b.cur = p
}

// Path data tokenizer: numbers may run together ("1.5.5", "-1-2", "1e-3"); arc flags are single digits.
@(private = "file")
Lexer :: struct {
	s: string,
	i: int,
}

@(private = "file")
skip :: proc(l: ^Lexer) {
	for l.i < len(l.s) && (l.s[l.i] == ' ' || l.s[l.i] == ',' || l.s[l.i] == '\n' || l.s[l.i] == '\t' || l.s[l.i] == '\r') do l.i += 1
}

@(private = "file")
num :: proc(l: ^Lexer) -> (f: f32, ok: bool) {
	skip(l)
	start := l.i
	if l.i < len(l.s) && (l.s[l.i] == '-' || l.s[l.i] == '+') do l.i += 1
	dot := false
	for l.i < len(l.s) {
		c := l.s[l.i]
		if c >= '0' && c <= '9' {
			l.i += 1
		} else if c == '.' && !dot {
			dot = true
			l.i += 1
		} else if (c == 'e' || c == 'E') && l.i + 1 < len(l.s) && l.s[l.i + 1] != 'x' {
			l.i += 1
			if l.i < len(l.s) && (l.s[l.i] == '-' || l.s[l.i] == '+') do l.i += 1
		} else do break
	}
	if l.i == start do return 0, false
	v, vok := strconv.parse_f32(l.s[start:l.i])
	return v, vok
}

@(private = "file")
flag :: proc(l: ^Lexer) -> bool {
	skip(l)
	if l.i < len(l.s) && (l.s[l.i] == '0' || l.s[l.i] == '1') {
		l.i += 1
		return l.s[l.i - 1] == '1'
	}
	return false
}

@(private = "file")
path_data :: proc(b: ^Builder, d: string) {
	l := Lexer{s = d}
	cmd: u8
	ctrl: [2]f32 // last control point (S / T reflection)
	prev: u8
	for {
		skip(&l)
		if l.i >= len(l.s) do break
		c := l.s[l.i]
		if (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') && c != 'e' && c != 'E' {
			cmd = c
			l.i += 1
			if c == 'z' || c == 'Z' {
				close(b)
				prev = cmd
				continue
			}
		} else if cmd == 0 || cmd == 'z' || cmd == 'Z' {
			return // malformed
		}
		rel := cmd >= 'a'
		o := b.cur if rel else [2]f32{}
		ok: bool
		switch cmd | 0x20 { // lowercase
		case 'm':
			x, _ := num(&l)
			y: f32
			y, ok = num(&l)
			if !ok do return
			move_to(b, o + {x, y})
			cmd = 'l' if rel else 'L' // further pairs are lines
		case 'l':
			x, _ := num(&l)
			y: f32
			y, ok = num(&l)
			if !ok do return
			line_to(b, o + {x, y})
		case 'h':
			x: f32
			x, ok = num(&l)
			if !ok do return
			line_to(b, {o.x + x, b.cur.y})
		case 'v':
			y: f32
			y, ok = num(&l)
			if !ok do return
			line_to(b, {b.cur.x, o.y + y})
		case 'c':
			v: [6]f32
			for &e in v {e, ok = num(&l); if !ok do return}
			c1, c2 := o + {v[0], v[1]}, o + {v[2], v[3]}
			cubic(b, c1, c2, o + {v[4], v[5]})
			ctrl = c2
		case 's':
			v: [4]f32
			for &e in v {e, ok = num(&l); if !ok do return}
			c1 := 2 * b.cur - ctrl if prev | 0x20 == 'c' || prev | 0x20 == 's' else b.cur
			c2 := o + {v[0], v[1]}
			cubic(b, c1, c2, o + {v[2], v[3]})
			ctrl = c2
		case 'q':
			v: [4]f32
			for &e in v {e, ok = num(&l); if !ok do return}
			c1 := o + {v[0], v[1]}
			quad(b, c1, o + {v[2], v[3]})
			ctrl = c1
		case 't':
			v: [2]f32
			for &e in v {e, ok = num(&l); if !ok do return}
			c1 := 2 * b.cur - ctrl if prev | 0x20 == 'q' || prev | 0x20 == 't' else b.cur
			quad(b, c1, o + {v[0], v[1]})
			ctrl = c1
		case 'a':
			rx, _ := num(&l)
			ry, _ := num(&l)
			rot, _ := num(&l)
			large := flag(&l)
			sweep := flag(&l)
			x, _ := num(&l)
			y: f32
			y, ok = num(&l)
			if !ok do return
			arc(b, rx, ry, rot, large, sweep, o + {x, y})
		case:
			return
		}
		prev = cmd
	}
	close(b)
}

@(private = "file")
Xing :: struct {
	x: f32,
	d: i8,
}

// Fill the collected edges into acc (coverage per pixel), 8 sub-scanlines, exact horizontal coverage.
@(private = "file")
fill_edges :: proc(edges: []Edge, size: int, evenodd: bool, cov: []f32) {
	SS :: 8
	xs := make([dynamic]Xing, context.temp_allocator)
	for py in 0 ..< size {
		for s in 0 ..< SS {
			sy := f32(py) + (f32(s) + 0.5) / SS
			clear(&xs)
			for e in edges {
				lo, hi := min(e.y0, e.y1), max(e.y0, e.y1)
				if sy < lo || sy >= hi do continue
				append(&xs, Xing{e.x0 + (sy - e.y0) * (e.x1 - e.x0) / (e.y1 - e.y0), e.dir})
			}
			if len(xs) < 2 do continue
			slice.sort_by(xs[:], proc(a, b: Xing) -> bool {return a.x < b.x})
			wind := 0
			for i in 0 ..< len(xs) - 1 {
				wind += int(xs[i].d)
				inside := (wind & 1) != 0 if evenodd else wind != 0
				if !inside do continue
				x0, x1 := clamp(xs[i].x, 0, f32(size)), clamp(xs[i + 1].x, 0, f32(size))
				if x1 <= x0 do continue
				row := cov[py * size:][:size]
				ix0, ix1 := int(x0), int(x1)
				if ix0 == ix1 {
					if ix0 < size do row[ix0] += (x1 - x0) / SS
					continue
				}
				row[ix0] += (f32(ix0 + 1) - x0) / SS
				for x in ix0 + 1 ..< ix1 do row[x] += 1.0 / SS
				if ix1 < size do row[ix1] += (x1 - f32(ix1)) / SS
			}
		}
	}
}

// ---------------------------------------------------------------------------
// XML (just enough for icon files)

@(private = "file")
attr :: proc(tag, name: string) -> (string, bool) {
	i := 0
	for {
		j := strings.index(tag[i:], name)
		if j < 0 do return "", false
		k := i + j
		i = k + len(name)
		// whole attribute name followed by =
		if k > 0 && tag[k - 1] != ' ' && tag[k - 1] != '\n' && tag[k - 1] != '\t' do continue
		rest := strings.trim_left_space(tag[i:])
		if !strings.has_prefix(rest, "=") do continue
		rest = strings.trim_left_space(rest[1:])
		if len(rest) == 0 do return "", false
		q := rest[0]
		if q != '"' && q != '\'' do return "", false
		end := strings.index_byte(rest[1:], q)
		if end < 0 do return "", false
		return rest[1:][:end], true
	}
}

// A property from the attribute or from style="name:value".
@(private = "file")
prop :: proc(tag, name: string) -> (string, bool) {
	if st, ok := attr(tag, "style"); ok {
		for decl in strings.split(st, ";", context.temp_allocator) {
			k, _, v := strings.partition(decl, ":")
			if strings.trim_space(k) == name do return strings.trim_space(v), true
		}
	}
	return attr(tag, name)
}

@(private = "file")
nums :: proc(s: string) -> [dynamic]f32 {
	out := make([dynamic]f32, context.temp_allocator)
	l := Lexer{s = s}
	for {
		v, ok := num(&l)
		if !ok do break
		append(&out, v)
	}
	return out
}

@(private = "file")
transform :: proc(s: string) -> Mat {
	m := IDENT
	rest := s
	for {
		open := strings.index_byte(rest, '(')
		if open < 0 do break
		shut := strings.index_byte(rest, ')')
		if shut < open do break
		name := strings.trim_space(strings.trim_left(rest[:open], ", "))
		v := nums(rest[open + 1:shut])
		t := IDENT
		switch name {
		case "matrix":    if len(v) == 6 do t = {v[0], v[1], v[2], v[3], v[4], v[5]}
		case "translate": if len(v) >= 1 do t = {1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0}
		case "scale":     if len(v) >= 1 do t = {v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0}
		case "rotate":
			if len(v) >= 1 {
				a := v[0] * math.PI / 180
				t = {math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0}
				if len(v) == 3 do t = mul(mul(Mat{1, 0, 0, 1, v[1], v[2]}, t), Mat{1, 0, 0, 1, -v[1], -v[2]})
			}
		}
		m = mul(m, t)
		rest = rest[shut + 1:]
	}
	return m
}

// Color of a fill value; gradients (url(#id)) use the average of their stops.
@(private = "file")
parse_color :: proc(v: string, grads: map[string]u32) -> (rgb: u32, ok: bool) {
	v := strings.trim_space(v)
	switch {
	case v == "none" || v == "transparent": return 0, false
	case strings.has_prefix(v, "url("):
		id := strings.trim(v[4:], "#)'\" ")
		c, found := grads[id]
		return c, found
	case strings.has_prefix(v, "#"):
		h := v[1:]
		if len(h) == 3 do h = strings.concatenate({h[0:1], h[0:1], h[1:2], h[1:2], h[2:3], h[2:3]}, context.temp_allocator)
		if len(h) < 6 do return 0, false
		n, nok := strconv.parse_uint(h[:6], 16)
		return u32(n), nok
	case strings.has_prefix(v, "rgb("):
		c := nums(v[4:])
		if len(c) < 3 do return 0, false
		return u32(clamp(c[0], 0, 255)) << 16 | u32(clamp(c[1], 0, 255)) << 8 | u32(clamp(c[2], 0, 255)), true
	case v == "currentColor": return 0, true
	}
	switch v {
	case "black":         return 0x000000, true
	case "white":         return 0xffffff, true
	case "red":           return 0xff0000, true
	case "gray", "grey":  return 0x808080, true
	}
	return 0, false
}

@(private = "file")
Style :: struct {
	m:       Mat,
	fill:    string,
	evenodd: bool,
	opacity: f32,
}

// Renders an SVG document into a size×size premultiplied ARGB image.
svg_rasterize :: proc(svg: string, size: int, allocator := context.allocator) -> []u32 {
	img := make([]u32, size * size, allocator)
	// gradients: id → average stop color (following href to another gradient)
	grads := make(map[string]u32, 8, context.temp_allocator)
	hrefs := make(map[string]string, 8, context.temp_allocator)
	sums := make(map[string][4]f32, 8, context.temp_allocator) // rgb sums + stop count
	{
		rest := svg
		cur := ""
		for {
			i := strings.index_byte(rest, '<')
			if i < 0 do break
			j := strings.index_byte(rest[i:], '>')
			if j < 0 do break
			tag := rest[i + 1:][:j - 1]
			rest = rest[i + j + 1:]
			if strings.has_prefix(tag, "linearGradient") || strings.has_prefix(tag, "radialGradient") {
				cur, _ = attr(tag, "id")
				if h, ok := attr(tag, "href"); ok do hrefs[cur] = strings.trim_left(h, "#")
				else if h2, ok2 := attr(tag, "xlink:href"); ok2 do hrefs[cur] = strings.trim_left(h2, "#")
			} else if strings.has_prefix(tag, "stop") && cur != "" {
				if sc, ok := prop(tag, "stop-color"); ok {
					if c, cok := parse_color(sc, grads); cok {
						sum := sums[cur]
						sum += {f32(c >> 16 & 255), f32(c >> 8 & 255), f32(c & 255), 1}
						sums[cur] = sum
					}
				}
			}
		}
		for id, v in sums do grads[id] = u32(v[0] / v[3]) << 16 | u32(v[1] / v[3]) << 8 | u32(v[2] / v[3])
		for id, target in hrefs do if id not_in grads {if c, ok := grads[target]; ok do grads[id] = c}
	}

	stack := make([dynamic]Style, context.temp_allocator)
	append(&stack, Style{m = IDENT, fill = "#000", opacity = 1})
	cov := make([]f32, size * size, context.temp_allocator)
	b := Builder{edges = make([dynamic]Edge, context.temp_allocator)}
	skipping := 0 // inside <defs>, <clipPath>, <mask>…
	rest := svg
	for {
		i := strings.index_byte(rest, '<')
		if i < 0 do break
		j := strings.index_byte(rest[i:], '>')
		if j < 0 do break
		raw := rest[i + 1:][:j - 1]
		rest = rest[i + j + 1:]
		if strings.has_prefix(raw, "?") || strings.has_prefix(raw, "!") do continue
		closing := strings.has_prefix(raw, "/")
		selfclose := strings.has_suffix(raw, "/")
		tag := strings.trim(raw, "/ \n\t")
		name := tag
		if sp := strings.index_any(tag, " \n\t"); sp >= 0 do name = tag[:sp]
		switch name {
		case "defs", "clipPath", "mask", "pattern", "symbol", "linearGradient", "radialGradient", "filter", "style", "title":
			if closing do skipping -= 1
			else if !selfclose do skipping += 1
			continue
		}
		if skipping > 0 do continue
		if closing {
			if (name == "g" || name == "svg" || name == "a") && len(stack) > 1 do pop(&stack)
			continue
		}
		top := stack[len(stack) - 1]
		st := top
		if v, ok := prop(tag, "fill"); ok do st.fill = v
		if v, ok := prop(tag, "fill-rule"); ok do st.evenodd = v == "evenodd"
		if v, ok := prop(tag, "opacity"); ok {o, _ := strconv.parse_f32(v); st.opacity *= o}
		if v, ok := prop(tag, "fill-opacity"); ok {o, _ := strconv.parse_f32(v); st.opacity *= o}
		if v, ok := attr(tag, "transform"); ok do st.m = mul(top.m, transform(v))
		if name == "svg" {
			vb: [dynamic]f32
			if v, ok := attr(tag, "viewBox"); ok do vb = nums(v)
			if len(vb) != 4 {
				w, _ := attr(tag, "width")
				h, _ := attr(tag, "height")
				ww, _ := strconv.parse_f32(strings.trim_right(w, "px"))
				hh, _ := strconv.parse_f32(strings.trim_right(h, "px"))
				vb = make([dynamic]f32, context.temp_allocator)
				append(&vb, 0, 0, ww if ww > 0 else 24, hh if hh > 0 else 24)
			}
			k := f32(size) / max(vb[2], vb[3])
			ox := (f32(size) - vb[2] * k) / 2 - vb[0] * k
			oy := (f32(size) - vb[3] * k) / 2 - vb[1] * k
			st.m = mul(Mat{k, 0, 0, k, ox, oy}, st.m)
			if !selfclose do append(&stack, st)
			continue
		}
		if name == "g" || name == "a" {
			if !selfclose do append(&stack, st)
			continue
		}
		clear(&b.edges)
		b.m = st.m
		b.open = false
		switch name {
		case "path":
			d, _ := attr(tag, "d")
			path_data(&b, d)
		case "rect":
			v := [6]f32{}
			for k, n in ([]string{"x", "y", "width", "height", "rx", "ry"}) {
				if s, ok := attr(tag, k); ok do v[n], _ = strconv.parse_f32(s)
			}
			x, y, w, h, rx, ry := v[0], v[1], v[2], v[3], v[4], v[5]
			if rx == 0 do rx = ry
			if ry == 0 do ry = rx
			rx, ry = min(rx, w / 2), min(ry, h / 2)
			if rx > 0 {
				move_to(&b, {x + rx, y})
				line_to(&b, {x + w - rx, y})
				arc(&b, rx, ry, 0, false, true, {x + w, y + ry})
				line_to(&b, {x + w, y + h - ry})
				arc(&b, rx, ry, 0, false, true, {x + w - rx, y + h})
				line_to(&b, {x + rx, y + h})
				arc(&b, rx, ry, 0, false, true, {x, y + h - ry})
				line_to(&b, {x, y + ry})
				arc(&b, rx, ry, 0, false, true, {x + rx, y})
			} else {
				move_to(&b, {x, y})
				line_to(&b, {x + w, y})
				line_to(&b, {x + w, y + h})
				line_to(&b, {x, y + h})
			}
			close(&b)
		case "circle", "ellipse":
			v := [4]f32{}
			for k, n in ([]string{"cx", "cy", "rx", "ry"}) {
				if s, ok := attr(tag, k); ok do v[n], _ = strconv.parse_f32(s)
			}
			if s, ok := attr(tag, "r"); ok {r, _ := strconv.parse_f32(s); v[2], v[3] = r, r}
			cx, cy, rx, ry := v[0], v[1], v[2], v[3]
			move_to(&b, {cx + rx, cy})
			arc(&b, rx, ry, 0, false, true, {cx - rx, cy})
			arc(&b, rx, ry, 0, false, true, {cx + rx, cy})
			close(&b)
		case "polygon":
			pts, _ := attr(tag, "points")
			v := nums(pts)
			for k := 0; k + 1 < len(v); k += 2 {
				if k == 0 do move_to(&b, {v[0], v[1]})
				else do line_to(&b, {v[k], v[k + 1]})
			}
			close(&b)
		case:
			continue
		}
		rgb, ok := parse_color(st.fill, grads)
		if !ok || len(b.edges) == 0 do continue
		slice.fill(cov, 0)
		fill_edges(b.edges[:], size, st.evenodd, cov)
		// composite "over" into the image
		for c, k in cov {
			if c <= 0 do continue
			a := u32(clamp(c, 0, 1) * clamp(st.opacity, 0, 1) * 255 + 0.5)
			if a == 0 do continue
			src := a << 24 | ((rgb >> 16 & 255) * a / 255) << 16 | ((rgb >> 8 & 255) * a / 255) << 8 | (rgb & 255) * a / 255
			d := img[k]
			inv := 255 - a
			img[k] = src + ((d >> 24 & 255) * inv / 255) << 24 + ((d >> 16 & 255) * inv / 255) << 16 + ((d >> 8 & 255) * inv / 255) << 8 + (d & 255) * inv / 255
		}
	}
	return img
}
