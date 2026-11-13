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
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:unicode/utf8"

MAX_PREVIEW :: 1600 // longest side kept in memory

View_Mode :: enum {
	Icon, Image, Text, Pdf, Video,
}

Preview :: struct {
	open, closing: bool,
	t0:            f32,
	from, cur:     Rect, // icon rect at open / last drawn card rect
	k:             int, // index in app.view
	mode:          View_Mode,
	img:           []u32, // image, PDF page, font sheet, video poster (premultiplied ARGB)
	img_w, img_h:  int,
	text:          string,
	lines:         [dynamic]string,
	info:          string,
	scroll:        f32,
	big:           bool, // document-sized card
	song:          bool, // audio file: offer "play"
	// zoom / pan (images, PDF)
	zoom:          f32,
	pan:           [2]f32,
	drag:          bool,
	drag_m, drag_p: [2]f32,
	// PDF
	pdf:           rawptr,
	page, pages:   int,
	page_w:        int, // width the current page was rendered at
	// video
	video:         ^Video,
	vpath:         string,
	vw, vh:        int,
	has_audio:     bool,
	dur:           f64,
	audio:         posix.pid_t,
	start_ms:      i64,
	paused, ended: bool,
	paused_at:     f64,
}
pv: Preview

@(private = "file")
free_content :: proc() {
	v_stop()
	pdf_close(pv.pdf)
	delete(pv.img)
	delete(pv.text)
	delete(pv.lines)
	delete(pv.info)
	delete(pv.vpath)
	pv.img, pv.text, pv.lines, pv.info, pv.vpath = nil, "", {}, "", ""
	pv.img_w, pv.img_h, pv.scroll, pv.pdf, pv.page, pv.pages, pv.page_w = 0, 0, 0, nil, 0, 0, 0
	pv.mode, pv.big, pv.song, pv.zoom, pv.pan, pv.drag, pv.ended = .Icon, false, false, 1, {}, false, false
}

@(private = "file")
set_pixels :: proc(px_: []u32, w, h: int) {
	delete(pv.img)
	pv.img, pv.img_w, pv.img_h = px_, w, h
	if pv.mode == .Icon do pv.mode = .Image
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
	set_pixels(out, w, h)
	return true
}

@(private = "file")
set_text :: proc(t: string, big := true) {
	delete(pv.text)
	tt, _ := strings.replace_all(t, "\t", "    ", context.temp_allocator)
	pv.text = strings.clone(tt)
	clear(&pv.lines)
	for l in strings.split_lines(pv.text, context.temp_allocator) do append(&pv.lines, l)
	pv.mode, pv.big = .Text, big
}

