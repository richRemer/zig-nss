const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nss = b.addStaticLibrary(.{
        .name = "nss",
        .root_source_file = b.path("nss.zig"),
        .target = target,
        .optimize = optimize,
    });

    const nss_unit_tests = b.addTest(.{
        .root_source_file = b.path("nss.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(nss_unit_tests);
    const test_step = b.step("test", "Run unit tests");

    b.installArtifact(nss);
    test_step.dependOn(&run_lib_unit_tests.step);
}
