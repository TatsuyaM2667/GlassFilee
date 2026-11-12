package main

// Music player in the style of Apple Music:
// - one click on a song plays it; the queue becomes every song in the folder and its
//   subfolders (gathered on a worker thread, so playback starts at once)
// - a mini player at the bottom (shuffle / repeat / seek / equalizer)
// - click it for the full "Now Playing" view: big art over a blurred backdrop,
//   large controls and the Up Next queue
// Playback runs in ffplay (no window): SIGSTOP/SIGCONT pause it, seeking restarts it.

import "core:fmt"
import "core:image"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:thread"

I_PLAY :: 0xf04b
I_PAUSE :: 0xf04c
I_PREV :: 0xf048
I_NEXT :: 0xf051
I_STOP :: 0xf00d
I_SHUFFLE :: 0xf074
I_REPEAT :: 0xf01e
I_CHEVRON_DOWN_BIG :: 0xf107

PLAYER_H :: 84
MAX_QUEUE :: 5000

// media keys (XF86Audio*)
K_AUDIO_PLAY :: 0x1008ff14
K_AUDIO_STOP :: 0x1008ff15
K_AUDIO_PREV :: 0x1008ff16
K_AUDIO_NEXT :: 0x1008ff17
K_AUDIO_PAUSE :: 0x1008ff31

Repeat :: enum {
	Off, All, One,
}

@(private = "file")
Meta :: struct {
	path:                 string,
	duration:             f64,
	title, artist, album: string,
	cover:                []u32,
	cw, ch:               int,
	blur:                 [16 * 16]u32, // tiny cover average: upscaled, it is the blurred backdrop
	done:                 bool,
	th:                   ^thread.Thread,
}

@(private = "file")
Scan :: struct {
	root:  string,
	paths: [dynamic]string,
	done:  bool,
	th:    ^thread.Thread,
}

Music :: struct {
	list:      [dynamic]string, // queue in folder order (absolute paths)
	order:     [dynamic]int, // play order (shuffled or 0..n)
	pos:       int, // index into order
	shuffle:   bool,
	repeat:    Repeat,
	pid:       posix.pid_t,
	paused:    bool,
	start_ms:  i64, // wall clock when position 0 would have been
	paused_at: f64,
	meta:      ^Meta,
	scan:      ^Scan,
	bar_t0:    f32,
	shown:     bool,
	full:      bool, // "Now Playing" view
	full_t0:   f32,
	art_scale: f32, // the big art shrinks a little while paused, like Apple Music
	panel_open: bool, // lyrics / Up Next shown (narrow layout: the art becomes a thumbnail)
	panel_k:   f32, // animated 0..1 for that transition
	q_scroll:  f32,
}
mu: Music

is_audio :: proc(e: Entry) -> bool {return !e.is_dir && cat_of(e.name) == .Audio}

// At least two songs, and songs are most of the files (covers/playlists don't count).
is_music_folder :: proc() -> bool {
	songs, files := 0, 0
	for e in app.entries[:app.base_count] {
		if e.is_dir || e.hidden do continue
		if is_audio(e) do songs += 1
		else if e.kind != .Image && e.kind != .Text do files += 1
	}
	return songs >= 2 && songs > files
}

music_playing :: proc() -> bool {return mu.pid != 0}

music_current :: proc() -> string {
	if len(mu.order) == 0 || mu.pos >= len(mu.order) do return ""
	return mu.list[mu.order[mu.pos]]
}

music_pos :: proc() -> f64 {
	if mu.paused || mu.pid == 0 do return mu.paused_at
	return f64(ticks_ms() - mu.start_ms) / 1000
}

// ---------------------------------------------------------------------------
// Queue

@(private = "file")
set_queue :: proc(paths: []string, current: string) {
	for p in mu.list do delete(p)
	clear(&mu.list)
	for p in paths do append(&mu.list, strings.clone(p))
	cur := 0
	for p, i in mu.list do if p == current {cur = i; break}
	rebuild_order(cur)
}

// Play order: current song first when shuffling, otherwise folder order.
@(private = "file")
rebuild_order :: proc(cur: int) {
	clear(&mu.order)
	for i in 0 ..< len(mu.list) do append(&mu.order, i)
	if mu.shuffle && len(mu.order) > 1 {
		rand.shuffle(mu.order[:])
		for v, i in mu.order do if v == cur {mu.order[0], mu.order[i] = mu.order[i], mu.order[0]; break}
		mu.pos = 0
	} else {
		mu.pos = cur
	}
}

music_set_shuffle :: proc(on: bool) {
	if len(mu.order) == 0 {
		mu.shuffle = on
		return
	}
	cur := mu.order[mu.pos]
	mu.shuffle = on
	rebuild_order(cur)
}

