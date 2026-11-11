const std = @import("std");

const core = @import("core");

test "core initialization" {
    core.init();
    defer core.cleanup();
}

test "list directory" {
    const allocator = std.testing.allocator;

    core.init();
    defer core.cleanup();

    const files = try core.listDir(allocator, ".");
    defer allocator.free(files);

    try std.testing.expect(files.len > 0);
}

test "file operations" {
    core.init();
    defer core.cleanup();

    const test_file = "test_file_gf.txt";
    const test_copy = "test_copy_gf.txt";
    const test_rename = "test_renamed_gf.txt";

    // Cleanup any existing test files
    std.fs.cwd().deleteFile(test_file) catch {};
    std.fs.cwd().deleteFile(test_copy) catch {};
    std.fs.cwd().deleteFile(test_rename) catch {};

    // Create test file
    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = "test content" });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Test exists
    const exists = try core.exists(test_file);
    try std.testing.expect(exists);

    // Test stat
    const info = try core.stat(test_file);
    try std.testing.expectEqual(core.FileType.regular, info.file_type);

    // Test copy
    try core.copy(test_file, test_copy);
    defer std.fs.cwd().deleteFile(test_copy) catch {};

    const copy_exists = try core.exists(test_copy);
    try std.testing.expect(copy_exists);

    // Test rename
    try core.rename(test_copy, test_rename);
    defer std.fs.cwd().deleteFile(test_rename) catch {};

    const renamed_exists = try core.exists(test_rename);
    try std.testing.expect(renamed_exists);

    // Test delete
    try core.delete(test_rename);
    const deleted_exists = try core.exists(test_rename);
    try std.testing.expect(!deleted_exists);
}

test "directory operations" {
    core.init();
    defer core.cleanup();

    const test_dir = "test_directory_gf";

    // Cleanup
    std.fs.cwd().deleteTree(test_dir) catch {};

    // Test mkdir
    try core.mkdir(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const exists = try core.exists(test_dir);
    try std.testing.expect(exists);

    // Test stat on directory
    const info = try core.stat(test_dir);
    try std.testing.expectEqual(core.FileType.directory, info.file_type);
}

test "recursive copy/delete, symlink delete keeps target" {
    const d = "test_tree_gf";
    std.fs.cwd().deleteTree(d) catch {};
    std.fs.cwd().deleteTree(d ++ "_copy") catch {};
    defer std.fs.cwd().deleteTree(d) catch {};
    defer std.fs.cwd().deleteTree(d ++ "_copy") catch {};

    try std.fs.cwd().makePath(d ++ "/sub");
    try std.fs.cwd().writeFile(.{ .sub_path = d ++ "/sub/a.txt", .data = "x" });

    try core.copy(d, d ++ "_copy");
    try std.testing.expect(try core.exists(d ++ "_copy/sub/a.txt"));
    try std.testing.expectError(error.AlreadyExists, core.copy(d, d ++ "_copy"));

    // deleting a symlink to a dir must not touch the target's contents
    try std.fs.cwd().symLink("sub", d ++ "/link", .{ .is_directory = true });
    try core.delete(d ++ "/link");
    try std.testing.expect(try core.exists(d ++ "/sub/a.txt"));

    try core.delete(d ++ "_copy");
    try std.testing.expect(!try core.exists(d ++ "_copy"));
}
