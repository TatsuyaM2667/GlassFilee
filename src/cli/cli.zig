const std = @import("std");
const core = @import("core");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    core.init();
    defer core.cleanup();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "ls") or std.mem.eql(u8, command, "list")) {
        const path = if (args.len > 2) args[2] else ".";
        try listCommand(allocator, path);
    } else if (std.mem.eql(u8, command, "cp") or std.mem.eql(u8, command, "copy")) {
        if (args.len < 4) {
            try stderr.print("Error: copy requires source and destination\n", .{});
            return error.InvalidArgs;
        }
        try copyCommand(args[2], args[3]);
    } else if (std.mem.eql(u8, command, "mv") or std.mem.eql(u8, command, "move")) {
        if (args.len < 4) {
            try stderr.print("Error: move requires source and destination\n", .{});
            return error.InvalidArgs;
        }
        try moveCommand(args[2], args[3]);
    } else if (std.mem.eql(u8, command, "rm") or std.mem.eql(u8, command, "delete")) {
        if (args.len < 3) {
            try stderr.print("Error: delete requires a path\n", .{});
            return error.InvalidArgs;
        }
        try deleteCommand(args[2]);
    } else if (std.mem.eql(u8, command, "mkdir")) {
        if (args.len < 3) {
            try stderr.print("Error: mkdir requires a path\n", .{});
            return error.InvalidArgs;
        }
        try mkdirCommand(args[2]);
    } else if (std.mem.eql(u8, command, "stat")) {
        if (args.len < 3) {
            try stderr.print("Error: stat requires a path\n", .{});
            return error.InvalidArgs;
        }
        try statCommand(args[2]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        try printUsage();
    } else {
        try stderr.print("Unknown command: {s}\n", .{command});
        try printUsage();
        return error.InvalidCommand;
    }
}

fn printUsage() !void {
    try stdout.print(
        \\GlassFilee CLI (v0.1)
        \\A lightweight file manager core with integrated conversion capabilities.
        \\
        \\USAGE:
        \\    gf-cli <command> [args...]
        \\
        \\COMMANDS:
        \\    ls, list [path]              List directory contents (default: current dir)
        \\    cp, copy <src> <dst>         Copy file
        \\    mv, move <src> <dst>         Move/rename file
        \\    rm, delete <path>            Delete file or directory
        \\    mkdir <path>                 Create directory
        \\    stat <path>                  Show file information
        \\    help, --help                 Show this help message
        \\
        \\EXAMPLES:
        \\    gf-cli ls /home/user/documents
        \\    gf-cli cp file.txt backup.txt
        \\    gf-cli mv old_name.txt new_name.txt
        \\    gf-cli mkdir my_folder
        \\    gf-cli stat important.doc
        \\
    , .{});
}

fn listCommand(allocator: std.mem.Allocator, path: []const u8) !void {
    try stdout.print("Listing: {s}\n", .{path});
    try stdout.print("{s}\n", .{"=" ** 80});

    const files = core.listDir(allocator, path) catch |err| {
        try stderr.print("Error listing directory: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(files);

    try stdout.print("{s:<40} {s:>12} {s:>10} {s}\n", .{ "Name", "Size", "Type", "Flags" });
    try stdout.print("{s}\n", .{"-" ** 80});

    for (files) |file| {
        const name = file.getName();
        const size_str = try formatSize(allocator, file.size);
        defer allocator.free(size_str);

        const type_str = switch (file.file_type) {
            .regular => "File",
            .directory => "Directory",
            .symlink => "Symlink",
            .unknown => "Unknown",
        };

        const hidden_str: []const u8 = if (file.is_hidden) "[HIDDEN]" else "";

        try stdout.print("{s:<40} {s:>12} {s:>10} {s}\n", .{
            name,
            size_str,
            type_str,
            hidden_str,
        });
    }

    try stdout.print("{s}\n", .{"=" ** 80});
    try stdout.print("Total: {} items\n", .{files.len});
}

fn copyCommand(src: []const u8, dst: []const u8) !void {
    try stdout.print("Copying: {s} -> {s}\n", .{ src, dst });

    core.copy(src, dst) catch |err| {
        try stderr.print("Error copying file: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("✓ Copy successful\n", .{});
}

fn moveCommand(src: []const u8, dst: []const u8) !void {
    try stdout.print("Moving: {s} -> {s}\n", .{ src, dst });

    core.move(src, dst) catch |err| {
        try stderr.print("Error moving file: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("✓ Move successful\n", .{});
}

fn deleteCommand(path: []const u8) !void {
    try stdout.print("Deleting: {s}\n", .{path});

    try stdout.print("Are you sure? (y/N): ", .{});
    const stdin = std.io.getStdIn().reader();
    var buf: [10]u8 = undefined;
    const input = try stdin.readUntilDelimiterOrEof(&buf, '\n');

    if (input == null or input.?[0] != 'y') {
        try stdout.print("Cancelled\n", .{});
        return;
    }

    core.delete(path) catch |err| {
        try stderr.print("Error deleting: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("✓ Delete successful\n", .{});
}

fn mkdirCommand(path: []const u8) !void {
    try stdout.print("Creating directory: {s}\n", .{path});

    core.mkdir(path) catch |err| {
        try stderr.print("Error creating directory: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("✓ Directory created\n", .{});
}

fn statCommand(path: []const u8) !void {
    const info = core.stat(path) catch |err| {
        try stderr.print("Error getting file info: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("\nFile Information:\n", .{});
    try stdout.print("  Name:     {s}\n", .{info.getName()});
    try stdout.print("  Path:     {s}\n", .{info.getPath()});
    try stdout.print("  Size:     {} bytes\n", .{info.size});
    try stdout.print("  Type:     {s}\n", .{@tagName(info.file_type)});
    try stdout.print("  Hidden:   {}\n", .{info.is_hidden});
    try stdout.print("  Modified: {}\n", .{info.modified});
}

fn formatSize(allocator: std.mem.Allocator, size: i64) ![]const u8 {
    const KB: i64 = 1024;
    const MB: i64 = KB * 1024;
    const GB: i64 = MB * 1024;

    if (size < KB) {
        return try std.fmt.allocPrint(allocator, "{} B", .{size});
    } else if (size < MB) {
        const kb = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(KB));
        return try std.fmt.allocPrint(allocator, "{d:.1} KB", .{kb});
    } else if (size < GB) {
        const mb = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(MB));
        return try std.fmt.allocPrint(allocator, "{d:.1} MB", .{mb});
    } else {
        const gb = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(GB));
        return try std.fmt.allocPrint(allocator, "{d:.1} GB", .{gb});
    }
}
