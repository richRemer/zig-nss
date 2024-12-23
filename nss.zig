const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const meta = std.meta;
const fmt = std.fmt;
const fs = std.fs;
const TagPayload = meta.TagPayload;

pub const conf = @import("nss/conf.zig");
pub const group = @import("nss/group.zig");
pub const passwd = @import("nss/passwd.zig");
pub const files = @import("nss/files.zig");
pub const testing = @import("nss/testing.zig");

/// NSS service context.
pub const NSS = struct {
    allocator: mem.Allocator,
    files: FileCache,

    pub const FileCache = std.StringHashMap([]const u8);

    /// Open NSS database.
    pub fn open(allocator: mem.Allocator) NSS {
        return .{
            .allocator = allocator,
            .files = FileCache.init(allocator),
        };
    }

    /// Close NSS database.
    pub fn close(this: *NSS) void {
        var values = this.files.valueIterator();
        var keys = this.files.keyIterator();

        while (values.next()) |value| {
            this.allocator.free(value.*);
        }

        while (keys.next()) |key| {
            this.allocator.free(key.*);
        }

        this.files.clearAndFree();
        this.files.deinit();
    }

    /// Lookup database entry by its key.
    pub fn getent(
        this: *NSS,
        comptime db: Database,
        key: []const u8,
    ) ?TagPayload(Entry, db) {
        // TODO: cache services
        const service = ServiceSwitch(db).init(this) catch return null;
        defer service.deinit();
        return service.find(key);
    }

    /// Lookup group database entry by GID.
    pub fn getgrgid(this: *NSS, gid: u32) ?group.Entry {
        const service = ServiceSwitch(.group).init(this) catch return null;
        defer service.deinit();
        return service.findGid(gid);
    }

    /// Lookup group database entry by name.
    pub fn getgrnam(this: *NSS, name: []const u8) ?group.Entry {
        const service = ServiceSwitch(.group).init(this) catch return null;
        defer service.deinit();
        return service.findName(name);
    }

    /// Lookup passwd database entry by login.
    pub fn getpwnam(this: *NSS, login: []const u8) ?passwd.Entry {
        const service = ServiceSwitch(.passwd).init(this) catch return null;
        defer service.deinit();
        return service.findLogin(login);
    }

    /// Lookup passwd database entry by UID.
    pub fn getpwuid(this: *NSS, uid: u32) ?passwd.Entry {
        const service = ServiceSwitch(.passwd).init(this) catch return null;
        defer service.deinit();
        return service.findUid(uid);
    }

    /// Open, read, and cache a file.  Use cached value if available.
    pub fn open_file(this: *NSS, absolute_path: []const u8) ![]const u8 {
        if (this.files.get(absolute_path)) |buffer| {
            return buffer;
        } else {
            const file = try fs.openFileAbsolute(absolute_path, .{});
            defer file.close();

            const allocator = this.allocator;
            const max_size = math.maxInt(usize);
            const buffer = try file.readToEndAlloc(allocator, max_size);
            errdefer allocator.free(buffer);

            const path = try this.allocator.dupe(u8, absolute_path);
            errdefer allocator.free(path);

            try this.files.put(path, buffer);
            return buffer;
        }
    }
};

