package main

// Sorting and grouping: 8 sort keys × ascending/descending × folders-first,
// optionally grouped (type, date, size, extension, tag, first letter) with section
// headers. The choice is remembered in ~/.config/ame-filemanager/view.conf.

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Group_By :: enum {
	None, Type, Date, Size, Ext, Tag, Initial,
}

SORT_NAMES := [Sort_Key]string {
	.Name     = "名前",
	.Modified = "更新日時",
	.Created  = "作成日時",
	.Accessed = "アクセス日時",
	.Size     = "サイズ",
	.Type     = "種類",
	.Ext      = "拡張子",
	.Tag      = "タグ",
}

GROUP_NAMES := [Group_By]string {
	.None    = "なし",
	.Type    = "種類",
	.Date    = "日付",
	.Size    = "サイズ",
	.Ext     = "拡張子",
	.Tag     = "タグ",
	.Initial = "頭文字",
}

KIND_NAMES := [Kind]string {
	.Generic  = "その他",
	.Text     = "テキスト",
	.Code     = "コード",
	.Image    = "画像",
	.Video    = "動画",
	.Audio    = "音楽",
	.Archive  = "圧縮ファイル",
	.Pdf      = "PDF",
	.Document = "文書",
	.Exec     = "実行ファイル",
}

DATE_GROUPS := [6]string{"今日", "昨日", "今週", "今月", "今年", "それ以前"}
SIZE_GROUPS := [6]string{"フォルダー", "空", "小（100 kB 未満）", "中（10 MB 未満）", "大（1 GB 未満）", "巨大（1 GB 以上）"}

Group :: struct {
	start: int, // first view index of the group
	label: string,
}

@(private = "file") day_marks: [5]i64 // start of today, yesterday, this week, this month, this year

entry_time :: proc(e: ^Entry) -> i64 {
	#partial switch app.sort {
	case .Created:  return e.btime if e.btime != 0 else e.mtime
	case .Accessed: return e.atime
	}
	return e.mtime
}

@(private = "file")
ext_of :: proc(e: ^Entry) -> string {
	if e.is_dir do return ""
	_, ext := file_ext(filepath.base(e.name))
	return ext
}

@(private = "file")
first_tag :: proc(e: ^Entry) -> int {
	m := mask_of(e.name)
	for t, i in tag_list do if m & (1 << t.id) != 0 do return i
	return len(tag_list) // untagged last
}

@(private = "file")
initial :: proc(e: ^Entry) -> string {
	r, _ := utf8.decode_rune_in_string(filepath.base(e.name))
	switch {
	case r >= '0' && r <= '9': return "0–9"
	case unicode.is_letter(r):
		buf: [4]u8
		n := encode_rune(buf[:], unicode.to_upper(r))
		return strings.clone(string(buf[:n]), context.temp_allocator)
	}
	return "記号"
}

// Group of an entry: rank orders groups, sub breaks ties (extension, initial).
group_key :: proc(e: ^Entry) -> (rank: int, sub: string) {
	switch app.group {
	case .None:
	case .Type:
		if e.is_dir do return 0, ""
		return 1 + int(e.kind), ""
	case .Date:
		t := entry_time(e)
		for m, i in day_marks do if t >= m do return i, ""
		return len(day_marks), ""
	case .Size:
		switch {
		case e.is_dir:                return 0, ""
		case e.size == 0:             return 1, ""
		case e.size < 100_000:        return 2, ""
		case e.size < 10_000_000:     return 3, ""
		case e.size < 1_000_000_000:  return 4, ""
		}
		return 5, ""
	case .Ext:
		if e.is_dir do return 0, ""
		x := ext_of(e)
		return 2 if x == "" else 1, x
	case .Tag:
		return first_tag(e), ""
	case .Initial:
		ini := initial(e)
		return 0 if ini == "0–9" else (2 if ini == "記号" else 1), ini
	}
	return 0, ""
}

group_label :: proc(e: ^Entry) -> string {
	rank, sub := group_key(e)
	switch app.group {
	case .None:
	case .Type:    return "フォルダー" if rank == 0 else KIND_NAMES[Kind(rank - 1)]
	case .Date:    return DATE_GROUPS[rank]
	case .Size:    return SIZE_GROUPS[rank]
	case .Ext:     return "フォルダー" if rank == 0 else (strings.to_upper(sub, context.temp_allocator) if rank == 1 else "拡張子なし")
	case .Tag:     return tag_list[rank].name if rank < len(tag_list) else "タグなし"
	case .Initial: return sub
	}
	return ""
}

grouping :: proc() -> bool {return app.group != .None && !tree_mode()}

