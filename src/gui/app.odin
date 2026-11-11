package main

// GlassFilee GUI: a GNOME Files–style file manager drawn in software on a
// translucent SDL3 window. Odin all the way down; no GTK, no GPU context.

import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import gf "../core"

// ---------------------------------------------------------------------------
// Theme (matches the ame-shell terminal: #060913 @ 0.7, #cdd6f4 text, #89b4fa accent)

BG: Color
FG :: Color{0xcd, 0xd6, 0xf4, 255}
DIM :: Color{0xcd, 0xd6, 0xf4, 150}
ACCENT :: Color{0x89, 0xb4, 0xfa, 255}
HOVER :: Color{0xff, 0xff, 0xff, 16}
ACTIVE :: Color{0xff, 0xff, 0xff, 30}
LINE :: Color{0xff, 0xff, 0xff, 22}
SEL :: Color{0x89, 0xb4, 0xfa, 70}
POP_BG :: Color{0x14, 0x18, 0x24, 250}
DANGER :: Color{0xf3, 0x8b, 0xa8, 255}

// Font Awesome codepoints in Symbols Nerd Font
I_BACK :: 0xf053
I_FWD :: 0xf054
I_SEARCH :: 0xf002
I_GRID :: 0xf009
I_LIST :: 0xf03a
I_MENU :: 0xf0c9
I_CLOSE :: 0xf00d
I_HOME :: 0xf015
I_DESKTOP :: 0xf108
I_DOCS :: 0xf15c
I_DOWNLOAD :: 0xf019
I_MUSIC :: 0xf001
I_PICTURES :: 0xf03e
I_VIDEO :: 0xf008
I_TRASH :: 0xf1f8
I_DRIVE :: 0xf0a0
I_FOLDER_OPEN :: 0xf07c
I_LINK :: 0xf0c1
I_SORT_UP :: 0xf0de
I_SORT_DOWN :: 0xf0dd

// ---------------------------------------------------------------------------
// State

Entry :: struct {
	name:                     string,
	size, mtime:              i64,
	is_dir, is_link, hidden:  bool,
	sel:                      bool,
	kind:                     Kind,
}

Place :: struct {
	label: string,
	icon:  rune,
	path:  string,
}

Act :: enum {
	None, Open, Back, Forward, Up, Home, Navigate, Path_Edit, Search, View_Grid, View_List,
	Main_Menu, Context, Copy, Cut, Paste, Rename, Trash, Delete, Restore, Mkdir, Select_All,
	Terminal, Hidden, Reload, Empty_Trash, Sort, Dialog_Ok, Dialog_Cancel, Close, Extract, Compress,
	New_Tab, Close_Tab, Switch_Tab, Next_Tab, Convert, Preview,
}

Pending :: struct {
	act: Act,
	i:   int,
	s:   string,
}

Dialog :: enum {
	None, Rename, Mkdir, Compress, Confirm_Delete, Confirm_Empty_Trash,
}

Focus :: enum {
	None, Path, Search, Dialog,
}

Sort_Key :: enum {
	Name, Size, Modified,
}

Edit :: struct {
	buf:         [dynamic]u8,
	cur, anchor: int,
	pre:         string,
}

Menu_Item :: struct {
	label: string,
	act:   Act,
	key:   string,
	ok:    bool,
}

Tab :: struct {
	cwd:       string,
	back, fwd: [dynamic]string,
	scroll:    f32,
}

App :: struct {
	tabs:              [dynamic]Tab, // the current tab's fields live in App; tabs[cur_tab] is refreshed on switch
	cur_tab:           int,
	tab_x:             f32, // animated position of the active-tab highlight
	ime_rect:          [4]i32,
	text_clip:         string,
	S:                 f32,
	running:           bool,
	home, trash_files: string,
	cwd:               string,
	listing:           virtual.Arena,
	// recursive search: results are appended after the base listing
	search_arena:      virtual.Arena,
	base_count:        int,
	walk_stack:        [dynamic]string,
	walk_q:            string,
	walking:           bool,
	entries:           [dynamic]Entry,
	view:              [dynamic]int,
	back, fwd:         [dynamic]string,
	places:            [dynamic]Place,
	grid, show_hidden: bool,
	sort:              Sort_Key,
	sort_desc:         bool,
	scroll, scroll_to: f32, // displayed / target (smooth scrolling)
	now, dt, last_t:   f32,
	animating:         bool, // something is still moving: keep drawing frames
	nav_t0, nav_dir:   f32,
	menu_t0, dlg_t0:   f32,
	toast_t0:          f32,
	prev_dialog:       Dialog,
	prev_menu:         bool,
	focus, anchor:     int,
	edit_focus:        Focus,
	path_edit, search: Edit,
	searching:         bool,
	dlg_edit:          Edit,
	dialog:            Dialog,
	dialog_target:     int,
	menu_open:         bool,
	menu_main:         bool,
	menu_pos:          [2]f32,
	menu_items:        [dynamic]Menu_Item,
	clip:              [dynamic]string,
	clip_cut:          bool,
	toast:             string,
	toast_until:       i64,
	// input for the current frame
	mx, my:            f32,
	pressed, released: bool,
	held:              bool,
	button, clicks:    u8,
	wheel:             f32,
	mod:               Mods,
	band_on:           bool,
	cdrag_on:          bool, // Ctrl held on an item: a drag opens the convert donut
	cdrag_x, cdrag_y:  f32,
	cdrag_toggle:      int, // entry to deselect if it turns out to be a plain Ctrl+click
	band_x, band_y:    f32,
	blocked:           bool,
	hdr_hot:           [dynamic]Rect,
	header_h:          f32,
	body:              Rect,
	cols:              int,
	text_input_on:     bool,
	pending:           [dynamic]Pending,
}

app: App

px :: #force_inline proc(v: f32) -> f32 {return v * app.S}
fs :: #force_inline proc(v: f32) -> i32 {return i32(math.round(v * app.S))}

push :: proc(act: Act, i := 0, s := "") {
	append(&app.pending, Pending{act, i, s})
}

toastf :: proc(format: string, args: ..any) {
	delete(app.toast)
	app.toast = fmt.aprintf(format, ..args)
	app.toast_until = ticks_ms() + 3500
	app.toast_t0 = now_s()
}

now_s :: proc() -> f32 {return f32(ticks_ms()) / 1000}

ease_out :: proc(x: f32) -> f32 {
	x := clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x) * (1 - x)
}

// Eased 0..1 progress of an animation that started at t0; keeps frames coming until done.
progress :: proc(t0, dur: f32) -> f32 {
	p := (app.now - t0) / dur
	if p < 1 do app.animating = true
	return ease_out(p)
}

status_text :: proc(st: gf.OperationStatus) -> string {
	#partial switch st {
	case .ErrorNotFound:   return "見つかりません"
	case .ErrorPermission: return "権限がありません"
	case .ErrorExists:     return "同じ名前のアイテムが既にあります"
	case .ErrorIO:         return "入出力エラー"
	case .ErrorInvalidPath: return "不正なパスです"
	}
	return "エラー"
}

// ---------------------------------------------------------------------------
// Directory model

kind_of :: proc(name: string, mode: os.Permissions) -> Kind {
	if _, _, ok := archive_kind(name); ok do return .Archive
	ext := strings.to_lower(filepath.ext(name), context.temp_allocator)
	switch ext {
	case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".avif", ".heic", ".tiff", ".ico", ".xcf", ".kra":
		return .Image
	case ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".wmv", ".flv":
		return .Video
	case ".mp3", ".flac", ".ogg", ".wav", ".m4a", ".opus", ".aac", ".wma":
		return .Audio
	case ".zip", ".tar", ".gz", ".xz", ".zst", ".7z", ".rar", ".bz2", ".tgz", ".deb", ".apk", ".rpm", ".iso":
		return .Archive
	case ".pdf":
		return .Pdf
	case ".doc", ".docx", ".odt", ".xls", ".xlsx", ".ods", ".ppt", ".pptx", ".odp", ".rtf", ".epub":
		return .Document
	case ".c", ".h", ".cpp", ".hpp", ".odin", ".zig", ".py", ".js", ".ts", ".tsx", ".jsx", ".rs", ".go",
	     ".java", ".kt", ".sh", ".html", ".css", ".json", ".toml", ".yaml", ".yml", ".xml", ".lua", ".rb", ".r", ".lean":
		return .Code
	case ".txt", ".md", ".log", ".csv", ".ini", ".conf", ".cfg", "":
		if ext == "" && .Execute_User in mode do return .Exec
		return .Text
	}
	return .Exec if .Execute_User in mode else .Generic
}

load :: proc(path: string) -> bool {
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil {
		toastf("「%s」を開けません", filepath.base(path))
		return false
	}
	virtual.arena_free_all(&app.listing)
	stop_walk()
	clear(&app.entries)
	a := virtual.arena_allocator(&app.listing)
	for fi in infos {
		e := Entry {
			name  = strings.clone(fi.name, a),
			size  = fi.size,
			mtime = fi.modification_time._nsec / 1_000_000_000,
		}
		e.is_link = fi.type == .Symlink
		e.is_dir = fi.type == .Directory || (e.is_link && os.is_dir(fi.fullpath))
		e.hidden = strings.has_prefix(fi.name, ".") || strings.has_suffix(fi.name, "~")
		e.kind = kind_of(fi.name, fi.mode)
		append(&app.entries, e)
	}
	app.base_count = len(app.entries)
	return true
}

// Natural, case-insensitive compare ("file2" < "file10").
natural_less :: proc(a, b: string) -> bool {
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		ca, cb := a[i], b[j]
		if is_digit(ca) && is_digit(cb) {
			si, sj := i, j
			for i < len(a) && is_digit(a[i]) do i += 1
			for j < len(b) && is_digit(b[j]) do j += 1
			na := strings.trim_left(a[si:i], "0")
			nb := strings.trim_left(b[sj:j], "0")
			if len(na) != len(nb) do return len(na) < len(nb)
			if na != nb do return na < nb
			continue
		}
		la, lb := to_lower(ca), to_lower(cb)
		if la != lb do return la < lb
		i += 1
		j += 1
	}
	return len(a) - i < len(b) - j
}
is_digit :: proc(c: u8) -> bool {return c >= '0' && c <= '9'}
to_lower :: proc(c: u8) -> u8 {return c + 32 if c >= 'A' && c <= 'Z' else c}