@(private = "file")
ffmpeg_frame :: proc(path: string, video: bool) -> bool {
	if !have_tool("ffmpeg") do return false
	vf := "thumbnail,scale='min(1600,iw)':-2" if video else "scale='min(1600,iw)':-2"
	_, out, _, err := os.process_exec({command = {"ffmpeg", "-v", "error", "-nostdin", "-i", path, "-an", "-frames:v", "1", "-vf", vf, "-f", "image2pipe", "-vcodec", "ppm", "-"}}, context.temp_allocator)
	if err != nil || len(out) == 0 do return false
	img, ierr := image.load_from_bytes(out, {.alpha_add_if_missing}, context.temp_allocator)
	return ierr == nil && set_image(img)
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
		set_text(folder_listing(path))
		return
	}
	ext := strings.to_lower(filepath.ext(e.name), context.temp_allocator)
	switch ext {
	case ".pdf":
		if doc, n := pdf_open(path); doc != nil && n > 0 {
			pv.pdf, pv.pages, pv.mode, pv.big = doc, n, .Pdf, true
			return
		}
	case ".svg", ".svgz":
		if img, w, h := svg_render_file(path, MAX_PREVIEW); img != nil {
			set_pixels(img, w, h)
			return
		}
	case ".ttf", ".otf", ".ttc", ".woff", ".woff2", ".pfb", ".pfa":
		if img, w, h, ok := font_sample(path, 1100, FG); ok {
			set_pixels(img, w, h)
			return
		}
	case ".docx", ".xlsx", ".pptx", ".odt", ".ods", ".odp", ".epub":
		if t := document_text(path); strings.trim_space(t) != "" {
			set_text(t)
			return
		}
	case ".gif":
		if v_probe(path) do return
	case ".png", ".jpg", ".jpeg", ".bmp", ".qoi", ".tga", ".ppm", ".pgm", ".pam":
		if img, err := image.load_from_file(path, {.alpha_add_if_missing}, context.temp_allocator); err == nil {
			if set_image(img) do return
		}
	}
	if _, tool, ok := archive_kind(e.name); ok && tool == "" {
		if t := archive_listing(path); t != "" {
			set_text(t)
			return
		}
	}
	#partial switch e.kind {
	case .Video:
		if v_probe(path) do return
	case .Image:
		if ffmpeg_frame(path, false) do return
	case .Audio:
		pv.song = true
		ffmpeg_frame(path, false) // album art, if any
		return
	}
	// text if it looks like UTF-8, otherwise a hex dump: every file shows something
	f, err := os.open(path)
	if err != nil do return
	defer os.close(f)
	buf: [65536]u8
	n, _ := os.read(f, buf[:])
	data := buf[:n]
	if n == 0 do return
	if strings.index_byte(string(data), 0) < 0 {
		for len(data) > 0 && !utf8.valid_string(string(data)) && len(data) > n - 4 do data = data[:len(data) - 1]
		if utf8.valid_string(string(data)) {
			set_text(string(data), e.kind != .Text && e.kind != .Code || len(data) > 2000)
			return
		}
	}
	set_text(hex_dump(buf[:min(n, 16384)]))
	delete(pv.info)
	pv.info = strings.concatenate({format_size(e.size), "  ·  バイナリ（先頭 16 KB）"})
}

// ---------------------------------------------------------------------------
// Video playback in the viewer: ffmpeg frames + ffplay for the sound

@(private = "file")
v_probe :: proc(path: string) -> bool {
	if !have_tool("ffmpeg") || !have_tool("ffprobe") do return false
	_, out, _, err := os.process_exec({command = {"ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height:format=duration", "-of", "default=nw=1", path}}, context.temp_allocator)
	if err != nil do return false
	w, h := 0, 0
	text := string(out)
	for line in strings.split_lines_iterator(&text) {
		k, _, v := strings.partition(line, "=")
		switch k {
		case "width":      if w == 0 do w, _ = strconv.parse_int(v)
		case "height":     if h == 0 do h, _ = strconv.parse_int(v)
		case "codec_type": if v == "audio" do pv.has_audio = true
		case "duration":   pv.dur, _ = strconv.parse_f64(v)
		}
	}
	if w <= 0 || h <= 0 do return false
	s := min(1280 / f64(w), 720 / f64(h), 1)
	pv.vw, pv.vh = max(int(f64(w) * s) &~ 1, 2), max(int(f64(h) * s) &~ 1, 2)
	pv.vpath = strings.clone(path)
	pv.mode = .Video
	ffmpeg_frame(path, true) // poster until the first frame arrives
	pv.mode = .Video
	v_start(0)
	return true
}

v_start :: proc(at: f64) {
	v_stop()
	if music_playing() && !mu.paused do music_toggle() // one thing making sound at a time
	pv.video = vid_open(pv.vpath, at, pv.vw, pv.vh)
	if pv.has_audio && have_tool("ffplay") {
		pv.audio = spawn({"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-ss", fmt_f(at), pv.vpath})
	}
	pv.start_ms = ticks_ms() - i64(at * 1000)
	pv.paused, pv.ended, pv.paused_at = false, false, at
}

v_stop :: proc() {
	vid_close(pv.video)
	pv.video = nil
	if pv.audio != 0 {
		posix.kill(pv.audio, .SIGCONT)
		posix.kill(pv.audio, .SIGTERM)
		status: i32
		posix.waitpid(pv.audio, &status, {})
		pv.audio = 0
	}
}

v_pos :: proc() -> f64 {
	if pv.paused || pv.ended do return pv.paused_at
	t := f64(ticks_ms() - pv.start_ms) / 1000
	return min(t, pv.dur) if pv.dur > 0 else t
}

