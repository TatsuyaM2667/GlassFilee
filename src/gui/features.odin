package main

// Things other file managers have that make daily use nicer:
// - New empty file (Nautilus / Dolphin "New Document")
// - Select by pattern, e.g. "*.jpg *.png" (Nautilus Ctrl+S)
// - Paste an image or text from the clipboard as a new file (Windows / macOS)
// - Tab completion in the path bar (Dolphin, shells)
// - Item counts for folders in list view (Nautilus, Finder)
// - Free space of the current drive at the bottom of the sidebar (Dolphin, Finder)
// - Tabs come back after a restart (browsers)

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

// ---------------------------------------------------------------------------
// New empty file

begin_new_file :: proc() {
	if in_trash() || is_tag_view() do return
	app.dialog = .New_File
	edit_set(&app.dlg_edit, "新しいテキスト.txt")
	app.dlg_edit.anchor = 0
	app.dlg_edit.cur = len("新しいテキスト") // name selected, extension kept
	app.edit_focus = .Dialog
}

new_file_ok :: proc() {
	name := strings.trim_space(edit_str(&app.dlg_edit))
	if name_problem(name) != "" do return
	path := full_path(name)
	fd := posix.open(strings.clone_to_cstring(path, context.temp_allocator), {.WRONLY, .CREAT, .EXCL, .CLOEXEC}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
	if fd < 0 {
		toastf("ファイルを作成できません")
		return
	}
	posix.close(fd)
	push_undo(.Mkdir, {{"", path}}) // undo removes it only while still empty
	app.dialog = .None
	select_after_reload(name)
}

// Reloads and selects (and scrolls to) the item with this name.
select_after_reload :: proc(name: string) {
	n := strings.clone(name, context.temp_allocator)
	reload()
	clear_sel()
	for k in 0 ..< len(app.view) do if app.entries[app.view[k]].name == n {
		app.entries[app.view[k]].sel = true
		app.focus, app.anchor = k, k
		ensure_visible(k)
	}
}

// ---------------------------------------------------------------------------
// Select by pattern

begin_select_pattern :: proc() {
	app.dialog = .Select_Pattern
	edit_set(&app.dlg_edit, "*.", false)
	app.edit_focus = .Dialog
}

// Space or comma separated globs, case-insensitive ("*.JPG" matches "a.jpg").
pattern_matches :: proc(patterns, name: string) -> bool {
	low := strings.to_lower(filepath.base(name), context.temp_allocator)
	spaced, _ := strings.replace_all(patterns, ",", " ", context.temp_allocator)
	for p in strings.fields(strings.to_lower(spaced, context.temp_allocator), context.temp_allocator) {
		if ok, _ := filepath.match(p, low); ok do return true
	}
	return false
}

select_pattern_ok :: proc() {
	pat := strings.trim_space(edit_str(&app.dlg_edit))
	if pat == "" do return
	n := 0
	first := -1
	for vi, k in app.view {
		e := &app.entries[vi]
		e.sel = pattern_matches(pat, e.name)
		if e.sel {
			n += 1
			if first < 0 do first = k
		}
	}
	app.dialog = .None
	if first >= 0 {
		app.focus, app.anchor = first, first
		ensure_visible(first)
	}
	toastf("%d 個を選択しました", n)
}

// ---------------------------------------------------------------------------
// Paste an image / text from the clipboard as a file

@(private = "file")
stamp :: proc() -> string {
	now := libc.time(nil)
	tm := libc.localtime(&now)^
	return fmt.tprintf("%d-%02d-%02d %02d.%02d.%02d", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec)
}

// Called by paste when the clipboard holds no files. True if something was saved.
paste_as_file :: proc() -> bool {
	if in_trash() || is_tag_view() do return false
	data := plat_get_clipboard_image()
	label, ext := "貼り付けた画像", ".png"
	if len(data) == 0 {
		text := plat_get_clipboard_text()
		if strings.trim_space(text) == "" do return false
		data = transmute([]u8)text
		label, ext = "貼り付けたテキスト", ".txt"
	}
	path := unique_dest(app.cwd, strings.concatenate({label, " ", stamp(), ext}, context.temp_allocator))
	if err := os.write_entire_file(path, data); err != nil {
		toastf("保存できません")
		return true
	}
	push_undo(.Copy, {{"", path}}) // undo moves it to the trash
	select_after_reload(filepath.base(path))
	toastf("「%s」として保存しました", filepath.base(path))
	return true
}

// ---------------------------------------------------------------------------
// Tab completion in the path bar

path_complete :: proc() {
	text := edit_str(&app.path_edit)
	tilde := strings.has_prefix(text, "~")
	full := strings.concatenate({app.home, text[1:]}, context.temp_allocator) if tilde else text
	slash := strings.last_index_byte(full, '/')
	if slash < 0 do return
	dir, prefix := full[:slash + 1], full[slash + 1:]
	infos, err := os.read_all_directory_by_path(dir if dir != "" else "/", context.temp_allocator)
	if err != nil do return
	matches := make([dynamic]string, context.temp_allocator)
	for fi in infos {
		if fi.type != .Directory do continue
		if strings.has_prefix(fi.name, ".") && !strings.has_prefix(prefix, ".") do continue
		if strings.has_prefix(fi.name, prefix) do append(&matches, fi.name)
	}
	if len(matches) == 0 { // then case-insensitively
		lp := strings.to_lower(prefix, context.temp_allocator)
		for fi in infos {
			if fi.type == .Directory && strings.has_prefix(strings.to_lower(fi.name, context.temp_allocator), lp) do append(&matches, fi.name)
		}
	}
	if len(matches) == 0 do return
	common := matches[0]
	for m in matches[1:] {
		n := 0
		for n < len(common) && n < len(m) && common[n] == m[n] do n += 1
		common = common[:n]
	}
	done := len(matches) == 1
	if !done && len(common) <= len(prefix) {
		shown := matches[:min(len(matches), 6)]
		toastf("%s%s", strings.join(shown, "  ", context.temp_allocator), " …" if len(matches) > 6 else "")
		return
	}
	out := strings.concatenate({dir, matches[0] if done else common, "/" if done else ""}, context.temp_allocator)
	if tilde do out = strings.concatenate({"~", out[len(app.home):]}, context.temp_allocator)
	edit_set(&app.path_edit, out)
}

// ---------------------------------------------------------------------------
// Item counts for folders (list view)

@(private = "file") counts: map[string]int // cleared on every reload

dir_counts_clear :: proc() {
	for k in counts do delete(k)
	clear(&counts)
}

// Entries in a folder (hidden ones only when shown), -1 if unreadable. Names only: no stat.
dir_count :: proc(path: string) -> int {
	if n, ok := counts[path]; ok do return n
	n := -1
	if d := posix.opendir(strings.clone_to_cstring(path, context.temp_allocator)); d != nil {
		n = 0
		for n < 100_000 {
			ent := posix.readdir(d)
			if ent == nil do break
			name := cstring(&ent.d_name[0])
			if name == "." || name == ".." do continue
			if !app.show_hidden && ent.d_name[0] == '.' do continue
			n += 1
		}
		posix.closedir(d)
	}
	counts[strings.clone(path)] = n
	return n
}

// ---------------------------------------------------------------------------
// Free space of the drive the current folder is on (bottom of the sidebar)

@(private = "file") space: struct {
	path:        string,
	at:          i64,
	free, total: u64,
	ok:          bool,
}

draw_free_space :: proc(w, H: f32) {
	if app.cwd != space.path || ticks_ms() - space.at > 10_000 {
		delete(space.path)
		space.path = strings.clone(app.cwd)
		space.at = ticks_ms()
		st: posix.statvfs_t
		space.ok = !is_tag_view() && posix.statvfs(strings.clone_to_cstring(app.cwd, context.temp_allocator), &st) == .OK
		if space.ok {
			space.free = u64(st.f_bavail) * u64(st.f_frsize)
			space.total = u64(st.f_blocks) * u64(st.f_frsize)
		}
	}
	if !space.ok || space.total == 0 do return
	r := Rect{0, H - px(52), w, px(52)}
	fill(r, hex(0x0b0f1a, 200))
	fill({px(12), r.y, w - px(24), 1}, LINE)
	label := fmt.tprintf("空き %s / %s", format_size(i64(space.free)), format_size(i64(space.total)))
	text(px(18), r.y + px(22), label, fs(12), DIM)
	used := 1 - f32(f64(space.free) / f64(space.total))
	bar := Rect{px(18), r.y + px(32), w - px(36), px(6)}
	rrect(bar, px(3), hex(0xffffff, 25))
	rrect({bar.x, bar.y, max(bar.h, bar.w * used), bar.h}, px(3), DANGER if used > 0.9 else ACCENT)
}

// ---------------------------------------------------------------------------
// Session: the tabs are reopened at the next start (when no folder is given)

@(private = "file")
session_path :: proc() -> string {
	p, _ := filepath.join({app_config_dir(), "session.conf"}, context.temp_allocator)
	return p
}

save_session :: proc() {
	save_tab()
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "cur\t%d\n", app.cur_tab)
	for t in app.tabs do if !strings.contains_rune(t.cwd, '\n') do fmt.sbprintf(&b, "tab\t%s\n", t.cwd)
	_ = os.make_directory_all(app_config_dir())
	_ = os.write_entire_file_from_string(session_path(), strings.to_string(b))
}

// The saved tabs that still exist, and which one was current.
session_load :: proc() -> (paths: [dynamic]string, cur: int) {
	paths = make([dynamic]string, context.temp_allocator)
	data, err := os.read_entire_file_from_path(session_path(), context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		k, _, v := strings.partition(line, "\t")
		switch k {
		case "cur": cur = max(0, int(libc.atoi(strings.clone_to_cstring(v, context.temp_allocator))))
		case "tab": if os.is_dir(v) || strings.has_prefix(v, "tag:") do append(&paths, v)
		}
	}
	return
}

// Recreates the saved tabs; false if there is nothing (usable) to restore.
restore_session :: proc() -> bool {
	paths, cur := session_load()
	if len(paths) == 0 do return false
	for p, i in paths {
		if i == 0 {
			delete(app.tabs[0].cwd)
			app.tabs[0].cwd = strings.clone(p)
		} else do append(&app.tabs, Tab{cwd = strings.clone(p)})
	}
	activate_tab(min(cur, len(app.tabs) - 1))
	return true
}
