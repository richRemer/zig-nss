const flatdb = @import("deps/flatdb/flatdb.zig");

pub const Entry = struct {
    name: []const u8,
    password: []const u8,
    uid: u32,
    gid: u32,
    info: []const u8,
    home: []const u8,
    shell: []const u8,
};