@(private = "file")
scan_worker :: proc(s: ^Scan) {
	defer {
		sync.atomic_store(&s.done, true)
		wake()
	}
	walk :: proc(dir: string, s: ^Scan) {
		infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil do return
		subdirs := make([dynamic]string, context.temp_allocator)
		for fi in infos {
			if len(s.paths) >= MAX_QUEUE do return
			if strings.has_prefix(fi.name, ".") do continue
			if fi.type == .Directory do append(&subdirs, fi.fullpath) // symlinks are not followed
			else if cat_of(fi.name) == .Audio do append(&s.paths, strings.clone(fi.fullpath))
		}
		for d in subdirs do walk(d, s)
	}
	walk(s.root, s)
	slice.sort_by(s.paths[:], natural_less) // folder by folder, track numbers in order
	free_all(context.temp_allocator)
}

@(private = "file")
scan_free :: proc() {
	s := mu.scan
	if s == nil do return
	thread.join(s.th)
	thread.destroy(s.th)
	for p in s.paths do delete(p)
	delete(s.paths)
	delete(s.root)
	free(s)
	mu.scan = nil
}

// Called from the main loop: swaps in the full queue when the scan finishes.
music_poll :: proc() -> bool {
	s := mu.scan
	if s == nil || !sync.atomic_load(&s.done) do return video_fresh()
	if md.pending_dir {
		// folder play: the queue is ready, start from its first song
		md.pending_dir = false
		if len(s.paths) == 0 {
			toastf("音楽ファイルが見つかりません")
		} else {
			set_queue(s.paths[:], s.paths[0])
			music_start(0)
		}
	} else {
		cur := strings.clone(music_current(), context.temp_allocator)
		if len(s.paths) > 0 do set_queue(s.paths[:], cur)
	}
	scan_free()
	return true
}

// Collects every song under root on a worker thread (music_poll picks it up).
music_scan :: proc(root: string) {
	scan_free()
	s := new(Scan)
	s.root = strings.clone(root)
	s.th = thread.create_and_start_with_poly_data(s, scan_worker)
	mu.scan = s
}

// Plays entry vi now; the queue grows to the whole folder tree in the background.
music_play_entry :: proc(vi: int) {
	if !have_tool("ffplay") {
		toastf("再生には ffplay（ffmpeg）が必要です")
		return
	}
	path := full_path(app.entries[vi].name)
	if path == music_current() {
		if mu.pid == 0 || mu.paused do music_toggle() // clicking the current song resumes it
		return
	}
	set_queue({path}, path)
	music_start(0)
	md.pending_dir = false
	music_scan(app.cwd if !is_tag_view() else filepath.dir(path))
}

// "すべて再生": the first song of the folder (tree).
music_play_folder :: proc(_: int) {
	for vi in app.view do if is_audio(app.entries[vi]) {
		music_play_entry(vi)
		return
	}
}

music_start :: proc(offset: f64) {
	music_kill()
	path := music_current()
	if path == "" do return
	pid := spawn({"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-ss", fmt.tprintf("%.2f", offset), path})
	if pid == 0 do return
	mu.pid = pid
	mu.paused = false
	mu.start_ms = ticks_ms() - i64(offset * 1000)
	mu.paused_at = offset
	media_track_started(path, offset)
	if mu.meta == nil || mu.meta.path != path {
		meta_free()
		m := new(Meta)
		m.path = strings.clone(path)
		m.th = thread.create_and_start_with_poly_data(m, meta_worker)
		mu.meta = m
	}
}

// Stops the player process (a stopped process must be continued to receive the signal).
music_kill :: proc() {
	video_stop()
	if mu.pid == 0 do return
	pid := mu.pid
	mu.pid = 0 // reap_jobs must not treat this exit as "song finished"
	posix.kill(pid, .SIGCONT)
	posix.kill(pid, .SIGTERM)
	status: i32
	posix.waitpid(pid, &status, {})
}

music_stop :: proc() {
	music_kill()
	scan_free()
	meta_free()
	for p in mu.list do delete(p)
	clear(&mu.list)
	clear(&mu.order)
	mu.full = false
	mu.paused = false
}

music_toggle :: proc() {
	if len(mu.order) == 0 do return
	if mu.pid == 0 {
		music_start(mu.paused_at)
		return
	}
	if mu.paused {
		posix.kill(mu.pid, .SIGCONT)
		mu.start_ms = ticks_ms() - i64(mu.paused_at * 1000)
		mu.paused = false
	} else {
		mu.paused_at = music_pos()
		posix.kill(mu.pid, .SIGSTOP)
		mu.paused = true
	}
	video_pause(mu.paused)
}

