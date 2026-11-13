package main

// Drag and drop, made visible: the dragged items lift into a stacked "ghost" with a
// count badge that springs after the pointer; drop targets (folders, sidebar places,
// bookmarks, drives, trash, tags) light up and pop; hovering a folder or a tab opens
// it (spring-loaded); a label says what will happen (move / copy / trash / tag, with
// Ctrl / Shift to switch); the list scrolls at the edges; on drop the ghost flies
// into the target, which bounces. Outside the window the compositor shows a picture
// of the same ghost.

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

Drop_Kind :: enum u8 {
	None, Dir, Trash, Tag,
}

Drag_Item :: struct {
	path:   string, // shared with dd.paths
	is_dir: bool,
	kind:   Kind,
	tint:   u8,
	mtime:  i64,
}

SPRING_OPEN :: 1.1 // seconds hovering a folder before it opens
SPRING_TAB :: 0.6
GHOST_BOX :: 104 // logical size of the ghost picture (pointer at its top-left)

dd: struct {
	items:          [dynamic]Drag_Item, // first few dragged items, for the ghost
	paths:          [dynamic]string, // every dragged path
	src_dir:        string,
	t0:             f32, // lift start
	gx, gy, gs:     f32, // ghost position / scale (springs)
	mods:           Mods,
	// target under the pointer, found while drawing this frame
	kind:           Drop_Kind,
	dir:            string, // folder path, trash path or "tag:N"
	tag:            u8,
	rect:           Rect,
	name:           string,
	invalid, keep:  bool,
	// kept from frame to frame: hover timing, cached move-or-copy
	hot:            string,
	hot_t0:         f32,
	hot_move:       bool,
	// after a drop
	fly_t0:         f32,
	fly_x, fly_y:   f32,
	fly_to:         Rect,
	bounce:         string,
	bounce_t0:      f32,
}

@(private = "file")
set_str :: proc(dst: ^string, s: string) {
	if dst^ == s do return
	delete(dst^)
	dst^ = strings.clone(s)
}

drag_clear :: proc() {
	for p in dd.paths do delete(p)
	clear(&dd.paths)
	clear(&dd.items)
	set_str(&dd.src_dir, "")
}

// Pointer moved far enough with the button down on a selected item.
drag_begin :: proc() {
	drag_clear()
	for vi in selection() {
		e := &app.entries[vi]
		p := strings.clone(full_path(e.name))
		append(&dd.paths, p)
		if len(dd.items) < 3 do append(&dd.items, Drag_Item{p, e.is_dir, e.kind, tint_of(e.name), e.mtime})
	}
	if len(dd.paths) == 0 do return
	set_str(&dd.src_dir, app.cwd)
	dd.t0, dd.fly_t0 = app.now, 0
	dd.gx, dd.gy, dd.gs = app.mx, app.my, 1
	// the same ghost, rendered once for the compositor (shown outside our window)
	sz := i32(px(GHOST_BOX))
	img := make([]u32, int(sz * sz), context.temp_allocator)
	saved := cv
	cv = Canvas{px = raw_data(img), w = sz, h = sz, stride = sz, clip = {0, 0, sz, sz}}
	draw_ghost(0, 0, 1)
	cv = saved
	plat_start_drag(dd.paths[:], img, sz, sz)
}

dragging_own :: proc() -> bool {return plat_dragging() && len(dd.paths) > 0}

