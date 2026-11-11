const std = @import("std");

// ============================================================================
// Types (must match Odin definitions exactly)
// ============================================================================

pub const FileType = enum(u8) {
    unknown = 0,
    regular = 1,
    directory = 2,
    symlink = 3,
};

pub const FileInfo = extern struct {
    name: [256]u8,
    name_len: u32,
    path: [1024]u8,
    path_len: u32,
    size: i64,
    modified: i64,
    file_type: FileType,
    is_hidden: bool,

    pub fn getName(self: *const FileInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getPath(self: *const FileInfo) []const u8 {
        return self.path[0..self.path_len];
    }
};

pub const OperationStatus = enum(i32) {
    success = 0,
    error_not_found = -1,
    error_permission = -2,
    error_exists = -3,
    error_io = -4,
    error_invalid_path = -5,
    error_unknown = -100,

    pub fn toError(self: OperationStatus) !void {
        return switch (self) {
            .success => {},
            .error_not_found => error.NotFound,
            .error_permission => error.PermissionDenied,
            .error_exists => error.AlreadyExists,
            .error_io => error.IoError,
            .error_invalid_path => error.InvalidPath,
            .error_unknown => error.Unknown,
        };
    }
};

// ============================================================================
// External Functions (implemented in Odin)
// ============================================================================

extern "c" fn gf_init() void;
extern "c" fn gf_cleanup() void;

extern "c" fn gf_list_dir(
    path: [*:0]const u8,
    out_files: [*]FileInfo,
    out_count: *c_int,
    max_count: c_int,
) OperationStatus;

extern "c" fn gf_copy(src: [*:0]const u8, dst: [*:0]const u8) OperationStatus;
extern "c" fn gf_move(src: [*:0]const u8, dst: [*:0]const u8) OperationStatus;
extern "c" fn gf_delete(path: [*:0]const u8) OperationStatus;
extern "c" fn gf_rename(old_path: [*:0]const u8, new_path: [*:0]const u8) OperationStatus;
extern "c" fn gf_mkdir(path: [*:0]const u8) OperationStatus;
extern "c" fn gf_exists(path: [*:0]const u8) bool;
extern "c" fn gf_stat(path: [*:0]const u8, out_info: *FileInfo) OperationStatus;

// ============================================================================
// Safe Zig Wrappers
// ============================================================================

pub fn init() void {
    gf_init();
}

pub fn cleanup() void {
    gf_cleanup();
}

/// Max entries returned by listDir; larger directories are truncated.
pub const max_list = 8192;

pub fn listDir(allocator: std.mem.Allocator, path: []const u8) ![]FileInfo {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var buffer = try allocator.alloc(FileInfo, max_list);
    errdefer allocator.free(buffer);

    var count: c_int = 0;
    const status = gf_list_dir(path_z.ptr, buffer.ptr, &count, max_list);
    try status.toError();

    if (count < buffer.len) {
        buffer = try allocator.realloc(buffer, @intCast(count));
    }

    return buffer;
}

pub fn copy(src: []const u8, dst: []const u8) !void {
    const allocator = std.heap.c_allocator;

    const src_z = try allocator.dupeZ(u8, src);
    defer allocator.free(src_z);

    const dst_z = try allocator.dupeZ(u8, dst);
    defer allocator.free(dst_z);

    const status = gf_copy(src_z.ptr, dst_z.ptr);
    try status.toError();
}

pub fn move(src: []const u8, dst: []const u8) !void {
    const allocator = std.heap.c_allocator;

    const src_z = try allocator.dupeZ(u8, src);
    defer allocator.free(src_z);

    const dst_z = try allocator.dupeZ(u8, dst);
    defer allocator.free(dst_z);

    const status = gf_move(src_z.ptr, dst_z.ptr);
    try status.toError();
}

pub fn delete(path: []const u8) !void {
    const allocator = std.heap.c_allocator;

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const status = gf_delete(path_z.ptr);
    try status.toError();
}

pub fn rename(old_path: []const u8, new_path: []const u8) !void {
    const allocator = std.heap.c_allocator;

    const old_z = try allocator.dupeZ(u8, old_path);
    defer allocator.free(old_z);

    const new_z = try allocator.dupeZ(u8, new_path);
    defer allocator.free(new_z);

    const status = gf_rename(old_z.ptr, new_z.ptr);
    try status.toError();
}

pub fn mkdir(path: []const u8) !void {
    const allocator = std.heap.c_allocator;

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const status = gf_mkdir(path_z.ptr);
    try status.toError();
}

pub fn exists(path: []const u8) !bool {
    const allocator = std.heap.c_allocator;

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    return gf_exists(path_z.ptr);
}

pub fn stat(path: []const u8) !FileInfo {
    const allocator = std.heap.c_allocator;

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var info: FileInfo = undefined;
    const status = gf_stat(path_z.ptr, &info);
    try status.toError();

    return info;
}