entry_less :: proc(x, y: int) -> bool {
	a, b := &app.entries[x], &app.entries[y]
	if a.is_dir != b.is_dir do return a.is_dir
	less: bool
	switch app.sort {
	case .Name:     less = natural_less(a.name, b.name)
	case .Size:     less = a.size < b.size if a.size != b.size else natural_less(a.name, b.name)
	case .Modified: less = a.mtime < b.mtime if a.mtime != b.mtime else natural_less(a.name, b.name)
	}
	return !less if app.sort_desc else less
}

refilter :: proc() {
	clear(&app.view)
	q := strings.to_lower(edit_str(&app.search), context.temp_allocator) if app.searching else ""
	if q != app.walk_q do start_walk(q)
	for e, i in app.entries {
		if i >= app.base_count && q == "" do break
		if !app.show_hidden && e.hidden do continue
		if q != "" && !strings.contains(strings.to_lower(filepath.base(e.name), context.temp_allocator), q) do continue
		append(&app.view, i)
	}
	slice.sort_by(app.view[:], entry_less)
	if app.focus >= len(app.view) do app.focus = len(app.view) - 1
}

Nav :: enum {
	Push, Back, Forward, Replace,
}

go_to :: proc(path: string, mode := Nav.Push, select_name := "") -> bool {
	p := path
	if !filepath.is_abs(p) do p, _ = filepath.join({app.cwd, p}, context.temp_allocator)
	p, _ = filepath.clean(p, context.temp_allocator)
	if !load(p) do return false
	new_cwd := strings.clone(p)
	switch mode {
	case .Push:
		if app.cwd != "" do append(&app.back, app.cwd)
		for s in app.fwd do delete(s)
		clear(&app.fwd)
	case .Back:    append(&app.fwd, app.cwd)
	case .Forward: append(&app.back, app.cwd)
	case .Replace: delete(app.cwd)
	}
	app.cwd = new_cwd
	if mode != .Replace {
		app.scroll, app.scroll_to = 0, 0
		app.nav_t0 = now_s()
		app.nav_dir = -1 if mode == .Back else 1
		app.focus, app.anchor = -1, -1
		app.searching = false
		if app.edit_focus == .Search || app.edit_focus == .Path do app.edit_focus = .None
	}
	refilter()
	if select_name != "" {
		for vi, k in app.view {
			if app.entries[vi].name == select_name {
				app.entries[vi].sel = true
				app.focus, app.anchor = k, k
				ensure_visible(k)
			}
		}
	}
	title := fmt.tprintf("%s — GlassFilee", location_name())
	plat_set_title(string(title))
	return true
}

reload :: proc() {
	// keep selection by name across reloads
	keep := make(map[string]bool, context.temp_allocator)
	for e in app.entries do if e.sel do keep[strings.clone(e.name, context.temp_allocator)] = true
	cwd := strings.clone(app.cwd, context.temp_allocator)
	if !go_to(cwd, .Replace) {
		go_to(app.home, .Push)
		return
	}
	for &e in app.entries do e.sel = e.name in keep
}

in_trash :: proc() -> bool {
	return app.cwd == app.trash_files
}

location_name :: proc() -> string {
	if in_trash() do return "ゴミ箱"
	if app.cwd == app.home do return "ホーム"
	if app.cwd == "/" do return "/"
	return filepath.base(app.cwd)
}

full_path :: proc(name: string) -> string {
	p, _ := filepath.join({app.cwd, name}, context.temp_allocator)
	return p
}

selection :: proc() -> [dynamic]int {
	out := make([dynamic]int, context.temp_allocator)
	for vi in app.view do if app.entries[vi].sel do append(&out, vi)
	return out
}

clear_sel :: proc() {
	for &e in app.entries do e.sel = false
}

format_size :: proc(size: i64) -> string {
	if size < 1000 do return fmt.tprintf("%d バイト", size)
	units := [?]string{"kB", "MB", "GB", "TB"}
	v := f64(size) / 1000
	u := 0
	for v >= 1000 && u < len(units) - 1 {
		v /= 1000
		u += 1
	}
	return fmt.tprintf("%.1f %s", v, units[u])
}

format_time :: proc(t: i64) -> string {
	tt := libc.time_t(t)
	now := libc.time(nil)
	tm := libc.localtime(&tt)^
	nt := libc.localtime(&now)^
	if tm.tm_year == nt.tm_year && tm.tm_yday == nt.tm_yday do return fmt.tprintf("%02d:%02d", tm.tm_hour, tm.tm_min)
	if tm.tm_year == nt.tm_year && tm.tm_yday == nt.tm_yday - 1 do return fmt.tprintf("昨日 %02d:%02d", tm.tm_hour, tm.tm_min)
	if tm.tm_year == nt.tm_year do return fmt.tprintf("%d月%d日", tm.tm_mon + 1, tm.tm_mday)
	return fmt.tprintf("%d年%d月%d日", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)
}

place_icon_for :: proc(path: string) -> rune {
	for p in app.places do if p.path == path && p.icon != I_HOME && p.icon != I_DRIVE && p.icon != I_TRASH do return p.icon
	return 0
}

// ---------------------------------------------------------------------------
// File operations

unique_dest :: proc(dir, name: string) -> string {
	dst, _ := filepath.join({dir, name}, context.temp_allocator)
	if !os.exists(dst) do return dst
	ext := filepath.ext(name)
	stem := name[:len(name) - len(ext)]
	if strings.has_prefix(name, ".") && ext == name do stem, ext = name, ""
	for n := 1; ; n += 1 {
		label := "(コピー)" if n == 1 else fmt.tprintf("(コピー %d)", n)
		dst, _ = filepath.join({dir, fmt.tprintf("%s %s%s", stem, label, ext)}, context.temp_allocator)
		if !os.exists(dst) do return dst
	}
}

do_paste :: proc() {
	srcs, cut := app.clip[:], app.clip_cut
	external := false
	if !plat_clipboard_is_ours() {
		if ext, ext_cut, ok := plat_get_clipboard_files(); ok do srcs, cut, external = ext[:], ext_cut, true
	}
	if len(srcs) == 0 {
		toastf("クリップボードは空です")
		return
	}
	done, failed := 0, 0
	last_err: gf.OperationStatus
	for src in srcs {
		if cut && filepath.dir(src) == app.cwd do continue
		if strings.has_prefix(app.cwd, src) && (len(app.cwd) == len(src) || app.cwd[len(src)] == '/') {
			toastf("フォルダーをそれ自身の中には貼り付けできません")
			return
		}
		dst := unique_dest(app.cwd, filepath.base(src))
		st := gf.move_file(src, dst) if cut else gf.copy_file(src, dst)
		if st == .Success do done += 1
		else {failed += 1; last_err = st}
	}
	if cut && !external {
		for s in app.clip do delete(s)
		clear(&app.clip)
	}
	reload()
	if failed > 0 do toastf("%d 個のアイテムを貼り付けできませんでした: %s", failed, status_text(last_err))
}

clip_selection :: proc(cut: bool) {
	sel := selection()
	if len(sel) == 0 do return
	for s in app.clip do delete(s)
	clear(&app.clip)
	for vi in sel do append(&app.clip, strings.clone(full_path(app.entries[vi].name)))
	app.clip_cut = cut
	plat_set_clipboard_files(app.clip[:], cut)
	n := len(sel)
	if n == 1 do toastf("「%s」を%sしました", app.entries[sel[0]].name, "切り取り" if cut else "コピー")
	else do toastf("%d 個のアイテムを%sしました", n, "切り取り" if cut else "コピー")
}

do_trash :: proc() {
	sel := selection()
	if len(sel) == 0 do return
	if in_trash() {
		app.dialog = .Confirm_Delete
		return
	}
	n, failed := 0, 0
	last := ""
	for vi in sel {
		name := app.entries[vi].name
		if gf.trash_path(full_path(name)) == .Success {
			n += 1
			last = strings.clone(name, context.temp_allocator)
		} else do failed += 1
	}
	reload()
	if failed > 0 do toastf("%d 個はゴミ箱へ移動できませんでした（Shift+Delete で完全に削除できます）", failed)
	else if n == 1 do toastf("「%s」をゴミ箱へ移動しました", last)
	else do toastf("%d 個のアイテムをゴミ箱へ移動しました", n)
}

do_delete :: proc() {
	failed := 0
	for vi in selection() {
		name := app.entries[vi].name
		st := gf.delete_from_trash(name) if in_trash() else gf.delete_path(full_path(name))
		if st != .Success do failed += 1
	}
	reload()
	if failed > 0 do toastf("%d 個のアイテムを削除できませんでした", failed)
}

do_restore :: proc() {
	failed := 0
	for vi in selection() {
		if gf.restore_from_trash(app.entries[vi].name) != .Success do failed += 1
	}
	reload()
	if failed > 0 do toastf("%d 個のアイテムを元に戻せませんでした（元の場所に同名のアイテムがあります）", failed)
}

open_entry :: proc(vi: int) {
	e := app.entries[vi]
	p := full_path(e.name)
	if e.is_dir {
		go_to(p)
		return
	}
	if spawn({"xdg-open", p}) == 0 do toastf("「%s」を開けません", e.name)
}

open_terminal :: proc() {
	terms := [?]string{os.get_env("TERMINAL", context.temp_allocator), "ame-terminal", "ghostty", "foot", "kgx", "gnome-terminal", "xterm"}
	for t in terms {
		if t == "" do continue
		if spawn({t}, app.cwd) != 0 do return
	}
	toastf("端末が見つかりません")
}

name_problem :: proc(name: string, allow := "", dir := "") -> string {
	if name == "" do return " "
	if strings.contains_rune(name, '/') do return "名前に「/」は使えません"
	if name == "." || name == ".." do return "その名前は使えません"
	if name != allow {
		if p, _ := filepath.join({app.cwd, dir, name}, context.temp_allocator); os.exists(p) do return "同じ名前のアイテムが既にあります"
	}
	if strings.has_prefix(name, ".") && !strings.has_prefix(allow, ".") do return "" // allowed, will be hidden
	return ""
}

