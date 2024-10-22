const std = @import("std");
const passwd = @import("nss-passwd.zig");
const meta = std.meta;
const TagPayload = meta.TagPayload;

pub const Database = enum {
    aliases,
    ethers,
    group,
    hosts,
    initgroups,
    netgroup,
    networks,
    passwd,
    protocols,
    publickey,
    rpc,
    services,
    shadow,
};

pub const DatabaseEntry = union(Database) {
    aliases: void,
    ethers: void,
    group: void,
    hosts: void,
    initgroups: void,
    netgroup: void,
    networks: void,
    passwd: passwd.Entry,
    protocols: void,
    publickey: void,
    rpc: void,
    services: void,
    shadow: void,
};

pub fn getent(
    comptime db: Database,
    key: []const u8,
) ?TagPayload(DatabaseEntry, db) {
    switch (db) {
        .passwd => return passwd.Entry{
            .login = key,
            .password = undefined,
            .uid = undefined,
            .gid = undefined,
            .info = undefined,
            .home = undefined,
            .shell = undefined,
        },
        else => return null,
    }
}

test "getent return by TagPayload" {
    const entry = getent(.passwd, "foo").?;
    try std.testing.expectEqual("foo", entry.login);
}
