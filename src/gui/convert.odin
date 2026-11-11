package main

// Filee-style conversion: Ctrl+drag selected files (or right-click → 変換…) opens a
// donut of target formats at the cursor; drop on a slice to convert next to the original.
// Engines are whatever is installed: ffmpeg, pandoc, LibreOffice, ImageMagick, bsdtar.

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

Cat :: enum {
	None, Image, Video, Audio, Doc, Office, Archive,
}

Target :: struct {
	label, ext, tool: string,
}

TARGETS := [Cat][]Target {
	.None    = {},
	.Image   = {{"PNG", "png", "ffmpeg"}, {"JPG", "jpg", "ffmpeg"}, {"WEBP", "webp", "ffmpeg"}, {"AVIF", "avif", "ffmpeg"},
	            {"GIF", "gif", "ffmpeg"}, {"BMP", "bmp", "ffmpeg"}, {"TIFF", "tiff", "ffmpeg"}, {"ICO", "ico", "ffmpeg"}, {"PDF", "pdf", "magick"}},
	.Video   = {{"MP4", "mp4", "ffmpeg"}, {"WEBM", "webm", "ffmpeg"}, {"MKV", "mkv", "ffmpeg"}, {"MOV", "mov", "ffmpeg"},
	            {"GIF", "gif", "ffmpeg"}, {"MP3", "mp3", "ffmpeg"}, {"M4A", "m4a", "ffmpeg"}},
	.Audio   = {{"MP3", "mp3", "ffmpeg"}, {"FLAC", "flac", "ffmpeg"}, {"OGG", "ogg", "ffmpeg"}, {"WAV", "wav", "ffmpeg"},
	            {"M4A", "m4a", "ffmpeg"}, {"OPUS", "opus", "ffmpeg"}},
	.Doc     = {{"PDF", "pdf", "soffice"}, {"DOCX", "docx", "pandoc"}, {"HTML", "html", "pandoc"}, {"MD", "md", "pandoc"},
	            {"EPUB", "epub", "pandoc"}, {"ODT", "odt", "pandoc"}, {"TXT", "txt", "pandoc"}},
	.Office  = {{"PDF", "pdf", "soffice"}},
	.Archive = {{"ZIP", "zip", "bsdtar"}, {"TAR.GZ", "tar.gz", "bsdtar"}, {"TAR.XZ", "tar.xz", "bsdtar"}, {"7Z", "7z", "bsdtar"}},
}

cat_of :: proc(name: string) -> Cat {
	if _, tool, ok := archive_kind(name); ok && tool == "" do return .Archive
	switch strings.to_lower(filepath.ext(name), context.temp_allocator) {
	case ".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".heif", ".ico", ".tga", ".jxl", ".qoi":
		return .Image
	case ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".wmv", ".flv", ".mpg", ".mpeg", ".ts":
		return .Video
	case ".mp3", ".flac", ".ogg", ".wav", ".m4a", ".opus", ".aac", ".wma", ".aiff":
		return .Audio
	case ".md", ".markdown", ".txt", ".html", ".htm", ".docx", ".odt", ".rst", ".epub", ".tex", ".org", ".rtf":
		return .Doc
	case ".xlsx", ".xls", ".ods", ".pptx", ".ppt", ".odp", ".doc", ".csv":
		return .Office
	}
	return .None
}

@(private = "file") tool_cache: map[string]bool

have_tool :: proc(name: string) -> bool {
	if v, ok := tool_cache[name]; ok do return v
	found := false
	path := os.get_env("PATH", context.temp_allocator)
	for dir in strings.split_iterator(&path, ":") {
		p, _ := filepath.join({dir, name}, context.temp_allocator)
		if os.exists(p) {found = true; break}
	}
	tool_cache[strings.clone(name)] = found
	return found
}

same_ext :: proc(a, b: string) -> bool {
	norm :: proc(s: string) -> string {
		switch s {
		case "jpeg": return "jpg"
		case "tif":  return "tiff"
		case "htm":  return "html"
		case "tgz":  return "tar.gz"
		}
		return s
	}
	return norm(a) == norm(b)
}

// Extension of a file name without the dot, with compound archive suffixes kept (tar.gz).
file_ext :: proc(name: string) -> (stem, ext: string) {
	if s, tool, ok := archive_kind(name); ok && tool == "" {
		return s, strings.to_lower(name[len(s) + 1:], context.temp_allocator)
	}
	e := filepath.ext(name)
	if e == "" || len(e) == len(name) do return name, ""
	return name[:len(name) - len(e)], strings.to_lower(e[1:], context.temp_allocator)
}