dialog_ok :: proc() {
	switch app.dialog {
	case .Rename:
		vi := app.dialog_target
		old := app.entries[vi].name
		dir := filepath.dir(old) if strings.contains_rune(old, '/') else "" // search result in a subfolder
		name := strings.trim_space(edit_str(&app.dlg_edit))
		if name_problem(name, filepath.base(old), dir) != "" do return
		if dir != "" do name, _ = filepath.join({dir, name}, context.temp_allocator)
		if name != old {
			if st := gf.rename_path(full_path(old), full_path(name)); st != .Success {
				toastf("名前を変更できません: %s", status_text(st))
				return
			}
		}
		app.dialog = .None
		n := strings.clone(name, context.temp_allocator)
		reload()
		clear_sel()
		for k in 0 ..< len(app.view) do if app.entries[app.view[k]].name == n {
			app.entries[app.view[k]].sel = true
			app.focus, app.anchor = k, k
			ensure_visible(k)
		}
	case .Mkdir:
		name := strings.trim_space(edit_str(&app.dlg_edit))
		if name_problem(name) != "" do return
		if st := gf.create_directory(full_path(name)); st != .Success {
			toastf("フォルダーを作成できません: %s", status_text(st))
			return
		}
		app.dialog = .None
		n := strings.clone(name, context.temp_allocator)
		reload()
		clear_sel()
		for k in 0 ..< len(app.view) do if app.entries[app.view[k]].name == n {
			app.entries[app.view[k]].sel = true
			app.focus, app.anchor = k, k
			ensure_visible(k)
		}
	case .Compress:
		name := strings.trim_space(edit_str(&app.dlg_edit))
		if name_problem(name) != "" do return
		app.dialog = .None
		compress(name)
	case .Confirm_Delete:
		app.dialog = .None
		do_delete()
	case .Confirm_Empty_Trash:
		app.dialog = .None
		if gf.empty_trash() != .Success do toastf("一部のアイテムを削除できませんでした")
		if in_trash() do reload()
	case .None:
	}
	if app.dialog == .None && app.edit_focus == .Dialog do app.edit_focus = .None
}

begin_rename :: proc() {
	sel := selection()
	if len(sel) != 1 || in_trash() do return
	e := app.entries[sel[0]]
	app.dialog = .Rename
	app.dialog_target = sel[0]
	base := filepath.base(e.name)
	edit_set(&app.dlg_edit, base)
	// select the name without its extension, like GNOME
	ext := filepath.ext(base)
	if !e.is_dir && ext != "" && len(ext) < len(base) do app.dlg_edit.cur = len(base) - len(ext)
	app.dlg_edit.anchor = 0
	app.edit_focus = .Dialog
}

begin_mkdir :: proc() {
	if in_trash() do return
	app.dialog = .Mkdir
	edit_set(&app.dlg_edit, "名称未設定フォルダー", true)
	app.edit_focus = .Dialog
}

run_pending :: proc() {
	for len(app.pending) > 0 {
		p := pop_front(&app.pending)
		switch p.act {
		case .None:
		case .Open:
			if p.i >= 0 && p.i < len(app.entries) do open_entry(p.i)
			else do for vi in selection() {open_entry(vi); if app.entries[vi].is_dir do break}
		case .Back:
			if n := len(app.back); n > 0 {
				prev := app.back[n - 1]
				from := strings.clone(filepath.base(app.cwd), context.temp_allocator)
				if go_to(prev, .Back, from) {
					pop(&app.back)
					delete(prev)
				}
			}
		case .Forward:
			if n := len(app.fwd); n > 0 {
				next := app.fwd[n - 1]
				if go_to(next, .Forward) {
					pop(&app.fwd)
					delete(next)
				}
			}
		case .Up:
			if app.cwd != "/" && !in_trash() {
				from := strings.clone(filepath.base(app.cwd), context.temp_allocator)
				go_to(filepath.dir(app.cwd), .Push, from)
			}
		case .Home:      go_to(app.home)
		case .Navigate:  if p.s != app.cwd do go_to(p.s)
		case .Path_Edit:
			edit_set(&app.path_edit, app.cwd, true)
			app.edit_focus = .Path
		case .Search:
			if app.searching && app.edit_focus == .Search {
				app.searching = false
				app.edit_focus = .None
			} else {
				if !app.searching do edit_set(&app.search, "")
				app.searching = true
				app.edit_focus = .Search
			}
			refilter()
		case .View_Grid: app.grid = true
		case .View_List: app.grid = false
		case .Main_Menu: open_menu(p.i, true)
		case .Context:   open_menu(p.i, false)
		case .Copy:      clip_selection(false)
		case .Cut:       clip_selection(true)
		case .Paste:     if !in_trash() do do_paste()
		case .Rename:    begin_rename()
		case .Trash:     do_trash()
		case .Delete:    if len(selection()) > 0 do app.dialog = .Confirm_Delete
		case .Restore:   do_restore()
		case .Mkdir:     begin_mkdir()
		case .Select_All: for vi in app.view do app.entries[vi].sel = true
		case .Terminal:  open_terminal()
		case .Hidden:
			app.show_hidden = !app.show_hidden
			refilter()
		case .Reload:    reload()
		case .Empty_Trash: app.dialog = .Confirm_Empty_Trash
		case .Sort:
			k := Sort_Key(p.i)
			if app.sort == k do app.sort_desc = !app.sort_desc
			else {app.sort = k; app.sort_desc = k != .Name}
			refilter()
		case .Dialog_Ok: dialog_ok()
		case .Dialog_Cancel:
			app.dialog = .None
			if app.edit_focus == .Dialog do app.edit_focus = .None
		case .Close:     app.running = false
		case .New_Tab:
			path := p.s
			if path == "" {
				sel := selection()
				path = app.cwd
				if len(sel) == 1 && app.entries[sel[0]].is_dir && p.i == -1 do path = full_path(app.entries[sel[0]].name)
			}
			new_tab(path)
		case .Close_Tab:  close_tab(p.i if p.i >= 0 else app.cur_tab)
		case .Switch_Tab: if p.i != app.cur_tab {save_tab(); activate_tab(p.i)}
		case .Convert:
			x, y := app.menu_pos.x, app.menu_pos.y
			if p.i != -1 do x, y = app.body.x + app.body.w / 2, app.body.y + app.body.h / 2
			donut_open(x, y, false)
		case .Preview:
			sel := selection()
			k := app.focus
			if len(sel) > 0 && (k < 0 || !app.entries[app.view[k]].sel) {
				for vi2, j in app.view do if vi2 == sel[0] {k = j; break}
			}
			if k < 0 && len(app.view) > 0 do k = 0
			preview_open(k)
		case .Next_Tab:
			if len(app.tabs) > 1 {
				save_tab()
				activate_tab((app.cur_tab + p.i + len(app.tabs)) % len(app.tabs))
			}
		case .Extract:   for vi in selection() do extract(vi)
		case .Compress:
			sel := selection()
			if len(sel) == 0 || in_trash() do break
			name := "アーカイブ"
			if len(sel) == 1 do name, _, _ = archive_kind(app.entries[sel[0]].name)
			if len(sel) == 1 && name == "" do name = app.entries[sel[0]].name
			app.dialog = .Compress
			edit_set(&app.dlg_edit, fmt.tprintf("%s.zip", name))
			app.dlg_edit.anchor, app.dlg_edit.cur = 0, len(app.dlg_edit.buf) - 4
			app.edit_focus = .Dialog

		}
	}
}

open_menu :: proc(vi: int, main_menu: bool) {
	clear(&app.menu_items)
	add :: proc(label: string, act: Act, key := "", ok := true) {
		append(&app.menu_items, Menu_Item{label, act, key, ok})
	}
	sep :: proc() {append(&app.menu_items, Menu_Item{})}
	n := len(selection())
	if main_menu {
		add("新しいフォルダー…", .Mkdir, "Shift+Ctrl+N", !in_trash())
		add("端末で開く", .Terminal, "", !in_trash())
		sep()
		add("アイコン表示", .View_Grid, "Ctrl+2")
		add("一覧表示", .View_List, "Ctrl+1")
		add("隠しファイルを隠す" if app.show_hidden else "隠しファイルを表示", .Hidden, "Ctrl+H")
		add("再読み込み", .Reload, "F5")
		sep()
		add("ゴミ箱を空にする", .Empty_Trash)
		add("閉じる", .Close, "Ctrl+Q")
	} else if vi >= 0 && in_trash() {
		add("元に戻す", .Restore)
		add("完全に削除…", .Delete, "Delete")
	} else if vi >= 0 {
		add("開く", .Open, "Enter")
		if n == 1 && app.entries[vi].is_dir do add("新しいタブで開く", .New_Tab, "中クリック")
		if n == 1 {
			if _, _, ok := archive_kind(app.entries[vi].name); ok do add("ここに展開", .Extract)
		}
		if cat_of(app.entries[vi].name) != .None do add("変換…", .Convert, "Ctrl+ドラッグ")
		add("プレビュー", .Preview, "Space")
		add("圧縮…", .Compress)
		sep()
		add("切り取り", .Cut, "Ctrl+X")
		add("コピー", .Copy, "Ctrl+C")
		add("名前を変更…", .Rename, "F2", n == 1)
		sep()
		add("ゴミ箱へ移動", .Trash, "Delete")
		add("完全に削除…", .Delete, "Shift+Delete")
	} else if in_trash() {
		add("すべて選択", .Select_All, "Ctrl+A")
		add("ゴミ箱を空にする", .Empty_Trash, "", len(app.view) > 0)
	} else {
		add("新しいフォルダー…", .Mkdir, "Shift+Ctrl+N")
		add("貼り付け", .Paste, "Ctrl+V")
		add("すべて選択", .Select_All, "Ctrl+A")
		sep()
		add("端末で開く", .Terminal)
		add("隠しファイルを隠す" if app.show_hidden else "隠しファイルを表示", .Hidden, "Ctrl+H")
	}
	app.menu_open, app.menu_main = true, main_menu
	app.menu_pos = {app.mx, app.my}
}

// ---------------------------------------------------------------------------
// Text entry

edit_str :: proc(e: ^Edit) -> string {return string(e.buf[:])}

edit_set :: proc(e: ^Edit, s: string, select_all := false) {
	clear(&e.buf)
	append(&e.buf, s)
	e.cur = len(s)
	e.anchor = 0 if select_all else e.cur
}

edit_del_sel :: proc(e: ^Edit) -> bool {
	if e.cur == e.anchor do return false
	a, b := min(e.cur, e.anchor), max(e.cur, e.anchor)
	remove_range(&e.buf, a, b)
	e.cur, e.anchor = a, a
	return true
}

edit_insert :: proc(e: ^Edit, s: string) {
	edit_del_sel(e)
	inject_at(&e.buf, e.cur, s)
	e.cur += len(s)
	e.anchor = e.cur
}

prev_rune :: proc(b: []u8, i: int) -> int {
	i := i - 1
	for i > 0 && b[i] & 0xC0 == 0x80 do i -= 1
	return max(i, 0)
}
next_rune :: proc(b: []u8, i: int) -> int {
	i := i + 1
	for i < len(b) && b[i] & 0xC0 == 0x80 do i += 1
	return min(i, len(b))
}

