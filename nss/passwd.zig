const std = @import("std");
const flatdb = @import("../deps/flatdb/flatdb.zig");
const DelimitedBufferIterator = flatdb.DelimitedBufferIterator;

/// Entry for passwd database.
pub const Entry = struct {
    login: []const u8,
    password: []const u8,
    uid: u32,
    gid: u32,
    info: []const u8,
    home: []const u8,
    shell: []const u8,

    pub fn iterateInfo(this: Entry) InfoIterator {
        return InfoIterator.init(this.info);
    }
};

/// Iterate over comma-separated passwd info fields.
pub const InfoIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{','},
    .delimit_mode = .separator,
});
