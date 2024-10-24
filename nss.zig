const std = @import("std");
const flatdb = @import("deps/flatdb/flatdb.zig");
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const meta = std.meta;
const fmt = std.fmt;
const fs = std.fs;
const TagPayload = meta.TagPayload;

pub const conf = @import("nss/conf.zig");
pub const passwd = @import("nss/passwd.zig");
pub const files = @import("nss/files.zig");

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
    passwd_files: files.PasswdService,

    pub fn tagFor(
        db: Database,
        source: Source,
    ) ?@typeInfo(DatabaseSource).@"union".tag_type.? {
        const db_name = @tagName(db);
        const source_name = @tagName(source);
        const Tag = @typeInfo(DatabaseSource).@"union".tag_type.?;
        const fields = @typeInfo(Tag).@"enum".fields;

        inline for (fields) |field| {
            if (field.name.len == db_name.len + 1 + source_name.len) {
                if (mem.startsWith(u8, field.name, db_name)) {
                    if (mem.endsWith(u8, field.name, source_name)) {
                        return @enumFromInt(field.value);
                    }
                }
            }
        }

        return null;
    }
};

/// Generic database entry.  Union of all database entry types.
pub const Entry = union(Database) {
    group: void, // TODO
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
                if (DatabaseSource.tagFor(db, source)) |db_source| {
                    const SourceService = svc: switch (db_source) {
                        .passwd_files => break :svc files.PasswdService,
                    };

                    return SourceService.init(this.nss).find(key);
                }
            }

            return null;
        }
    };
}

test "getent(.passwd, ...)" {
    const allocator = std.testing.allocator;
    var nss = NSS.open(allocator);
    defer nss.close();

    try mock_file(&nss, "/etc/nsswitch.conf", "passwd: files\n");
    try mock_file(&nss, "/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");

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

fn mock_file(nss: *NSS, path: []const u8, data: []const u8) !void {
    const allocator = nss.allocator;
    const key = try allocator.dupe(u8, path);
    errdefer allocator.free(key);

    const val = try allocator.dupe(u8, data);
    errdefer allocator.free(val);

    try nss.files.put(key, val);
}
