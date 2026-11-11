package main

// Filee-style conversion: Ctrl+drag selected files (or right-click → 変換…) opens a
// donut of target formats at the cursor; drop on a slice to convert next to the original.
// Engines are whatever is installed: ffmpeg, pandoc, LibreOffice, ImageMagick, bsdtar.

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

Cat :: enum {
	None, Image, Video, Audio, Doc, Office, Archive,
}

Target :: struct {
	label, ext, tool: string, // ext "" = keep the source's extension
	args:             string, // extra ffmpeg arguments (space separated, no shell)
	suffix:           string, // appended to the output name (tools on the donut's back face)
}

TARGETS := [Cat][]Target {
	.None    = {},
	.Image   = {{"PNG", "png", "ffmpeg", "", ""}, {"JPG", "jpg", "ffmpeg", "", ""}, {"WEBP", "webp", "ffmpeg", "", ""}, {"AVIF", "avif", "ffmpeg", "", ""},
	            {"GIF", "gif", "ffmpeg", "", ""}, {"BMP", "bmp", "ffmpeg", "", ""}, {"TIFF", "tiff", "ffmpeg", "", ""}, {"ICO", "ico", "ffmpeg", "", ""}, {"PDF", "pdf", "magick", "", ""}},
	.Video   = {{"MP4", "mp4", "ffmpeg", "", ""}, {"WEBM", "webm", "ffmpeg", "", ""}, {"MKV", "mkv", "ffmpeg", "", ""}, {"MOV", "mov", "ffmpeg", "", ""},
	            {"GIF", "gif", "ffmpeg", "", ""}, {"MP3", "mp3", "ffmpeg", "", ""}, {"M4A", "m4a", "ffmpeg", "", ""}},
	.Audio   = {{"MP3", "mp3", "ffmpeg", "", ""}, {"FLAC", "flac", "ffmpeg", "", ""}, {"OGG", "ogg", "ffmpeg", "", ""}, {"WAV", "wav", "ffmpeg", "", ""},
	            {"M4A", "m4a", "ffmpeg", "", ""}, {"OPUS", "opus", "ffmpeg", "", ""}},
	.Doc     = {{"PDF", "pdf", "soffice", "", ""}, {"DOCX", "docx", "pandoc", "", ""}, {"HTML", "html", "pandoc", "", ""}, {"MD", "md", "pandoc", "", ""},
	            {"EPUB", "epub", "pandoc", "", ""}, {"ODT", "odt", "pandoc", "", ""}, {"TXT", "txt", "pandoc", "", ""}},
	.Office  = {{"PDF", "pdf", "soffice", "", ""}},
	.Archive = {{"ZIP", "zip", "bsdtar", "", ""}, {"TAR.GZ", "tar.gz", "bsdtar", "", ""}, {"TAR.XZ", "tar.xz", "bsdtar", "", ""}, {"7Z", "7z", "bsdtar", "", ""}},
}

