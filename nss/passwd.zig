const std = @import("std");
const flatdb = @import("../deps/flatdb/flatdb.zig");
const fmt = std.fmt;
const DelimitedBufferIterator = flatdb.DelimitedBufferIterator;

pub const db_path = "/etc/passwd";

pub const Entry = struct {
    login: []const u8,
    password: []const u8,
    uid: u32,
    gid: u32,
    info: []const u8,
    home: []const u8,
    shell: []const u8,

    pub const key = "login";

    pub const Iterator = struct {
        inner: LineIterator,

        pub fn init(buffer: []const u8) Iterator {
            return .{ .inner = LineIterator.init(buffer) };
        }

        pub fn next(this: *Iterator) ?Entry {
            while (this.inner.next()) |line| {
                var entry: Entry = undefined;
                var field_it = FieldIterator.init(line);

                entry.login = field_it.next() orelse continue;
                entry.password = field_it.next() orelse continue;
                const uid = field_it.next() orelse continue;
                const gid = field_it.next() orelse continue;
                entry.info = field_it.next() orelse continue;
                entry.home = field_it.next() orelse continue;
                entry.shell = field_it.next() orelse continue;

                if (field_it.next() != null) continue;

                entry.uid = fmt.parseInt(u32, uid, 10) catch continue;
                entry.gid = fmt.parseInt(u32, gid, 10) catch continue;

                return entry;
            }

            return null;
        }
    };

    pub fn iterateInfo(this: Entry) InfoIterator {
        return InfoIterator.init(this.info);
    }
};

const LineIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{'\n'},
    .delimit_mode = .terminator,
    .collapse = true,
});

const FieldIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{':'},
    .delimit_mode = .separator,
});

pub const InfoIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{','},
    .delimit_mode = .separator,
});

test "read passwd" {
    const buffer =
        \\root:x:0:0:root:/root:/bin/bash
        \\daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
        \\bin:x:2:2:bin:/bin:/usr/sbin/nologin
        \\
    ;

    var it = Entry.Iterator.init(buffer);
    const maybe_entry = it.next();

    try std.testing.expect(null != maybe_entry);
    try std.testing.expectEqualStrings("root", maybe_entry.?.login);
    try std.testing.expectEqualStrings("x", maybe_entry.?.password);
    try std.testing.expectEqual(0, maybe_entry.?.uid);
    try std.testing.expectEqual(0, maybe_entry.?.gid);
    try std.testing.expectEqualStrings("root", maybe_entry.?.info);
    try std.testing.expectEqualStrings("/root", maybe_entry.?.home);
    try std.testing.expectEqualStrings("/bin/bash", maybe_entry.?.shell);

    try std.testing.expect(null != it.next());
    try std.testing.expect(null != it.next());
    try std.testing.expectEqual(null, it.next());

    var info_it = maybe_entry.?.iterateInfo();

    try std.testing.expectEqualStrings("root", info_it.next().?);
    try std.testing.expectEqual(null, info_it.next());
}
