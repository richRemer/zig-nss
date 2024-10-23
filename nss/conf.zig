const std = @import("std");
const flatdb = @import("../deps/flatdb/flatdb.zig");
const nss = @import("../nss.zig");
const trim = @import("data/trim.zig");
const mem = std.mem;
const meta = std.meta;
const DelimitedBufferIterator = flatdb.DelimitedBufferIterator;
const DelimitedBufferOptions = flatdb.DelimitedBufferOptions;

// TODO: test various corner cases in GNU implementation
// TODO:    - whitespace before db name
// TODO:    - db name alone without colon
// TODO:    - no space between db name and values
// TODO:    - whitespace before comments
// TODO:    - comments after records
// TODO:    - record+comment with no whitespace

pub const db_path = "/etc/nsswitch.conf";

pub const Entry = struct {
    database: nss.Database,
    sources: []const u8,

    pub const Iterator = struct {
        inner: RecordIterator,

        pub fn init(buffer: []const u8) Iterator {
            return .{ .inner = RecordIterator.init(buffer) };
        }

        pub fn next(this: *Iterator) ?Entry {
            records: while (this.inner.next()) |record| {
                const fields = @typeInfo(nss.Database).@"enum".fields;
                const db: nss.Database = tag: inline for (fields) |field| {
                    if (mem.startsWith(u8, record, field.name ++ ":")) {
                        const tag: nss.Database = @enumFromInt(field.value);

                        if (meta.TagPayload(nss.DatabaseEntry, tag) != void) {
                            break :tag tag;
                        }
                    }
                } else continue :records;

                return Entry{
                    .database = db,
                    .sources = trimLead(record[@tagName(db).len + 1 ..]),
                };
            }

            return null;
        }
    };

    pub fn iterateSources(this: Entry) SourceIterator {
        return SourceIterator.init(this.sources);
    }
};

const RecordIterator = struct {
    inner: LineIterator,

    pub fn init(buffer: []const u8) RecordIterator {
        return .{ .inner = LineIterator.init(buffer) };
    }

    pub fn next(this: *RecordIterator) ?[]const u8 {
        while (this.inner.next()) |line| {
            const data = RecordIterator.trim(line);
            if (data.len > 0) return data;
        }

        return null;
    }

    fn trim(line: []const u8) []const u8 {
        var trimmed = line;

        trimmed = trimLead(trimmed); // scan to non-WS
        trimmed = trimComment(trimmed); // scan to comment/end
        trimmed = trimTail(trimmed); // scan back to final non-WS

        return trimmed;
    }
};

const LineIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{'\n'},
    .delimit_mode = .terminator,
    .collapse = true,
});

const SourceIterator = DelimitedBufferIterator(u8, .{
    .delims = ws,
    .delimit_mode = .terminator,
    .collapse = true,
});

const ws = &.{ ' ', '\t' };

inline fn trimLead(buffer: []const u8) []const u8 {
    return trim.ltrim(u8, buffer, ws);
}

inline fn trimTail(buffer: []const u8) []const u8 {
    return trim.rtrim(u8, buffer, ws);
}

inline fn trimComment(buffer: []const u8) []const u8 {
    return trim.until(u8, buffer, &.{'#'});
}

test "read nsswitch.conf" {
    const buffer =
        \\# /etc/nsswitch.conf
        \\#
        \\# Example configuration of GNU Name Service Switch functionality.
        \\# If you have the `glibc-doc-reference' and `info' packages installed, try:
        \\# `info libc "Name Service Switch"' for information about this file.
        \\
        \\passwd:         files systemd
        \\group:          files systemd
        \\shadow:         files
        \\gshadow:        files
        \\
        \\hosts:          files mdns4_minimal [NOTFOUND=return] dns
        \\networks:       files
        \\
        \\protocols:      db files
        \\services:       db files
        \\ethers:         db files
        \\rpc:            db files
        \\
        \\netgroup:       nis
        \\
    ;

    var it = Entry.Iterator.init(buffer);
    const maybe_entry = it.next();

    try std.testing.expect(null != maybe_entry);
    try std.testing.expectEqual(nss.Database.passwd, maybe_entry.?.database);
    try std.testing.expectEqualStrings("files systemd", maybe_entry.?.sources);
    try std.testing.expectEqual(null, it.next());

    var sources_it = maybe_entry.?.iterateSources();

    try std.testing.expectEqualStrings("files", sources_it.next().?);
    try std.testing.expectEqualStrings("systemd", sources_it.next().?);
    try std.testing.expectEqual(null, sources_it.next());
}