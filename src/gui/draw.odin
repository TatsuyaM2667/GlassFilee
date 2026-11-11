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

@(private = "file")
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
	for y in y0 ..< y1 {
		qy := abs(f32(y) + 0.5 - cy) - hy
		for x in x0 ..< x1 {
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

folder_icon :: proc(x, y, s: f32, emblem: rune = 0) {
	rrect({x + 0.06 * s, y + 0.12 * s, 0.38 * s, 0.14 * s}, 0.05 * s, hex(0x1c71d8))
	rrect({x + 0.06 * s, y + 0.17 * s, 0.88 * s, 0.68 * s}, 0.07 * s, hex(0x1c71d8))
	rrect({x + 0.12 * s, y + 0.24 * s, 0.76 * s, 0.30 * s}, 0.03 * s, hex(0xdeddda))
	rrect({x + 0.06 * s, y + 0.31 * s, 0.88 * s, 0.56 * s}, 0.07 * s, hex(0x3584e4))
	rrect({x + 0.06 * s, y + 0.31 * s, 0.88 * s, 0.50 * s}, 0.07 * s, hex(0x62a0ea))
	if emblem != 0 && s >= 32 {
		glyph_center({x + 0.06 * s, y + 0.34 * s, 0.88 * s, 0.48 * s}, emblem, i32(0.24 * s), hex(0x1a5fb4, 220))
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

file_icon :: proc(x, y, s: f32, kind: Kind) {
	page := Rect{x + 0.18 * s, y + 0.06 * s, 0.64 * s, 0.86 * s}
	rrect(page, 0.06 * s, hex(0xf6f5f4, 240))
	rrect({page.x + page.w - 0.2 * s, page.y, 0.2 * s, 0.2 * s}, 0.04 * s, hex(0xc0bfbc))
	band := Rect{page.x, page.y + page.h * 0.52, page.w, page.h * 0.3}
	if s >= 32 {
		glyph_center(band, KIND_GLYPH[kind], i32(0.26 * s), hex(KIND_COLOR[kind]))
	} else {
		rrect(shrink(band, 0.08 * s), 0.03 * s, hex(KIND_COLOR[kind]))
	}
}
