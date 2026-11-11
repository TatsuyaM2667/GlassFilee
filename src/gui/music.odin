package main

// Music player: a folder of songs gets a player bar (cover art, title/artist,
// controls, seek bar, equalizer animation). Playback runs in ffplay (no window);
// pause/resume is SIGSTOP/SIGCONT, seeking restarts it at the new position.

import "core:fmt"
import "core:image"
import "core:math"
import "core:os"
import "core:path/filepath"
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

PLAYER_H :: 84

@(private = "file")
Meta :: struct {
	path:                 string,
	duration:             f64,
	title, artist, album: string,
	cover:                []u32,
	cw, ch:               int,
	done:                 bool,
	th:                   ^thread.Thread,
}

Music :: struct {
	list:      [dynamic]string, // absolute paths
	idx:       int,
	pid:       posix.pid_t,
	paused:    bool,
	start_ms:  i64, // wall clock when position 0 would have been
	paused_at: f64, // position while paused
	meta:      ^Meta,
	bar_t0:    f32,
	shown:     bool,
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

music_pos :: proc() -> f64 {
	if mu.paused do return mu.paused_at
	return f64(ticks_ms() - mu.start_ms) / 1000
}

// Plays the current folder's songs, starting at view index k (or the first song).
music_play_folder :: proc(k: int) {
	if !have_tool("ffplay") {
		toastf("再生には ffplay（ffmpeg）が必要です")
		return
	}
	for p in mu.list do delete(p)
	clear(&mu.list)
	start := 0
	for vi, j in app.view {
		e := app.entries[vi]
		if !is_audio(e) do continue
		if j == k do start = len(mu.list)
		append(&mu.list, strings.clone(full_path(e.name)))
	}
	if len(mu.list) == 0 do return
	music_start(start, 0)
}

music_start :: proc(idx: int, offset: f64) {
	music_kill()
	mu.idx = idx
	path := mu.list[idx]
	pid := spawn({"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-ss", fmt.tprintf("%.2f", offset), path})
	if pid == 0 do return
	mu.pid = pid
	mu.paused = false
	mu.start_ms = ticks_ms() - i64(offset * 1000)
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
	meta_free()
	for p in mu.list do delete(p)
	clear(&mu.list)
}

music_toggle :: proc() {
	if mu.pid == 0 {
		if len(mu.list) > 0 do music_start(mu.idx, mu.paused_at)
		else do music_play_folder(app.focus)
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
}

music_step :: proc(d: int) {
	if len(mu.list) == 0 do return
	if d < 0 && music_pos() > 3 {
		music_start(mu.idx, 0) // "previous" restarts the song first, like most players
		return
	}
	music_start((mu.idx + d + len(mu.list)) % len(mu.list), 0)
}

// Called by reap_jobs for every exited child; true if it was the player.
music_child_exited :: proc(pid: posix.pid_t) -> bool {
	if pid != mu.pid || pid == 0 do return false
	mu.pid = 0
	if mu.idx + 1 < len(mu.list) do music_start(mu.idx + 1, 0)
	return true
}

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
	// cover: a picture next to the songs, else the art embedded in the file
	src := m.path
	for name in ([]string{"cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "Cover.jpg", "Folder.jpg", "AlbumArt.jpg"}) {
		p, _ := filepath.join({filepath.dir(m.path), name}, context.temp_allocator)
		if os.exists(p) {src = p; break}
	}
	_, img_bytes, _, ierr := os.process_exec({command = {"ffmpeg", "-v", "error", "-nostdin", "-i", src, "-an", "-frames:v", "1", "-vf", "scale=160:160:force_original_aspect_ratio=increase,crop=160:160", "-f", "image2pipe", "-vcodec", "ppm", "-"}}, context.temp_allocator)
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
		}
	}
	free_all(context.temp_allocator)
}

@(private = "file")
fmt_time :: proc(t: f64) -> string {
	s := int(max(t, 0))
	return fmt.tprintf("%d:%02d", s / 60, s % 60)
}

// Height the player takes at the bottom of the content area (0 = hidden).
player_height :: proc() -> f32 {
	show := music_playing() || mu.paused || len(mu.list) > 0 || is_music_folder()
	if show && !mu.shown do mu.bar_t0 = now_s()
	mu.shown = show
	if !show do return 0
	return px(PLAYER_H) * progress(mu.bar_t0, 0.3)
}

