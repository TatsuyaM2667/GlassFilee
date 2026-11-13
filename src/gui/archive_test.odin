package main

import "core:os"
import "core:sys/posix"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

@(test)
archive_kind_test :: proc(t: ^testing.T) {
	Case :: struct {name, stem, tool: string, ok: bool}
	cases := []Case {
		{"a.tar.gz", "a", "", true}, {"A.TAR.XZ", "A", "", true}, {"x.zip", "x", "", true},
		{"y.7z", "y", "", true}, {"z.tgz", "z", "", true}, {"log.txt.gz", "log.txt", "gzip", true},
		{"d.zst", "d", "zstd", true}, {"e.bz2", "e", "bzip2", true}, {"f.xz", "f", "xz", true},
		{"note.txt", "", "", false}, {".zip", "", "", false},
	}
	for c in cases {
		stem, tool, ok := archive_kind(c.name)
		testing.expectf(t, stem == c.stem && tool == c.tool && ok == c.ok, "%s -> %q %q %v", c.name, stem, tool, ok)
	}
}

@(test)
flatten_test :: proc(t: ^testing.T) {
	base := os.get_env("GF_TEST_DIR", context.temp_allocator)
	if base == "" do return // needs a scratch dir
	j :: proc(a: ..string) -> string {return strings.concatenate(a, context.temp_allocator)}
	// single top-level folder: moved up, wrapper removed
	_ = os.make_directory_all(j(base, "/one/proj"))
	_ = os.write_entire_file_from_string(j(base, "/one/proj/a.txt"), "x")
	flatten(j(base, "/one"))
	testing.expect(t, os.exists(j(base, "/proj/a.txt")))
	testing.expect(t, !os.exists(j(base, "/one")))
	// several entries: left as is
	_ = os.make_directory_all(j(base, "/two/x"))
	_ = os.write_entire_file_from_string(j(base, "/two/y.txt"), "y")
	flatten(j(base, "/two"))
	testing.expect(t, os.exists(j(base, "/two/x")) && os.exists(j(base, "/two/y.txt")))
}

@(test)
tags_follow_renames :: proc(t: ^testing.T) {
	base := os.get_env("GF_TEST_DIR", context.temp_allocator)
	if base == "" do return
	posix_setenv_config(base) // save_tags writes into the scratch dir, never the real config
	file_tags[strings.clone("/a/dir")] = 1 << 2
	file_tags[strings.clone("/a/dir/x.txt")] = 1 << 3
	file_tags[strings.clone("/a/dirx")] = 1 << 4 // shares the prefix but is a different folder
	tags_moved("/a/dir", "/b/new")
	testing.expect_value(t, file_tags["/b/new"], u64(1 << 2))
	testing.expect_value(t, file_tags["/b/new/x.txt"], u64(1 << 3))
	testing.expect_value(t, file_tags["/a/dirx"], u64(1 << 4))
	testing.expect(t, "/a/dir" not_in file_tags)
	append(&tag_list, Tag{2, 0, "無色"}, Tag{3, 5, "青"})
	testing.expect_value(t, tint_of_mask(1 << 2 | 1 << 3), u8(5)) // first *colored* tag wins
}

@(private = "file")
posix_setenv_config :: proc(base: string) {
	posix.setenv("XDG_CONFIG_HOME", strings.clone_to_cstring(base, context.temp_allocator), true)
}

@(test)
lrc_parse :: proc(t: ^testing.T) {
	src := "[ar:Ame Band]\n[ti:Rain]\n[offset:+500]\n[00:01.00]first\n[00:10.50][00:30:00]chorus\n[00:05.25]second\nno stamp\n[00:20.00]\n"
	lines := make([dynamic]Lyric_Line, context.temp_allocator)
	parse_lrc(src, &lines)
	testing.expect_value(t, len(lines), 5)
	// sorted by time, offset (+0.5 s) applied, repeated stamps expanded
	testing.expect_value(t, lines[0].text, "first")
	testing.expect_value(t, lines[0].t, 0.5)
	testing.expect_value(t, lines[1].text, "second")
	testing.expect_value(t, lines[2].text, "chorus")
	testing.expect_value(t, lines[2].t, 10.0)
	testing.expect_value(t, lines[3].text, "") // instrumental gap
	testing.expect_value(t, lines[4].text, "chorus")
	testing.expect_value(t, lines[4].t, 29.5) // [00:30:00] variant
}

