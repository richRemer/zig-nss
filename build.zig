const std = @import("std");
const QuickBuild = @import("qb.zig").QuickBuild;

pub fn build(b: *std.Build) !void {
    try QuickBuild(.{
        .src_path = ".",
        .deps = .{.flatdb},
        .outs = .{
            .nss = .{
                .gen = .{ .mod, .unit },
                .zig = .{.flatdb},
            },
        },
    }).setup(b);
}