v_toggle :: proc() {
	if pv.mode != .Video do return
	if pv.ended || pv.video == nil {
		v_start(0 if pv.ended else pv.paused_at)
		return
	}
	if pv.paused {
		vid_pause(pv.video, false)
		if pv.audio != 0 do posix.kill(pv.audio, .SIGCONT)
		pv.start_ms = ticks_ms() - i64(pv.paused_at * 1000)
		pv.paused = false
	} else {
		pv.paused_at = v_pos()
		vid_pause(pv.video, true)
		if pv.audio != 0 do posix.kill(pv.audio, .SIGSTOP)
		pv.paused = true
	}
}

// ---------------------------------------------------------------------------

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

// Files the viewer handles better than handing them to another app (double-click).
viewer_handles :: proc(e: Entry) -> bool {
	if e.is_dir do return false
	#partial switch e.kind {
	case .Image, .Video, .Pdf, .Text, .Code, .Document: return true
	}
	switch strings.to_lower(filepath.ext(e.name), context.temp_allocator) {
	case ".svg", ".svgz", ".ttf", ".otf", ".ttc", ".woff", ".woff2", ".epub": return true
	}
	return false
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
	v_stop()
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

pdf_page :: proc(d: int) {
	if pv.mode != .Pdf do return
	p := clamp(pv.page + d, 0, pv.pages - 1)
	if p == pv.page do return
	pv.page, pv.page_w, pv.zoom, pv.pan = p, 0, 1, {}
}

@(private = "file")
zoom_at :: proc(f: f32, c: [2]f32) {
	z := clamp(pv.zoom * f, 1, 8)
	f := z / pv.zoom
	pv.pan = (pv.pan - c) * f + c // keep the point under the cursor in place
	pv.zoom = z
	if pv.zoom <= 1.0001 do pv.pan = {}
}

// Keys while the viewer is open.
viewer_key :: proc(key: u32, ctrl: bool) {
	cols := app.cols if app.grid else 1
	switch key {
	case K_ESCAPE:              preview_close()
	case K_SPACE:               if pv.mode == .Video do v_toggle(); else do preview_close()
	case K_LEFT:                if pv.mode == .Video && ctrl do v_start(max(v_pos() - 10, 0)); else do preview_step(-1)
	case K_RIGHT:               if pv.mode == .Video && ctrl do v_start(v_pos() + 10); else do preview_step(1)
	case K_UP:                  if pv.mode == .Pdf do pdf_page(-1); else if pv.mode == .Text do pv.scroll = max(pv.scroll - px(60), 0); else do preview_step(-cols)
	case K_DOWN:                if pv.mode == .Pdf do pdf_page(1); else if pv.mode == .Text do pv.scroll += px(60); else do preview_step(cols)
	case K_PAGEUP:              if pv.mode == .Pdf do pdf_page(-1); else do pv.scroll = max(pv.scroll - px(600), 0)
	case K_PAGEDOWN:            if pv.mode == .Pdf do pdf_page(1); else do pv.scroll += px(600)
	case '+', '=':              zoom_at(1.25, {})
	case '-':                   zoom_at(0.8, {})
	case '0':                   pv.zoom, pv.pan = 1, {}
	case K_RETURN, K_KP_ENTER:  if pv.k < len(app.view) do spawn({"xdg-open", full_path(app.entries[app.view[pv.k]].name)})
	}
}

lerp_rect :: proc(a, b: Rect, t: f32) -> Rect {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t}
}

