package main

// Software renderer into a premultiplied ARGB8888 buffer (the Wayland shm surface).

import "core:math"

Color :: [4]u8 // r, g, b, a (straight alpha)

Rect :: struct {
	x, y, w, h: f32,
}

Canvas :: struct {
	px:     [^]u32,
	w, h:   i32,
	stride: i32, // in pixels
	clip:   [4]i32, // x0, y0, x1, y1
}

cv: Canvas
draw_alpha: u32 = 255 // global opacity for fade animations

hex :: proc(v: u32, a: u8 = 255) -> Color {
	return {u8(v >> 16), u8(v >> 8), u8(v), a}
}

with_alpha :: proc(c: Color, a: u8) -> Color {
	return {c.r, c.g, c.b, a}
}

contains :: proc(r: Rect, x, y: f32) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

shrink :: proc(r: Rect, d: f32) -> Rect {
	return {r.x + d, r.y + d, r.w - 2 * d, r.h - 2 * d}
}

set_clip :: proc(r: Rect) {
	cv.clip = {
		max(i32(math.floor(r.x)), 0),
		max(i32(math.floor(r.y)), 0),
		min(i32(math.ceil(r.x + r.w)), cv.w),
		min(i32(math.ceil(r.y + r.h)), cv.h),
	}
}

reset_clip :: proc() {
	cv.clip = {0, 0, cv.w, cv.h}
}

clear_canvas :: proc(c: Color) {
	a := u32(c.a)
	p := a << 24 | (u32(c.r) * a / 255) << 16 | (u32(c.g) * a / 255) << 8 | u32(c.b) * a / 255
	for y in 0 ..< cv.h {
		row := cv.px[y * cv.stride:][:cv.w]
		for &v in row do v = p
	}
}

blend :: #force_inline proc(p: ^u32, c: Color, cov: u32) {
	a := (u32(c.a) * cov * draw_alpha + 32512) / 65025
	if a == 0 do return
	inv := 255 - a
	d := p^
	r := (u32(c.r) * a + ((d >> 16) & 0xff) * inv + 127) / 255
	g := (u32(c.g) * a + ((d >> 8) & 0xff) * inv + 127) / 255
	b := (u32(c.b) * a + (d & 0xff) * inv + 127) / 255
	oa := a + ((d >> 24) * inv + 127) / 255
	p^ = oa << 24 | r << 16 | g << 8 | b
}

fill :: proc(r: Rect, c: Color) {
	x0 := max(i32(math.round(r.x)), cv.clip[0])
	y0 := max(i32(math.round(r.y)), cv.clip[1])
	x1 := min(i32(math.round(r.x + r.w)), cv.clip[2])
	y1 := min(i32(math.round(r.y + r.h)), cv.clip[3])
	for y in y0 ..< y1 {
		for x in x0 ..< x1 do blend(&cv.px[y * cv.stride + x], c, 255)
	}
}