// Sort order: group, then folders first (if on), then the key, then the name.
entry_less :: proc(x, y: int) -> bool {
	a, b := &app.entries[x], &app.entries[y]
	if grouping() {
		ra, sa := group_key(a)
		rb, sb := group_key(b)
		if ra != rb do return ra < rb
		if sa != sb do return natural_less(sa, sb)
	}
	if app.dirs_first && a.is_dir != b.is_dir do return a.is_dir
	cmp := 0
	switch app.sort {
	case .Name:
	case .Modified, .Created, .Accessed:
		ta, tb := entry_time(a), entry_time(b)
		cmp = -1 if ta < tb else (1 if ta > tb else 0)
	case .Size:
		cmp = -1 if a.size < b.size else (1 if a.size > b.size else 0)
	case .Type:
		cmp = -1 if a.kind < b.kind else (1 if a.kind > b.kind else 0)
	case .Ext:
		ea, eb := ext_of(a), ext_of(b)
		cmp = 0 if ea == eb else (-1 if natural_less(ea, eb) else 1)
	case .Tag:
		ta, tb := first_tag(a), first_tag(b)
		cmp = -1 if ta < tb else (1 if ta > tb else 0)
	}
	if cmp == 0 {
		if natural_less(a.name, b.name) do cmp = -1
		else if natural_less(b.name, a.name) do cmp = 1
	}
	return cmp > 0 if app.sort_desc else cmp < 0
}

// Called before sorting: local-time day boundaries for date groups.
prepare_sort :: proc() {
	now := libc.time(nil)
	tm := libc.localtime(&now)^
	tm.tm_hour, tm.tm_min, tm.tm_sec = 0, 0, 0
	today := i64(libc.mktime(&tm))
	wd := (tm.tm_wday + 6) % 7 // Monday = 0
	m := tm
	m.tm_mday = 1
	month := i64(libc.mktime(&m))
	y := tm
	y.tm_mday, y.tm_mon = 1, 0
	year := i64(libc.mktime(&y))
	day_marks = {today, today - 86400, today - i64(wd) * 86400, month, year}
}

// Section boundaries over the sorted view.
build_groups :: proc() {
	for g in app.groups do delete(g.label)
	clear(&app.groups)
	if !grouping() do return
	prev := ""
	for vi, k in app.view {
		l := group_label(&app.entries[vi])
		if k == 0 || l != prev {
			append(&app.groups, Group{k, strings.clone(l)})
			prev = l
		}
	}
}

// ---------------------------------------------------------------------------
// Layout: item rects (body coordinates) with room for group headers

GROUP_HDR :: 40

Header :: struct {
	y:     f32,
	label: string,
	count: int,
}

layout_items :: proc() {
	clear(&app.lay)
	clear(&app.hdrs)
	n := len(app.view)
	gi := 0
	add_header :: proc(gi: ^int, k, n: int, y: ^f32) {
		g := app.groups[gi^]
		end := app.groups[gi^ + 1].start if gi^ + 1 < len(app.groups) else n
		append(&app.hdrs, Header{y^, g.label, end - k})
		y^ += px(GROUP_HDR)
		gi^ += 1
	}
	if app.grid {
		pad := px(12)
		cols := max(app.cols, 1)
		cw := (app.body.w - 2 * pad) / f32(cols)
		y := pad
		col := 0
		for k in 0 ..< n {
			if gi < len(app.groups) && app.groups[gi].start == k {
				if col != 0 {y += px(GRID_CELL_H); col = 0}
				add_header(&gi, k, n, &y)
			}
			append(&app.lay, Rect{pad + f32(col) * cw, y, cw, px(GRID_CELL_H)})
			col += 1
			if col == cols {col = 0; y += px(GRID_CELL_H)}
		}
		if col != 0 do y += px(GRID_CELL_H)
		app.lay_h = y + pad
		return
	}
	tree := tree_mode()
	y := px(TREE_HEAD) + px(4) if tree else px(LIST_HEAD_H)
	rh := px(TREE_ROW) if tree else px(LIST_ROW_H)
	for k in 0 ..< n {
		if gi < len(app.groups) && app.groups[gi].start == k do add_header(&gi, k, n, &y)
		append(&app.lay, Rect{0, y, app.body.w, rh})
		y += rh
	}
	app.lay_h = y + px(48)
}

draw_group_headers :: proc(b: Rect) {
	for h in app.hdrs {
		y := b.y + h.y - app.scroll
		if y > b.y + b.h || y + px(GROUP_HDR) < b.y do continue
		r := Rect{b.x + px(16), y, b.w - px(32), px(GROUP_HDR)}
		w := text(r.x, r.y + px(26), h.label, fs(15), FG, true)
		text(r.x + w + px(10), r.y + px(26), fmt.tprintf("%d", h.count), fs(12), DIM)
		fill({r.x, r.y + px(GROUP_HDR) - px(6), r.w, 1}, LINE)
	}
}

// ---------------------------------------------------------------------------
// Persisted choice