@(private = "file")
fit :: proc(w, h: int, area: Rect, up: f32) -> Rect {
	s := min(area.w / f32(w), area.h / f32(h), up)
	return {area.x + (area.w - f32(w) * s) / 2, area.y + (area.h - f32(h) * s) / 2, f32(w) * s, f32(h) * s}
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

	fill({0, 0, W, H}, hex(0x000000, u8(130 * p)))
	e := app.entries[app.view[pv.k]] if pv.k < len(app.view) else Entry{}
	cap_h := px(52)
	margin := px(36)
	maxw, maxh := W - 2 * margin, H - 2 * margin - cap_h
	cw, ch: f32
	switch {
	case pv.big:
		cw, ch = maxw, maxh
	case pv.mode == .Video:
		f := fit(pv.vw, pv.vh, {0, 0, maxw, maxh}, 2)
		cw, ch = max(f.w, px(420)), f.h
	case pv.img != nil:
		f := fit(pv.img_w, pv.img_h, {0, 0, maxw, maxh}, 2)
		cw, ch = max(f.w, px(420)), max(f.h, px(160))
	case pv.mode == .Text:
		cw, ch = min(maxw, px(900)), maxh
	case:
		cw, ch = px(360), px(240)
	}
	target := Rect{(W - cw) / 2, (H - ch - cap_h) / 2, cw, ch + cap_h}
	r := lerp_rect(pv.from, target, p)
	pv.cur = r
	draw_alpha = u32(clamp(p * 1.4, 0, 1) * 255)
	defer draw_alpha = 255
	rrect({r.x, r.y + px(6), r.w, r.h}, px(14), hex(0x000000, 80)) // soft drop shadow
	rrect(r, px(14), POP_BG)
	area := Rect{r.x, r.y, r.w, max(r.h - cap_h * p, 1)}
	inner := shrink(area, px(6) * p)

	// PDF: render the page at the size it is shown (re-rendered after zooming settles)
	if pv.mode == .Pdf {
		want := min(int(inner.w * pv.zoom), 3000)
		if pv.img == nil || (!app.animating && abs(want - pv.page_w) > want / 10) {
			if img, w, h := pdf_render(pv.pdf, pv.page, want); img != nil {
				delete(pv.img)
				pv.img, pv.img_w, pv.img_h, pv.page_w = img, w, h, want
			}
		}
	}

	// wheel / drag
	in_area := hovering(area)
	mc := [2]f32{app.mx - (inner.x + inner.w / 2), app.my - (inner.y + inner.h / 2)}
	if app.wheel != 0 && in_area {
		switch pv.mode {
		case .Image, .Icon:
			zoom_at(math.pow(1.2, app.wheel), mc)
		case .Pdf:
			if .Ctrl in app.mod do zoom_at(math.pow(1.2, app.wheel), mc)
			else if pv.zoom > 1 do pv.pan.y += app.wheel * px(80)
			else do pdf_page(-1 if app.wheel > 0 else 1)
		case .Text:
			pv.scroll -= app.wheel * px(60)
		case .Video:
		}
	}
	if (pv.mode == .Image || pv.mode == .Pdf) && pv.img != nil {
		if app.pressed && app.button == 1 && in_area {
			if app.clicks >= 2 {
				if pv.zoom > 1 do pv.zoom, pv.pan = 1, {}
				else do zoom_at(2.5, mc)
			} else if pv.zoom > 1 {
				pv.drag, pv.drag_m, pv.drag_p = true, {app.mx, app.my}, pv.pan
			}
		}
		if pv.drag {
			if app.held do pv.pan = pv.drag_p + ([2]f32{app.mx, app.my} - pv.drag_m)
			else do pv.drag = false
		}
	}

	switch pv.mode {
	case .Image, .Pdf:
		if pv.img == nil do break
		f := fit(pv.img_w, pv.img_h, inner, 2 if pv.mode == .Image else 4)
		z := Rect{f.x + f.w / 2 + pv.pan.x - f.w * pv.zoom / 2, f.y + f.h / 2 + pv.pan.y - f.h * pv.zoom / 2, f.w * pv.zoom, f.h * pv.zoom}
		set_clip(inner)
		blit_scaled(z, pv.img, pv.img_w, pv.img_h)
		reset_clip()
	case .Video:
		f := fit(pv.vw, pv.vh, inner, 2)
		if !vid_draw(pv.video, f) && pv.img != nil do blit_scaled(f, pv.img, pv.img_w, pv.img_h)
		if pv.dur > 0 && v_pos() >= pv.dur - 0.05 && !pv.ended {
			pv.paused_at, pv.ended = pv.dur, true
			v_stop()
		}
		draw_video_controls(inner)
	case .Text:
		set_clip(shrink(area, px(16)))
		size := fs(13)
		lh := px(19)
		pv.scroll = clamp(pv.scroll, 0, max(0, f32(len(pv.lines)) * lh - area.h + px(32)))
		first := int(pv.scroll / lh)
		y := area.y + px(16) + f32(first) * lh - pv.scroll
		for i in first ..< len(pv.lines) {
			if y > area.y + area.h do break
			text(area.x + px(16), y + lh * 0.75, pv.lines[i], size, FG)
			y += lh
		}
		reset_clip()
	case .Icon:
		s := min(area.w, area.h) * 0.5
		ix, iy := area.x + (area.w - s) / 2, area.y + (area.h - s) / 2
		if e.is_dir do folder_icon(ix, iy, s, 0, tint_of(e.name))
		else do file_icon(ix, iy, s, e.kind, e.name)
	}

	// caption: name, info, page / zoom, buttons
	if p > 0.5 {
		cr := Rect{r.x + px(16), r.y + r.h - cap_h, r.w - px(32), cap_h}
		size := fs(14)
		info := pv.info
		if pv.mode == .Image && pv.img != nil do info = strings.concatenate({info, "  ·  ", itoa(pv.img_w), "×", itoa(pv.img_h)}, context.temp_allocator)
		if pv.mode == .Pdf do info = strings.concatenate({info, "  ·  ", itoa(pv.page + 1), " / ", itoa(pv.pages), " ページ"}, context.temp_allocator)
		if pv.zoom > 1.001 do info = strings.concatenate({info, "  ·  ", itoa(int(pv.zoom * 100 + 0.5)), "%"}, context.temp_allocator)
		bx := cr.x + cr.w
		ext := Rect{bx - px(36), cr.y + (cr.h - px(32)) / 2, px(32), px(32)}
		if icon_button(ext, 0xf08e) && pv.k < len(app.view) do spawn({"xdg-open", full_path(e.name)}) // 外部アプリで開く
		bx = ext.x - px(6)
		if pv.mode == .Pdf {
			nb := Rect{bx - px(32), ext.y, px(32), px(32)}
			if icon_button(nb, I_FWD, false, pv.page < pv.pages - 1) do pdf_page(1)
			pb := Rect{nb.x - px(34), ext.y, px(32), px(32)}
			if icon_button(pb, I_BACK, false, pv.page > 0) do pdf_page(-1)
			bx = pb.x - px(6)
		}
		if pv.song {
			pb := Rect{bx - px(84), ext.y, px(80), px(32)}
			if text_button(pb, "▶ 再生", 1) {
				music_play_entry(app.view[pv.k])
				preview_close()
			}
			bx = pb.x - px(6)
		}
		iw := f32(text_width(info, fs(12)))
		text(bx - iw - px(4), baseline(cr, fs(12)), info, fs(12), DIM)
		text(cr.x, baseline(cr, size), ellipsize(filepath.base(e.name), size, bx - iw - px(16) - cr.x, true), size, FG, true)
	}
	if app.pressed && !contains(r, app.mx, app.my) do preview_close()
}