// Anti-aliased rounded rectangle; ring > 0 draws only a border of that width.
rrect :: proc(r: Rect, rad: f32, c: Color, ring: f32 = 0) {
	if r.w <= 0 || r.h <= 0 do return
	rad := min(rad, r.w / 2, r.h / 2)
	x0 := max(i32(math.floor(r.x)), cv.clip[0])
	y0 := max(i32(math.floor(r.y)), cv.clip[1])
	x1 := min(i32(math.ceil(r.x + r.w)), cv.clip[2])
	y1 := min(i32(math.ceil(r.y + r.h)), cv.clip[3])
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	hx, hy := r.w / 2 - rad, r.h / 2 - rad
	edge_px :: #force_inline proc(x, y: i32, cx, hx, qy, rad, ring: f32, c: Color) {
		qx := abs(f32(x) + 0.5 - cx) - hx
		d: f32
		if qx > 0 && qy > 0 {
			d = math.sqrt(qx * qx + qy * qy) - rad
		} else {
			d = max(qx, qy) - rad
		}
		cov := clamp(0.5 - d, 0, 1)
		if ring > 0 do cov -= clamp(0.5 - d - ring, 0, 1)
		if cov > 0 do blend(&cv.px[y * cv.stride + x], c, u32(cov * 255))
	}
	for y in y0 ..< y1 {
		qy := abs(f32(y) + 0.5 - cy) - hy
		// rows away from the corners: only the left/right edges need anti-aliasing,
		// the middle is solid (filled) or, for a ring, empty (skipped)
		if qy < -0.5 && qy - rad < -(ring + 1) {
			m := min(0, rad - ring - 1)
			ix0 := max(i32(math.ceil(cx - (hx + m) - 0.5)), x0)
			ix1 := min(i32(math.floor(cx + (hx + m) - 0.5)) + 1, x1)
			if ix1 > ix0 {
				for x in x0 ..< ix0 do edge_px(x, y, cx, hx, qy, rad, ring, c)
				if ring <= 0 {
					row := cv.px[y * cv.stride:]
					for x in ix0 ..< ix1 do blend(&row[x], c, 255)
				}
				for x in ix1 ..< x1 do edge_px(x, y, cx, hx, qy, rad, ring, c)
				continue
			}
		}
		for x in x0 ..< x1 do edge_px(x, y, cx, hx, qy, rad, ring, c)
	}
}

// Draws text with its baseline at y; returns the advance width.
text :: proc(x, y: f32, s: string, size: i32, c: Color, bold := false) -> f32 {
	pen := i32(math.round(x))
	by := i32(math.round(y))
	for r in s {
		g := get_glyph(r, size, bold)
		gx, gy := pen + g.left, by - g.top
		for j in 0 ..< g.h {
			py := gy + j
			if py < cv.clip[1] || py >= cv.clip[3] do continue
			for i in 0 ..< g.w {
				px := gx + i
				if px < cv.clip[0] || px >= cv.clip[2] do continue
				if m := g.px[j * g.w + i]; m != 0 do blend(&cv.px[py * cv.stride + px], c, u32(m))
			}
		}
		pen += g.adv
	}
	return f32(pen) - x
}

// Baseline that vertically centers a line of `size` px text inside r.
baseline :: proc(r: Rect, size: i32) -> f32 {
	asc, desc := font_metrics(size)
	return math.round(r.y + (r.h + f32(asc - desc)) / 2)
}

// Centered single glyph (icons from the symbol font).
glyph_center :: proc(r: Rect, g: rune, size: i32, c: Color) {
	gl := get_glyph(g, size)
	x := r.x + (r.w - f32(gl.w)) / 2 - f32(gl.left)
	y := r.y + (r.h - f32(gl.h)) / 2 + f32(gl.top)
	buf: [4]u8
	n := encode_rune(buf[:], g)
	text(x, y, string(buf[:n]), size, c)
}

encode_rune :: proc(buf: []u8, r: rune) -> int {
	switch {
	case r < 0x80:
		buf[0] = u8(r); return 1
	case r < 0x800:
		buf[0] = u8(0xC0 | r >> 6); buf[1] = u8(0x80 | r & 0x3F); return 2
	case r < 0x10000:
		buf[0] = u8(0xE0 | r >> 12); buf[1] = u8(0x80 | (r >> 6) & 0x3F); buf[2] = u8(0x80 | r & 0x3F); return 3
	}
	buf[0] = u8(0xF0 | r >> 18); buf[1] = u8(0x80 | (r >> 12) & 0x3F)
	buf[2] = u8(0x80 | (r >> 6) & 0x3F); buf[3] = u8(0x80 | r & 0x3F)
	return 4
}

// ---------------------------------------------------------------------------
// Adwaita-style file icons, drawn procedurally (no icon theme / SVG loader needed)