@(test)
xml_text_extract :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	xml_text(`<w:document><w:body><w:p><w:r><w:t>見出し</w:t></w:r></w:p><w:p><w:t>A &amp; B</w:t><w:tab/><w:t>&lt;x&gt;</w:t></w:p></w:body></w:document>`, &b)
	testing.expect_value(t, strings.to_string(b), "見出し\nA & B\t<x>\n")
	h := strings.builder_make(context.temp_allocator)
	xml_text(`<html><head><title>T</title><style>p{color:red}</style></head><body><p>本文</p><script>var x=1;</script><br/>次</body></html>`, &h)
	testing.expect_value(t, strings.to_string(h), "本文\n\n次")
}

@(test)
test_sort_and_group :: proc(t: ^testing.T) {
	saved_entries, saved_sort, saved_desc, saved_dirs, saved_group := app.entries, app.sort, app.sort_desc, app.dirs_first, app.group
	defer {app.entries, app.sort, app.sort_desc, app.dirs_first, app.group = saved_entries, saved_sort, saved_desc, saved_dirs, saved_group}
	es := [?]Entry {
		{name = "b.txt", size = 50, kind = .Text},
		{name = "dir", is_dir = true},
		{name = "a.png", size = 5_000_000, kind = .Image},
		{name = "c.txt", size = 0, kind = .Text},
	}
	app.entries = make([dynamic]Entry, context.temp_allocator)
	append(&app.entries, ..es[:])
	app.group, app.dirs_first, app.sort, app.sort_desc = .None, true, .Size, true
	testing.expect(t, entry_less(1, 2)) // folders first beats size
	testing.expect(t, entry_less(2, 0)) // bigger first when descending
	app.dirs_first = false
	testing.expect(t, entry_less(1, 3)) // equal sizes: name tiebreak, reversed too when descending
	app.group, app.sort, app.sort_desc = .Size, .Name, false
	r, _ := group_key(&app.entries[3])
	testing.expect_value(t, r, 1) // empty
	testing.expect(t, entry_less(3, 0)) // empty group before small group, despite the name
	testing.expect_value(t, group_label(&app.entries[2]), "中（10 MB 未満）")
	app.group = .Ext
	testing.expect(t, entry_less(2, 0)) // PNG group before TXT group
}

@(test)
test_folder_sort_memory :: proc(t: ^testing.T) {
	tmp := "/tmp/ame-fm-test-prefs"
	_ = os.remove_all(tmp)
	defer _ = os.remove_all(tmp)
	old_xdg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
	posix.setenv("XDG_CONFIG_HOME", "/tmp/ame-fm-test-prefs", true) // never touch the user's config
	defer {
		if old_xdg != "" do posix.setenv("XDG_CONFIG_HOME", strings.clone_to_cstring(old_xdg, context.temp_allocator), true)
		else do posix.unsetenv("XDG_CONFIG_HOME")
	}
	saved_cwd := app.cwd
	defer app.cwd = saved_cwd

	load_view_prefs() // nothing saved: defaults
	testing.expect(t, app.dirs_first)
	app.cwd = "/music"
	app.sort, app.sort_desc, app.group = .Size, true, .Ext
	remember_sort()
	app.cwd = "/docs"
	app.sort, app.sort_desc, app.group = .Modified, false, .None
	remember_sort()

	load_view_prefs()
	apply_folder_prefs("/music")
	testing.expect_value(t, app.sort, Sort_Key.Size)
	testing.expect_value(t, app.group, Group_By.Ext)
	testing.expect(t, app.sort_desc)
	apply_folder_prefs("/elsewhere") // unseen folder: the last choice
	testing.expect_value(t, app.sort, Sort_Key.Modified)
	testing.expect(t, !app.sort_desc)
}

@(test)
test_drop_into_self :: proc(t: ^testing.T) {
	defer drag_clear()
	append(&dd.paths, strings.clone("/home/u/写真"))
	testing.expect(t, !dir_ok("/home/u/写真"))
	testing.expect(t, !dir_ok("/home/u/写真/2026"))
	testing.expect(t, dir_ok("/home/u/写真2")) // only a real subfolder counts
	testing.expect(t, dir_ok("/home/u"))
}