@(private = "file")
draw_video_controls :: proc(a: Rect) {
	bar := Rect{a.x + px(12), a.y + a.h - px(52), a.w - px(24), px(44)}
	rrect(bar, px(12), hex(0x000000, 150))
	pb := Rect{bar.x + px(6), bar.y + px(6), px(32), px(32)}
	playing := pv.video != nil && !pv.paused && !pv.ended
	if icon_button(pb, I_PAUSE if playing else I_PLAY) do v_toggle()
	pos := v_pos()
	t := fmt.tprintf("%d:%02d / %d:%02d", int(pos) / 60, int(pos) % 60, int(pv.dur) / 60, int(pv.dur) % 60)
	tw := f32(text_width(t, fs(12)))
	text(bar.x + bar.w - tw - px(12), baseline(bar, fs(12)), t, fs(12), FG)
	sb := Rect{pb.x + pb.w + px(10), bar.y + bar.h / 2 - px(2), bar.w - pb.w - tw - px(40), px(4)}
	rrect(sb, px(2), hex(0xffffff, 60))
	if pv.dur > 0 {
		f := f32(clamp(pos / pv.dur, 0, 1))
		rrect({sb.x, sb.y, sb.w * f, sb.h}, px(2), ACCENT)
		hit := Rect{sb.x, sb.y - px(10), sb.w, px(24)}
		if hovering(hit) do rrect({sb.x + sb.w * f - px(6), sb.y - px(4), px(12), px(12)}, px(6), FG)
		if clicked(hit) do v_start(f64((app.mx - sb.x) / sb.w) * pv.dur)
	}
	if playing do app.animating = pv.video == nil // frames come from the decoder; this only covers the gap
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