@(private = "file")
view_conf :: proc() -> string {
	p, _ := filepath.join({app_config_dir(), "view.conf"}, context.temp_allocator)
	return p
}

load_view_prefs :: proc() {
	app.dirs_first = true
	defer {default_pref = current_pref(); load_folder_prefs()}
	data, err := os.read_entire_file_from_path(view_conf(), context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		k, _, v := strings.partition(line, "=")
		switch k {
		case "sort":  for s in Sort_Key do if fmt.tprint(s) == v do app.sort = s
		case "desc":  app.sort_desc = v == "1"
		case "dirs":  app.dirs_first = v != "0"
		case "group": for g in Group_By do if fmt.tprint(g) == v do app.group = g
		case "view":
			app.grid, app.tree = v == "grid", v == "tree"
		}
	}
}

save_view_prefs :: proc() {
	view := "grid" if app.grid else ("tree" if app.tree else "list")
	s := fmt.tprintf("sort=%v\ndesc=%d\ndirs=%d\ngroup=%v\nview=%s\n", app.sort, int(app.sort_desc), int(app.dirs_first), app.group, view)
	p := view_conf()
	_ = os.make_directory_all(filepath.dir(p))
	_ = os.write_entire_file_from_string(p, s)
}

// Per-folder order: folders.conf holds one "sort\tdesc\tdirs\tgroup\tpath" line per
// folder the user changed; other folders use the last choice made anywhere.

Sort_Pref :: struct {
	sort:  Sort_Key,
	desc:  bool,
	dirs:  bool,
	group: Group_By,
}

@(private = "file") default_pref: Sort_Pref
@(private = "file") folder_prefs: map[string]Sort_Pref

@(private = "file")
current_pref :: proc() -> Sort_Pref {return {app.sort, app.sort_desc, app.dirs_first, app.group}}

@(private = "file")
folders_conf :: proc() -> string {
	p, _ := filepath.join({app_config_dir(), "folders.conf"}, context.temp_allocator)
	return p
}

apply_folder_prefs :: proc(path: string) {
	pr, ok := folder_prefs[path]
	if !ok do pr = default_pref
	app.sort, app.sort_desc, app.dirs_first, app.group = pr.sort, pr.desc, pr.dirs, pr.group
}

// The user changed the order here: remember it for this folder and as the default.
remember_sort :: proc() {
	pr := current_pref()
	default_pref = pr
	if app.cwd != "" && !strings.contains(app.cwd, "\n") {
		if app.cwd in folder_prefs do folder_prefs[app.cwd] = pr
		else do folder_prefs[strings.clone(app.cwd)] = pr
	}
	save_view_prefs()
	b := strings.builder_make(context.temp_allocator)
	for path, f in folder_prefs {
		fmt.sbprintf(&b, "%v\t%d\t%d\t%v\t%s\n", f.sort, int(f.desc), int(f.dirs), f.group, path)
	}
	_ = os.write_entire_file_from_string(folders_conf(), strings.to_string(b))
}

@(private = "file")
load_folder_prefs :: proc() {
	data, err := os.read_entire_file_from_path(folders_conf(), context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		f := strings.split_n(line, "\t", 5, context.temp_allocator)
		if len(f) != 5 || f[4] == "" do continue
		pr := Sort_Pref{dirs = f[2] != "0", desc = f[1] == "1"}
		for s in Sort_Key do if fmt.tprint(s) == f[0] do pr.sort = s
		for g in Group_By do if fmt.tprint(g) == f[3] do pr.group = g
		folder_prefs[strings.clone(f[4])] = pr
	}
}

// Radial menus for sorting and grouping.
open_sort_menu :: proc() {
	clear(&app.menu_items)
	for name, s in SORT_NAMES {
		append(&app.menu_items, Menu_Item{label = name, act = .Sort_By, arg = int(s), has_arg = true, on = app.sort == s, ok = true})
	}
	append(&app.menu_items, Menu_Item{label = "降順" if app.sort_desc else "昇順", act = .Sort_Dir, on = app.sort_desc, ok = true})
	append(&app.menu_items, Menu_Item{label = "フォルダー優先", act = .Dirs_First, on = app.dirs_first, ok = true})
	append(&app.menu_items, Menu_Item{label = "グループ…", act = .Group_Menu, on = app.group != .None, ok = true}) // labels must outlive the frame: literals only
	app.menu_open, app.menu_main = true, false
	app.prev_menu = false
}

open_group_menu :: proc() {
	clear(&app.menu_items)
	for name, g in GROUP_NAMES {
		append(&app.menu_items, Menu_Item{label = name, act = .Group_By, arg = int(g), has_arg = true, on = app.group == g, ok = true})
	}
	app.menu_open, app.menu_main = true, false
	app.prev_menu = false
}