convert_cmd :: proc(t: Target, src, dst: string) -> []string {
	switch t.tool {
	case "ffmpeg":
		args := make([dynamic]string, context.temp_allocator)
		append(&args, "ffmpeg", "-nostdin", "-v", "error", "-n", "-i", src)
		switch t.ext {
		case "gif": if cat_of(src) == .Video do append(&args, "-vf", "fps=12,scale='min(640,iw)':-1")
		case "mp3", "m4a": append(&args, "-vn")
		case "jpg": append(&args, "-q:v", "2")
		case "ico": append(&args, "-vf", "scale='min(256,iw)':'min(256,ih)':force_original_aspect_ratio=decrease")
		}
		append(&args, dst)
		return args[:]
	case "pandoc":
		if t.ext == "txt" do return slice_of({"pandoc", src, "-t", "plain", "-o", dst})
		return slice_of({"pandoc", src, "-o", dst})
	case "soffice":
		return slice_of({"soffice", "--headless", "--convert-to", t.ext, "--outdir", filepath.dir(dst), src})
	case "magick":
		return slice_of({"magick", src, dst})
	case "bsdtar":
		return slice_of({"bsdtar", "-a", "-cf", dst, strings.concatenate({"@", src}, context.temp_allocator)})
	}
	return nil
}

@(private = "file")
slice_of :: proc(a: []string) -> []string {
	out := make([]string, len(a), context.temp_allocator)
	copy(out, a)
	return out
}

// Starts one conversion job per file; output goes next to each source.
convert_files :: proc(t: Target, names: []string) {
	started := 0
	for name in names {
		stem, ext := file_ext(name)
		if same_ext(ext, t.ext) do continue
		src := full_path(name)
		dir := filepath.dir(src)
		dst := unique_dest(dir, strings.concatenate({filepath.base(stem), ".", t.ext}, context.temp_allocator))
		if t.tool == "soffice" {
			// LibreOffice picks the output name itself: never let it overwrite
			dst, _ = filepath.join({dir, strings.concatenate({filepath.base(stem), ".", t.ext}, context.temp_allocator)}, context.temp_allocator)
			if os.exists(dst) {
				toastf("「%s」は既にあります", filepath.base(dst))
				continue
			}
		}
		pid := spawn(convert_cmd(t, src, dst), dir)
		if pid == 0 do continue
		// shortcut: all files convert in parallel; queue them if huge batches overload the CPU
		append(&jobs, Job{pid = pid, kind = .Convert, label = strings.clone(filepath.base(dst)), src = strings.clone(name), dest = strings.clone(dst)})
		started += 1
	}
	if started == 1 do toastf("%s に変換しています…", t.label)
	else if started > 1 do toastf("%d 個のファイルを %s に変換しています…", started, t.label)
}

converting :: proc(name: string) -> bool {
	for j in jobs do if j.kind == .Convert && j.src == name do return true
	return false
}

// ---------------------------------------------------------------------------
// Donut menu

Donut :: struct {
	open, closing, drag: bool,
	t0:                  f32,
	c:                   [2]f32,
	targets:             [dynamic]Target,
	files:               [dynamic]string,
	hover, chosen:       int,
	grow:                [16]f32, // per-slice hover animation
}
dn: Donut

donut_open :: proc(x, y: f32, drag: bool) {
	sel := selection()
	if len(sel) == 0 do return
	cat := cat_of(app.entries[sel[0]].name)
	clear(&dn.targets)
	for f in dn.files do delete(f)
	clear(&dn.files)
	for vi in sel {
		if cat_of(app.entries[vi].name) == cat do append(&dn.files, strings.clone(app.entries[vi].name))
	}
	_, first_ext := file_ext(dn.files[0]) // the first selected file always matches its own category
	for t in TARGETS[cat] {
		if len(dn.files) == 1 && same_ext(first_ext, t.ext) do continue
		if have_tool(t.tool) && len(dn.targets) < len(dn.grow) do append(&dn.targets, t)
	}
	if len(dn.targets) == 0 {
		toastf("この種類のファイルは変換できません（ffmpeg / pandoc / LibreOffice などが必要です）")
		return
	}
	W, H := f32(cv.w), f32(cv.h)
	m := px(150)
	dn.c = {clamp(x, m, max(m, W - m)), clamp(y, m, max(m, H - m))}
	dn.open, dn.closing, dn.drag = true, false, drag
	dn.t0, dn.hover, dn.chosen = now_s(), -1, -1
	dn.grow = {}
}

donut_choose :: proc(i: int) {
	if i >= 0 && i < len(dn.targets) do convert_files(dn.targets[i], dn.files[:])
	dn.chosen = i
	dn.closing, dn.t0 = true, now_s()
}