/// Known databases understood by NSS, but not necessarily supported in this
/// implementation.
pub const Database = enum {
    group,
    passwd,

    pub fn fromName(name: []const u8) ?Database {
        const fields = @typeInfo(Database).@"enum".fields;

        inline for (fields) |field| {
            if (mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }

        return null;
    }
};

/// Known sources understood by NSS, but not necessarily supported in this
/// implementation.
pub const Source = enum {
    files, // supports pretty much everything
    // TODO: https://man.archlinux.org/man/core/systemd/libnss_systemd.so.2.8.en
    systemd, // supports passwd, group, shadow, gshadow

    pub fn fromName(name: []const u8) ?Source {
        const fields = @typeInfo(Source).@"enum".fields;

        inline for (fields) |field| {
            if (mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }

        return null;
    }
};

/// Supported database sources.
pub const DatabaseSource = union(enum) {
    group_files: files.GroupService,
    passwd_files: files.PasswdService,
};

/// Generic database entry.  Union of all database entry types.
pub const Entry = union(Database) {
    group: group.Entry,
    passwd: passwd.Entry,
};

/// Generic database service.  Union of all database service types.
pub const Service = union(Database) {
    group: void, // TODO
    passwd: void, // TODO
};

/// Create a switched service that uses the NSS conf (/etc/nsswitch.conf) to
/// switch between different sources.
pub fn ServiceSwitch(db: Database) type {
    const T = TagPayload(Entry, db);

    const group_impl = struct {
        pub fn findGid(this: anytype, gid: u32) ?group.Entry {
            for (this.sources) |source| {
                const maybe_service = switch (source) {
                    .files => files.GroupService.init(this.nss),
                    else => null,
                };

                if (maybe_service) |service| {
                    if (service.findGid(gid)) |entry| return entry;
                }
            }

            return null;
        }

        pub fn findName(this: anytype, name: []const u8) ?group.Entry {
            for (this.sources) |source| {
                const maybe_service = switch (source) {
                    .files => files.GroupService.init(this.nss),
                    else => null,
                };

                if (maybe_service) |service| {
                    if (service.findName(name)) |entry| return entry;
                }
            }

            return null;
        }
    };

    const passwd_impl = struct {
        pub fn findLogin(this: anytype, login: []const u8) ?passwd.Entry {
            for (this.sources) |source| {
                const maybe_service = switch (source) {
                    .files => files.PasswdService.init(this.nss),
                    else => null,
                };

                if (maybe_service) |service| {
                    if (service.findLogin(login)) |entry| return entry;
                }
            }

            return null;
        }

        pub fn findUid(this: anytype, uid: u32) ?passwd.Entry {
            for (this.sources) |source| {
                const maybe_service = switch (source) {
                    .files => files.PasswdService.init(this.nss),
                    else => null,
                };

                if (maybe_service) |service| {
                    if (service.findUid(uid)) |entry| return entry;
                }
            }

            return null;
        }
    };

    return struct {
        nss: *NSS,
        sources: []const Source,

        pub fn init(nss: *NSS) !@This() {
            var sources = std.ArrayList(Source).init(nss.allocator);
            defer sources.deinit();

            const buffer = nss.open_file(conf.db_path) catch &.{};
            const nsswitch = conf.Service.init(buffer);

            if (nsswitch.find(db)) |entry| {
                var it = entry.iterateSources();

                while (it.next()) |name| {
                    if (Source.fromName(name)) |source| {
                        // TODO: handle directives like [NOTFOUND=return]
                        try sources.append(source);
                    }
                }
            }

            return .{
                .nss = nss,
                .sources = try sources.toOwnedSlice(),
            };
        }

        pub fn deinit(this: @This()) void {
            this.nss.allocator.free(this.sources);
        }

        pub fn find(this: @This(), key: []const u8) ?T {
            for (this.sources) |source| {
                const maybe_service = switch (db) {
                    .group => switch (source) {
                        .files => files.GroupService.init(this.nss),
                        else => null,
                    },
                    .passwd => switch (source) {
                        .files => files.PasswdService.init(this.nss),
                        else => null,
                    },
                };

                if (maybe_service) |service| {
                    return service.find(key);
                }
            }

            return null;
        }

        pub usingnamespace if (db == .group) group_impl else struct {};
        pub usingnamespace if (db == .passwd) passwd_impl else struct {};
    };
}

test "getent(.passwd, ...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "passwd: files\n");
    try testing.mockFile(&nss, "/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");

    if (nss.getent(.passwd, "root")) |entry| {
        try std.testing.expectEqualStrings("root", entry.login);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.uid);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("root", entry.info);
        try std.testing.expectEqualStrings("/root", entry.home);
        try std.testing.expectEqualStrings("/bin/bash", entry.shell);
    } else {
        return error.EntryNotFound;
    }
}

test "getent(.group, ...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "group: files\n");
    try testing.mockFile(&nss, "/etc/group", "root:x:0:\n");

    if (nss.getent(.group, "root")) |entry| {
        try std.testing.expectEqualStrings("root", entry.name);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("", entry.users);
    } else {
        return error.EntryNotFound;
    }
}

test "getgrgid(...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "group: files\n");
    try testing.mockFile(&nss, "/etc/group", "root:x:0:\n");

    if (nss.getgrgid(0)) |entry| {
        try std.testing.expectEqualStrings("root", entry.name);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("", entry.users);
    } else {
        return error.EntryNotFound;
    }
}

test "getgrnam(...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "group: files\n");
    try testing.mockFile(&nss, "/etc/group", "root:x:0:\n");

    if (nss.getgrnam("root")) |entry| {
        try std.testing.expectEqualStrings("root", entry.name);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("", entry.users);
    } else {
        return error.EntryNotFound;
    }
}

test "getpwnam(...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "passwd: files\n");
    try testing.mockFile(&nss, "/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");

    if (nss.getpwnam("root")) |entry| {
        try std.testing.expectEqualStrings("root", entry.login);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.uid);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("root", entry.info);
        try std.testing.expectEqualStrings("/root", entry.home);
        try std.testing.expectEqualStrings("/bin/bash", entry.shell);
    } else {
        return error.EntryNotFound;
    }
}

test "getpwuid(...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try testing.mockFile(&nss, "/etc/nsswitch.conf", "passwd: files\n");
    try testing.mockFile(&nss, "/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");

    if (nss.getpwuid(0)) |entry| {
        try std.testing.expectEqualStrings("root", entry.login);
        try std.testing.expectEqualStrings("x", entry.password);
        try std.testing.expectEqual(0, entry.uid);
        try std.testing.expectEqual(0, entry.gid);
        try std.testing.expectEqualStrings("root", entry.info);
        try std.testing.expectEqualStrings("/root", entry.home);
        try std.testing.expectEqualStrings("/bin/bash", entry.shell);
    } else {
        return error.EntryNotFound;
    }
}