// d = +1 next / -1 previous; auto = the song ended by itself.
music_step :: proc(d: int, auto := false) {
	n := len(mu.order)
	if n == 0 do return
	if auto && mu.repeat == .One {
		music_start(0)
		return
	}
	if d < 0 && music_pos() > 3 {
		music_start(0) // "previous" restarts the song first
		return
	}
	next := mu.pos + d
	if next >= n || next < 0 {
		if mu.repeat != .All && auto {
			// end of the queue: stay on the last song, stopped at its end
			mu.paused_at = 0
			mu.paused = false
			return
		}
		next = (next + n) % n
	}
	mu.pos = next
	music_start(0)
}

music_seek :: proc(t: f64) {
	if len(mu.order) == 0 do return
	if mu.paused {
		mu.paused_at = max(t, 0)
		music_kill()
		mu.paused = true
		return
	}
	music_start(max(t, 0))
}

// Called by reap_jobs for every exited child; true if it was the player.
music_child_exited :: proc(pid: posix.pid_t) -> bool {
	if pid != mu.pid || pid == 0 do return false
	mu.pid = 0
	music_step(1, true)
	return true
}

// Keys while the Now Playing view is open (and media keys everywhere).
music_key :: proc(key: u32) -> bool {
	switch key {
	case K_AUDIO_PLAY, K_AUDIO_PAUSE: music_toggle(); return true
	case K_AUDIO_NEXT: music_step(1); return true
	case K_AUDIO_PREV: music_step(-1); return true
	case K_AUDIO_STOP: music_stop(); return true
	}
	if !mu.full do return false
	switch key {
	case K_ESCAPE:       mu.full = false
	case K_SPACE:        music_toggle()
	case K_RIGHT:        music_seek(music_pos() + 10)
	case K_LEFT:         music_seek(music_pos() - 10)
	case K_DOWN, K_UP:   music_step(1 if key == K_DOWN else -1)
	}
	return true
}

// ---------------------------------------------------------------------------
// Metadata (ffprobe) and cover art (folder image or embedded art), on a thread

@(private = "file")
meta_free :: proc() {
	m := mu.meta
	if m == nil do return
	thread.join(m.th)
	thread.destroy(m.th)
	delete(m.path)
	delete(m.title)
	delete(m.artist)
	delete(m.album)
	delete(m.cover)
	free(m)
	mu.meta = nil
	// caches keyed by this Meta must not match a future one at the same address
	bd.key, art.key = nil, nil
}

