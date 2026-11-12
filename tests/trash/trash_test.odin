package trash_test

// Run: GF_TEST_DIR=<empty scratch dir> odin test tests/trash
// Uses an isolated XDG_DATA_HOME inside GF_TEST_DIR, so the real trash is never touched.

import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import gf "../../src/core"

@(test)
trash_restore_delete :: proc(t: ^testing.T) {
	base := os.get_env("GF_TEST_DIR", context.temp_allocator)
	if base == "" {
		testing.fail_now(t, "set GF_TEST_DIR to an empty scratch directory")
	}
	data := strings.concatenate({base, "/data"}, context.temp_allocator)
	work := strings.concatenate({base, "/work"}, context.temp_allocator)
	_ = os.make_directory_all(data)
	_ = os.make_directory_all(strings.concatenate({work, "/sub"}, context.temp_allocator))
	posix.setenv("XDG_DATA_HOME", strings.clone_to_cstring(data, context.temp_allocator), true)
	file := strings.concatenate({work, "/a b.txt"}, context.temp_allocator)
	_ = os.write_entire_file_from_string(file, "x")
	_ = os.write_entire_file_from_string(strings.concatenate({work, "/sub/c.txt"}, context.temp_allocator), "y")

	td := gf.trash_dir(context.temp_allocator)
	testing.expect_value(t, td, strings.concatenate({data, "/Trash"}, context.temp_allocator))

	// trash, then restore (the space is URL-escaped in .trashinfo)
	testing.expect_value(t, gf.trash_path(file), gf.OperationStatus.Success)
	testing.expect(t, !os.exists(file))
	testing.expect(t, os.exists(strings.concatenate({td, "/files/a b.txt"}, context.temp_allocator)))
	info, _ := os.read_entire_file_from_path(strings.concatenate({td, "/info/a b.txt.trashinfo"}, context.temp_allocator), context.temp_allocator)
	testing.expect(t, strings.contains(string(info), "/work/a%20b.txt\n"))
	testing.expect_value(t, gf.restore_from_trash("a b.txt"), gf.OperationStatus.Success)
	testing.expect(t, os.exists(file))

	// the same name trashed twice gets a unique trash name
	testing.expect_value(t, gf.trash_path(file), gf.OperationStatus.Success)
	_ = os.write_entire_file_from_string(file, "z")
	testing.expect_value(t, gf.trash_path(file), gf.OperationStatus.Success)
	testing.expect(t, os.exists(strings.concatenate({td, "/files/a b.txt.2"}, context.temp_allocator)))

	// restoring onto an existing file is refused
	_ = os.write_entire_file_from_string(file, "w")
	testing.expect_value(t, gf.restore_from_trash("a b.txt"), gf.OperationStatus.ErrorExists)

	// folders, permanent delete of one item, then empty everything
	testing.expect_value(t, gf.trash_path(strings.concatenate({work, "/sub"}, context.temp_allocator)), gf.OperationStatus.Success)
	testing.expect_value(t, gf.delete_from_trash("a b.txt.2"), gf.OperationStatus.Success)
	testing.expect_value(t, gf.empty_trash(), gf.OperationStatus.Success)
	left, _ := os.read_all_directory_by_path(strings.concatenate({td, "/files"}, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, len(left), 0)
}

@(test)
copy_tree_progress_and_cancel :: proc(t: ^testing.T) {
	base := os.get_env("GF_TEST_DIR", context.temp_allocator)
	if base == "" do return
	j :: proc(a: ..string) -> string {return strings.concatenate(a, context.temp_allocator)}
	// never the real trash: this test trashes a folder at the end
	_ = os.make_directory_all(j(base, "/ctdata"))
	posix.setenv("XDG_DATA_HOME", strings.clone_to_cstring(j(base, "/ctdata"), context.temp_allocator), true)
	_ = os.make_directory_all(j(base, "/ct/src/sub"))
	_ = os.write_entire_file_from_string(j(base, "/ct/src/a.txt"), "hello")
	_ = os.write_entire_file_from_string(j(base, "/ct/src/sub/b.txt"), "world!")
	_ = os.symlink("a.txt", j(base, "/ct/src/link"))

	p: gf.Progress
	testing.expect_value(t, gf.tree_size(j(base, "/ct/src")), i64(11 + len("a.txt"))) // file bytes + the link's own size (its target text)
	testing.expect_value(t, gf.copy_tree(j(base, "/ct/src"), j(base, "/ct/dst"), &p), gf.OperationStatus.Success)
	testing.expect_value(t, p.done, i64(11))
	data, _ := os.read_entire_file_from_path(j(base, "/ct/dst/sub/b.txt"), context.temp_allocator)
	testing.expect_value(t, string(data), "world!")
	target, _ := os.read_link(j(base, "/ct/dst/link"), context.temp_allocator)
	testing.expect_value(t, target, "a.txt") // symlinks are copied as links
	testing.expect_value(t, gf.copy_tree(j(base, "/ct/src"), j(base, "/ct/dst"), &p), gf.OperationStatus.ErrorExists)

	// a cancelled copy stops and leaves no half-written file behind
	c := gf.Progress{cancel = true}
	testing.expect_value(t, gf.copy_tree(j(base, "/ct/src/a.txt"), j(base, "/ct/c.txt"), &c), gf.OperationStatus.Cancelled)
	testing.expect(t, !os.exists(j(base, "/ct/c.txt")))

	st, name := gf.trash_path_named(j(base, "/ct/dst"))
	testing.expect_value(t, st, gf.OperationStatus.Success)
	testing.expect_value(t, name, "dst")
}