donut_key :: proc(key: u32) -> bool {
	n := len(dn.targets)
	switch key {
	case K_ESCAPE:              donut_choose(-1)
	case K_LEFT, K_UP:          dn.hover = (max(dn.hover, 0) - 1 + n) % n
	case K_RIGHT, K_DOWN, K_TAB: dn.hover = (dn.hover + 1) % n
	case K_RETURN, K_KP_ENTER:  if dn.hover >= 0 do donut_choose(dn.hover)
	case: return false
	}
	return true
}

draw_donut :: proc() {
	if !dn.open do return
	p: f32
	if dn.closing {
		p = 1 - progress(dn.t0, 0.2)
		if p <= 0.001 {dn.open = false; return}
	} else do p = progress(dn.t0, 0.34)

	n := len(dn.targets)
	step := 2 * math.PI / f32(n)
	spin := (1 - p) * -0.9 // swirls into place
	r0 := px(50) * (0.6 + 0.4 * p)
	r1 := px(128) * (0.55 + 0.45 * p)
	cx, cy := dn.c.x, dn.c.y

	// hover: which slice is under the pointer
	if !dn.closing {
		dx, dy := app.mx - cx, app.my - cy
		d := math.sqrt(dx * dx + dy * dy)
		if d > r0 * 0.9 && d < r1 + px(40) {
			a := math.atan2(dy, dx) + math.PI / 2 - spin + step / 2
			for a < 0 do a += 2 * math.PI
			dn.hover = int(a / step) % n
		} else if app.mx != dn.c.x || app.my != dn.c.y {
			if d <= r0 * 0.9 do dn.hover = -1
		}
	}

	draw_alpha = u32(clamp(p * 1.3, 0, 1) * 255)
	defer draw_alpha = 255
	ring_seg(cx, cy + px(3), r0 - px(2), r1 + px(4), 0, 2 * math.PI, hex(0x000000, 28)) // soft shadow
	for i in 0 ..< n {
		target := f32(1) if i == dn.hover || i == dn.chosen else 0
		if d := target - dn.grow[i]; abs(d) > 0.01 {
			dn.grow[i] += d * (1 - math.exp(-app.dt * 20))
			app.animating = true
		} else do dn.grow[i] = target
		g := dn.grow[i]
		// staggered appearance around the ring
		sp := clamp(p * 1.6 - f32(i) * 0.06, 0, 1)
		mid := -math.PI / 2 + f32(i) * step + spin
		gap := 0.025 + 0.02 * (1 - sp)
		ro := r0 + (r1 - r0) * sp + g * px(12)
		col := hex(0x1b2133, 245)
		if g > 0 do col = mix(col, with_alpha(ACCENT, 245), g)
		ring_seg(cx, cy, r0, ro, mid - step / 2 + gap, mid + step / 2 - gap, col)
		lr := (r0 + ro) / 2
		lx, ly := cx + math.cos(mid) * lr, cy + math.sin(mid) * lr
		size := fs(13 + 2 * g)
		label := dn.targets[i].label
		tw := f32(text_width(label, size, true))
		asc, dsc := font_metrics(size)
		text(lx - tw / 2, ly + f32(asc - dsc) / 2, label, size, mix(FG, hex(0x060913), g), true)
	}
	// center disc
	ring_seg(cx, cy, 0, r0 - px(6), 0, 2 * math.PI, hex(0x10141f, 250))
	center := "変換"
	if dn.hover >= 0 do center = strings.concatenate({"→ ", dn.targets[dn.hover].label}, context.temp_allocator)
	size := fs(14)
	tw := f32(text_width(center, size, true))
	text(cx - tw / 2, cy + px(1), center, size, FG, true)
	sub := fmt_count(len(dn.files))
	sw := f32(text_width(sub, fs(11)))
	text(cx - sw / 2, cy + px(17), sub, fs(11), DIM)

	if dn.closing do return
	if dn.drag {
		if app.released do donut_choose(dn.hover)
	} else if app.pressed {
		donut_choose(dn.hover if app.button == 1 else -1)
	}
}

mix :: proc(a, b: Color, t: f32) -> Color {
	t := clamp(t, 0, 1)
	return {
		u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t), u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
		u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t), u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
	}
}

// Indeterminate progress ring around an icon while it converts.
progress_ring :: proc(r: Rect) {
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	rad := max(r.w, r.h) / 2 + px(4)
	ring_seg(cx, cy, rad - px(3), rad, 0, 2 * math.PI, hex(0xffffff, 30))
	a := app.now * 5
	ring_seg(cx, cy, rad - px(3), rad, a, a + 1.6 + math.sin(app.now * 3) * 0.6, ACCENT)
}