@(private = "file")
meta_worker :: proc(m: ^Meta) {
	defer {
		sync.atomic_store(&m.done, true)
		wake()
	}
	_, out, _, err := os.process_exec({command = {"ffprobe", "-v", "error", "-show_entries", "format=duration:format_tags=title,artist,album", "-of", "default=nw=1", m.path}}, context.temp_allocator)
	if err == nil {
		text := string(out)
		for line in strings.split_lines_iterator(&text) {
			k, _, v := strings.partition(line, "=")
			switch strings.to_lower(k, context.temp_allocator) {
			case "duration":   m.duration, _ = strconv.parse_f64(v)
			case "tag:title":  m.title = strings.clone(v)
			case "tag:artist": m.artist = strings.clone(v)
			case "tag:album":  m.album = strings.clone(v)
			}
		}
	}
	src := m.path
	for name in ([]string{"cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "Cover.jpg", "Folder.jpg", "AlbumArt.jpg"}) {
		p, _ := filepath.join({filepath.dir(m.path), name}, context.temp_allocator)
		if os.exists(p) {src = p; break}
	}
	_, img_bytes, _, ierr := os.process_exec({command = {"ffmpeg", "-v", "error", "-nostdin", "-i", src, "-an", "-frames:v", "1", "-vf", "scale=400:400:force_original_aspect_ratio=increase,crop=400:400", "-f", "image2pipe", "-vcodec", "ppm", "-"}}, context.temp_allocator)
	if ierr == nil && len(img_bytes) > 0 {
		// the PPM decoder returns RGB (3 channels) even when asked to add alpha
		if img, e := image.load_from_bytes(img_bytes, {.alpha_add_if_missing}, context.temp_allocator); e == nil && img.depth == 8 && img.channels >= 3 {
			m.cw, m.ch = img.width, img.height
			m.cover = make([]u32, m.cw * m.ch)
			px := img.pixels.buf[:]
			ch := img.channels
			for i in 0 ..< m.cw * m.ch {
				m.cover[i] = 0xff000000 | u32(px[i * ch]) << 16 | u32(px[i * ch + 1]) << 8 | u32(px[i * ch + 2])
			}
			// 16×16 block averages: upscaled smoothly, this reads as a heavy blur
			bw, bh := m.cw / 16, m.ch / 16
			for by in 0 ..< 16 do for bx in 0 ..< 16 {
				r, g, b: int
				for y in 0 ..< bh do for x in 0 ..< bw {
					c := m.cover[(by * bh + y) * m.cw + bx * bw + x]
					r += int(c >> 16 & 255); g += int(c >> 8 & 255); b += int(c & 255)
				}
				n := max(bw * bh, 1)
				m.blur[by * 16 + bx] = 0xff000000 | u32(r / n) << 16 | u32(g / n) << 8 | u32(b / n)
			}
		}
	}
	free_all(context.temp_allocator)
}

@(private = "file")
fmt_time :: proc(t: f64) -> string {
	s := int(max(t, 0))
	return fmt.tprintf("%d:%02d", s / 60, s % 60)
}

@(private = "file")
song_title :: proc() -> (title, sub: string) {
	m := mu.meta
	ready := m != nil && sync.atomic_load(&m.done)
	title = filepath.stem(music_current())
	if ready && m.title != "" do title = m.title
	sub = filepath.base(filepath.dir(music_current()))
	if ready && m.artist != "" do sub = m.artist
	if ready && m.album != "" do sub = strings.concatenate({sub, " — ", m.album}, context.temp_allocator)
	return
}

// Blurred-art backdrop, composited once per cover and size (blur, darkening, bottom
// gradient), then just blended each frame.
@(private = "file") bd: struct {
	px:   []u32,
	w, h: int,
	key:  rawptr,
}

@(private = "file")
backdrop :: proc(r: Rect, m: ^Meta) {
	w, h := int(r.w), int(r.h)
	if bd.key != m || bd.w != w || bd.h != h {
		delete(bd.px)
		bd.px = scale_image(m.blur[:], 16, 16, w, h)
		bd.w, bd.h, bd.key = w, h, m
		for y in 0 ..< h {
			// layers: art at 88 %, black 41 %, then a darkening ramp on the lower half
			t := clamp((f32(y) / f32(h) - 0.45) / 0.55, 0, 1)
			g := t * t * 0.43
			keep := 0.88 * (1 - 0.41) * (1 - g)
			alpha := 1 - (1 - 0.88) * (1 - 0.41) * (1 - g)
			a8 := u32(alpha * 255)
			row := bd.px[y * w:][:w]
			for &c in row {
				rr := u32(f32((c >> 16) & 255) * keep)
				gg := u32(f32((c >> 8) & 255) * keep)
				bb := u32(f32(c & 255) * keep)
				c = a8 << 24 | rr << 16 | gg << 8 | bb
			}
		}
	}
	blit_image(r.x, r.y, bd.px, bd.w, bd.h)
}

@(private = "file") art: struct {
	px:   []u32,
	w, h: int,
	key:  rawptr,
}

@(private = "file")
cover_or_placeholder :: proc(r: Rect, radius: f32) {
	m := mu.meta
	if m != nil && sync.atomic_load(&m.done) && m.cover != nil {
		w, h := int(math.round(r.w)), int(math.round(r.h))
		if art.key == m && art.w == w && art.h == h {
			blit_image(r.x, r.y, art.px, w, h)
		} else if app.animating {
			blit_scaled(r, m.cover, m.cw, m.ch) // size still changing: sample directly
		} else {
			delete(art.px)
			art.px = scale_image(m.cover, m.cw, m.ch, w, h)
			art.w, art.h, art.key = w, h, m
			blit_image(r.x, r.y, art.px, w, h)
		}
		rrect(r, radius, hex(0xffffff, 30), px(1))
		return
	}
	rrect(r, radius, mix(with_alpha(ACCENT, 210), hex(0xcba6f7), 0.5 + 0.5 * f32(math.sin(app.now * 0.8))))
	glyph_center(r, I_MUSIC, i32(r.h * 0.36), hex(0x060913, 200))
}

// Small "now playing" bars drawn on the playing song's icon.
eq_badge :: proc(x, y, s: f32) {
	rrect({x - s * 0.1, y - s * 0.1, s * 1.2, s * 1.2}, s * 0.3, with_alpha(ACCENT, 235))
	playing := mu.pid != 0 && !mu.paused
	for i in 0 ..< 3 {
		h := s * 0.25
		if playing do h = s * (0.25 + 0.5 * (0.5 + 0.5 * math.sin(app.now * (7 + f32(i) * 2.3) + f32(i) * 1.9)))
		rrect({x + s * (0.15 + f32(i) * 0.27), y + s * 0.85 - h, s * 0.18, h}, s * 0.06, hex(0x060913))
	}
}

is_now_playing :: proc(name: string) -> bool {
	return len(mu.order) > 0 && full_path(name) == music_current()
}

// ---------------------------------------------------------------------------
// Mini player

// Height the player takes at the bottom of the content area (0 = hidden).
player_height :: proc() -> f32 {
	show := len(mu.order) > 0 || is_music_folder()
	if show && !mu.shown do mu.bar_t0 = now_s()
	mu.shown = show
	if !show || mu.full do return 0
	return px(PLAYER_H) * progress(mu.bar_t0, 0.3)
}

@(private = "file")
toggle_button :: proc(r: Rect, icon: rune, on: bool, badge := "") -> bool {
	hot(r)
	if hovering(r) do rrect(r, px(6), HOVER)
	glyph_center(r, icon, fs(13), ACCENT if on else DIM)
	if on do rrect({r.x + r.w / 2 - px(2), r.y + r.h - px(6), px(4), px(4)}, px(2), ACCENT)
	if badge != "" do text(r.x + r.w - px(9), r.y + px(12), badge, fs(9), ACCENT, true)
	return clicked(r)
}

draw_player :: proc(r: Rect) {
	if r.h <= 1 do return
	set_clip(r)
	defer reset_clip()
	fill(r, hex(0x0b0f1c, 150))
	fill({r.x, r.y, r.w, 1}, LINE)
	active := len(mu.order) > 0

	cs := px(60)
	cr := Rect{r.x + px(14), r.y + (px(PLAYER_H) - cs) / 2, cs, cs}
	tx := cr.x + cs + px(14)
	cx := r.x + r.w / 2
	info_w := max(cx - px(min(r.w * 0.18, 210) + 20) - tx, px(60))
	title, sub: string
	if active {
		cover_or_placeholder(cr, px(8))
		title, sub = song_title()
		sub = strings.concatenate({sub, fmt.tprintf("  ·  %d / %d", mu.pos + 1, len(mu.order))}, context.temp_allocator)
		if k := current_lyric(music_pos()); k >= 0 && md.lyrics[k].text != "" do sub = strings.concatenate({"♪ ", md.lyrics[k].text}, context.temp_allocator)
		if mu.scan != nil do sub = strings.concatenate({sub, " …"}, context.temp_allocator)
	} else {
		rrect(cr, px(8), mix(with_alpha(ACCENT, 210), hex(0xcba6f7), 0.5))
		glyph_center(cr, I_MUSIC, fs(22), hex(0x060913, 200))
		title = location_name()
		n := 0
		for e in app.entries[:app.base_count] do if is_audio(e) do n += 1
		sub = fmt.tprintf("%d 曲 · クリックで再生", n)
	}
	text(tx, r.y + px(36), ellipsize(title, fs(14), info_w, true), fs(14), FG, true)
	text(tx, r.y + px(58), ellipsize(sub, fs(12), info_w), fs(12), DIM)
	// the cover/title area opens Now Playing
	open_r := Rect{cr.x, cr.y, tx + info_w - cr.x, cs}
	if active && hovering(open_r) do rrect({open_r.x - px(4), open_r.y - px(4), open_r.w + px(8), open_r.h + px(8)}, px(10), hex(0xffffff, 10))
	if active && clicked(open_r) {
		mu.full, mu.full_t0 = true, now_s()
	}

	// controls
	cy := r.y + px(30)
	pb := Rect{cx - px(20), cy - px(20), px(40), px(40)}
	playing := music_playing() && !mu.paused
	rrect(pb, px(20), with_alpha(ACCENT, 255 if hovering(pb) else 225))
	glyph_center({pb.x + (0 if playing else px(2)), pb.y, pb.w, pb.h}, I_PAUSE if playing else I_PLAY, fs(15), hex(0x060913))
	if clicked(pb) {
		if active do music_toggle()
		else do music_play_folder(0)
	}
	if active {
		if icon_button({cx - px(66), cy - px(17), px(34), px(34)}, I_PREV) do music_step(-1)
		if icon_button({cx + px(32), cy - px(17), px(34), px(34)}, I_NEXT) do music_step(1)
		if toggle_button({cx - px(108), cy - px(15), px(30), px(30)}, I_SHUFFLE, mu.shuffle) do music_set_shuffle(!mu.shuffle)
		if toggle_button({cx + px(78), cy - px(15), px(30), px(30)}, I_REPEAT, mu.repeat != .Off, "1" if mu.repeat == .One else "") do mu.repeat = Repeat((int(mu.repeat) + 1) % 3)
		m := mu.meta
		dur := m.duration if m != nil && sync.atomic_load(&m.done) else 0
		bw := min(r.w * 0.36, px(420))
		seek_bar({cx - bw / 2, r.y + px(62), bw, px(4)}, dur, px(10))
	}

	// equalizer + stop
	right := r.x + r.w - px(14)
	if active {
		sb := Rect{right - px(34), r.y + (px(PLAYER_H) - px(34)) / 2, px(34), px(34)}
		if icon_button(sb, I_STOP) do music_stop()
		right -= px(46)
	}
	bars := 18
	ew := px(4)
	ex := right - f32(bars) * (ew + px(3))
	if ex > cx + px(130) do equalizer(ex, r.y + px(PLAYER_H) / 2 + px(20), bars, ew, px(40), playing)
}

@(private = "file")
equalizer :: proc(x, base_y: f32, bars: int, w, max_h: f32, playing: bool) {
	for i in 0 ..< bars {
		h := px(6)
		if playing {
			t := app.now
			fi := f32(i)
			v := 0.5 + 0.25 * math.sin(t * 6.1 + fi * 0.9) + 0.18 * math.sin(t * 9.7 + fi * 2.3) + 0.12 * math.sin(t * 3.3 - fi * 1.7)
			h = px(6) + clamp(v, 0, 1) * max_h
		}
		col := mix(ACCENT, hex(0xcba6f7), f32(i) / f32(bars))
		rrect({x + f32(i) * (w + px(3)), base_y - h, w, h}, px(2), col)
	}
}

@(private = "file")
seek_bar :: proc(bar: Rect, dur: f64, knob: f32) {
	pos := music_pos()
	rrect(bar, bar.h / 2, hex(0xffffff, 30))
	if dur > 0 {
		f := f32(clamp(pos / dur, 0, 1))
		rrect({bar.x, bar.y, bar.w * f, bar.h}, bar.h / 2, ACCENT)
		hit := Rect{bar.x, bar.y - px(8), bar.w, bar.h + px(16)}
		k := knob * (1.3 if hovering(hit) else 1)
		rrect({bar.x + bar.w * f - k / 2, bar.y + bar.h / 2 - k / 2, k, k}, k / 2, FG)
		if clicked(hit) do music_seek(f64((app.mx - bar.x) / bar.w) * dur)
	}
	text(bar.x - px(44), bar.y + px(5), fmt_time(pos), fs(11), DIM)
	if dur > 0 do text(bar.x + bar.w + px(10), bar.y + px(5), fmt_time(dur), fs(11), DIM)
}

// ---------------------------------------------------------------------------
// Now Playing (full view)

draw_now_playing :: proc(area: Rect) {
	if !mu.full || len(mu.order) == 0 {
		mu.full = false
		return
	}
	p := progress(mu.full_t0, 0.4)
	r := Rect{area.x, area.y + (1 - p) * area.h, area.w, area.h}
	set_clip(area)
	defer reset_clip()
	m := mu.meta
	ready := m != nil && sync.atomic_load(&m.done)

	// living backdrop: the blurred art drifts slowly behind everything, darker toward the bottom
	if ready && m.cover != nil {
		backdrop(r, m)
	} else {
		fill(r, hex(0x0b0f1c, 225))
	}

	// sheet grabber + close
	rrect({r.x + r.w / 2 - px(19), r.y + px(8), px(38), px(5)}, px(3), hex(0xffffff, 90))
	if icon_button({r.x + px(14), r.y + px(14), px(36), px(36)}, I_CHEVRON_DOWN_BIG) do mu.full = false

	wide := r.w > px(820)
	L := Rect{r.x, r.y, r.w * 0.46, r.h} if wide else r
	margin := px(36)
	colw := L.w - 2 * margin
	has_lyrics := len(md.lyrics) > 0

	// panel (lyrics / queue) slides the art into a thumbnail on narrow windows
	open_target: f32 = 1 if mu.panel_open && !wide else 0
	if d := open_target - mu.panel_k; abs(d) > 0.002 {
		mu.panel_k += d * (1 - math.exp(-app.dt * 10))
		app.animating = true
	} else do mu.panel_k = open_target
	k := ease_out(mu.panel_k)

	// bottom block, anchored to the bottom of the column (lifted below when the art is big)
	row_y := L.y + L.h - px(46) // bottom row of toggles
	ctl_y := row_y - px(78) // play / prev / next
	bar_y := ctl_y - px(58) // seek bar
	info_y := bar_y - px(62) // title / artist (big-art layout)

	// art (or music video), big ↔ thumbnail
	target: f32 = 1 if music_playing() && !mu.paused else 0.86
	if d := target - mu.art_scale; abs(d) > 0.002 {
		mu.art_scale += d * (1 - math.exp(-app.dt * 9))
		app.animating = true
	} else do mu.art_scale = target
	video_sync()
	avail_h := info_y - px(20) - (L.y + px(56))
	big_s := min(colw, avail_h, px(440))
	bw_, bh_ := big_s, big_s
	if md.mv != "" do bw_, bh_ = min(colw, avail_h * 16 / 9, px(640)), min(colw, avail_h * 16 / 9, px(640)) * 9 / 16
	bw_, bh_ = bw_ * mu.art_scale, bh_ * mu.art_scale
	big := Rect{L.x + (L.w - bw_) / 2, L.y + px(56) + (avail_h - bh_) / 2, bw_, bh_}
	// with the art big, art + text + controls sit together, centered; with a panel open
	// the controls stay at the bottom to leave room for lyrics / Up Next
	lift := max(avail_h - bh_, 0) * 0.5 * (1 - k)
	row_y -= lift
	ctl_y -= lift
	bar_y -= lift
	info_y -= lift
	small := Rect{L.x + margin, L.y + px(58), px(64) * (16.0 / 9 if md.mv != "" else 1), px(64)}
	art_r := lerp_rect(big, small, k)
	radius := px(12) - px(4) * k
	for i in 1 ..< 10 { // soft shadow: faint rings spreading out (rings: the art covers the middle)
		g := px(f32(i) * 3)
		rrect({art_r.x - g, art_r.y - g + px(14), art_r.w + 2 * g, art_r.h + 2 * g}, radius + g, hex(0x000000, 9), g + px(14))
	}
	if !draw_video(art_r) do cover_or_placeholder(art_r, radius)

	// text and seek bar line up with the art's edges while it is big (like Apple Music)
	cx0 := big.x + (L.x + margin - big.x) * k
	cw := big.w + (colw - big.w) * k
	// title / artist: under the big art_r, or next to the thumbnail
	title, sub := song_title()
	if k < 0.99 {
		draw_alpha = u32((1 - k) * 255)
		text(cx0, info_y + px(22), ellipsize(title, fs(22), cw, true), fs(22), FG, true)
		text(cx0, info_y + px(48), ellipsize(sub, fs(16), cw), fs(16), with_alpha(FG, 165))
		draw_alpha = 255
	}
	if k > 0.01 {
		draw_alpha = u32(k * 255)
		tx := small.x + small.w + px(14)
		text(tx, small.y + px(28), ellipsize(title, fs(17), L.x + L.w - margin - tx, true), fs(17), FG, true)
		text(tx, small.y + px(50), ellipsize(sub, fs(14), L.x + L.w - margin - tx), fs(14), with_alpha(FG, 165))
		draw_alpha = 255
	}

	// seek bar: thin, knob only on hover; elapsed and remaining time under it
	dur := m.duration if ready else 0
	pos := music_pos()
	bar := Rect{cx0, bar_y, cw, px(5)}
	hit := Rect{bar.x, bar.y - px(10), bar.w, bar.h + px(20)}
	hov := hovering(hit)
	if hov do bar = {bar.x, bar.y - px(1.5), bar.w, px(8)}
	rrect(bar, bar.h / 2, hex(0xffffff, 55))
	if dur > 0 {
		f := f32(clamp(pos / dur, 0, 1))
		rrect({bar.x, bar.y, max(bar.w * f, bar.h), bar.h}, bar.h / 2, hex(0xffffff, 225))
		if hov do rrect({bar.x + bar.w * f - px(7), bar.y + bar.h / 2 - px(7), px(14), px(14)}, px(7), FG)
		if clicked(hit) do music_seek(f64((app.mx - bar.x) / bar.w) * dur)
	}
	text(bar.x, bar_y + px(26), fmt_time(pos), fs(12), with_alpha(FG, 150), true)
	if dur > 0 {
		rem := strings.concatenate({"-", fmt_time(dur - pos)}, context.temp_allocator)
		text(bar.x + bar.w - f32(text_width(rem, fs(12), true)), bar_y + px(26), rem, fs(12), with_alpha(FG, 150), true)
	}

	// transport: plain big glyphs, a soft circle on hover
	playing := music_playing() && !mu.paused
	ccx := L.x + L.w / 2
	glyph_btn :: proc(c: [2]f32, rad: f32, icon: rune, size: i32) -> bool {
		r := Rect{c.x - rad, c.y - rad, 2 * rad, 2 * rad}
		if hovering(r) do rrect(r, rad, hex(0xffffff, app.held ? 40 : 22))
		glyph_center(r, icon, size, FG)
		return clicked(r)
	}
	gap := min(colw / 3.2, px(110))
	if glyph_btn({ccx - gap, ctl_y}, px(30), I_PREV, fs(26)) do music_step(-1)
	if glyph_btn({ccx, ctl_y}, px(40), I_PAUSE if playing else I_PLAY, fs(38)) do music_toggle()
	if glyph_btn({ccx + gap, ctl_y}, px(30), I_NEXT, fs(26)) do music_step(1)

	// bottom row: lyrics · shuffle · repeat · up next
	slots := [4]f32{-1.5, -0.5, 0.5, 1.5}
	step := min(colw / 4, px(96))
	pill :: proc(c: [2]f32, icon: rune, on: bool, enabled := true, badge := "") -> bool {
		r := Rect{c.x - px(22), c.y - px(17), px(44), px(34)}
		hot(r)
		if on do rrect(r, px(10), hex(0xffffff, 50))
		else if enabled && hovering(r) do rrect(r, px(10), hex(0xffffff, 20))
		glyph_center(r, icon, fs(16), FG if on else with_alpha(FG, 150 if enabled else 60))
		if badge != "" do text(r.x + r.w - px(12), r.y + px(13), badge, fs(9), FG, true)
		return enabled && clicked(r)
	}
	lyr_on := (wide && md.panel == .Lyrics && has_lyrics) || (!wide && mu.panel_open && md.panel == .Lyrics)
	que_on := (wide && (md.panel == .Queue || !has_lyrics)) || (!wide && mu.panel_open && md.panel == .Queue)
	if pill({ccx + slots[0] * step, row_y}, I_LYRICS, lyr_on, has_lyrics) {
		if !wide && lyr_on do mu.panel_open = false
		else {md.panel = .Lyrics; mu.panel_open = true}
	}
	if pill({ccx + slots[1] * step, row_y}, I_SHUFFLE, mu.shuffle) do music_set_shuffle(!mu.shuffle)
	if pill({ccx + slots[2] * step, row_y}, I_REPEAT, mu.repeat != .Off, true, "1" if mu.repeat == .One else "") do mu.repeat = Repeat((int(mu.repeat) + 1) % 3)
	if pill({ccx + slots[3] * step, row_y}, I_QUEUE, que_on) {
		if !wide && que_on do mu.panel_open = false
		else {md.panel = .Queue; mu.panel_open = true}
	}

	// lyrics / Up Next
	pr: Rect
	if wide {
		pr = {L.x + L.w + px(10), r.y + px(56), r.w - L.w - px(46), r.h - px(80)}
	} else {
		if k < 0.05 do return
		top := small.y + small.h + px(20)
		pr = {L.x + margin - px(12), top, colw + px(24), bar_y - px(26) - top}
		draw_alpha = u32(k * 255)
	}
	defer draw_alpha = 255
	if md.panel == .Lyrics && has_lyrics {
		draw_lyrics(pr)
	} else {
		draw_queue(pr)
	}
}

draw_queue :: proc(qr: Rect) {
	text(qr.x + px(12), qr.y + px(18), "次に再生", fs(17), FG, true)
	if mu.scan != nil do text(qr.x + px(110), qr.y + px(18), "曲を集めています…", fs(12), with_alpha(FG, 140))
	rows := Rect{qr.x, qr.y + px(30), qr.w, qr.h - px(30)}
	row_h := px(54)
	n := len(mu.order)
	if app.wheel != 0 && hovering(rows) do mu.q_scroll = clamp(mu.q_scroll - app.wheel * px(80), 0, max(0, f32(n - mu.pos) * row_h - rows.h))
	set_clip(rows)
	defer set_clip({0, 0, f32(cv.w), f32(cv.h)})
	ry := rows.y - mu.q_scroll
	for k in mu.pos ..< n {
		if ry > rows.y + rows.h do break
		if ry + row_h >= rows.y {
			rr := Rect{rows.x, ry, rows.w, row_h - px(4)}
			cur := k == mu.pos
			if cur do rrect(rr, px(10), hex(0xffffff, 34))
			else if hovering(rr) do rrect(rr, px(10), hex(0xffffff, 16))
			path := mu.list[mu.order[k]]
			// album art from the thumbnail cache when there is one
			ar := Rect{rr.x + px(10), rr.y + px(5), rr.h - px(10), rr.h - px(10)}
			if th := thumb_get(path, 0, .Audio); th != nil {
				blit_scaled(ar, th.px, th.w, th.h)
				rrect(ar, px(5), hex(0xffffff, 30), px(1))
			} else {
				rrect(ar, px(6), hex(0xffffff, 28))
				glyph_center(ar, I_MUSIC, fs(13), with_alpha(FG, 160))
			}
			if cur do eq_badge(ar.x + ar.w - px(14), ar.y + ar.h - px(14), px(14))
			tx := ar.x + ar.w + px(12)
			text(tx, rr.y + px(22), ellipsize(filepath.stem(path), fs(14), rr.x + rr.w - tx - px(10), cur), fs(14), FG, cur)
			text(tx, rr.y + px(40), ellipsize(filepath.base(filepath.dir(path)), fs(12), rr.x + rr.w - tx - px(10)), fs(12), with_alpha(FG, 140))
			if clicked(rr) && !cur {
				mu.pos = k
				music_start(0)
			}
		}
		ry += row_h
	}
}