edit_key :: proc(e: ^Edit, key: u32, ctrl, shift: bool) -> bool {
	switch key {
	case K_BACKSPACE:
		if !edit_del_sel(e) && e.cur > 0 {
			p := prev_rune(e.buf[:], e.cur)
			remove_range(&e.buf, p, e.cur)
			e.cur, e.anchor = p, p
		}
	case K_DELETE:
		if !edit_del_sel(e) && e.cur < len(e.buf) {
			remove_range(&e.buf, e.cur, next_rune(e.buf[:], e.cur))
		}
	case K_LEFT:
		if !shift && e.cur != e.anchor do e.cur = min(e.cur, e.anchor)
		else if e.cur > 0 do e.cur = prev_rune(e.buf[:], e.cur)
		if !shift do e.anchor = e.cur
	case K_RIGHT:
		if !shift && e.cur != e.anchor do e.cur = max(e.cur, e.anchor)
		else if e.cur < len(e.buf) do e.cur = next_rune(e.buf[:], e.cur)
		if !shift do e.anchor = e.cur
	case K_HOME:
		e.cur = 0
		if !shift do e.anchor = 0
	case K_END:
		e.cur = len(e.buf)
		if !shift do e.anchor = e.cur
	case K_A:
		if !ctrl do return false
		e.anchor, e.cur = 0, len(e.buf)
	case K_C, K_X:
		if !ctrl do return false
		if e.cur != e.anchor {
			s := string(e.buf[min(e.cur, e.anchor):max(e.cur, e.anchor)])
			// shortcut: app-internal text clipboard (no wl_data_device yet)
			delete(app.text_clip)
			app.text_clip = strings.clone(s)
			if key == K_X do edit_del_sel(e)
		}
	case K_V:
		if !ctrl do return false
		if app.text_clip != "" do edit_insert(e, app.text_clip)
	case:
		return false
	}
	return true
}

active_edit :: proc() -> ^Edit {
	switch app.edit_focus {
	case .Path:   return &app.path_edit
	case .Search: return &app.search
	case .Dialog: return &app.dlg_edit if app.dialog == .Rename || app.dialog == .Mkdir || app.dialog == .Compress else nil
	case .None:
	}
	return nil
}

draw_edit :: proc(e: ^Edit, r: Rect, focused: bool, icon: rune = 0) {
	rrect(r, px(6), hex(0xffffff, 18))
	if focused do rrect(r, px(6), with_alpha(ACCENT, 210), px(2))
	size := fs(14)
	x := r.x + px(10)
	if icon != 0 {
		glyph_center({r.x + px(4), r.y, px(28), r.h}, icon, fs(14), DIM)
		x = r.x + px(34)
	}
	inner := Rect{x, r.y, r.x + r.w - px(10) - x, r.h}
	s := edit_str(e)
	cur_x := f32(text_width(s[:e.cur], size)) + f32(text_width(e.pre, size))
	off := max(0, cur_x - inner.w + px(2))
	set_clip(inner)
	tx := inner.x - off
	bl := baseline(r, size)
	if e.cur != e.anchor {
		a, b := min(e.cur, e.anchor), max(e.cur, e.anchor)
		sx := tx + f32(text_width(s[:a], size))
		fill({sx, r.y + px(7), f32(text_width(s[a:b], size)), r.h - px(14)}, with_alpha(ACCENT, 110))
	}
	w := text(tx, bl, s[:e.cur], size, FG)
	if e.pre != "" {
		pw := text(tx + w, bl, e.pre, size, FG)
		fill({tx + w, bl + px(2), pw, px(1)}, FG)
		w += pw
	}
	text(tx + w, bl, s[e.cur:], size, FG)
	if focused do fill({tx + cur_x, r.y + px(8), px(1.5), r.h - px(16)}, FG)
	reset_clip()
	if focused {
		app.ime_rect = {i32((tx + cur_x) / app.S), i32(r.y / app.S), 2, i32(r.h / app.S)}
	}
}

// ---------------------------------------------------------------------------
// Widgets

hovering :: proc(r: Rect) -> bool {
	return !app.blocked && contains(r, app.mx, app.my)
}

clicked :: proc(r: Rect) -> bool {
	return hovering(r) && app.pressed && app.button == 1
}

hot :: proc(r: Rect) {
	if r.y < app.header_h do append(&app.hdr_hot, r)
}

icon_button :: proc(r: Rect, icon: rune, active := false, enabled := true) -> bool {
	hot(r)
	h := enabled && hovering(r)
	if active do rrect(r, px(6), ACTIVE)
	else if h do rrect(r, px(6), ACTIVE if app.held else HOVER)
	glyph_center(r, icon, fs(16), FG if enabled else with_alpha(FG, 70))
	return enabled && clicked(r)
}

text_button :: proc(r: Rect, label: string, style := 0) -> bool {
	// style: 0 normal, 1 suggested (accent), 2 destructive
	h := hovering(r)
	bg := hex(0xffffff, 26 if h else 16)
	fg := FG
	if style == 1 {bg = with_alpha(ACCENT, 255 if h else 225); fg = hex(0x060913)}
	if style == 2 {bg = with_alpha(DANGER, 255 if h else 225); fg = hex(0x060913)}
	rrect(r, px(8), bg)
	size := fs(14)
	tw := f32(text_width(label, size, true))
	text(r.x + (r.w - tw) / 2, baseline(r, size), label, size, fg, true)
	return clicked(r)
}

ellipsize :: proc(s: string, size: i32, maxw: f32, bold := false, middle := false) -> string {
	if f32(text_width(s, size, bold)) <= maxw do return s
	ell := f32(text_width("…", size, bold))
	if middle {
		half := (maxw - ell) / 2
		acc: f32
		head := 0
		for r, i in s {
			a := f32(get_glyph(r, size, bold).adv)
			if acc + a > half do break
			acc += a
			head = i + utf8.rune_size(r)
		}
		acc = 0
		tail := len(s)
		for tail > head {
			p := prev_rune(transmute([]u8)s, tail)
			r, _ := utf8.decode_rune_in_string(s[p:])
			a := f32(get_glyph(r, size, bold).adv)
			if acc + a > half do break
			acc += a
			tail = p
		}
		return strings.concatenate({s[:head], "…", s[tail:]}, context.temp_allocator)
	}
	acc: f32
	cut := 0
	for r, i in s {
		a := f32(get_glyph(r, size, bold).adv)
		if acc + a + ell > maxw do break
		acc += a
		cut = i + utf8.rune_size(r)
	}
	return strings.concatenate({s[:cut], "…"}, context.temp_allocator)
}

// Splits a name into at most two lines for the icon grid.
wrap2 :: proc(s: string, size: i32, maxw: f32) -> (string, string) {
	if f32(text_width(s, size)) <= maxw do return s, ""
	acc: f32
	cut, brk := len(s), -1
	for r, i in s {
		a := f32(get_glyph(r, size).adv)
		if acc + a > maxw {cut = i; break}
		acc += a
		if r == ' ' || r == '-' || r == '_' || r == '.' do brk = i + 1
	}
	if brk > cut / 2 do cut = brk
	if cut == 0 do cut = next_rune(transmute([]u8)s, 0)
	return s[:cut], ellipsize(s[cut:], size, maxw)
}

// ---------------------------------------------------------------------------
// Frame

GRID_CELL_W :: 112
GRID_CELL_H :: 124
LIST_ROW_H :: 40
LIST_HEAD_H :: 32

item_rect :: proc(k: int) -> Rect {
	// in body coordinates (before scroll)
	if app.grid {
		pad := px(12)
		cw := (app.body.w - 2 * pad) / f32(app.cols)
		return {pad + f32(k % app.cols) * cw, pad + f32(k / app.cols) * px(GRID_CELL_H), cw, px(GRID_CELL_H)}
	}
	return {0, px(LIST_HEAD_H) + f32(k) * px(LIST_ROW_H), app.body.w, px(LIST_ROW_H)}
}

content_height :: proc() -> f32 {
	n := len(app.view)
	if app.grid do return px(24) + f32((n + app.cols - 1) / max(app.cols, 1)) * px(GRID_CELL_H)
	return px(LIST_HEAD_H) + f32(n) * px(LIST_ROW_H) + px(48)
}

ensure_visible :: proc(k: int) {
	if k < 0 || app.body.h <= 0 do return
	r := item_rect(k)
	top := px(LIST_HEAD_H) if !app.grid else 0
	if r.y - top < app.scroll_to do app.scroll_to = r.y - top
	if r.y + r.h > app.scroll_to + app.body.h do app.scroll_to = r.y + r.h - app.body.h
}

frame :: proc() {
	W, H := f32(cv.w), f32(cv.h)
	t := now_s()
	app.dt = clamp(t - app.last_t, 0, 1.0 / 30)
	app.last_t, app.now = t, t
	app.animating = false
	if app.dialog != app.prev_dialog {
		if app.dialog != .None do app.dlg_t0 = t
		app.prev_dialog = app.dialog
	}
	if app.menu_open && !app.prev_menu do app.menu_t0 = t
	app.prev_menu = app.menu_open
	draw_alpha = 255

	reset_clip()
	clear_canvas(BG)
	clear(&app.hdr_hot)
	app.header_h = px(47)
	app.blocked = app.menu_open || app.dialog != .None || pv.open || dn.open
	if app.released do app.band_on = false
	if app.cdrag_on {
		if app.released {
			if app.cdrag_toggle >= 0 && app.cdrag_toggle < len(app.entries) do app.entries[app.cdrag_toggle].sel = false
			app.cdrag_on = false
		} else if app.held && math.hypot(app.mx - app.cdrag_x, app.my - app.cdrag_y) > px(8) {
			app.cdrag_on = false
			donut_open(app.mx, app.my, true)
			app.blocked = true
		}
	}

	sidebar_w := px(220) if W > px(640) else 0
	if sidebar_w > 0 do draw_sidebar(sidebar_w, H)

	cx := sidebar_w + (1 if sidebar_w > 0 else 0)
	draw_header({cx, 0, W - cx, app.header_h})
	fill({cx, app.header_h - 1, W - cx, 1}, LINE)

	top := app.header_h
	if len(app.tabs) > 1 {
		draw_tabbar({cx, top, W - cx, px(38)})
		top += px(38)
	}
	app.body = {cx, top, W - cx, H - top}
	draw_body()

	app.blocked = false
	if app.menu_open do draw_menu()
	if app.dialog != .None do draw_dialog(W, H)
	draw_preview(W, H)
	draw_donut()
	draw_toast(W, H)
}


