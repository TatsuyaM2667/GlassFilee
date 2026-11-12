package main

// Properties (Ctrl+I) and batch rename (F2 with several items selected).

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import gf "../core"

// ---------------------------------------------------------------------------
// Properties

Props :: struct {
	names:  [dynamic]string, // entry names (relative to cwd)
	prog:   gf.Progress, // done = bytes counted so far
	items:  i64, // files + folders inside (atomic)
	done:   bool,
	th:     ^thread.Thread,
}
props: ^Props

@(private = "file")
count_tree :: proc(path: string, p: ^Props) {
	info, err := os.lstat(path, context.temp_allocator)
	if err != nil || sync.atomic_load(&p.prog.cancel) do return
	if info.type != .Directory {
		sync.atomic_add(&p.prog.done, info.size)
		return
	}
	infos, rerr := os.read_all_directory_by_path(path, context.temp_allocator)
	if rerr != nil do return
	for fi in infos {
		sync.atomic_add(&p.items, 1)
		count_tree(fi.fullpath, p)
	}
}

@(private = "file")
props_worker :: proc(p: ^Props) {
	for n in p.names {
		count_tree(n, p) // names are absolute: workers never read app state
		free_all(context.temp_allocator)
	}
	sync.atomic_store(&p.done, true)
	wake()
}

props_open :: proc() {
	sel := selection()
	if len(sel) == 0 do return
	props_close()
	props = new(Props)
	for vi in sel do append(&props.names, strings.clone(full_path(app.entries[vi].name)))
	props.th = thread.create_and_start_with_poly_data(props, props_worker)
	app.dialog = .Props
}

props_close :: proc() {
	if props == nil do return
	sync.atomic_store(&props.prog.cancel, true)
	thread.join(props.th)
	thread.destroy(props.th)
	for n in props.names do delete(n)
	delete(props.names)
	free(props)
	props = nil
}

perm_string :: proc(m: os.Permissions) -> string {
	b: [9]u8
	bits := [9]os.Permission_Flag{.Read_User, .Write_User, .Execute_User, .Read_Group, .Write_Group, .Execute_Group, .Read_Other, .Write_Other, .Execute_Other}
	chars := "rwxrwxrwx"
	for f, i in bits do b[i] = chars[i] if f in m else '-'
	return strings.clone(string(b[:]), context.temp_allocator)
}

full_date :: proc(t: i64) -> string {
	tt := libc.time_t(t)
	tm := libc.localtime(&tt)^
	return fmt.tprintf("%d年%d月%d日 %02d:%02d", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min)
}

draw_props :: proc(W, H: f32) {
	if props == nil do return
	p := progress(app.dlg_t0, 0.22)
	fill({0, 0, W, H}, hex(0x000000, u8(90 * p)))
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	w := min(px(460), W - px(32))
	h := px(330)
	r := Rect{(W - w) / 2, (H - h) / 2 + (1 - p) * px(24), w, h}
	rrect(r, px(14), POP_BG)
	rrect(r, px(14), LINE, px(1))

	first := props.names[0]
	info, _ := os.lstat(first, context.temp_allocator)
	multi := len(props.names) > 1
	is := px(64)
	if info.type == .Directory && !multi do folder_icon(r.x + px(24), r.y + px(24), is, 0, tint_of_mask(file_tags[first]))
	else do file_icon(r.x + px(24), r.y + px(24), is, kind_of(first, info.mode))
	title := fmt.tprintf("%d 個のアイテム", len(props.names)) if multi else filepath.base(first)
	text(r.x + px(104), r.y + px(52), ellipsize(title, fs(16), r.w - px(128), true), fs(16), FG, true)
	done := sync.atomic_load(&props.done)
	size := sync.atomic_load(&props.prog.done)
	items := sync.atomic_load(&props.items)
	size_s := fmt.tprintf("%s（%d バイト）", format_size(size), size)
	if !done {
		size_s = strings.concatenate({size_s, " 計算中…"}, context.temp_allocator)
		app.animating = true
	}
	rows := make([dynamic][2]string, context.temp_allocator)
	if !multi {
		kind := "フォルダー" if info.type == .Directory else ("シンボリックリンク" if info.type == .Symlink else strings.to_upper(strings.trim_prefix(filepath.ext(first), "."), context.temp_allocator))
		if kind == "" do kind = "ファイル"
		append(&rows, [2]string{"種類", kind})
	}
	append(&rows, [2]string{"場所", filepath.dir(first)})
	append(&rows, [2]string{"サイズ", size_s})
	if info.type == .Directory || multi do append(&rows, [2]string{"内容", fmt.tprintf("%d 個のアイテム", items)})
	if !multi {
		append(&rows, [2]string{"更新日時", full_date(info.modification_time._nsec / 1_000_000_000)})
		append(&rows, [2]string{"アクセス権", perm_string(info.mode)})
	}
	y := r.y + px(118)
	for row in rows {
		text(r.x + px(28), y, row[0], fs(13), DIM)
		text(r.x + px(120), y, ellipsize(row[1], fs(13), r.w - px(148)), fs(13), FG)
		y += px(28)
	}
	br := Rect{r.x + r.w - px(124), r.y + r.h - px(56), px(100), px(36)}
	if text_button(br, "閉じる") do push(.Dialog_Cancel)
}

// ---------------------------------------------------------------------------
// Batch rename: "*" = original name, "###" = number (zero-padded to the run length)

