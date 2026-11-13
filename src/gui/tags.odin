package main

// Tags like the iPad Files app: named tags with an optional color, several per item.
// The sidebar lists them; clicking one shows every tagged item from anywhere.
// A folder takes the color of its first colored tag; files show small dots.
// Stored in ~/.config/ame-filemanager/tags.conf:
//   tag\t<id>\t<color>\t<name>      file\t<hex bitmask of tag ids>\t<absolute path>

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

TAG_COLORS := [8]u32{0, 0xf38ba8, 0xfab387, 0xf9e2af, 0xa6e3a1, 0x89b4fa, 0xcba6f7, 0x9399b2}
TAG_NAMES := [8]string{"色なし", "赤", "オレンジ", "黄", "緑", "青", "紫", "グレー"}
I_TAG :: 0xf02b

Tag :: struct {
	id:    u8, // bit in file masks (shortcut: at most 64 tags)
	color: u8,
	name:  string,
}

tag_list: [dynamic]Tag
file_tags: map[string]u64 // absolute path -> tag bits

// ~/.config/ame-filemanager (moved over from the old "glassfilee" name once).
app_config_dir :: proc() -> string {
	base, _ := os.user_config_dir(context.temp_allocator)
	dir, _ := filepath.join({base, "ame-filemanager"}, context.temp_allocator)
	old, _ := filepath.join({base, "glassfilee"}, context.temp_allocator)
	if !os.exists(dir) && os.is_dir(old) do _ = os.rename(old, dir)
	return dir
}

@(private = "file")
tags_conf :: proc() -> string {
	p, _ := filepath.join({app_config_dir(), "tags.conf"}, context.temp_allocator)
	return p
}

load_tags :: proc() {
	data, err := os.read_entire_file_from_path(tags_conf(), context.temp_allocator)
	if err == nil {
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			f := strings.split_n(line, "\t", 4, context.temp_allocator)
			if len(f) == 4 && f[0] == "tag" {
				id, _ := strconv.parse_uint(f[1])
				c, _ := strconv.parse_uint(f[2])
				if id < 64 && c < 8 do append(&tag_list, Tag{u8(id), u8(c), strings.clone(f[3])})
			} else if len(f) >= 3 && f[0] == "file" {
				_, _, rest := strings.partition(line[5:], "\t")
				mask, _ := strconv.parse_u64_of_base(f[1], 16)
				if mask != 0 do file_tags[strings.clone(rest)] = mask
			}
		}
		return
	}
	// first run: the seven color tags iPad starts with, plus the old color-only tags
	for c in u8(1) ..= 7 do append(&tag_list, Tag{c, c, strings.clone(TAG_NAMES[c])})
	old, _ := filepath.join({app_config_dir(), "tags"}, context.temp_allocator)
	if odata, oerr := os.read_entire_file_from_path(old, context.temp_allocator); oerr == nil {
		text := string(odata)
		for line in strings.split_lines_iterator(&text) {
			c, _, path := strings.partition(line, "\t")
			if len(c) == 1 && c[0] >= '1' && c[0] <= '7' && path != "" do file_tags[strings.clone(path)] = 1 << (c[0] - '0')
		}
		_ = os.remove(old)
	}
	save_tags()
}

save_tags :: proc() {
	b := strings.builder_make(context.temp_allocator)
	for t in tag_list do fmt.sbprintf(&b, "tag\t%d\t%d\t%s\n", t.id, t.color, t.name)
	for path, mask in file_tags do fmt.sbprintf(&b, "file\t%x\t%s\n", mask, path)
	p := tags_conf()
	_ = os.make_directory_all(filepath.dir(p))
	_ = os.write_entire_file_from_string(p, strings.to_string(b))
}

tag_by_id :: proc(id: u8) -> ^Tag {
	for &t in tag_list do if t.id == id do return &t
	return nil
}

mask_of :: proc(name: string) -> u64 {
	if len(file_tags) == 0 do return 0
	return file_tags[full_path(name)]
}

// Color a folder takes: its first colored tag, in sidebar order.
tint_of :: proc(name: string) -> u8 {return tint_of_mask(mask_of(name))}

tint_of_mask :: proc(m: u64) -> u8 {
	if m == 0 do return 0
	for t in tag_list do if m & (1 << t.id) != 0 && t.color != 0 do return t.color
	return 0
}