// Stack of up to three cards plus a count badge; (x, y) is the pointer.
draw_ghost :: proc(x, y, sc: f32) {
	n := len(dd.items)
	if n == 0 do return
	cs := px(72) * sc
	cx, cy := x + px(18) * sc, y + px(30) * sc
	for i := n - 1; i >= 0; i -= 1 {
		off := f32(i) * px(6) * sc
		r := Rect{cx + off, cy - off, cs, cs}
		rrect({r.x, r.y + px(4) * sc, r.w, r.h}, px(14) * sc, hex(0x000000, 70))
		rrect(r, px(14) * sc, hex(0x1e2433, 235 if i == 0 else 200))
		rrect(r, px(14) * sc, hex(0xffffff, 40), px(1))
		if i != 0 do continue
		it := dd.items[0]
		is := cs * 0.7
		ix, iy := r.x + (cs - is) / 2, r.y + (cs - is) / 2
		if it.is_dir {
			folder_icon(ix, iy, is, 0, it.tint)
		} else if it.kind == .Image || it.kind == .Video || it.kind == .Audio {
			if th := thumb_get(it.path, it.mtime, it.kind); th != nil do draw_thumb(ix, iy, is, th, it.kind)
			else do file_icon(ix, iy, is, it.kind, it.path)
		} else do file_icon(ix, iy, is, it.kind, it.path)
	}
	if len(dd.paths) > 1 {
		label := fmt.tprintf("%d", len(dd.paths))
		size := i32(f32(fs(12)) * sc)
		bw := max(px(22) * sc, f32(text_width(label, size, true)) + px(12) * sc)
		b := Rect{cx + cs - bw / 2, cy - px(11) * sc, bw, px(22) * sc}
		rrect(b, b.h / 2, ACCENT)
		text(b.x + (b.w - f32(text_width(label, size, true))) / 2, baseline(b, size), label, size, hex(0x11131c), true)
	}
}

// ---------------------------------------------------------------------------
// Drop targets

@(private = "file")
same_device :: proc(a, b: string) -> bool {
	sa, sb: posix.stat_t
	if posix.stat(strings.clone_to_cstring(a, context.temp_allocator), &sa) != .OK do return false
	if posix.stat(strings.clone_to_cstring(b, context.temp_allocator), &sb) != .OK do return false
	return sa.st_dev == sb.st_dev
}

// Like GNOME Files: move within a drive, copy across drives; Ctrl copies, Shift moves.
drop_is_move :: proc() -> bool {
	if .Ctrl in dd.mods do return false
	if .Shift in dd.mods do return true
	return dd.hot_move if dragging_own() else false
}

// A folder can't be dropped into itself or its own subfolders.
dir_ok :: proc(dir: string) -> bool {
	for p in dd.paths do if dir == p || strings.has_prefix(dir, p) && len(dir) > len(p) && dir[len(p)] == '/' do return false
	return true
}

@(private = "file")
set_hot :: proc(key: string) -> (changed: bool) {
	if key == dd.hot do return false
	set_str(&dd.hot, key)
	dd.hot_t0 = app.now
	return true
}

// Registers r as a drop target if the drag is over it; draws its highlight.
// t: eased highlight (0..1); spring: hover countdown before the folder opens (-1: none).
drop_hover :: proc(r: Rect, kind: Drop_Kind, path: string, name: string, rad: f32, tag: u8 = 0) -> (on: bool, t: f32, spring: f32) {
	spring = -1
	if !app.dnd_on || dd.kind != .None || dd.invalid || !contains(r, app.dnd_x, app.dnd_y) do return
	changed := set_hot(fmt.tprintf("%v|%d|%s", kind, tag, path))
	if kind == .Dir && !dir_ok(path) {
		dd.invalid = true
		rrect(r, rad, with_alpha(DANGER, 30))
		rrect(r, rad, with_alpha(DANGER, 200), px(2))
		return
	}
	if changed && kind == .Dir && len(dd.paths) > 0 do dd.hot_move = same_device(dd.paths[0], path)
	dd.kind, dd.tag, dd.rect = kind, tag, r
	set_str(&dd.dir, path)
	set_str(&dd.name, name)
	t = progress(dd.hot_t0, 0.18)
	rrect(r, rad, with_alpha(ACCENT, u8(60 * t)))
	rrect(r, rad, with_alpha(ACCENT, u8(230 * t)), px(2))
	if kind == .Dir && path != app.cwd && !app.blocked { // blocked: the inactive split pane, where Navigate would hit the other pane
		el := app.now - dd.hot_t0
		app.animating = true
		spring = clamp((el - 0.35) / (SPRING_OPEN - 0.35), 0, 1)
		if el > SPRING_OPEN {
			push(.Navigate, 0, strings.clone(path, context.temp_allocator))
			dd.hot_t0 = app.now + 1e6 // once
			spring = -1
		}
	}
	return true, t, spring
}