draw_sidebar :: proc(w, H: f32) {
	fill({0, 0, w, H}, hex(0xffffff, 8))
	fill({w, 0, 1, H}, LINE)
	hh := app.header_h
	size := fs(15)
	title := "GlassFilee"
	tw := f32(text_width(title, size, true))
	text((w - px(40) - tw) / 2 + px(4), baseline({0, 0, w, hh}, size), title, size, FG, true)
	mb := Rect{w - px(40), px(6.5), px(34), px(34)}
	if icon_button(mb, I_MENU, app.menu_open && app.menu_main) do push(.Main_Menu)

	y := hh + px(6)
	for p, i in app.places {
		if p.path == "/" {
			fill({px(12), y + px(6), w - px(24), 1}, LINE)
			y += px(13)
		}
		r := Rect{px(6), y, w - px(12), px(36)}
		active := app.cwd == p.path
		if active do rrect(r, px(6), ACTIVE)
		else if hovering(r) do rrect(r, px(6), HOVER)
		glyph_center({r.x + px(6), r.y, px(28), r.h}, p.icon, fs(15), FG)
		text(r.x + px(42), baseline(r, fs(14)), ellipsize(p.label, fs(14), r.w - px(50)), fs(14), FG, active)
		if clicked(r) do push(.Navigate, i, p.path)
		if hovering(r) && app.pressed && app.button == 2 do push(.New_Tab, 0, p.path)
		y += px(38)
	}
}

draw_header :: proc(r: Rect) {
	bs := px(34)
	y := r.y + px(6.5)
	x := r.x + px(6)
	if icon_button({x, y, bs, bs}, I_BACK, false, len(app.back) > 0) do push(.Back)
	x += bs + px(2)
	if icon_button({x, y, bs, bs}, I_FWD, false, len(app.fwd) > 0) do push(.Forward)
	x += bs + px(8)

	right := r.x + r.w - px(6)
	// close button: round, like libadwaita window controls
	cr := Rect{right - bs, y, bs, bs}
	hot(cr)
	circ := Rect{cr.x + px(5), cr.y + px(5), px(24), px(24)}
	rrect(circ, px(12), hex(0xffffff, 40 if hovering(cr) else 22))
	glyph_center(circ, I_CLOSE, fs(12), FG)
	if clicked(cr) do push(.Close)
	right -= bs + px(8)
	right -= bs
	if icon_button({right, y, bs, bs}, I_LIST if app.grid else I_GRID) do push(.View_List if app.grid else .View_Grid)
	right -= bs + px(2)
	if icon_button({right, y, bs, bs}, I_SEARCH, app.searching) do push(.Search)
	if len(jobs) > 0 || app.walking {
		right -= bs + px(2)
		cx, cy := right + bs / 2, y + bs / 2
		head := int(app.now * 12) % 8
		for i in 0 ..< 8 {
			a := f32(i) / 8 * 2 * math.PI
			fade := u8(60 + 195 * ((8 + i - head) % 8) / 7)
			d := px(3)
			rrect({cx + math.cos(a) * px(9) - d / 2, cy + math.sin(a) * px(9) - d / 2, d, d}, d / 2, with_alpha(ACCENT, fade))
		}
	}
	right -= px(8)

	bar := Rect{x, y, max(right - x, px(60)), bs}
	hot(bar)
	switch {
	case app.edit_focus == .Path:
		draw_edit(&app.path_edit, bar, true)
	case app.searching:
		draw_edit(&app.search, bar, app.edit_focus == .Search, I_SEARCH)
		if clicked(bar) do app.edit_focus = .Search
	case:
		draw_pathbar(bar)
	}
}

draw_pathbar :: proc(bar: Rect) {
	rrect(bar, px(6), hex(0xffffff, 14))
	Seg :: struct {
		label: string,
		path:  string,
		icon:  rune,
	}
	segs := make([dynamic]Seg, context.temp_allocator)
	if in_trash() {
		append(&segs, Seg{"ゴミ箱", app.trash_files, I_TRASH})
	} else {
		rest := app.cwd
		base := "/"
		if app.cwd == app.home || strings.has_prefix(app.cwd, strings.concatenate({app.home, "/"}, context.temp_allocator)) {
			append(&segs, Seg{"ホーム", app.home, I_HOME})
			rest = app.cwd[len(app.home):]
			base = app.home
		} else {
			append(&segs, Seg{"", "/", I_DRIVE})
		}
		acc := base
		for part in strings.split(strings.trim(rest, "/"), "/", context.temp_allocator) {
			if part == "" do continue
			acc, _ = filepath.join({acc, part}, context.temp_allocator)
			append(&segs, Seg{part, acc, 0})
		}
	}
	size := fs(14)
	seg_w :: proc(s: Seg, size: i32, last: bool) -> f32 {
		w := f32(text_width(s.label, size, last)) + px(20)
		if s.icon != 0 do w += px(20) if s.label != "" else px(8)
		return w
	}
	sep_w := px(14)
	total: f32
	for s, i in segs do total += seg_w(s, size, i == len(segs) - 1) + sep_w
	first := 0
	avail := bar.w - px(8)
	for total > avail && first < len(segs) - 1 {
		total -= seg_w(segs[first], size, false) + sep_w
		first += 1
	}
	x := bar.x + px(4)
	on_seg := false
	for i in first ..< len(segs) {
		s := segs[i]
		last := i == len(segs) - 1
		w := min(seg_w(s, size, last), bar.x + bar.w - px(4) - x)
		r := Rect{x, bar.y + px(3), w, bar.h - px(6)}
		if hovering(r) {
			on_seg = true
			if !last do rrect(r, px(5), HOVER)
		}
		tx := r.x + px(10)
		if s.icon != 0 {
			glyph_center({tx - px(2), r.y, px(18), r.h}, s.icon, fs(13), FG)
			tx += px(20) if s.label != "" else px(8)
		}
		set_clip(r)
		text(tx, baseline(r, size), s.label, size, FG if last else DIM, last)
		reset_clip()
		if clicked(r) && !last do push(.Navigate, 0, s.path)
		x += w
		if !last {
			text(x + px(3), baseline(r, size), "/", size, with_alpha(FG, 90))
			x += sep_w
		}
	}
	if clicked(bar) && !on_seg do push(.Path_Edit)
}

draw_body :: proc() {
	b := app.body
	n := len(app.view)
	app.cols = max(1, int((b.w - px(24)) / px(GRID_CELL_W)))
	max_scroll := max(0, content_height() - b.h)
	if app.wheel != 0 && hovering(b) do app.scroll_to -= app.wheel * px(72)
	app.scroll_to = clamp(app.scroll_to, 0, max_scroll)
	if d := app.scroll_to - app.scroll; abs(d) < 0.5 {
		app.scroll = app.scroll_to
	} else {
		app.scroll += d * (1 - math.exp(-app.dt * 16)) // frame-rate independent easing
		app.animating = true
	}
	app.scroll = clamp(app.scroll, 0, max_scroll)

	if n == 0 {
		msg := "結果が見つかりません" if app.searching else ("ゴミ箱は空です" if in_trash() else "フォルダーは空です")
		icon: rune = I_SEARCH if app.searching else (I_TRASH if in_trash() else I_FOLDER_OPEN)
		cy := b.y + b.h / 2
		glyph_center({b.x, cy - px(90), b.w, px(80)}, icon, fs(64), with_alpha(FG, 90))
		size := fs(20)
		tw := f32(text_width(msg, size, true))
		text(b.x + (b.w - tw) / 2, cy + px(20), msg, size, DIM, true)
		if hovering(b) && app.pressed && app.button == 3 do push(.Context, -1)
		return
	}

	set_clip(b)
	hit_item := false
	bx, by := b.x, b.y - app.scroll

	// rubber band selection
	band: Rect
	if app.band_on {
		x0, y0 := app.band_x, app.band_y
		x1, y1 := app.mx - b.x, app.my - b.y + app.scroll
		band = {min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0)}
		ctrl := .Ctrl in app.mod
		for vi, k in app.view {
			r := item_rect(k)
			if app.grid do r = shrink(r, px(3))
			inter := r.x < band.x + band.w && band.x < r.x + r.w && r.y < band.y + band.h && band.y < r.y + r.h
			if inter do app.entries[vi].sel = true
			else if !ctrl do app.entries[vi].sel = false
		}
	}

	if !app.grid {
		draw_list_header(b)
	}
	first, last := 0, n
	if app.grid {
		rh := px(GRID_CELL_H)
		first = max(0, int((app.scroll - px(12)) / rh) * app.cols)
		last = min(n, (int((app.scroll + b.h) / rh) + 2) * app.cols)
	} else {
		first = max(0, int((app.scroll - px(LIST_HEAD_H)) / px(LIST_ROW_H)))
		last = min(n, first + int(b.h / px(LIST_ROW_H)) + 2)
	}
	if !app.grid do set_clip({b.x, b.y + px(LIST_HEAD_H), b.w, b.h - px(LIST_HEAD_H)})
	for k in first ..< last {
		vi := app.view[k]
		e := &app.entries[vi]
		ir := item_rect(k)
		r := Rect{bx + ir.x, by + ir.y, ir.w, ir.h}
		ip := progress(app.nav_t0 + f32(min(k - first, 30)) * 0.016, 0.3)
		if ip < 1 {
			draw_alpha = u32(ip * 255)
			r.x += (1 - ip) * px(22) * app.nav_dir
			r.y += (1 - ip) * px(10)
		}
		defer draw_alpha = 255
		hit := shrink(r, px(3)) if app.grid else Rect{r.x + px(6), r.y + px(1), r.w - px(12), r.h - px(2)}
		hov := hovering(hit) && !app.band_on
		if e.sel do rrect(hit, px(10 if app.grid else 8), SEL)
		else if hov do rrect(hit, px(10 if app.grid else 8), HOVER)
		col := with_alpha(FG, 150) if e.hidden else FG
		if app.grid {
			is := px(64)
			ix, iy := r.x + (r.w - is) / 2, r.y + px(8)
			if e.is_dir do folder_icon(ix, iy, is, place_icon_for(full_path(e.name)))
			else do file_icon(ix, iy, is, e.kind)
			if len(jobs) > 0 && converting(e.name) do progress_ring({ix, iy, is, is})
			if e.is_link do glyph_center({ix + is - px(20), iy + is - px(20), px(20), px(20)}, I_LINK, fs(12), FG)
			size := fs(14)
			l1, l2 := wrap2(filepath.base(e.name), size, hit.w - px(8))
			ty := iy + is + px(20)
			text(r.x + (r.w - f32(text_width(l1, size))) / 2, ty, l1, size, col)
			if l2 != "" do text(r.x + (r.w - f32(text_width(l2, size))) / 2, ty + px(18), l2, size, col)
		} else {
			is := px(28)
			ix, iy := r.x + px(16), r.y + (r.h - is) / 2
			if e.is_dir do folder_icon(ix, iy, is)
			else do file_icon(ix, iy, is, e.kind)
			if len(jobs) > 0 && converting(e.name) do progress_ring({ix, iy, is, is})
			size := fs(14)
			bl := baseline(r, size)
			date_w, size_w := px(150), px(100)
			name_w := r.w - px(60) - date_w - size_w - px(16)
			nw := text(r.x + px(56), bl, ellipsize(filepath.base(e.name), size, name_w, false, true), size, col)
			if strings.contains_rune(e.name, '/') && nw < name_w - px(40) { // search hit in a subfolder
				text(r.x + px(66) + nw, bl, ellipsize(filepath.dir(e.name), fs(12), name_w - nw - px(12), false, true), fs(12), with_alpha(FG, 110))
			}
			sz := "—" if e.is_dir else format_size(e.size)
			sx := r.x + r.w - date_w - px(16) - f32(text_width(sz, size))
			text(sx, bl, sz, size, DIM)
			text(r.x + r.w - date_w, bl, format_time(e.mtime), size, DIM)
		}
		if hov && app.pressed {
			hit_item = true
			ctrl := .Ctrl in app.mod
			shift := .Shift in app.mod
			if app.button == 1 {
				if ctrl {
					// deselect on release only: a Ctrl+drag of a selection must keep it selected
					app.cdrag_toggle = vi if e.sel else -1
					e.sel = true
					app.cdrag_on, app.cdrag_x, app.cdrag_y = true, app.mx, app.my
					app.anchor = k
				} else if shift && app.anchor >= 0 {
					clear_sel()
					for j in min(app.anchor, k) ..= max(app.anchor, k) do app.entries[app.view[j]].sel = true
				} else {
					if !e.sel {clear_sel(); e.sel = true}
					app.anchor = k
				}
				app.focus = k
				if app.clicks >= 2 && !ctrl && !shift {
					clear_sel()
					e.sel = true
					push(.Open, vi)
				}
			} else if app.button == 3 {
				if !e.sel {clear_sel(); e.sel = true; app.anchor = k}
				app.focus = k
				push(.Context, vi)
			} else if app.button == 2 && e.is_dir {
				push(.New_Tab, 0, full_path(e.name))
			}
		}
	}
	set_clip(b)

	if app.band_on && band.w > 0 && band.h > 0 {
		br := Rect{bx + band.x, by + band.y, band.w, band.h}
		fill(br, with_alpha(ACCENT, 40))
		rrect(br, 0, with_alpha(ACCENT, 160), px(1))
	}

	if hovering(b) && app.pressed && !hit_item {
		ctrl := .Ctrl in app.mod
		if app.button == 1 {
			if !ctrl do clear_sel()
			app.band_on = true
			app.band_x, app.band_y = app.mx - b.x, app.my - b.y + app.scroll
			if app.edit_focus == .Path do app.edit_focus = .None
		} else if app.button == 3 {
			clear_sel()
			push(.Context, -1)
		}
	}

	// overlay scrollbar
	ch := content_height()
	if ch > b.h {
		th := max(px(40), b.h * b.h / ch)
		ty := b.y + (b.h - th) * (app.scroll / (ch - b.h))
		rrect({b.x + b.w - px(8), ty + px(2), px(4), th - px(4)}, px(2), hex(0xffffff, 60))
	}
	reset_clip()
	draw_floating_bar(b)
}

