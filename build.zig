const std = @import("std");

// Requires Zig 0.13.x. The Odin core must be built first into zig-cache/libgfcore.a
// (build.sh / `make odin-core` do this).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const odin_lib = b.path("zig-cache/libgfcore.a");
    const core_mod = b.addModule("core", .{ .root_source_file = b.path("src/bindings/core.zig") });

    // CLI
    const cli_exe = b.addExecutable(.{
        .name = "gf-cli",
        .root_source_file = b.path("src/cli/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_exe.root_module.addImport("core", core_mod);
    cli_exe.addObjectFile(odin_lib);
    cli_exe.linkLibC();
    b.installArtifact(cli_exe);

    const run_cli_cmd = b.addRunArtifact(cli_exe);
    run_cli_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cli_cmd.addArgs(args);
    b.step("run", "Run the CLI tool").dependOn(&run_cli_cmd.step);

    // Tests
    const core_tests = b.addTest(.{
        .root_source_file = b.path("src/core/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_tests.root_module.addImport("core", core_mod);
    core_tests.addObjectFile(odin_lib);
    core_tests.linkLibC();
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(core_tests).step);
}