// Hovering a tab while dragging switches to it.
tab_drag_hover :: proc(tr: Rect, i: int) {
	if !app.dnd_on || i == app.cur_tab || !contains(tr, app.dnd_x, app.dnd_y) do return
	set_hot(fmt.tprintf("tab|%d", i))
	dd.keep = true
	el := app.now - dd.hot_t0
	app.animating = true
	rrect(tr, px(7), with_alpha(ACCENT, 50))
	f := clamp(el / SPRING_TAB, 0, 1)
	fill({tr.x + px(8), tr.y + tr.h - px(3), (tr.w - px(16)) * f, px(2)}, ACCENT)
	if el > SPRING_TAB {
		push(.Switch_Tab, i)
		dd.hot_t0 = app.now + 1e6
	}
}

// The folder on screen takes drops anywhere else in the pane.
body_drop :: proc(b: Rect) {
	if in_trash() || is_tag_view() do return
	if dragging_own() && dd.src_dir == app.cwd do return // dropping back where it came from: nothing to show
	if !app.dnd_on || dd.kind != .None || dd.invalid || !contains(b, app.dnd_x, app.dnd_y) do return
	drop_hover(shrink(b, px(4)), .Dir, app.cwd, location_name(), px(12))
}

// Extra scale for an item that just received a drop.
bounce_of :: proc(path: string) -> f32 {
	if dd.bounce == "" || path != dd.bounce do return 0
	p := (app.now - dd.bounce_t0) / 0.45
	if p >= 1 do return 0
	app.animating = true
	if p < 0 do return 0 // waiting for the ghost to land
	return math.sin(p * math.PI) * 0.16 * (1 - p)
}

// Lets the list scroll when the pointer is near its top or bottom edge.
drag_autoscroll :: proc(b: Rect, max_scroll: f32) {
	if !app.dnd_on || !contains(b, app.dnd_x, app.dnd_y) do return
	edge := px(56)
	d: f32
	if app.dnd_y < b.y + edge do d = -(1 - (app.dnd_y - b.y) / edge)
	else if app.dnd_y > b.y + b.h - edge do d = 1 - (b.y + b.h - app.dnd_y) / edge
	if d == 0 do return
	app.scroll_to = clamp(app.scroll_to + d * px(900) * app.dt, 0, max_scroll)
	app.animating = true
}

// ---------------------------------------------------------------------------
// Frame start / end

drag_frame_begin :: proc() {
	dd.kind, dd.invalid, dd.keep = .None, false, false
}

draw_drag_overlay :: proc(W, H: f32) {
	if dd.kind == .None && !dd.keep && !dd.invalid && dd.hot != "" do set_str(&dd.hot, "")
	own := dragging_own()
	if app.dnd_on && own {
		k := 1 - math.exp(-app.dt * 24)
		dd.gx += (app.dnd_x - dd.gx) * k
		dd.gy += (app.dnd_y - dd.gy) * k
		want: f32 = 0.86 if dd.kind != .None else 1
		dd.gs += (want - dd.gs) * (1 - math.exp(-app.dt * 14))
		if abs(app.dnd_x - dd.gx) + abs(app.dnd_y - dd.gy) > 0.5 || abs(want - dd.gs) > 0.005 do app.animating = true
		// lift: pops up with a little overshoot
		p := clamp((app.now - dd.t0) / 0.3, 0, 1)
		if p < 1 do app.animating = true
		q := p - 1
		lift := 1 + 2.70158 * q * q * q + 1.70158 * q * q
		draw_ghost(dd.gx, dd.gy, dd.gs * (0.55 + 0.45 * lift))
	}
	if app.dnd_on do draw_drop_label(app.dnd_x, app.dnd_y, own, W, H)

	if dd.fly_t0 > 0 {
		p := progress(dd.fly_t0, 0.34)
		if p >= 1 {
			dd.fly_t0 = 0
			if !plat_dragging() do drag_clear()
		} else {
			sc := 1 - 0.7 * p
			tx := dd.fly_to.x + dd.fly_to.w / 2 - px(54) * sc
			ty := dd.fly_to.y + dd.fly_to.h / 2 - px(66) * sc
			draw_alpha = u32(255 * (1 - p * p))
			draw_ghost(dd.fly_x + (tx - dd.fly_x) * p, dd.fly_y + (ty - dd.fly_y) * p, sc)
			draw_alpha = 255
		}
	}
}

