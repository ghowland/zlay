// build.zig

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "clay_layout_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });


    // Run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run src");
    run_step.dependOn(&run_cmd.step);


    b.installArtifact(exe);
}