// Back face of the donut (Tab / wheel flips it): edits that keep the format.
ZIP_ALL :: Target{"ZIPにまとめる", "zip", "zip_all", "", ""}
TOOLS := [Cat][]Target {
	.None    = {ZIP_ALL},
	.Image   = {{"右に回転", "", "ffmpeg", "-vf transpose=1", "_回転"}, {"左に回転", "", "ffmpeg", "-vf transpose=2", "_回転"},
	            {"左右反転", "", "ffmpeg", "-vf hflip", "_反転"}, {"白黒", "", "ffmpeg", "-vf format=gray", "_白黒"},
	            {"半分に縮小", "", "ffmpeg", "-vf scale=iw/2:-2", "_縮小"}, {"正方形", "", "ffmpeg", "-vf crop=min(iw\\,ih):min(iw\\,ih)", "_正方形"}, ZIP_ALL},
	.Video   = {{"右に回転", "", "ffmpeg", "-vf transpose=1", "_回転"}, {"左右反転", "", "ffmpeg", "-vf hflip", "_反転"},
	            {"音声を削除", "", "ffmpeg", "-an -c:v copy", "_無音"}, {"半分に縮小", "", "ffmpeg", "-vf scale=iw/2:-2", "_縮小"},
	            {"最初の10秒", "", "ffmpeg", "-t 10", "_10秒"}, ZIP_ALL},
	.Audio   = {{"音量を整える", "", "ffmpeg", "-af loudnorm", "_正規化"}, {"モノラル", "", "ffmpeg", "-ac 1", "_モノラル"},
	            {"最初の30秒", "", "ffmpeg", "-t 30", "_30秒"}, ZIP_ALL},
	.Doc     = {ZIP_ALL},
	.Office  = {ZIP_ALL},
	.Archive = {ZIP_ALL},
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

convert_cmd :: proc(t: Target, src, dst: string, prog_path := "-") -> []string {
	switch t.tool {
	case "ffmpeg":
		args := make([dynamic]string, context.temp_allocator)
		// -progress feeds the real progress ring; "Duration:" comes from the info-level log
		append(&args, "ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-v", "info", "-n", "-progress", prog_path, "-i", src)
		switch t.ext {
		case "gif": if cat_of(src) == .Video do append(&args, "-vf", "fps=12,scale='min(640,iw)':-1")
		case "mp3", "m4a": append(&args, "-vn")
		case "jpg": append(&args, "-q:v", "2")
		case "ico": append(&args, "-vf", "scale='min(256,iw)':'min(256,ih)':force_original_aspect_ratio=decrease")
		}
		for a in strings.fields(t.args, context.temp_allocator) do append(&args, a)
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

// Starts one conversion (or back-face tool) job per file; output goes next to each source.
convert_files :: proc(t: Target, names: []string) {
	if t.tool == "zip_all" {
		compress(filepath.base(unique_dest(app.cwd, "アーカイブ.zip")))
		return
	}
	started := 0
	for name in names {
		stem, ext := file_ext(name)
		if t.suffix == "" && same_ext(ext, t.ext) do continue
		out_ext := t.ext
		if out_ext == "" do out_ext = "png" if ext == "heic" || ext == "heif" else ext // ffmpeg can't write HEIC
		src := name if filepath.is_abs(name) else full_path(name)
		dir := filepath.dir(src)
		base := strings.concatenate({filepath.base(stem), t.suffix, ".", out_ext}, context.temp_allocator)
		dst := unique_dest(dir, base)
		if t.tool == "soffice" {
			// LibreOffice picks the output name itself: never let it overwrite
			dst, _ = filepath.join({dir, base}, context.temp_allocator)
			if os.exists(dst) {
				toastf("「%s」は既にあります", filepath.base(dst))
				continue
			}
		}
		job := Job{kind = .Convert, label = strings.clone(filepath.base(dst)), src = strings.clone(name), dest = strings.clone(dst)}
		log := ""
		if t.tool == "ffmpeg" {
			job.prog_path = strings.clone(tmp_path("prog"))
			job.log_path = strings.clone(tmp_path("log"))
			log = job.log_path
		}
		job.pid = spawn(convert_cmd(t, src, dst, job.prog_path if job.prog_path != "" else "-"), dir, log)
		if job.pid == 0 {
			free_job(job)
			continue
		}
		// shortcut: all files convert in parallel; queue them if huge batches overload the CPU
		append(&jobs, job)
		started += 1
	}
	if started == 1 do toastf("%s を実行しています…", t.label)
	else if started > 1 do toastf("%d 個のファイルに「%s」を実行しています…", started, t.label)
}

@(private = "file") tmp_seq: int

tmp_path :: proc(ext: string) -> string {
	dir := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if dir == "" do dir = "/tmp"
	tmp_seq += 1
	p, _ := filepath.join({dir, strings.concatenate({"ame-filemanager-", itoa_tmp(int(posix.getpid())), "-", itoa_tmp(tmp_seq), ".", ext}, context.temp_allocator)}, context.temp_allocator)
	return p
}

// Reads ffmpeg's log (for the duration) and -progress output (for the position).
update_progress :: proc() {
	for &j in jobs {
		if j.kind != .Convert || j.prog_path == "" do continue
		if j.duration_us == 0 {
			if data, err := os.read_entire_file_from_path(j.log_path, context.temp_allocator); err == nil {
				if i := strings.index(string(data), "Duration: "); i >= 0 && i + 21 <= len(data) {
					t := string(data[i + 10:i + 21]) // HH:MM:SS.cc
					h, m, sec := parse_int(t[0:2]), parse_int(t[3:5]), parse_int(t[6:8])
					cs := parse_int(t[9:11])
					j.duration_us = (i64(h) * 3600 + i64(m) * 60 + i64(sec)) * 1_000_000 + i64(cs) * 10_000
					if j.duration_us == 0 do j.duration_us = -1
				}
			}
		}
		if j.duration_us <= 0 do continue
		if data, err := os.read_entire_file_from_path(j.prog_path, context.temp_allocator); err == nil {
			s := string(data)
			if i := strings.last_index(s, "out_time_us="); i >= 0 {
				rest := s[i + 12:]
				if e := strings.index_byte(rest, '\n'); e >= 0 do rest = rest[:e]
				j.frac = clamp(f32(parse_int(rest)) / f32(j.duration_us), 0, 1)
			}
		}
	}
}

@(private = "file")
parse_int :: proc(s: string) -> int {
	n := 0
	for ch in s {
		if ch < '0' || ch > '9' do break
		n = n * 10 + int(ch - '0')
	}
	return n
}

// -1 = not converting; 0..1 = progress; 2 = running with unknown progress.
converting :: proc(name: string) -> f32 {
	for j in jobs do if j.kind == .Convert && j.src == name do return j.frac if j.frac > 0 else 2
	return -1
}

// ---------------------------------------------------------------------------
// Donut menu

Donut :: struct {
	open, closing, drag: bool,
	t0:                  f32,
	c:                   [2]f32,
	targets:             [dynamic]Target, // front face: formats
	tools:               [dynamic]Target, // back face: edits
	back:                bool,
	flip_t0:             f32,
	rule:                bool, // choosing a format for a folder's auto-conversion
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
	clear(&dn.tools)
	for t in TOOLS[cat] do if t.tool == "zip_all" || have_tool(t.tool) do append(&dn.tools, t)
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
	dn.rule, dn.back = false, len(dn.targets) == 0 // nothing to convert to: open on the tools side
	if len(dn.targets) == 0 && len(dn.tools) == 0 do return
	donut_show(x, y, drag)
}

// Donut for choosing a folder's auto-convert format (every format any engine can make).
donut_open_rule :: proc(x, y: f32) {
	clear(&dn.targets)
	clear(&dn.tools)
	for f in dn.files do delete(f)
	clear(&dn.files)
	for cat in ([]Cat{.Image, .Video, .Audio, .Doc, .Office}) {
		outer: for t in TARGETS[cat] {
			if !have_tool(t.tool) || len(dn.targets) >= len(dn.grow) do continue
			for u in dn.targets do if u.label == t.label do continue outer
			append(&dn.targets, t)
		}
	}
	if len(dn.targets) == 0 do return
	dn.rule, dn.back = true, false
	donut_show(x, y, false)
}

@(private = "file")
donut_show :: proc(x, y: f32, drag: bool) {
	W, H := f32(cv.w), f32(cv.h)
	m := px(150)
	dn.c = {clamp(x, m, max(m, W - m)), clamp(y, m, max(m, H - m))}
	dn.open, dn.closing, dn.drag = true, false, drag
	dn.t0, dn.hover, dn.chosen = now_s(), -1, -1
	dn.grow = {}
}

face :: proc() -> []Target {return dn.tools[:] if dn.back else dn.targets[:]}

donut_flip :: proc() {
	if dn.rule || len(dn.tools) == 0 || len(dn.targets) == 0 do return
	dn.back = !dn.back
	dn.flip_t0 = now_s()
	dn.hover = -1
	dn.grow = {}
}

donut_choose :: proc(i: int) {
	f := face()
	if i >= 0 && i < len(f) {
		if dn.rule do add_rule(app.cwd, f[i])
		else do convert_files(f[i], dn.files[:])
	}
	dn.chosen = i
	dn.closing, dn.t0 = true, now_s()
}

donut_key :: proc(key: u32) -> bool {
	n := len(face())
	switch key {
	case K_ESCAPE:              donut_choose(-1)
	case K_TAB:                 donut_flip()
	case K_LEFT, K_UP:          dn.hover = (max(dn.hover, 0) - 1 + n) % n
	case K_RIGHT, K_DOWN:       dn.hover = (dn.hover + 1) % n
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

	if app.wheel != 0 && !dn.closing do donut_flip()
	// flip: the ring collapses, turns, and opens on the other face
	fp := clamp((app.now - dn.flip_t0) / 0.36, 0, 1)
	if fp < 1 do app.animating = true
	squash := abs(math.cos(fp * math.PI))
	targets := face()
	if fp < 0.5 do targets = dn.targets[:] if dn.back else dn.tools[:] // still showing the old face
	n := len(targets)
	if n == 0 do return
	step := 2 * math.PI / f32(n)
	spin := (1 - p) * -0.9 + fp * math.PI // swirls into place
	r0 := px(50) * (0.6 + 0.4 * p) * (0.5 + 0.5 * squash)
	r1 := px(128) * (0.55 + 0.45 * p) * (0.35 + 0.65 * squash)
	cx, cy := dn.c.x, dn.c.y

	// hover: which slice is under the pointer
	if !dn.closing && fp >= 1 {
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
		col := hex(0x2a1f38, 245) if dn.back else hex(0x1b2133, 245)
		if g > 0 do col = mix(col, with_alpha(ACCENT, 245), g)
		ring_seg(cx, cy, r0, ro, mid - step / 2 + gap, mid + step / 2 - gap, col)
		lr := (r0 + ro) / 2
		lx, ly := cx + math.cos(mid) * lr, cy + math.sin(mid) * lr
		size := fs(13 + 2 * g)
		label := targets[i].label
		tw := f32(text_width(label, size, true))
		asc, dsc := font_metrics(size)
		text(lx - tw / 2, ly + f32(asc - dsc) / 2, label, size, mix(FG, hex(0x060913), g), true)
	}
	// center disc
	ring_seg(cx, cy, 0, r0 - px(6), 0, 2 * math.PI, hex(0x10141f, 250))
	center := "自動変換" if dn.rule else ("ツール" if dn.back else "変換")
	if dn.hover >= 0 && dn.hover < n do center = strings.concatenate({"→ ", targets[dn.hover].label}, context.temp_allocator)
	size := fs(14)
	tw := f32(text_width(center, size, true))
	text(cx - tw / 2, cy + px(1), center, size, FG, true)
	sub := "このフォルダー" if dn.rule else fmt_count(len(dn.files))
	if !dn.rule && len(dn.tools) > 0 && len(dn.targets) > 0 do sub = strings.concatenate({sub, " · Tab で裏返す"}, context.temp_allocator)
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

// Progress ring around an icon while it converts (frac > 1 = unknown: spinning arc).
progress_ring :: proc(r: Rect, frac: f32) {
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	rad := max(r.w, r.h) / 2 + px(4)
	ring_seg(cx, cy, rad - px(3), rad, 0, 2 * math.PI, hex(0xffffff, 30))
	app.animating = true
	if frac <= 1 {
		ring_seg(cx, cy, rad - px(3), rad, -math.PI / 2, -math.PI / 2 + max(frac, 0.02) * 2 * math.PI, ACCENT)
		pct := strings.concatenate({itoa_tmp(int(frac * 100)), "%"}, context.temp_allocator)
		pw := f32(text_width(pct, fs(10), true))
		rrect({cx - pw / 2 - px(5), r.y + r.h - px(4), pw + px(10), px(16)}, px(8), with_alpha(ACCENT, 230))
		text(cx - pw / 2, r.y + r.h + px(8), pct, fs(10), hex(0x060913), true)
		return
	}
	a := app.now * 5
	ring_seg(cx, cy, rad - px(3), rad, a, a + 1.6 + math.sin(app.now * 3) * 0.6, ACCENT)
}

// ---------------------------------------------------------------------------
// Auto-convert folders (Filee's "watch"): files arriving in the folder are converted.

Rule :: struct {
	dir:     string,
	target:  Target,
	seen:    map[string]bool,
	scan_at: i64,
}
rules: [dynamic]Rule

@(private = "file")
rules_file :: proc() -> string {
	p, _ := filepath.join({app_config_dir(), "watch.conf"}, context.temp_allocator)
	return p
}

@(private = "file")
snapshot :: proc(r: ^Rule) {
	infos, err := os.read_all_directory_by_path(r.dir, context.temp_allocator)
	if err != nil do return
	for fi in infos do if fi.name not_in r.seen do r.seen[strings.clone(fi.name)] = true
}

@(private = "file")
find_target :: proc(ext: string) -> (Target, bool) {
	for cat in Cat do for t in TARGETS[cat] do if t.ext == ext && have_tool(t.tool) do return t, true
	return {}, false
}

load_rules :: proc() {
	data, err := os.read_entire_file_from_path(rules_file(), context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		dir, _, ext := strings.partition(line, "\t")
		t, ok := find_target(ext)
		if !ok || !os.is_dir(dir) do continue
		r := Rule{dir = strings.clone(dir), target = t}
		snapshot(&r)
		append(&rules, r)
	}
}

@(private = "file")
save_rules :: proc() {
	b := strings.builder_make(context.temp_allocator)
	for r in rules {
		strings.write_string(&b, r.dir)
		strings.write_byte(&b, '\t')
		strings.write_string(&b, r.target.ext)
		strings.write_byte(&b, '\n')
	}
	p := rules_file()
	_ = os.make_directory_all(filepath.dir(p))
	_ = os.write_entire_file_from_string(p, strings.to_string(b))
}

rule_for :: proc(dir: string) -> ^Rule {
	for &r in rules do if r.dir == dir do return &r
	return nil
}

add_rule :: proc(dir: string, t: Target) {
	remove_rule(dir, false)
	r := Rule{dir = strings.clone(dir), target = t}
	snapshot(&r) // only files arriving from now on
	append(&rules, r)
	save_rules()
	toastf("このフォルダーに入ったファイルを自動で %s に変換します", t.label)
}

remove_rule :: proc(dir: string, announce := true) {
	for r, i in rules {
		if r.dir != dir do continue
		for k in r.seen do delete(k)
		delete(r.seen)
		delete(r.dir)
		ordered_remove(&rules, i)
		save_rules()
		if announce do toastf("自動変換を停止しました")
		return
	}
}

rule_dir_changed :: proc(dir: string) {
	if r := rule_for(dir); r != nil do r.scan_at = ticks_ms() + 1500 // wait for writes to settle
}

rules_deadline :: proc() -> i64 {
	d: i64
	for r in rules do if r.scan_at != 0 && (d == 0 || r.scan_at < d) do d = r.scan_at
	return d
}

// Converts files that appeared in watched folders. True if something started.
rules_tick :: proc() -> bool {
	started := false
	now := ticks_ms()
	for &r in rules {
		if r.scan_at == 0 || now < r.scan_at do continue
		r.scan_at = 0
		infos, err := os.read_all_directory_by_path(r.dir, context.temp_allocator)
		if err != nil do continue
		for fi in infos {
			if fi.name in r.seen do continue
			r.seen[strings.clone(fi.name)] = true
			if fi.type != .Regular do continue
			_, ext := file_ext(fi.name)
			if same_ext(ext, r.target.ext) do continue
			// the target must be one this file's category can produce
			for t in TARGETS[cat_of(fi.name)] {
				if t.ext == r.target.ext && have_tool(t.tool) {
					convert_files(t, {fi.fullpath})
					started = true
					break
				}
			}
		}
	}
	return started
}