@(private = "file")
draw_drop_label :: proc(x, y: f32, own: bool, W, H: f32) {
	icon: rune
	msg, hint := "", ""
	col := FG
	switch dd.kind {
	case .None:
		if !dd.invalid do return
		icon, msg, col = 0xf05e, "ここには置けません", DANGER // ban
	case .Dir:
		same := own
		for p in dd.paths do if filepath.dir(p) != dd.dir do same = false
		if same {
			icon, msg, col = 0xf05e, "元の場所です", DIM
		} else {
			move := drop_is_move() if own else .Shift in dd.mods
			icon = 0xf061 if move else 0xf0c5 // arrow-right / copy
			msg = fmt.tprintf("%s → %s", "移動" if move else "コピー", dd.name)
			hint = "Ctrl でコピー" if move else "Shift で移動"
		}
	case .Trash: icon, msg = I_TRASH, "ゴミ箱へ移動"
	case .Tag:   icon, msg = I_TAG, fmt.tprintf("タグ「%s」を付ける", dd.name)
	}
	size := fs(13)
	tw := f32(text_width(msg, size, true))
	hw := f32(text_width(hint, fs(11))) if hint != "" else 0
	w := px(40) + tw + (hw + px(14) if hint != "" else 0)
	h := px(30)
	px_ := x + px(22)
	py := y + (px(108) if own && app.dnd_on else px(22))
	px_ = clamp(px_, px(4), W - w - px(4))
	py = clamp(py, px(4), H - h - px(4))
	r := Rect{px_, py, w, h}
	rrect({r.x, r.y + px(3), r.w, r.h}, h / 2, hex(0x000000, 70))
	rrect(r, h / 2, POP_BG)
	rrect(r, h / 2, with_alpha(col, 120), px(1))
	glyph_center({r.x + px(8), r.y, px(22), h}, icon, fs(12), col)
	text(r.x + px(32), baseline(r, size), msg, size, col, true)
	if hint != "" do text(r.x + px(46) + tw, baseline(r, fs(11)), hint, fs(11), DIM)
}

// ---------------------------------------------------------------------------
// The drop itself (text: newline separated paths; action: compositor's 1 copy / 2 move)

drag_drop :: proc(text: string, action: u8) {
	srcs := strings.split(text, "\n", context.temp_allocator)
	if len(srcs) == 0 || srcs[0] == "" do return
	own := len(dd.paths) > 0 && dd.paths[0] == srcs[0]
	switch dd.kind {
	case .None: return
	case .Dir:
		same := true
		for p in srcs do if filepath.dir(p) != dd.dir do same = false
		if same do return // dropping where it already is does nothing
		// someone else's drag is moved only when the compositor (and the source) agreed
		start_op(srcs, dd.dir, drop_is_move() if own else action == 2)
	case .Trash: trash_paths(srcs)
	case .Tag:   tag_paths(srcs, dd.tag)
	}
	if own {
		dd.fly_t0, dd.fly_x, dd.fly_y, dd.fly_to = app.now, dd.gx, dd.gy, dd.rect
	}
	set_str(&dd.bounce, dd.dir)
	dd.bounce_t0 = app.now + (0.25 if own else 0) // after the ghost lands
}
