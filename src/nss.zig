const std = @import("std");
const passwd = @import("nss-passwd.zig");
const meta = std.meta;
const TagPayload = meta.TagPayload;

pub const Database = enum {
    passwd,
};

pub const DatabaseEntry = union(Database) {
    passwd: passwd.Entry,
};

pub fn getent(
    comptime db: Database,
    key: []const u8,
) ?TagPayload(DatabaseEntry, db) {
    _ = key;
    switch (db) {
        //.passwd => return passwd.Entry{ .name = key },
        else => return null,
    }
}

test "payload return" {
    const entry = getent(.passwd, "foo").?;
    try std.testing.expectEqualStrings("foo", entry.name);
}
