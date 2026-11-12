package main

// Quick preview (Space), like GNOME Sushi: zooms out of the item's icon.
// Images: Odin's decoders (png/jpeg/bmp/qoi/tga/netpbm); other images and
// video frames: ffmpeg -> PPM pipe. Text: first 64 KB.

import "core:image"
import _ "core:image/bmp"
import _ "core:image/jpeg"
import _ "core:image/netpbm"
import _ "core:image/png"
import _ "core:image/qoi"
import _ "core:image/tga"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"

MAX_PREVIEW :: 1600 // longest side kept in memory

Preview :: struct {
	open, closing: bool,
	t0:            f32,
	from, cur:     Rect, // icon rect at open / last drawn card rect
	k:             int, // index in app.view
	img:           []u32, // premultiplied ARGB
	img_w, img_h:  int,
	text:          string,
	lines:         [dynamic]string,
	info:          string,
	scroll:        f32,
}
pv: Preview

@(private = "file")
free_content :: proc() {
	delete(pv.img)
	delete(pv.text)
	delete(pv.lines)
	delete(pv.info)
	pv.img, pv.text, pv.lines, pv.info, pv.img_w, pv.img_h, pv.scroll = nil, "", {}, "", 0, 0, 0
}

@(private = "file")
set_image :: proc(img: ^image.Image) -> bool {
	if img == nil || img.depth != 8 || img.channels < 3 do return false
	src := img.pixels.buf[:]
	ch := img.channels
	// box-downscale to MAX_PREVIEW so a 50 MP photo doesn't stay in memory
	sc := max(1, int(math.ceil(f32(max(img.width, img.height)) / MAX_PREVIEW)))
	w, h := img.width / sc, img.height / sc
	if w == 0 || h == 0 do return false
	out := make([]u32, w * h)
	for y in 0 ..< h {
		for x in 0 ..< w {
			r, g, b, a: int
			for dy in 0 ..< sc do for dx in 0 ..< sc {
				i := ((y * sc + dy) * img.width + x * sc + dx) * ch
				pa := int(src[i + 3]) if ch == 4 else 255
				r += int(src[i]) * pa / 255
				g += int(src[i + 1]) * pa / 255
				b += int(src[i + 2]) * pa / 255
				a += pa
			}
			n := sc * sc
			out[y * w + x] = u32(a / n) << 24 | u32(r / n) << 16 | u32(g / n) << 8 | u32(b / n)
		}
	}
	pv.img, pv.img_w, pv.img_h = out, w, h
	return true
}

@(private = "file")
load_content :: proc(e: Entry) {
	free_content()
	path := full_path(e.name)
	pv.info = strings.clone(e.is_dir ? "フォルダー" : format_size(e.size))
	if e.is_dir {
		if infos, err := os.read_all_directory_by_path(path, context.temp_allocator); err == nil {
			delete(pv.info)
			pv.info = strings.clone(fmt_count(len(infos)))
		}
		return
	}
	lower := strings.to_lower(filepath.ext(e.name), context.temp_allocator)
	switch lower {
	case ".png", ".jpg", ".jpeg", ".bmp", ".qoi", ".tga", ".ppm", ".pgm", ".pam":
		if img, err := image.load_from_file(path, {.alpha_add_if_missing}, context.temp_allocator); err == nil {
			if set_image(img) do return
		}
	}
	if (e.kind == .Image || e.kind == .Video) && have_tool("ffmpeg") {
		vf := "thumbnail,scale='min(1600,iw)':-2" if e.kind == .Video else "scale='min(1600,iw)':-2"
		_, out, _, err := os.process_exec({command = {"ffmpeg", "-v", "error", "-nostdin", "-i", path, "-frames:v", "1", "-vf", vf, "-f", "image2pipe", "-vcodec", "ppm", "-"}}, context.temp_allocator)
		if err == nil && len(out) > 0 {
			if img, ierr := image.load_from_bytes(out, {.alpha_add_if_missing}, context.temp_allocator); ierr == nil {
				if set_image(img) do return
			}
		}
	}
	// text: first 64 KB if it looks like UTF-8 text
	f, err := os.open(path)
	if err != nil do return
	defer os.close(f)
	buf: [65536]u8
	n, _ := os.read(f, buf[:])
	data := buf[:n]
	if n > 0 && strings.index_byte(string(data), 0) < 0 {
		// cut a UTF-8 sequence split by the 64 KB limit
		for len(data) > 0 && !utf8.valid_string(string(data)) && len(data) > n - 4 do data = data[:len(data) - 1]
		if utf8.valid_string(string(data)) {
			t, _ := strings.replace_all(string(data), "\t", "    ")
			pv.text = strings.clone(t)
			pv.lines = make([dynamic]string)
			for l in strings.split_lines(pv.text, context.temp_allocator) do append(&pv.lines, l)
		}
	}
}

