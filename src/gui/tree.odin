package main

// Tree view (Ctrl+3), styled after Obsidian's file explorer: chevrons, indent
// guides, compact rows, purple selection. Expanded folders' children are loaded
// into the same entry list the recursive search uses, so selection, menus,
// drag-and-drop and preview all work on nested rows unchanged.

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:mem/virtual"

OBSIDIAN :: Color{0xa8, 0x82, 0xff, 255}
TREE_HEAD :: 36
TREE_ROW :: 30
I_CHEVRON_RIGHT :: 0xf054
I_CHEVRON_DOWN :: 0xf078
I_SITEMAP :: 0xf0e8
I_COLLAPSE :: 0xf066

tree_mode :: proc() -> bool {
	return app.tree && !app.searching && !is_tag_view()
}

@(private = "file")
parent_of :: proc(name: string) -> string {
	i := strings.last_index_byte(name, '/')
	return name[:i] if i >= 0 else ""
}

// Rebuilds app.view in tree order (called from refilter).
build_tree_view :: proc() {
	a := virtual.arena_allocator(&app.search_arena)
	// load the children of expanded folders (repeat: a loaded child may itself be expanded)
	for changed := true; changed; {
		changed = false
		for name in app.expanded {
			if name in app.tree_loaded do continue
			app.tree_loaded[strings.clone(name, a)] = true
			changed = true
			infos, err := os.read_all_directory_by_path(full_path(name), context.temp_allocator)
			if err != nil do continue
			for fi in infos {
				e := Entry {
					name  = strings.concatenate({name, "/", fi.name}, a),
					size  = fi.size,
					mtime = fi.modification_time._nsec / 1_000_000_000,
					btime = fi.creation_time._nsec / 1_000_000_000,
					atime = fi.access_time._nsec / 1_000_000_000,
				}
				e.is_link = fi.type == .Symlink
				e.is_dir = fi.type == .Directory || (e.is_link && os.is_dir(fi.fullpath))
				e.hidden = strings.has_prefix(fi.name, ".") || strings.has_suffix(fi.name, "~")
				e.kind = kind_of(fi.name, fi.mode)
				append(&app.entries, e)
			}
		}
	}
	kids := make(map[string][dynamic]int, context.temp_allocator)
	for e, i in app.entries {
		if !app.show_hidden && e.hidden do continue
		p := parent_of(e.name)
		if p != "" && p not_in app.expanded do continue
		if p not_in kids do kids[p] = make([dynamic]int, context.temp_allocator)
		append(&kids[p], i)
	}
	clear(&app.view)
	emit :: proc(kids: ^map[string][dynamic]int, parent: string) {
		list, ok := kids[parent]
		if !ok do return
		slice.sort_by(list[:], entry_less)
		for i in list {
			append(&app.view, i)
			e := app.entries[i]
			if e.is_dir && e.name in app.expanded do emit(kids, e.name)
		}
	}
	emit(&kids, "")
	if app.focus >= len(app.view) do app.focus = len(app.view) - 1
}

tree_toggle :: proc(vi: int) {
	name := app.entries[vi].name
	if name in app.expanded {
		// collapse this folder and everything below it
		drop := make([dynamic]string, context.temp_allocator)
		for k in app.expanded do if k == name || strings.has_prefix(k, strings.concatenate({name, "/"}, context.temp_allocator)) do append(&drop, k)
		for k in drop {
			key, _ := delete_key(&app.expanded, k)
			delete(key)
		}
	} else {
		app.expanded[strings.clone(name)] = now_s()
	}
	refilter()
}

tree_collapse_all :: proc() {
	for k in app.expanded do delete(k)
	clear(&app.expanded)
	refilter()
}

draw_tree_header :: proc(b: Rect) {
	h := Rect{b.x, b.y, b.w, px(TREE_HEAD)}
	fill({h.x + px(12), h.y + h.h - 1, h.w - px(24), 1}, LINE)
	title := strings.to_upper(location_name(), context.temp_allocator)
	text(h.x + px(16), baseline(h, fs(12)), ellipsize(title, fs(12), h.w - px(120), true), fs(12), with_alpha(OBSIDIAN, 230), true)
	bs := px(28)
	x := h.x + h.w - px(10) - bs
	if icon_button({x, h.y + (h.h - bs) / 2, bs, bs}, I_COLLAPSE) do tree_collapse_all()
	x -= bs + px(4)
	if icon_button({x, h.y + (h.h - bs) / 2, bs, bs}, 0xf07b) do push(.Mkdir)
}

// Draws one tree row; r is the row rect, hit the highlight rect.
draw_tree_row :: proc(e: ^Entry, r, hit: Rect, hov: bool) {
	depth := strings.count(e.name, "/")
	indent := px(18)
	x0 := r.x + px(10)
	for l in 0 ..< depth do fill({x0 + f32(l) * indent + px(7), r.y, 1, r.h}, hex(0xffffff, 20)) // indent guides
	x := x0 + f32(depth) * indent
	cy := r.y + r.h / 2
	if e.is_dir {
		t0, open := app.expanded[e.name]
		f: f32 = progress(t0, 0.15) if open else 0
		cr := Rect{x - px(2), r.y, px(18), r.h}
		if f < 1 {
			draw_alpha = u32((1 - f) * f32(draw_alpha))
			glyph_center(cr, I_CHEVRON_RIGHT, fs(10), DIM)
			draw_alpha = 255
		}
		if f > 0 {
			saved := draw_alpha
			draw_alpha = u32(f * 255)
			glyph_center(cr, I_CHEVRON_DOWN, fs(10), DIM)
			draw_alpha = saved
		}
		folder_icon(x + px(18), cy - px(9), px(18), 0, tint_of(e.name))
	} else if is_now_playing(e.name) {
		eq_badge(x + px(20), cy - px(7), px(14))
	} else if l, ok := lang_of(e.name); ok && l.glyph != 0 {
		glyph_center({x + px(16), r.y, px(22), r.h}, l.glyph, fs(12), DIM)
	} else {
		glyph_center({x + px(16), r.y, px(22), r.h}, KIND_GLYPH[e.kind], fs(12), hex(KIND_COLOR[e.kind], 220))
	}
	col := with_alpha(FG, 150) if e.hidden else FG
	nx := x + px(44)
	name := filepath.base(e.name)
	right := r.x + r.w - px(16)
	if !e.is_dir {
		sz := format_size(e.size)
		sw := f32(text_width(sz, fs(11)))
		right -= sw
		text(right, baseline(r, fs(11)), sz, fs(11), with_alpha(FG, 90))
		right -= px(12)
	}
	nw := text(nx, baseline(r, fs(14)), ellipsize(name, fs(14), right - nx - px(30), e.is_dir), fs(14), col, e.is_dir)
	file_tag_dots(nx + nw + px(10), cy, px(4), e.name)
	git_dot(nx + nw + px(10), cy, px(4), e.name)
}