draw_list_header :: proc(b: Rect) {
	h := Rect{b.x, b.y, b.w, px(LIST_HEAD_H)}
	fill({h.x, h.y + h.h - 1, h.w, 1}, LINE)
	size := fs(13)
	bl := baseline(h, size)
	date_w, size_w := px(150), px(100)
	cols := [3]struct {
		label: string,
		r:     Rect,
		key:   Sort_Key,
	} {
		{"名前", {h.x + px(6), h.y, h.w - date_w - size_w - px(28), h.h}, .Name},
		{"サイズ", {h.x + h.w - date_w - size_w - px(16), h.y, size_w, h.h}, .Size},
		{"更新日時", {h.x + h.w - date_w - px(8), h.y, date_w, h.h}, .Modified},
	}
	for c in cols {
		if hovering(c.r) do rrect(shrink(c.r, px(2)), px(5), HOVER)
		active := app.sort == c.key
		tx := c.r.x + px(50) if c.key == .Name else c.r.x + px(8)
		w := text(tx, bl, c.label, size, FG if active else DIM, active)
		if active do glyph_center({tx + w + px(2), h.y, px(16), h.h}, I_SORT_DOWN if app.sort_desc else I_SORT_UP, fs(11), FG)
		if clicked(c.r) do push(.Sort, int(c.key))
	}
}

draw_floating_bar :: proc(b: Rect) {
	sel := selection()
	if len(sel) == 0 do return
	msg: string
	if len(sel) == 1 {
		e := app.entries[sel[0]]
		msg = fmt.tprintf("「%s」を選択しました", ellipsize(e.name, fs(13), px(260)))
		if !e.is_dir do msg = fmt.tprintf("%s (%s)", msg, format_size(e.size))
	} else {
		total: i64
		files := 0
		for vi in sel do if !app.entries[vi].is_dir {total += app.entries[vi].size; files += 1}
		msg = fmt.tprintf("%d 個のアイテムを選択しました", len(sel))
		if files > 0 do msg = fmt.tprintf("%s (%s)", msg, format_size(total))
	}
	size := fs(13)
	w := f32(text_width(msg, size)) + px(24)
	r := Rect{b.x + b.w - w - px(12), b.y + b.h - px(42), w, px(30)}
	rrect(r, px(8), POP_BG)
	rrect(r, px(8), LINE, px(1))
	text(r.x + px(12), baseline(r, size), msg, size, FG)
}

draw_menu :: proc() {
	size := fs(14)
	item_h, sep_h, pad := px(32), px(9), px(6)
	w := px(200)
	h := 2 * pad
	for it in app.menu_items {
		if it.label == "" {h += sep_h; continue}
		w = max(w, f32(text_width(it.label, size) + text_width(it.key, fs(13))) + px(56))
		h += item_h
	}
	p := progress(app.menu_t0, 0.16)
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	x := min(app.menu_pos.x, f32(cv.w) - w - px(4))
	y := app.menu_pos.y - (1 - p) * px(8)
	if y + h > f32(cv.h) - px(4) do y = max(px(4), y - h)
	r := Rect{x, y, w, h}
	rrect({r.x, r.y + px(2), r.w, r.h}, px(12), hex(0x000000, 70))
	rrect(r, px(12), POP_BG)
	rrect(r, px(12), LINE, px(1))
	iy := y + pad
	for it in app.menu_items {
		if it.label == "" {
			fill({x + px(12), iy + sep_h / 2, w - px(24), 1}, LINE)
			iy += sep_h
			continue
		}
		ir := Rect{x + pad, iy, w - 2 * pad, item_h}
		col := FG if it.ok else with_alpha(FG, 80)
		if it.ok && hovering(ir) do rrect(ir, px(6), HOVER)
		text(ir.x + px(10), baseline(ir, size), it.label, size, col)
		if it.key != "" {
			kw := f32(text_width(it.key, fs(13)))
			text(ir.x + ir.w - kw - px(10), baseline(ir, fs(13)), it.key, fs(13), with_alpha(col, 120))
		}
		if it.ok && clicked(ir) {
			push(it.act, -1)
			app.menu_open = false
		}
		iy += item_h
	}
	if app.pressed && !contains(r, app.mx, app.my) do app.menu_open = false
}

draw_dialog :: proc(W, H: f32) {
	p := progress(app.dlg_t0, 0.22)
	fill({0, 0, W, H}, hex(0x000000, u8(90 * p)))
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	w := min(px(400), W - px(32))
	is_input := app.dialog == .Rename || app.dialog == .Mkdir || app.dialog == .Compress
	h := px(196) if is_input else px(170)
	r := Rect{(W - w) / 2, (H - h) / 2 + (1 - p) * px(24), w, h}
	rrect(r, px(14), POP_BG)
	rrect(r, px(14), LINE, px(1))

	title, body, ok := "", "", ""
	style := 1
	problem := ""
	n := len(selection())
	switch app.dialog {
	case .Rename:
		e := app.entries[app.dialog_target]
		title = "フォルダー名の変更" if e.is_dir else "ファイル名の変更"
		ok = "名前を変更"
		problem = name_problem(strings.trim_space(edit_str(&app.dlg_edit)), filepath.base(e.name), filepath.dir(e.name) if strings.contains_rune(e.name, '/') else "")
	case .Compress:
		title, ok = "圧縮（.zip / .tar.gz / .tar.xz / .7z）", "作成"
		problem = name_problem(strings.trim_space(edit_str(&app.dlg_edit)))
	case .Mkdir:
		title, ok = "新しいフォルダー", "作成"
		problem = name_problem(strings.trim_space(edit_str(&app.dlg_edit)))
	case .Confirm_Delete:
		if n == 1 do title = fmt.tprintf("「%s」を完全に削除しますか？", ellipsize(app.entries[selection()[0]].name, fs(14), px(200)))
		else do title = fmt.tprintf("%d 個のアイテムを完全に削除しますか？", n)
		body, ok, style = "完全に削除したアイテムは元に戻せません。", "削除", 2
	case .Confirm_Empty_Trash:
		title = "ゴミ箱を空にしますか？"
		body, ok, style = "ゴミ箱内のすべてのアイテムが完全に削除されます。", "ゴミ箱を空にする", 2
	case .None:
	}
	tsize := fs(16)
	tw := f32(text_width(title, tsize, true))
	text(r.x + (r.w - min(tw, r.w)) / 2, r.y + px(40), ellipsize(title, tsize, r.w - px(32), true), tsize, FG, true)
	if is_input {
		er := Rect{r.x + px(24), r.y + px(64), r.w - px(48), px(36)}
		draw_edit(&app.dlg_edit, er, true)
		if problem != "" && problem != " " do text(er.x + px(2), er.y + er.h + px(22), problem, fs(13), DANGER)
	} else {
		bsize := fs(14)
		bw := f32(text_width(body, bsize))
		text(r.x + (r.w - min(bw, r.w)) / 2, r.y + px(76), ellipsize(body, bsize, r.w - px(32)), bsize, DIM)
	}
	bw := (r.w - px(24 * 2 + 12)) / 2
	by := r.y + r.h - px(24 + 36)
	if text_button({r.x + px(24), by, bw, px(36)}, "キャンセル") do push(.Dialog_Cancel)
	if text_button({r.x + px(36) + bw, by, bw, px(36)}, ok, style if problem == "" else 0) && problem == "" do push(.Dialog_Ok)
}

