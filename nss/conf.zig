const std = @import("std");
const nss = @import("../nss.zig");
const ltrim = @import("data/trim.zig").ltrim;
const rtrim = @import("data/trim.zig").rtrim;
const until = @import("data/trim.zig").until;
const DelimitedBufferIterator = @import("flatdb").DelimitedBufferIterator;
const mem = std.mem;
const meta = std.meta;

// TODO: test various corner cases in GNU implementation
// TODO:    - whitespace before db name
// TODO:    - db name alone without colon
// TODO:    - no space between db name and values
// TODO:    - whitespace before comments
// TODO:    - comments after records
// TODO:    - record+comment with no whitespace

pub const db_path = "/etc/nsswitch.conf";

const ws = &.{ ' ', '\t' }; // whitespace characters

pub const Service = struct {
    buffer: []const u8,

    pub fn init(buffer: []const u8) Service {
        return .{ .buffer = buffer };
    }

    pub fn find(this: Service, db: nss.Database) ?Entry {
        var it = Entry.Iterator.init(this.buffer);

        while (it.next()) |entry| {
            if (entry.database == db) return entry;
        }

        return null;
    }
};

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

                        if (meta.TagPayload(nss.Entry, tag) != void) {
                            break :tag tag;
                        }
                    }
                } else continue :records;

                return Entry{
                    .database = db,
                    .sources = ltrim(u8, record[@tagName(db).len + 1 ..], ws),
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

    fn trim(string: []const u8) []const u8 {
        return rtrim(u8, until(u8, ltrim(u8, string, ws), &.{'#'}), ws);
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