draw_player :: proc(r: Rect) {
	if r.h <= 1 do return
	set_clip(r)
	defer reset_clip()
	fill(r, hex(0x0b0f1c, 150))
	fill({r.x, r.y, r.w, 1}, LINE)
	active := len(mu.list) > 0
	m := mu.meta
	ready := m != nil && sync.atomic_load(&m.done)

	// cover art
	cs := px(60)
	cr := Rect{r.x + px(14), r.y + (px(PLAYER_H) - cs) / 2, cs, cs}
	if ready && m.cover != nil {
		blit_scaled(cr, m.cover, m.cw, m.ch)
		rrect(cr, px(6), hex(0xffffff, 30), px(1))
	} else {
		rrect(cr, px(8), mix(with_alpha(ACCENT, 200), hex(0xcba6f7), 0.5 + 0.5 * f32(math.sin(app.now * 0.8))))
		glyph_center(cr, I_MUSIC, fs(22), hex(0x060913, 200))
	}

	// title / artist
	tx := cr.x + cs + px(14)
	title, sub: string
	if active {
		title = filepath.stem(mu.list[mu.idx])
		if ready && m.title != "" do title = m.title
		sub = fmt.tprintf("%d / %d 曲", mu.idx + 1, len(mu.list))
		if ready && m.artist != "" do sub = strings.concatenate({m.artist, "  ·  ", sub}, context.temp_allocator)
	} else {
		title = location_name()
		n := 0
		for e in app.entries[:app.base_count] do if is_audio(e) do n += 1
		sub = fmt.tprintf("%d 曲 · すべて再生できます", n)
	}
	cx := r.x + r.w / 2
	info_w := max(cx - px(min(r.w * 0.18, 210) + 20) - tx, px(60)) // stop before the seek bar's time label
	text(tx, r.y + px(36), ellipsize(title, fs(14), info_w, true), fs(14), FG, true)
	text(tx, r.y + px(58), ellipsize(sub, fs(12), info_w), fs(12), DIM)

	// controls
	cy := r.y + px(30)
	pb := Rect{cx - px(20), cy - px(20), px(40), px(40)}
	playing := music_playing() && !mu.paused
	rrect(pb, px(20), with_alpha(ACCENT, 255 if hovering(pb) else 225))
	glyph_center({pb.x + (playing ? 0 : px(2)), pb.y, pb.w, pb.h}, I_PAUSE if playing else I_PLAY, fs(15), hex(0x060913))
	if clicked(pb) do music_toggle()
	if active {
		if icon_button({cx - px(66), cy - px(17), px(34), px(34)}, I_PREV) do music_step(-1)
		if icon_button({cx + px(32), cy - px(17), px(34), px(34)}, I_NEXT) do music_step(1)
	}

	// seek bar
	if active {
		dur := m.duration if ready else 0
		pos := music_pos()
		bw := min(r.w * 0.36, px(420))
		bar := Rect{cx - bw / 2, r.y + px(62), bw, px(4)}
		rrect(bar, px(2), hex(0xffffff, 30))
		if dur > 0 {
			f := f32(clamp(pos / dur, 0, 1))
			rrect({bar.x, bar.y, bar.w * f, bar.h}, px(2), ACCENT)
			rrect({bar.x + bar.w * f - px(5), bar.y - px(3), px(10), px(10)}, px(5), FG)
			hit := Rect{bar.x, bar.y - px(8), bar.w, px(20)}
			if clicked(hit) do music_start(mu.idx, f64((app.mx - bar.x) / bar.w) * dur)
		}
		text(bar.x - px(44), bar.y + px(5), fmt_time(pos), fs(11), DIM)
		if dur > 0 do text(bar.x + bar.w + px(10), bar.y + px(5), fmt_time(dur), fs(11), DIM)
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
	if ex > cx + px(110) {
		for i in 0 ..< bars {
			h := px(6)
			if playing {
				t := app.now
				fi := f32(i)
				v := 0.5 + 0.25 * math.sin(t * 6.1 + fi * 0.9) + 0.18 * math.sin(t * 9.7 + fi * 2.3) + 0.12 * math.sin(t * 3.3 - fi * 1.7)
				h = px(6) + clamp(v, 0, 1) * px(40)
			}
			col := mix(ACCENT, hex(0xcba6f7), f32(i) / f32(bars))
			rrect({ex + f32(i) * (ew + px(3)), r.y + px(PLAYER_H) / 2 + px(20) - h, ew, h}, px(2), col)
		}
	}
}
