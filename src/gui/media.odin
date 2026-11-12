package main

// Extras for the player:
// - "音楽を再生" on a folder: every song under it, in order
// - synced lyrics from a same-named .lrc file (Apple Music style scrolling)
// - a same-named music video (.mp4/.mkv/.webm/.mov) plays in place of the art,
//   decoded by ffmpeg into raw frames and kept in step with the song

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:thread"

I_LYRICS :: 0xf10e // quote
I_QUEUE :: 0xf03a

VIDEO_W :: 640
VIDEO_H :: 360

Lyric_Line :: struct {
	t:    f64,
	text: string,
}

Panel :: enum {
	Lyrics, Queue,
}

// A video decoded by ffmpeg into raw frames on a worker thread (music videos, viewer).
Video :: struct {
	pid:    posix.pid_t,
	out:    ^os.File, // read end of ffmpeg's stdout
	th:     ^thread.Thread,
	lock:   sync.Mutex,
	frame:  []u32, // latest complete frame (ARGB)
	w, h:   int,
	fresh:  bool, // a new frame arrived since the last draw
	stop:   bool,
	paused: bool,
}

Media :: struct {
	lyrics:      [dynamic]Lyric_Line,
	lyrics_buf:  string, // owns the line texts
	lyrics_for:  string, // track the lyrics belong to
	lyric_y:     f32, // animated scroll position (lines)
	mv:          string, // music video path ("" = none)
	video:       ^Video,
	panel:       Panel,
	pending_dir: bool, // folder play: start when the scan finishes
}
md: Media

// ---------------------------------------------------------------------------
// LRC: "[mm:ss.xx]text", several stamps per line allowed, optional [offset:+ms]

parse_lrc :: proc(text: string, out: ^[dynamic]Lyric_Line) {
	offset: f64
	src := text
	for line in strings.split_lines_iterator(&src) {
		l := strings.trim_space(line)
		stamps := make([dynamic]f64, context.temp_allocator)
		for strings.has_prefix(l, "[") {
			end := strings.index_byte(l, ']')
			if end < 0 do break
			tag := l[1:end]
			l = l[end + 1:]
			if strings.has_prefix(tag, "offset:") {
				ms, _ := strconv.parse_f64(strings.trim_space(tag[7:]))
				offset = ms / 1000
				continue
			}
			if strings.count(tag, ":") == 2 { // "[mm:ss:xx]" variant
				i := strings.last_index_byte(tag, ':')
				tag = strings.concatenate({tag[:i], ".", tag[i + 1:]}, context.temp_allocator)
			}
			mm, _, ss := strings.partition(tag, ":")
			m, ok1 := strconv.parse_f64(mm)
			s, ok2 := strconv.parse_f64(ss)
			if ok1 && ok2 do append(&stamps, m * 60 + s)
		}
		for t in stamps do append(out, Lyric_Line{t, strings.trim_space(l)})
	}
	// LRC files are usually ordered, but repeated stamps ("[00:10][01:20]chorus") are not
	for i in 1 ..< len(out) {
		for j := i; j > 0 && out[j - 1].t > out[j].t; j -= 1 do out[j - 1], out[j] = out[j], out[j - 1]
	}
	// a positive offset shows lyrics earlier
	for &ln in out do ln.t = max(ln.t - offset, 0)
}

@(private = "file")
same_name :: proc(path: string, exts: []string) -> string {
	stem := path[:len(path) - len(filepath.ext(path))]
	for e in exts {
		p := strings.concatenate({stem, e}, context.temp_allocator)
		if os.exists(p) do return p
	}
	return ""
}

// Called whenever a song starts (from music_start).
media_track_started :: proc(path: string, offset: f64) {
	if md.lyrics_for != path {
		clear(&md.lyrics)
		delete(md.lyrics_buf)
		delete(md.lyrics_for)
		md.lyrics_buf, md.lyrics_for = "", strings.clone(path)
		if lrc := same_name(path, {".lrc", ".LRC"}); lrc != "" {
			if data, err := os.read_entire_file_from_path(lrc, context.allocator); err == nil {
				md.lyrics_buf = string(data)
				parse_lrc(md.lyrics_buf, &md.lyrics)
			}
		}
		md.lyric_y = 0
		delete(md.mv)
		md.mv = strings.clone(same_name(path, {".mp4", ".mkv", ".webm", ".mov", ".MP4"}))
		md.panel = .Lyrics if len(md.lyrics) > 0 else .Queue
	}
	video_stop() // restarts at the new position when Now Playing shows it
	_ = offset
}

current_lyric :: proc(pos: f64) -> int {
	k := -1
	for ln, i in md.lyrics {
		if ln.t > pos do break
		k = i
	}
	return k
}

// ---------------------------------------------------------------------------
// Video decoding (shared by music videos and the viewer)

@(private = "file")
video_worker :: proc(v: ^Video) {
	buf := make([]u8, v.w * v.h * 4)
	defer delete(buf)
	for !sync.atomic_load(&v.stop) {
		got := 0
		for got < len(buf) {
			r, err := os.read(v.out, buf[got:])
			if err != nil || r <= 0 do return
			got += r
		}
		sync.mutex_lock(&v.lock)
		copy(v.frame, slice.reinterpret([]u32, buf)) // bgra bytes == 0xAARRGGBB words
		sync.atomic_store(&v.fresh, true)
		sync.mutex_unlock(&v.lock)
		wake()
	}
}