@(test)
test_lang_icon :: proc(t: ^testing.T) {
	l, ok := lang_of("/x/Main.PY")
	testing.expect(t, ok && l.icon == "python") // case-insensitive extension
	_, ok = lang_of("Dockerfile")
	testing.expect(t, ok) // known name without extension
	_, ok = lang_of("photo.png")
	testing.expect(t, !ok)
	testing.expect_value(t, kind_of("View.swift", {}), Kind.Code) // languages outside the old list count as code
}

@(test)
test_project_detect :: proc(t: ^testing.T) {
	testing.expect(t, toml_dep("[dependencies]\nyew = \"0.21\"", "yew"))
	testing.expect(t, toml_dep("[dependencies.yew]\nversion = \"0.21\"", "yew"))
	testing.expect(t, !toml_dep("[dependencies]\nyewtil = \"1\"", "yew")) // a longer crate name is not yew
	dir := "/tmp/ame-fm-test-proj"
	_ = os.remove_all(dir)
	defer _ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	_ = os.write_entire_file_from_string("/tmp/ame-fm-test-proj/package.json", `{"dependencies":{"next":"15","react":"19"}}`)
	l, ok := project_detect(dir)
	testing.expect(t, ok && l.label == "Next.js") // Next wins over the React it depends on
	l, ok = lang_of("vite.config.ts")
	testing.expect(t, ok && l.label == "Vite")
}

@(test)
test_split_label :: proc(t: ^testing.T) {
	r := utf8.string_to_runes("フォルダー優先", context.temp_allocator)
	testing.expect_value(t, label_cut(r), 5) // フォルダー|優先: at the script change, not before ー
	r = utf8.string_to_runes("ここに展開", context.temp_allocator)
	testing.expect_value(t, label_cut(r), 3) // after the particle に
}

@(test)
test_svg_rasterize :: proc(t: ^testing.T) {
	img := svg_rasterize(`<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></svg>`, 10, context.temp_allocator)
	testing.expect_value(t, img[0], u32(0xffff0000))
	testing.expect_value(t, img[99], u32(0xffff0000))
	// even-odd: a square with a square hole
	img = svg_rasterize(`<svg viewBox="0 0 10 10"><path fill-rule="evenodd" fill="#fff" d="M0 0h10v10H0zM3 3h4v4H3z"/></svg>`, 10, context.temp_allocator)
	testing.expect_value(t, img[0], u32(0xffffffff))
	testing.expect_value(t, img[5 * 10 + 5] >> 24, u32(0)) // hole
	// circle (arcs): covered area ≈ πr²
	img = svg_rasterize(`<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="16" fill="#000"/></svg>`, 40, context.temp_allocator)
	area: f32
	for p in img do area += f32(p >> 24) / 255
	testing.expect(t, abs(area - 3.14159 * 16 * 16) < 12)
	// gradients take the average of their stops; relative commands, compact numbers
	img = svg_rasterize(`<svg viewBox="0 0 4 4"><defs><linearGradient id="g"><stop stop-color="#000"/><stop stop-color="#fefefe"/></linearGradient></defs><path fill="url(#g)" d="m0 0h4v4h-4z"/></svg>`, 4, context.temp_allocator)
	testing.expect_value(t, img[5], u32(0xff7f7f7f))
}

@(test)
test_project_main_language :: proc(t: ^testing.T) {
	dir := "/tmp/ame-fm-test-lang"
	_ = os.remove_all(dir)
	defer _ = os.remove_all(dir)
	_ = os.make_directory_all("/tmp/ame-fm-test-lang/src/gui")
	_ = os.make_directory_all("/tmp/ame-fm-test-lang/zig-out")
	_ = os.write_entire_file_from_string("/tmp/ame-fm-test-lang/build.zig", "const std = @import(\"std\");")
	_ = os.write_entire_file_from_string("/tmp/ame-fm-test-lang/src/gui/app.odin", strings.repeat("x := 1\n", 500, context.temp_allocator))
	_ = os.write_entire_file_from_string("/tmp/ame-fm-test-lang/zig-out/huge.zig", strings.repeat("// build output\n", 5000, context.temp_allocator))
	l, ok := project_detect(dir)
	testing.expect(t, ok && l.label == "Odin") // most code is Odin; build.zig and zig-out don't decide it
	_ = os.remove_all("/tmp/ame-fm-test-lang/src")
	l, ok = project_detect(dir)
	testing.expect(t, ok && l.label == "Zig") // no sources: the build file still says Zig
}