draw_toast :: proc(W, H: f32) {
	if app.toast == "" || ticks_ms() > app.toast_until do return
	size := fs(14)
	msg := ellipsize(app.toast, size, W - px(80))
	w := f32(text_width(msg, size)) + px(36)
	p := progress(app.toast_t0, 0.3)
	left := f32(app.toast_until - ticks_ms()) / 300 // fade out over the last 300 ms
	if left < 1 do app.animating = true
	draw_alpha = u32(p * clamp(left, 0, 1) * 255)
	defer draw_alpha = 255
	r := Rect{(W - w) / 2, H - px(96) + (1 - p) * px(48), w, px(40)}
	rrect(r, px(20), hex(0x1e2230, 245))
	text(r.x + px(18), baseline(r, size), msg, size, FG)
}

// ---------------------------------------------------------------------------
// Input

// Window move/resize from the client-drawn header and edges (no server decorations).
window_grab :: proc(x, y: f32) -> bool {
	if app.menu_open || app.dialog != .None || pv.open || dn.open do return false
	W, H, e := f32(cv.w), f32(cv.h), px(5)
	left, right, top, bottom := x < e, x > W - e, y < e, y > H - e
	edge: Maybe(Edge)
	switch {
	case top && left:     edge = .Top_Left
	case top && right:    edge = .Top_Right
	case bottom && left:  edge = .Bottom_Left
	case bottom && right: edge = .Bottom_Right
	case left:            edge = .Left
	case right:           edge = .Right
	case top:             edge = .Top
	case bottom:          edge = .Bottom
	}
	if e, ok := edge.?; ok {
		plat_resize(e)
		return true
	}
	if y < app.header_h {
		for r in app.hdr_hot do if contains(r, x, y) do return false
		plat_move()
		return true
	}
	return false
}

move_focus :: proc(delta: int, shift: bool) {
	n := len(app.view)
	if n == 0 do return
	k := app.focus
	if k < 0 do k = 0 if delta > 0 else n - 1
	else do k = clamp(k + delta, 0, n - 1)
	app.focus = k
	clear_sel()
	if shift && app.anchor >= 0 {
		for j in min(app.anchor, k) ..= max(app.anchor, k) do app.entries[app.view[j]].sel = true
	} else {
		app.entries[app.view[k]].sel = true
		app.anchor = k
	}
	ensure_visible(k)
}

on_key :: proc(ev: Ev) {
	key := ev.key
	ctrl, shift, alt := .Ctrl in ev.mods, .Shift in ev.mods, .Alt in ev.mods

	if dn.open {
		if !dn.closing do donut_key(key)
		return
	}
	if pv.open {
		cols := app.cols if app.grid else 1
		switch key {
		case K_SPACE, K_ESCAPE: preview_close()
		case K_LEFT:            preview_step(-1)
		case K_RIGHT:           preview_step(1)
		case K_UP:              preview_step(-cols)
		case K_DOWN:            preview_step(cols)
		}
		return
	}
	if app.menu_open {
		if key == K_ESCAPE do app.menu_open = false
		return
	}
	if app.dialog != .None {
		if e := active_edit(); e != nil && e.pre == "" {
			if edit_key(e, key, ctrl, shift) do return
			if ev.text != "" {
				edit_insert(e, ev.text)
				return
			}
		}
		switch key {
		case K_ESCAPE: push(.Dialog_Cancel)
		case K_RETURN, K_KP_ENTER: push(.Dialog_Ok)
		}
		return
	}
	if e := active_edit(); e != nil {
		if e.pre != "" do return // IME is composing
		if edit_key(e, key, ctrl, shift) || ev.text != "" {
			if ev.text != "" && !(ctrl && key == K_V) do edit_insert(e, ev.text)
			if app.edit_focus == .Search do refilter()
			return
		}
		switch key {
		case K_ESCAPE:
			if app.edit_focus == .Search {
				app.searching = false
				refilter()
			}
			app.edit_focus = .None
			return
		case K_RETURN, K_KP_ENTER:
			if app.edit_focus == .Path {
				app.edit_focus = .None
				p := strings.clone(strings.trim_space(edit_str(&app.path_edit)), context.temp_allocator)
				if strings.has_prefix(p, "~") do p = strings.concatenate({app.home, p[1:]}, context.temp_allocator)
				push(.Navigate, 0, p)
			} else {
				app.edit_focus = .None
				if len(selection()) == 0 && len(app.view) > 0 do move_focus(-len(app.view), false)
				push(.Open, -1)
			}
			return
		case K_DOWN:
			if app.edit_focus == .Search {
				app.edit_focus = .None
				move_focus(1, false)
			}
			return
		}
		if !ctrl && !alt do return
	}

	cols := app.cols if app.grid else 1
	switch {
	case ctrl && key == K_L: push(.Path_Edit)
	case ctrl && key == K_F: push(.Search)
	case ctrl && key == K_H: push(.Hidden)
	case ctrl && key == K_1: push(.View_List)
	case ctrl && key == K_2: push(.View_Grid)
	case ctrl && key == K_A: push(.Select_All)
	case ctrl && key == K_C: push(.Copy)
	case ctrl && key == K_X: push(.Cut)
	case ctrl && key == K_V: push(.Paste)
	case ctrl && shift && key == K_N: push(.Mkdir)
	case ctrl && key == K_R: push(.Reload)
	case ctrl && key == K_Q: push(.Close)
	case ctrl && key == K_W: push(.Close_Tab, app.cur_tab)
	case ctrl && key == K_T: push(.New_Tab)
	case ctrl && (key == K_TAB || key == K_PAGEDOWN): push(.Next_Tab, 1)
	case ctrl && (key == K_ISO_LEFT_TAB || key == K_PAGEUP): push(.Next_Tab, -1)
	case key == K_F5: push(.Reload)
	case key == K_F2: push(.Rename)
	case key == K_DELETE && shift: push(.Delete)
	case key == K_DELETE: push(.Trash)
	case alt && key == K_LEFT: push(.Back)
	case alt && key == K_RIGHT: push(.Forward)
	case alt && key == K_UP: push(.Up)
	case alt && key == K_DOWN: push(.Open, -1)
	case alt && key == K_HOME: push(.Home)
	case key == K_RETURN || key == K_KP_ENTER: push(.Open, -1)
	case key == K_LEFT && app.grid: move_focus(-1, shift)
	case key == K_RIGHT && app.grid: move_focus(1, shift)
	case key == K_UP: move_focus(-cols, shift)
	case key == K_DOWN: move_focus(cols, shift)
	case key == K_HOME: move_focus(-len(app.view), shift)
	case key == K_END: move_focus(len(app.view), shift)
	case key == K_ESCAPE:
		if app.searching {app.searching = false; refilter()}
		else do clear_sel()
	case key == K_MENU || (shift && key == K_F10):
		app.mx, app.my = app.body.x + app.body.w / 3, app.body.y + app.body.h / 3
		sel := selection()
		push(.Context, sel[0] if len(sel) > 0 else -1)
	case key == K_SPACE && !ctrl && !alt: push(.Preview)
	case ctrl && key == K_E: push(.Convert)
	case !ctrl && !alt && ev.text != "":
		// type-ahead search like GNOME Files
		edit_set(&app.search, ev.text)
		app.searching = true
		app.edit_focus = .Search
		refilter()
	}
}

// Applies one event; returns true when a frame should run right away
// (clicks and keys are processed one by one so none get merged).
on_event :: proc(ev: Ev) -> bool {
	defer if ev.kind != .Preedit do delete(ev.text)
	app.mod = ev.mods
	switch ev.kind {
	case .None:
	case .Quit:
		app.running = false
	case .Motion:
		app.mx, app.my = ev.x * app.S, ev.y * app.S
	case .Down:
		app.mx, app.my = ev.x * app.S, ev.y * app.S
		if ev.button == 1 && window_grab(app.mx, app.my) do return false
		app.pressed, app.held = true, true
		app.button, app.clicks = ev.button, ev.clicks
		if app.edit_focus == .Path && app.my > app.header_h do app.edit_focus = .None
		return true
	case .Up:
		app.released, app.held = true, false
		return true
	case .Wheel:
		app.wheel += ev.wheel
		app.mx, app.my = ev.x * app.S, ev.y * app.S
	case .Key:
		on_key(ev)
		return true
	case .Text:
		if e := active_edit(); e != nil {
			edit_insert(e, ev.text)
			if app.edit_focus == .Search do refilter()
		}
		return true
	case .Preedit:
		if e := active_edit(); e != nil {
			delete(e.pre)
			e.pre = ev.text
		} else do delete(ev.text)
	case .Focus:
		if app.dialog == .None do reload() // pick up changes made by other programs
	}
	return false
}

// ---------------------------------------------------------------------------

build_places :: proc() {
	add :: proc(label: string, icon: rune, path: string) {
		if os.is_dir(path) do append(&app.places, Place{label, icon, strings.clone(path)})
	}
	add("ホーム", I_HOME, app.home)
	dirs := [?]struct {
		key, fallback, label: string,
		icon:                 rune,
	} {
		{"XDG_DESKTOP_DIR", "Desktop", "デスクトップ", I_DESKTOP},
		{"XDG_DOCUMENTS_DIR", "Documents", "ドキュメント", I_DOCS},
		{"XDG_DOWNLOAD_DIR", "Downloads", "ダウンロード", I_DOWNLOAD},
		{"XDG_MUSIC_DIR", "Music", "ミュージック", I_MUSIC},
		{"XDG_PICTURES_DIR", "Pictures", "ピクチャ", I_PICTURES},
		{"XDG_VIDEOS_DIR", "Videos", "ビデオ", I_VIDEO},
	}
	// ~/.config/user-dirs.dirs (localized folder names)
	user_dirs := make(map[string]string, context.temp_allocator)
	cfg, _ := filepath.join({app.home, ".config/user-dirs.dirs"}, context.temp_allocator)
	if data, err := os.read_entire_file_from_path(cfg, context.temp_allocator); err == nil {
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			k, _, v := strings.partition(line, "=")
			v = strings.trim(v, "\"")
			if strings.has_prefix(v, "$HOME") do v = strings.concatenate({app.home, v[5:]}, context.temp_allocator)
			if k != "" && v != "" && v != app.home do user_dirs[k] = v
		}
	}
	for d in dirs {
		p, ok := user_dirs[d.key]
		if !ok do p, _ = filepath.join({app.home, d.fallback}, context.temp_allocator)
		add(d.label, d.icon, p)
	}
	os.make_directory_all(app.trash_files)
	append(&app.places, Place{"ゴミ箱", I_TRASH, app.trash_files})
	append(&app.places, Place{"コンピューター", I_DRIVE, "/"})
}