create_tag :: proc(name: string, color: u8) -> u8 {
	used: u64
	for t in tag_list do used |= 1 << t.id
	id: u8 = 1
	for id < 63 && used & (1 << id) != 0 do id += 1
	append(&tag_list, Tag{id, color, strings.clone(name)})
	save_tags()
	return id
}

delete_tag :: proc(id: u8) {
	for t, i in tag_list do if t.id == id {
		delete(t.name)
		ordered_remove(&tag_list, i)
		break
	}
	empty := make([dynamic]string, context.temp_allocator)
	for path, &mask in file_tags {
		mask &~= 1 << id
		if mask == 0 do append(&empty, path)
	}
	for p in empty {
		k, _ := delete_key(&file_tags, p)
		delete(k)
	}
	save_tags()
	if app.cwd == fmt.tprintf("tag:%d", id) do go_to(app.home)
}

// Adds the tag to the selection, or removes it if every selected item has it.
toggle_tag :: proc(id: u8) {
	sel := selection()
	if len(sel) == 0 do return
	all := true
	for vi in sel do if mask_of(app.entries[vi].name) & (1 << id) == 0 do all = false
	for vi in sel {
		p := full_path(app.entries[vi].name)
		m := file_tags[p] if p in file_tags else 0
		m = m &~ (1 << id) if all else m | (1 << id)
		if m == 0 {
			if p in file_tags {
				k, _ := delete_key(&file_tags, p)
				delete(k)
			}
		} else if p in file_tags {
			file_tags[p] = m
		} else {
			file_tags[strings.clone(p)] = m
		}
	}
	save_tags()
	if is_tag_view() do reload()
	else do refilter()
}

// Adds a tag to files dropped onto it in the sidebar.
tag_paths :: proc(paths: []string, id: u8) {
	for p in paths {
		if p in file_tags do file_tags[p] |= 1 << id
		else do file_tags[strings.clone(p)] = 1 << id
	}
	save_tags()
	if t := tag_by_id(id); t != nil do toastf("%d 個にタグ「%s」を付けました", len(paths), t.name)
	if is_tag_view() do reload()
	else do refilter()
}

// Keeps tags attached when we rename or move something (whole subtrees included).
tags_moved :: proc(old, new: string) {
	moved := make([dynamic][2]string, context.temp_allocator)
	for p in file_tags {
		if p == old || (strings.has_prefix(p, old) && p[len(old)] == '/') do append(&moved, [2]string{p, strings.concatenate({new, p[len(old):]}, context.temp_allocator)})
	}
	if len(moved) == 0 do return
	for mv in moved {
		k, m := delete_key(&file_tags, mv[0])
		delete(k)
		file_tags[strings.clone(mv[1])] = m
	}
	save_tags()
}

// ---------------------------------------------------------------------------
// Tag view: "tag:<id>" as the current location lists tagged items from anywhere.
// Entry names are absolute paths without the leading "/" so nested-name handling applies.

is_tag_view :: proc() -> bool {return strings.has_prefix(app.cwd, "tag:")}

load_tag_view :: proc(path: string) -> bool {
	id, ok := strconv.parse_uint(path[4:])
	if !ok || tag_by_id(u8(id)) == nil do return false
	clear(&app.entries)
	for p, m in file_tags {
		if m & (1 << u64(id)) == 0 do continue
		info, err := os.lstat(p, context.temp_allocator)
		if err != nil do continue // gone (moved by another program)
		e := Entry {
			name  = strings.clone(p[1:], virtual.arena_allocator(&app.listing)),
			size  = info.size,
			mtime = info.modification_time._nsec / 1_000_000_000,
			btime = info.creation_time._nsec / 1_000_000_000,
			atime = info.access_time._nsec / 1_000_000_000,
		}
		e.is_link = info.type == .Symlink
		e.is_dir = info.type == .Directory || (e.is_link && os.is_dir(p))
		e.kind = kind_of(info.name, info.mode)
		append(&app.entries, e)
	}
	app.base_count = len(app.entries)
	return true
}

// ---------------------------------------------------------------------------
// The little color arc under the radial menu

Arc_Item :: struct {
	color: u8,
	label: string,
	on:    bool,
}

menu_tag_id := -1 // sidebar tag whose menu is open (the arc then picks its color)

