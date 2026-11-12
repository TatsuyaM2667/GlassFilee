package main

import "core:os"
import "core:sys/posix"
import "core:strings"
import "core:testing"

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