dump_frame :: proc(path: string) {
	// debug: raw premultiplied ARGB with a 8-byte w/h header (see tools/dump2png.py)
	buf := make([]u8, 8 + int(cv.w * cv.h) * 4, context.temp_allocator)
	(^[2]i32)(&buf[0])^ = {cv.w, cv.h}
	for y in 0 ..< cv.h {
		copy(buf[8 + int(y * cv.w) * 4:][:cv.w * 4], ([^]u8)(&cv.px[y * cv.stride])[:cv.w * 4])
	}
	_ = os.write_entire_file(path, buf)
}

main :: proc() {
	opacity := 0.7
	if s := os.get_env("GF_OPACITY", context.temp_allocator); s != "" {
		if v, ok := strconv.parse_f64(s); ok do opacity = clamp(v, 0, 1)
	}
	BG = hex(0x060913, u8(opacity * 255))

	if !font_init() {
		fmt.eprintln("GlassFilee: no usable font found")
		os.exit(1)
	}
	if !plat_init("GlassFilee", "glassfilee", 1000, 640) {
		fmt.eprintln("GlassFilee: cannot open a Wayland window (WAYLAND_DISPLAY not set or compositor lacks xdg-shell)")
		os.exit(1)
	}

	app.home = os.get_env("HOME", context.allocator)
	if app.home == "" do app.home = "/"
	td := gf.trash_dir()
	app.trash_files, _ = filepath.join({td, "files"})
	app.grid = true
	app.focus, app.anchor = -1, -1
	app.running = true
	app.S = 1
	build_places()
	append(&app.tabs, Tab{})

	start := app.home
	if len(os.args) > 1 {
		start = os.args[1]
		if strings.has_prefix(start, "file://") do start = start[7:]
		if !os.is_dir(start) do start = filepath.dir(start)
	}
	if !go_to(start) do go_to(app.home)
	dump_path := os.get_env("GF_DUMP", context.allocator)


	dirty, urgent := true, false
	for app.running && !plat_closed() {
		if app.walking {
			if step_walk() do refilter()
			dirty = true
		}
		// clicks/keys draw at once; hover/scroll wait for the compositor's frame callback
		if dirty && (urgent || plat_can_draw()) {
			buf, bw, bh := plat_begin()
			if buf != nil {
				app.S = f32(plat_scale())
				cv = Canvas{buf.px, bw, bh, bw, {0, 0, bw, bh}}
				frame()
				app.pressed, app.released, app.wheel = false, false, 0
				if len(app.pending) > 0 {
					run_pending()
					frame()
				}
				plat_present(buf)
				dirty, urgent = false, false
				if app.animating do dirty = true // next frame comes with the frame callback
				if dump_path != "" && !app.animating { // dump the settled frame
					dump_frame(dump_path)
					break
				}
			}
		}
		want := app.edit_focus != .None && active_edit() != nil
		plat_text_input(want, app.ime_rect)
		free_all(context.temp_allocator)

		timeout := -1
		if app.toast != "" && app.toast_until > ticks_ms() do timeout = int(app.toast_until - ticks_ms()) + 10
		if dirty do timeout = 16 // waiting for the compositor to release a buffer
		if len(jobs) > 0 && (timeout < 0 || timeout > 100) do timeout = 100 // poll children + spinner
		if app.walking do timeout = 0 // keep searching between events
		alive, redraw, timed_out := plat_wait(timeout)
		if !alive do break
		if reap_jobs() && app.dialog == .None do reload()
		// timeout = toast expired or retrying a busy buffer
		if redraw || timed_out do dirty = true
		if len(events) == 0 do continue
		// apply events; stop at the first click/key so it gets its own frame
		n := 0
		for n < len(events) {
			ev := events[n]
			n += 1
			dirty = true
			if on_event(ev) {
				if len(app.pending) > 0 do run_pending()
				urgent = true
				break
			}
		}
		remove_range(&events, 0, n)
	}
}

// ---------------------------------------------------------------------------
// Tabs

save_tab :: proc() {
	t := &app.tabs[app.cur_tab]
	delete(t.cwd)
	t.cwd = strings.clone(app.cwd)
	t.back, t.fwd, t.scroll = app.back, app.fwd, app.scroll_to
}

// Makes tab i current. The previous tab must have been saved (or freed) first.
activate_tab :: proc(i: int) {
	t := &app.tabs[i]
	app.cur_tab = i
	app.back, app.fwd = t.back, t.fwd
	app.searching = false
	if app.edit_focus == .Search || app.edit_focus == .Path do app.edit_focus = .None
	if !go_to(t.cwd, .Replace) do go_to(app.home, .Replace)
	app.scroll_to = t.scroll
	app.nav_t0, app.nav_dir = now_s(), 0
}

new_tab :: proc(path: string) {
	save_tab()
	append(&app.tabs, Tab{cwd = strings.clone(path)})
	activate_tab(len(app.tabs) - 1)
}

close_tab :: proc(i: int) {
	if len(app.tabs) <= 1 {
		app.running = false
		return
	}
	free_history :: proc(back, fwd: ^[dynamic]string) {
		for s in back do delete(s)
		for s in fwd do delete(s)
		delete(back^)
		delete(fwd^)
	}
	t := &app.tabs[i]
	if i == app.cur_tab do free_history(&app.back, &app.fwd) // the live copies are the real ones
	else do free_history(&t.back, &t.fwd)
	delete(t.cwd)
	ordered_remove(&app.tabs, i)
	if i < app.cur_tab {
		app.cur_tab -= 1
	} else if i == app.cur_tab {
		activate_tab(min(i, len(app.tabs) - 1))
	}
}

tab_title :: proc(i: int) -> string {
	if i == app.cur_tab do return location_name()
	c := app.tabs[i].cwd
	if c == app.trash_files do return "ゴミ箱"
	if c == app.home do return "ホーム"
	return filepath.base(c)
}

draw_tabbar :: proc(r: Rect) {
	fill({r.x, r.y + r.h - 1, r.w, 1}, LINE)
	n := len(app.tabs)
	tw := min(px(240), (r.w - px(12)) / f32(n))
	x0 := r.x + px(6)
	target := x0 + f32(app.cur_tab) * tw
	if app.tab_x == 0 do app.tab_x = target
	if d := target - app.tab_x; abs(d) > 0.5 {
		app.tab_x += d * (1 - math.exp(-app.dt * 18))
		app.animating = true
	} else do app.tab_x = target
	rrect({app.tab_x + px(2), r.y + px(4), tw - px(4), r.h - px(9)}, px(7), ACTIVE)
	size := fs(13)
	for i in 0 ..< n {
		tr := Rect{x0 + f32(i) * tw + px(2), r.y + px(4), tw - px(4), r.h - px(9)}
		hov := hovering(tr)
		if hov && i != app.cur_tab do rrect(tr, px(7), HOVER)
		title := ellipsize(tab_title(i), size, tr.w - px(44), i == app.cur_tab)
		ttw := f32(text_width(title, size, i == app.cur_tab))
		text(tr.x + (tr.w - ttw) / 2, baseline(tr, size), title, size, FG if i == app.cur_tab else DIM, i == app.cur_tab)
		cr := Rect{tr.x + tr.w - px(28), tr.y + (tr.h - px(22)) / 2, px(22), px(22)}
		if hov || i == app.cur_tab {
			if hovering(cr) do rrect(cr, px(11), HOVER)
			glyph_center(cr, I_CLOSE, fs(10), DIM)
		}
		switch {
		case clicked(cr) && (hov || i == app.cur_tab): push(.Close_Tab, i)
		case clicked(tr):                              push(.Switch_Tab, i)
		case hov && app.pressed && app.button == 2:    push(.Close_Tab, i)
		}
	}
}

// ---------------------------------------------------------------------------
// Recursive search: walks subfolders a few ms per frame so typing stays smooth

MAX_SEARCH_RESULTS :: 5000

stop_walk :: proc() {
	virtual.arena_free_all(&app.search_arena)
	app.walk_stack = {}
	app.walk_q = ""
	app.walking = false
	app.base_count = len(app.entries)
}

start_walk :: proc(q: string) {
	resize(&app.entries, app.base_count)
	base := app.base_count
	stop_walk()
	app.base_count = base
	if q == "" do return
	a := virtual.arena_allocator(&app.search_arena)
	app.walk_q = strings.clone(q, a)
	app.walk_stack = make([dynamic]string, a)
	for e in app.entries[:app.base_count] {
		if e.is_dir && !e.is_link && (app.show_hidden || !e.hidden) do append(&app.walk_stack, e.name)
	}
	app.walking = len(app.walk_stack) > 0
}

// Returns true if new results were added.
step_walk :: proc(budget_ms: i64 = 6) -> bool {
	a := virtual.arena_allocator(&app.search_arena)
	t0 := ticks_ms()
	added := false
	for len(app.walk_stack) > 0 && ticks_ms() - t0 < budget_ms {
		if len(app.entries) - app.base_count >= MAX_SEARCH_RESULTS {
			clear(&app.walk_stack)
			break
		}
		rel := pop(&app.walk_stack)
		infos, err := os.read_all_directory_by_path(full_path(rel), context.temp_allocator)
		if err != nil do continue
		for fi in infos {
			hidden := strings.has_prefix(fi.name, ".")
			if hidden && !app.show_hidden do continue
			child, _ := filepath.join({rel, fi.name}, a)
			is_dir := fi.type == .Directory
			if is_dir do append(&app.walk_stack, child) // symlinks are not followed (no loops)
			if strings.contains(strings.to_lower(fi.name, context.temp_allocator), app.walk_q) {
				append(&app.entries, Entry {
					name = child, size = fi.size, mtime = fi.modification_time._nsec / 1_000_000_000,
					is_dir = is_dir, is_link = fi.type == .Symlink, hidden = hidden, kind = kind_of(fi.name, fi.mode),
				})
				added = true
			}
		}
	}
	app.walking = len(app.walk_stack) > 0
	return added
}