batch_name :: proc(tmpl: string, old: string, n: int) -> string {
	stem, ext := file_ext(filepath.base(old))
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(tmpl); {
		switch tmpl[i] {
		case '*':
			strings.write_string(&b, filepath.base(stem))
			i += 1
		case '#':
			run := 0
			for i < len(tmpl) && tmpl[i] == '#' {run += 1; i += 1}
			fmt.sbprintf(&b, "%0*d", run, n)
		case:
			strings.write_byte(&b, tmpl[i])
			i += 1
		}
	}
	if ext != "" && !strings.contains_rune(tmpl, '.') {
		strings.write_byte(&b, '.')
		strings.write_string(&b, ext)
	}
	return strings.to_string(b)
}

// New names for the selection, and the first problem found (or "").
batch_plan :: proc() -> (olds, news: [dynamic]string, problem: string) {
	olds = make([dynamic]string, context.temp_allocator)
	news = make([dynamic]string, context.temp_allocator)
	tmpl := strings.trim_space(edit_str(&app.dlg_edit))
	if tmpl == "" do return olds, news, " "
	seen := make(map[string]bool, context.temp_allocator)
	renamed := make(map[string]bool, context.temp_allocator)
	for vi in selection() do renamed[filepath.base(app.entries[vi].name)] = true
	for vi, i in selection() {
		old := app.entries[vi].name
		nn := batch_name(tmpl, old, i + 1)
		if strings.contains_rune(nn, '/') do problem = "名前に「/」は使えません"
		dir := filepath.dir(old) if strings.contains_rune(old, '/') else ""
		rel := nn
		if dir != "" do rel, _ = filepath.join({dir, nn}, context.temp_allocator)
		if rel in seen do problem = "同じ名前が重複します（# で番号を入れてください）"
		seen[rel] = true
		if os.exists(full_path(rel)) && !renamed[nn] do problem = "同じ名前のアイテムが既にあります"
		append(&olds, old)
		append(&news, rel)
	}
	return
}

batch_apply :: proc() {
	olds, news, problem := batch_plan()
	if problem != "" do return
	// two phases so swaps like a→b, b→a work
	tmps := make([dynamic]string, context.temp_allocator)
	for o, i in olds {
		t := fmt.tprintf("%s.gf-rename-%d", full_path(o), i)
		if os.rename(full_path(o), t) != nil {
			toastf("「%s」の名前を変更できません", o)
			for t2, k in tmps do os.rename(t2, full_path(olds[k])) // roll back
			return
		}
		append(&tmps, t)
	}
	undo := make([dynamic][2]string, context.temp_allocator)
	for t, i in tmps {
		if os.rename(t, full_path(news[i])) == nil {
			append(&undo, [2]string{full_path(olds[i]), full_path(news[i])})
			tags_moved(full_path(olds[i]), full_path(news[i]))
		} else {
			os.rename(t, full_path(olds[i]))
		}
	}
	push_undo(.Rename, undo[:])
	app.dialog = .None
	app.edit_focus = .None
	reload()
	toast_undo(fmt_items(len(undo), "名前変更しました"))
}

draw_batch :: proc(W, H: f32) {
	p := progress(app.dlg_t0, 0.22)
	fill({0, 0, W, H}, hex(0x000000, u8(90 * p)))
	draw_alpha = u32(p * 255)
	defer draw_alpha = 255
	w := min(px(480), W - px(32))
	h := px(360)
	r := Rect{(W - w) / 2, (H - h) / 2 + (1 - p) * px(24), w, h}
	rrect(r, px(14), POP_BG)
	rrect(r, px(14), LINE, px(1))
	olds, news, problem := batch_plan()
	title := fmt.tprintf("%d 個のアイテムの名前を変更", len(olds))
	tw := f32(text_width(title, fs(16), true))
	text(r.x + (r.w - tw) / 2, r.y + px(40), title, fs(16), FG, true)
	er := Rect{r.x + px(24), r.y + px(60), r.w - px(48), px(36)}
	draw_edit(&app.dlg_edit, er, true)
	text(er.x, er.y + er.h + px(20), "* = 元の名前　# = 番号（## で 01, 02…）", fs(12), DIM)
	y := er.y + er.h + px(48)
	for i in 0 ..< min(len(olds), 5) {
		a := ellipsize(filepath.base(olds[i]), fs(13), r.w / 2 - px(40))
		text(er.x, y, a, fs(13), DIM)
		text(r.x + r.w / 2 - px(8), y, "→", fs(13), DIM)
		text(r.x + r.w / 2 + px(14), y, ellipsize(filepath.base(news[i]), fs(13), r.w / 2 - px(40)), fs(13), FG)
		y += px(22)
	}
	if len(olds) > 5 do text(er.x, y, fmt.tprintf("ほか %d 個", len(olds) - 5), fs(12), DIM)
	if problem != "" && problem != " " do text(er.x, r.y + r.h - px(76), problem, fs(13), DANGER)
	bw := (r.w - px(24 * 2 + 12)) / 2
	by := r.y + r.h - px(24 + 36)
	if text_button({r.x + px(24), by, bw, px(36)}, "キャンセル") do push(.Dialog_Cancel)
	if text_button({r.x + px(36) + bw, by, bw, px(36)}, "名前を変更", 1 if problem == "" else 0) && problem == "" do push(.Dialog_Ok)
}