arc_items :: proc() -> [dynamic]Arc_Item {
	out := make([dynamic]Arc_Item, context.temp_allocator)
	if menu_tag_id >= 0 {
		t := tag_by_id(u8(menu_tag_id))
		for c in u8(0) ..< 8 do append(&out, Arc_Item{c, TAG_NAMES[c], t != nil && t.color == c})
		return out
	}
	sel := selection()
	for t in tag_list {
		if len(out) == 8 do break
		on := len(sel) > 0
		for vi in sel do if mask_of(app.entries[vi].name) & (1 << t.id) == 0 do on = false
		append(&out, Arc_Item{t.color, t.name, on})
	}
	return out
}

arc_click :: proc(i: int) {
	if menu_tag_id >= 0 {
		if t := tag_by_id(u8(menu_tag_id)); t != nil {
			t.color = u8(i)
			save_tags()
		}
		return
	}
	if i < len(tag_list) do toggle_tag(tag_list[i].id)
}

tag_dot :: proc(x, y, r: f32, c: u8, on := false) {
	rrect({x - r, y - r, 2 * r, 2 * r}, r, hex(0x10141f, 230))
	if c == 0 {
		rrect({x - r + px(1.5), y - r + px(1.5), 2 * r - px(3), 2 * r - px(3)}, r, DIM, px(1.5))
	} else {
		rrect({x - r + px(1.5), y - r + px(1.5), 2 * r - px(3), 2 * r - px(3)}, r, hex(TAG_COLORS[c]))
	}
	if on do rrect({x - r - px(3), y - r - px(3), 2 * r + px(6), 2 * r + px(6)}, r + px(3), FG, px(1.5))
}

// Up to three colored dots for a file's tags.
file_tag_dots :: proc(x, y, r: f32, name: string) {
	m := mask_of(name)
	if m == 0 do return
	n := 0
	for t in tag_list {
		if m & (1 << t.id) == 0 do continue
		tag_dot(x + f32(n) * r * 1.4, y, r, t.color)
		n += 1
		if n == 3 do break
	}
}

draw_sidebar_tags :: proc(y: ^f32, w: f32) {
	side_section(y, w, "タグ")
	for t in tag_list {
		path := fmt.tprintf("tag:%d", t.id)
		r := side_row(y, w, 0, t.name, app.cwd == path)
		tag_dot(r.x + px(20), r.y + r.h / 2, px(7), t.color)
		if b := bounce_of(path); b > 0 do rrect(r, px(6), with_alpha(ACCENT, u8(min(b * 900, 120))))
		drop_hover(r, .Tag, path, t.name, px(6), t.id)
		if clicked(r) do push(.Navigate, 0, strings.clone(path, context.temp_allocator))
		if hovering(r) && app.pressed && app.button == 3 {
			menu_tag_id = int(t.id)
			push(.Side_Menu)
		}
	}
	r := side_row(y, w, I_PLUS, "新しいタグ…", false, true)
	if clicked(r) do push(.Tag_New)
}

// ---------------------------------------------------------------------------
// Dialogs: tag picker (iPad's tag sheet) and new / edit tag

tag_edit_id := -1 // -1 = creating a new tag
tag_edit_color: u8
tag_new_for_selection: bool // a tag created from the picker is applied right away

tag_begin_edit :: proc(id: int) {
	tag_edit_id = id
	tag_edit_color = 0
	name := ""
	if id >= 0 {
		if t := tag_by_id(u8(id)); t != nil {
			name = t.name
			tag_edit_color = t.color
		}
	}
	edit_set(&app.dlg_edit, name, true)
	app.dialog = .Tag_Edit
	app.edit_focus = .Dialog
}

tag_edit_ok :: proc() {
	name := strings.trim_space(edit_str(&app.dlg_edit))
	if name == "" do return
	if tag_edit_id >= 0 {
		if t := tag_by_id(u8(tag_edit_id)); t != nil {
			delete(t.name)
			t.name = strings.clone(name)
			t.color = tag_edit_color
			save_tags()
		}
	} else {
		id := create_tag(name, tag_edit_color)
		if tag_new_for_selection do toggle_tag(id)
	}
	back_to_picker := tag_new_for_selection
	tag_new_for_selection = false
	app.dialog = .Tag_Pick if back_to_picker else .None
	app.edit_focus = .None
}

