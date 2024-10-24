const std = @import("std");
const flatdb = @import("../deps/flatdb/flatdb.zig");
const passwd = @import("passwd.zig");
const NSS = @import("../nss.zig").NSS;
const mem = std.mem;
const fmt = std.fmt;
const DelimitedBufferIterator = flatdb.DelimitedBufferIterator;

/// Provide passwd service backed by /etc/passwd file.
pub const PasswdService = struct {
    nss: *NSS,

    pub fn init(nss: *NSS) PasswdService {
        return .{ .nss = nss };
    }

    /// Lookup passwd entry by username.
    /// TODO: support UID
    pub fn find(this: PasswdService, key: []const u8) ?passwd.Entry {
        const buffer = this.nss.open_file("/etc/passwd") catch return null;
        var it = PasswdIterator.init(buffer);

        while (it.next()) |entry| {
            if (mem.eql(u8, entry.login, key)) return entry;
        }

        return null;
    }
};

/// Iterate over entries in buffer read from /etc/passwd.
pub const PasswdIterator = struct {
    inner: LineIterator,

    pub fn init(buffer: []const u8) PasswdIterator {
        return .{ .inner = LineIterator.init(buffer) };
    }

    /// Return next entry.  Malformed entries are ignored.
    /// TODO: handle comments
    pub fn next(this: *PasswdIterator) ?passwd.Entry {
        while (this.inner.next()) |line| {
            var entry: passwd.Entry = undefined;
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

const LineIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{'\n'},
    .delimit_mode = .terminator,
    .collapse = true,
});

const FieldIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{':'},
    .delimit_mode = .separator,
});