fmt_count :: proc(n: int) -> string {
	return n == 0 ? "空のフォルダー" : strings.concatenate({itoa(n), " 個のアイテム"}, context.temp_allocator)
}

@(private = "file")
itoa :: proc(n: int) -> string {
	buf: [24]u8
	i := len(buf)
	v := n
	for {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
		if v == 0 do break
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}

// Screen rect of item k's icon (for the zoom origin).
@(private = "file")
icon_rect :: proc(k: int) -> Rect {
	ir := item_rect(k)
	r := Rect{app.body.x + ir.x, app.body.y + ir.y - app.scroll, ir.w, ir.h}
	if app.grid do return {r.x + (r.w - px(64)) / 2, r.y + px(8), px(64), px(64)}
	return {r.x + px(16), r.y + (r.h - px(28)) / 2, px(28), px(28)}
}

preview_open :: proc(k: int) {
	if k < 0 || k >= len(app.view) do return
	pv.k = k
	load_content(app.entries[app.view[k]])
	pv.open, pv.closing, pv.t0 = true, false, now_s()
	pv.from = icon_rect(k)
}

preview_close :: proc() {
	if !pv.open || pv.closing do return
	pv.closing, pv.t0 = true, now_s()
	pv.from = icon_rect(pv.k)
}

preview_step :: proc(d: int) {
	k := clamp(pv.k + d, 0, len(app.view) - 1)
	if k == pv.k do return
	clear_sel()
	app.entries[app.view[k]].sel = true
	app.focus, app.anchor = k, k
	ensure_visible(k)
	pv.k = k
	load_content(app.entries[app.view[k]])
	pv.from, pv.t0 = pv.cur, now_s() - 0.12 // short settle instead of a full zoom
}

lerp_rect :: proc(a, b: Rect, t: f32) -> Rect {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t}
}