@(private = "file")
color_row :: proc(x, y: f32, cur: u8) -> (picked: int) {
	picked = -1
	for c in 0 ..< 8 {
		cx := x + f32(c) * px(34) + px(14)
		hit := Rect{cx - px(14), y - px(14), px(28), px(28)}
		if hovering(hit) do rrect(hit, px(14), HOVER)
		tag_dot(cx, y, px(10), u8(c), u8(c) == cur)
		if clicked(hit) do picked = c
	}
	return
}

draw_tag_edit :: proc(W, H: f32) {
	p := progress(app.dlg_t0, 0.22)
	fill({0, 0, W, H}, hex(0x000000, u8(90 * p)))
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	w := min(px(400), W - px(32))
	h := px(230)
	r := Rect{(W - w) / 2, (H - h) / 2 + (1 - p) * px(24), w, h}
	rrect(r, px(14), POP_BG)
	rrect(r, px(14), LINE, px(1))
	title := "新しいタグ" if tag_edit_id < 0 else "タグを編集"
	tw := f32(text_width(title, fs(16), true))
	text(r.x + (r.w - tw) / 2, r.y + px(40), title, fs(16), FG, true)
	er := Rect{r.x + px(24), r.y + px(60), r.w - px(48), px(36)}
	draw_edit(&app.dlg_edit, er, true)
	if c := color_row(er.x, er.y + er.h + px(30), tag_edit_color); c >= 0 do tag_edit_color = u8(c)
	bw := (r.w - px(24 * 2 + 12)) / 2
	by := r.y + r.h - px(24 + 36)
	ok := strings.trim_space(edit_str(&app.dlg_edit)) != ""
	if text_button({r.x + px(24), by, bw, px(36)}, "キャンセル") do push(.Dialog_Cancel)
	if text_button({r.x + px(36) + bw, by, bw, px(36)}, "作成" if tag_edit_id < 0 else "保存", 1 if ok else 0) && ok do push(.Dialog_Ok)
}

draw_tag_pick :: proc(W, H: f32) {
	p := progress(app.dlg_t0, 0.22)
	fill({0, 0, W, H}, hex(0x000000, u8(90 * p)))
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	rows := len(tag_list) + 1
	w := min(px(380), W - px(32))
	h := min(px(140) + f32(rows) * px(40), H - px(40))
	r := Rect{(W - w) / 2, (H - h) / 2 + (1 - p) * px(24), w, h}
	rrect(r, px(14), POP_BG)
	rrect(r, px(14), LINE, px(1))
	sel := selection()
	title := fmt.tprintf("タグ（%d 個のアイテム）", len(sel))
	tw := f32(text_width(title, fs(16), true))
	text(r.x + (r.w - tw) / 2, r.y + px(40), title, fs(16), FG, true)
	set_clip({r.x, r.y + px(56), r.w, r.h - px(56) - px(72)})
	y := r.y + px(60)
	for t in tag_list {
		row := Rect{r.x + px(14), y, r.w - px(28), px(38)}
		if hovering(row) do rrect(row, px(8), HOVER)
		tag_dot(row.x + px(20), row.y + row.h / 2, px(8), t.color)
		text(row.x + px(42), baseline(row, fs(14)), t.name, fs(14), FG)
		have := 0
		for vi in sel do if mask_of(app.entries[vi].name) & (1 << t.id) != 0 do have += 1
		mark := "✓" if have == len(sel) && have > 0 else ("−" if have > 0 else "")
		if mark != "" do text(row.x + row.w - px(28), baseline(row, fs(15)), mark, fs(15), ACCENT, true)
		if clicked(row) do toggle_tag(t.id)
		y += px(40)
	}
	nr := Rect{r.x + px(14), y, r.w - px(28), px(38)}
	if hovering(nr) do rrect(nr, px(8), HOVER)
	glyph_center({nr.x + px(8), nr.y, px(24), nr.h}, I_PLUS, fs(13), ACCENT)
	text(nr.x + px(42), baseline(nr, fs(14)), "新しいタグ…", fs(14), ACCENT)
	if clicked(nr) {
		tag_new_for_selection = true
		push(.Tag_New)
	}
	reset_clip()
	br := Rect{r.x + r.w - px(124), r.y + r.h - px(56), px(100), px(36)}
	if text_button(br, "完了", 1) do push(.Dialog_Cancel)
}