// Starts decoding path from `at` seconds, letterboxed into w×h, paced at playback speed.
vid_open :: proc(path: string, at: f64, w, h: int) -> ^Video {
	r, wr, err := os.pipe()
	if err != nil do return nil
	vf := fmt_vf(w, h)
	p, perr := os.process_start({
		// -re paces decoding at playback speed, so frames arrive when they should be shown
		command = {"ffmpeg", "-v", "error", "-nostdin", "-re", "-ss", fmt_f(at), "-i", path, "-an", "-vf", vf, "-pix_fmt", "bgra", "-f", "rawvideo", "-"},
		stdout  = wr,
	})
	os.close(wr)
	if perr != nil {
		os.close(r)
		return nil
	}
	when ODIN_OS == .Linux {
		if p.handle != 0 && p.handle != ~uintptr(0) do posix.close(posix.FD(p.handle))
	}
	v := new(Video)
	v.pid, v.out, v.w, v.h = posix.pid_t(p.pid), r, w, h
	v.frame = make([]u32, w * h)
	v.th = thread.create_and_start_with_poly_data(v, video_worker)
	return v
}

@(private = "file")
fmt_vf :: proc(w, h: int) -> string {
	return strings.concatenate({"scale=", itoa_tmp(w), ":", itoa_tmp(h), ":force_original_aspect_ratio=decrease,pad=", itoa_tmp(w), ":", itoa_tmp(h), ":(ow-iw)/2:(oh-ih)/2,fps=24"}, context.temp_allocator)
}

fmt_f :: proc(f: f64) -> string {
	buf: [32]u8
	return strings.clone(strconv.write_float(buf[:], f, 'f', 2, 64), context.temp_allocator)
}

vid_close :: proc(v: ^Video) {
	if v == nil do return
	sync.atomic_store(&v.stop, true)
	posix.kill(v.pid, .SIGCONT)
	posix.kill(v.pid, .SIGTERM)
	status: i32
	posix.waitpid(v.pid, &status, {}) // also unblocks the reader (pipe closes)
	thread.join(v.th)
	thread.destroy(v.th)
	os.close(v.out)
	delete(v.frame)
	free(v)
}

vid_pause :: proc(v: ^Video, paused: bool) {
	if v == nil do return
	posix.kill(v.pid, .SIGSTOP if paused else .SIGCONT)
	v.paused = paused
}

vid_fresh :: proc(v: ^Video) -> bool {return v != nil && sync.atomic_load(&v.fresh)}

vid_draw :: proc(v: ^Video, r: Rect) -> bool {
	if v == nil do return false
	sync.mutex_lock(&v.lock)
	blit_scaled(r, v.frame, v.w, v.h)
	sync.atomic_store(&v.fresh, false)
	sync.mutex_unlock(&v.lock)
	return true
}

// Music video in Now Playing ------------------------------------------------

video_stop :: proc() {
	vid_close(md.video)
	md.video = nil
}

video_pause :: proc(paused: bool) {vid_pause(md.video, paused)}

// Keeps the decoder running exactly while Now Playing shows the video.
video_sync :: proc() {
	want := mu.full && md.mv != "" && mu.pid != 0
	if want && md.video == nil do md.video = vid_open(md.mv, music_pos(), VIDEO_W, VIDEO_H)
	else if !want && md.video != nil do video_stop()
}

// True when a new video frame is waiting (main loop: redraw).
video_fresh :: proc() -> bool {return vid_fresh(md.video) || vid_fresh(pv.video)}

draw_video :: proc(r: Rect) -> bool {return vid_draw(md.video, r)}

// ---------------------------------------------------------------------------
// Folder play (right-click a folder → 音楽を再生)

music_play_dir :: proc(path: string) {
	if !have_tool("ffplay") {
		toastf("再生には ffplay（ffmpeg）が必要です")
		return
	}
	music_stop()
	md.pending_dir = true
	music_scan(path)
	toastf("「%s」の曲を集めています…", filepath.base(path))
}

// Lyrics panel: the current line large and bright, the rest dimmer the farther away.
draw_lyrics :: proc(r: Rect) {
	pos := music_pos()
	cur := current_lyric(pos)
	line_h := px(58)
	target := f32(max(cur, 0))
	if d := target - md.lyric_y; abs(d) > 0.001 {
		md.lyric_y += d * (1 - math.exp(-app.dt * 7))
		app.animating = true
	} else do md.lyric_y = target
	set_clip(r)
	defer set_clip({0, 0, f32(cv.w), f32(cv.h)})
	// Apple Music style: big bold left-aligned lines, the current one white, the rest
	// translucent; lines already sung fade faster than the ones coming up
	anchor := r.y + r.h * 0.3
	size := fs(26)
	for ln, i in md.lyrics {
		y := anchor + (f32(i) - md.lyric_y) * line_h
		if y < r.y - line_h || y > r.y + r.h + line_h do continue
		dist := f32(i) - md.lyric_y
		is_cur := i == cur
		a: f32 = 1 if is_cur else (0.42 - abs(dist) * 0.05 if dist > 0 else 0.30 - abs(dist) * 0.08)
		a = clamp(a, 0.08, 1)
		// soft fade at the panel's top and bottom edges
		edge := min((y - r.y) / px(60), (r.y + r.h - y) / px(60))
		a *= clamp(edge, 0, 1)
		txt := ln.text if ln.text != "" else "• • •"
		lr := Rect{r.x, y - line_h / 2, r.w, line_h}
		if hovering(lr) && !is_cur do rrect(lr, px(10), hex(0xffffff, 14))
		text(lr.x + px(12), baseline(lr, size), ellipsize(txt, size, lr.w - px(24), true), size, with_alpha(FG, u8(a * 255)), true)
		if clicked(lr) do music_seek(ln.t) // jump to that line
	}
}