draw_preview :: proc(W, H: f32) {
	if !pv.open do return
	p: f32
	if pv.closing {
		p = 1 - progress(pv.t0, 0.22)
		if p <= 0.001 {
			pv.open = false
			free_content()
			return
		}
	} else do p = progress(pv.t0, 0.32)

	fill({0, 0, W, H}, hex(0x000000, u8(110 * p)))
	e := app.entries[app.view[pv.k]] if pv.k < len(app.view) else Entry{}
	cap_h := px(48)
	margin := px(48)
	maxw, maxh := W - 2 * margin, H - 2 * margin - cap_h
	cw, ch: f32
	if pv.img != nil {
		s := min(maxw / f32(pv.img_w), maxh / f32(pv.img_h), 2)
		cw, ch = f32(pv.img_w) * s, f32(pv.img_h) * s
	} else if pv.text != "" {
		cw, ch = min(maxw, px(860)), maxh
	} else {
		cw, ch = px(320), px(220)
	}
	target := Rect{(W - cw) / 2, (H - ch - cap_h) / 2, cw, ch + cap_h}
	r := lerp_rect(pv.from, target, p)
	pv.cur = r
	draw_alpha = u32(clamp(p * 1.4, 0, 1) * 255)
	defer draw_alpha = 255
	rrect({r.x, r.y + px(6), r.w, r.h}, px(14), hex(0x000000, 80)) // soft drop shadow
	rrect(r, px(14), POP_BG)
	area := Rect{r.x, r.y, r.w, max(r.h - cap_h * p, 1)}

	switch {
	case pv.img != nil:
		blit_scaled(shrink(area, px(6) * p), pv.img, pv.img_w, pv.img_h)
	case pv.text != "":
		set_clip(shrink(area, px(16)))
		size := fs(13)
		lh := px(19)
		if app.wheel != 0 do pv.scroll = clamp(pv.scroll - app.wheel * px(60), 0, max(0, f32(len(pv.lines)) * lh - area.h + px(32)))
		first := int(pv.scroll / lh)
		y := area.y + px(16) + f32(first) * lh - pv.scroll
		for i in first ..< len(pv.lines) {
			if y > area.y + area.h do break
			text(area.x + px(16), y + lh * 0.75, pv.lines[i], size, FG)
			y += lh
		}
		reset_clip()
	case:
		s := min(area.w, area.h) * 0.5
		ix, iy := area.x + (area.w - s) / 2, area.y + (area.h - s) / 2
		if e.is_dir do folder_icon(ix, iy, s, 0, tint_of(e.name))
		else do file_icon(ix, iy, s, e.kind)
	}
	// caption
	if p > 0.5 {
		cr := Rect{r.x + px(16), r.y + r.h - cap_h, r.w - px(32), cap_h}
		size := fs(14)
		info := pv.info
		if pv.img != nil do info = strings.concatenate({info, "  ·  ", itoa(pv.img_w), "×", itoa(pv.img_h)}, context.temp_allocator)
		iw := f32(text_width(info, fs(12)))
		text(cr.x, baseline(cr, size), ellipsize(filepath.base(e.name), size, cr.w - iw - px(16), true), size, FG, true)
		text(cr.x + cr.w - iw, baseline(cr, fs(12)), info, fs(12), DIM)
	}
	if app.pressed && !contains(r, app.mx, app.my) do preview_close()
}

// Bilinear-scaled blit of a premultiplied image into r (respecting clip and draw_alpha).
blit_scaled :: proc(r: Rect, img: []u32, iw, ih: int) {
	x0 := max(i32(r.x), cv.clip[0])
	y0 := max(i32(r.y), cv.clip[1])
	x1 := min(i32(r.x + r.w), cv.clip[2])
	y1 := min(i32(r.y + r.h), cv.clip[3])
	if x1 <= x0 || y1 <= y0 do return
	sx := f32(iw) / r.w
	sy := f32(ih) / r.h
	ga := draw_alpha
	for y in y0 ..< y1 {
		fy := clamp((f32(y) + 0.5 - r.y) * sy - 0.5, 0, f32(ih - 1))
		iy := int(fy)
		iy1 := min(iy + 1, ih - 1)
		wy := u32((fy - f32(iy)) * 256)
		row := cv.px[y * cv.stride:]
		for x in x0 ..< x1 {
			fx := clamp((f32(x) + 0.5 - r.x) * sx - 0.5, 0, f32(iw - 1))
			ix := int(fx)
			ix1 := min(ix + 1, iw - 1)
			wx := u32((fx - f32(ix)) * 256)
			a, b := img[iy * iw + ix], img[iy * iw + ix1]
			c, d := img[iy1 * iw + ix], img[iy1 * iw + ix1]
			s: u32
			for sh := u32(0); sh < 32; sh += 8 {
				top := ((a >> sh) & 255) * (256 - wx) + ((b >> sh) & 255) * wx
				bot := ((c >> sh) & 255) * (256 - wx) + ((d >> sh) & 255) * wx
				v := (top * (256 - wy) + bot * wy) >> 16
				s |= ((v * ga + 127) / 255) << sh
			}
			sa := s >> 24
			dst := row[x]
			inv := 255 - sa
			o: u32
			for sh := u32(0); sh < 32; sh += 8 {
				o |= min(((s >> sh) & 255) + (((dst >> sh) & 255) * inv + 127) / 255, 255) << sh
			}
			row[x] = o
		}
	}
}