// tint: 0 = Adwaita blue, 1..7 = TAG_COLORS (the folder itself takes the color)
folder_icon :: proc(x, y, s: f32, emblem: rune = 0, tint: u8 = 0) {
	base: u32 = 0x62a0ea if tint == 0 else TAG_COLORS[tint]
	shade :: proc(c: u32, f: f32, a: u8 = 255) -> Color {
		return {u8(f32((c >> 16) & 255) * f), u8(f32((c >> 8) & 255) * f), u8(f32(c & 255) * f), a}
	}
	back, mid := shade(base, 0.62), shade(base, 0.8)
	rrect({x + 0.06 * s, y + 0.12 * s, 0.38 * s, 0.14 * s}, 0.05 * s, back)
	rrect({x + 0.06 * s, y + 0.17 * s, 0.88 * s, 0.68 * s}, 0.07 * s, back)
	rrect({x + 0.12 * s, y + 0.24 * s, 0.76 * s, 0.30 * s}, 0.03 * s, hex(0xdeddda))
	rrect({x + 0.06 * s, y + 0.31 * s, 0.88 * s, 0.56 * s}, 0.07 * s, mid)
	rrect({x + 0.06 * s, y + 0.31 * s, 0.88 * s, 0.50 * s}, 0.07 * s, hex(base))
	if emblem != 0 && s >= 32 {
		glyph_center({x + 0.06 * s, y + 0.34 * s, 0.88 * s, 0.48 * s}, emblem, i32(0.24 * s), shade(base, 0.45, 220))
	}
}

Kind :: enum u8 {
	Generic, Text, Code, Image, Video, Audio, Archive, Pdf, Document, Exec,
}

KIND_COLOR := [Kind]u32 {
	.Generic  = 0x9a9996,
	.Text     = 0x77767b,
	.Code     = 0x3584e4,
	.Image    = 0x9141ac,
	.Video    = 0xe01b24,
	.Audio    = 0xe66100,
	.Archive  = 0x865e3c,
	.Pdf      = 0xc01c28,
	.Document = 0x1c71d8,
	.Exec     = 0x26a269,
}

KIND_GLYPH := [Kind]rune {
	.Generic  = 0xf016, // fa-file-o
	.Text     = 0xf0f6, // fa-file-text-o
	.Code     = 0xf121, // fa-code
	.Image    = 0xf03e, // fa-picture-o
	.Video    = 0xf008, // fa-film
	.Audio    = 0xf001, // fa-music
	.Archive  = 0xf1c6, // fa-file-archive-o
	.Pdf      = 0xf1c1, // fa-file-pdf-o
	.Document = 0xf15c, // fa-file-text
	.Exec     = 0xf120, // fa-terminal
}

// name (optional) picks a programming-language logo by extension / file name.
file_icon :: proc(x, y, s: f32, kind: Kind, name := "") {
	page := Rect{x + 0.18 * s, y + 0.06 * s, 0.64 * s, 0.86 * s}
	rrect(page, 0.06 * s, hex(0xf6f5f4, 240))
	rrect({page.x + page.w - 0.2 * s, page.y, 0.2 * s, 0.2 * s}, 0.04 * s, hex(0xc0bfbc))
	band := Rect{page.x, page.y + page.h * 0.52, page.w, page.h * 0.3}
	if name != "" {
		if l, ok := lang_of(name); ok {
			// small (list rows) gets a bigger share of the page so the logo stays readable
			draw_lang({page.x, page.y + page.h * 0.25, page.w, page.h * 0.65}, l, (0.42 if s >= 32 else 0.5) * s)
			return
		}
	}
	if s >= 32 {
		glyph_center(band, KIND_GLYPH[kind], i32(0.26 * s), hex(KIND_COLOR[kind]))
	} else {
		rrect(shrink(band, 0.08 * s), 0.03 * s, hex(KIND_COLOR[kind]))
	}
}

