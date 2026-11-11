package main

import "core:os"
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