// Anti-aliased ring sector between radii r0..r1 and angles a0..a1 (radians, clockwise from +x).
ring_seg :: proc(cx, cy, r0, r1, a0, a1: f32, c: Color) {
	x0 := max(i32(cx - r1 - 1), cv.clip[0])
	y0 := max(i32(cy - r1 - 1), cv.clip[1])
	x1 := min(i32(cx + r1 + 2), cv.clip[2])
	y1 := min(i32(cy + r1 + 2), cv.clip[3])
	full := a1 - a0 >= 2 * math.PI - 0.001
	mid := (a0 + a1) / 2
	half := (a1 - a0) / 2
	for y in y0 ..< y1 {
		dy := f32(y) + 0.5 - cy
		for x in x0 ..< x1 {
			dx := f32(x) + 0.5 - cx
			d := math.sqrt(dx * dx + dy * dy)
			cov := clamp(d - r0 + 0.5, 0, 1) * clamp(r1 - d + 0.5, 0, 1)
			if cov <= 0 do continue
			if !full {
				// angular distance to the sector, converted to px along the arc for AA
				da := math.atan2(dy, dx) - mid
				for da > math.PI do da -= 2 * math.PI
				for da < -math.PI do da += 2 * math.PI
				cov *= clamp((half - abs(da)) * d + 0.5, 0, 1)
				if cov <= 0 do continue
			}
			blend(&cv.px[y * cv.stride + x], c, u32(cov * 255))
		}
	}
}

// Bilinear resize into a new premultiplied image (for caching scaled pictures).
scale_image :: proc(src: []u32, sw, sh, w, h: int, allocator := context.allocator) -> []u32 {
	out := make([]u32, w * h, allocator)
	sx, sy := f32(sw) / f32(w), f32(sh) / f32(h)
	for y in 0 ..< h {
		fy := clamp((f32(y) + 0.5) * sy - 0.5, 0, f32(sh - 1))
		iy := int(fy)
		iy1 := min(iy + 1, sh - 1)
		wy := u32((fy - f32(iy)) * 256)
		for x in 0 ..< w {
			fx := clamp((f32(x) + 0.5) * sx - 0.5, 0, f32(sw - 1))
			ix := int(fx)
			ix1 := min(ix + 1, sw - 1)
			wx := u32((fx - f32(ix)) * 256)
			a, b := src[iy * sw + ix], src[iy * sw + ix1]
			c, d := src[iy1 * sw + ix], src[iy1 * sw + ix1]
			s: u32
			for sh8 := u32(0); sh8 < 32; sh8 += 8 {
				top := ((a >> sh8) & 255) * (256 - wx) + ((b >> sh8) & 255) * wx
				bot := ((c >> sh8) & 255) * (256 - wx) + ((d >> sh8) & 255) * wx
				s |= ((top * (256 - wy) + bot * wy) >> 16) << sh8
			}
			out[y * w + x] = s
		}
	}
	return out
}

// Blends a premultiplied image at (x, y) without scaling (cheap: no sampling).
blit_image :: proc(x, y: f32, img: []u32, w, h: int) {
	ox, oy := i32(math.round(x)), i32(math.round(y))
	x0 := max(ox, cv.clip[0])
	y0 := max(oy, cv.clip[1])
	x1 := min(ox + i32(w), cv.clip[2])
	y1 := min(oy + i32(h), cv.clip[3])
	for py in y0 ..< y1 {
		src := img[int(py - oy) * w:]
		dst := cv.px[py * cv.stride:]
		for px_ in x0 ..< x1 {
			s := src[px_ - ox]
			sa := s >> 24
			if sa == 255 && draw_alpha == 255 {
				dst[px_] = s
				continue
			}
			if draw_alpha != 255 {
				t: u32
				for sh8 := u32(0); sh8 < 32; sh8 += 8 do t |= ((((s >> sh8) & 255) * draw_alpha + 127) / 255) << sh8
				s = t
				sa = s >> 24
			}
			// premultiplied "over", two channels per multiply (SWAR), /256 instead of /255
			inv := 256 - sa
			dd := dst[px_]
			rb := ((dd & 0x00ff00ff) * inv >> 8) & 0x00ff00ff
			ag := ((dd >> 8) & 0x00ff00ff) * inv & 0xff00ff00
			dst[px_] = s + rb + ag
		}
	}
}
