const std = @import("std");
const flatdb = @import("../deps/flatdb/flatdb.zig");
const group = @import("group.zig");
const passwd = @import("passwd.zig");
const NSS = @import("../nss.zig").NSS;
const mem = std.mem;
const fmt = std.fmt;
const CutBufferIterator = flatdb.CutBufferIterator;
const DelimitedBufferIterator = flatdb.DelimitedBufferIterator;
const FilterBufferIterator = flatdb.FilterBufferIterator;
const TrimBufferIterator = flatdb.TrimBufferIterator;

/// Provide group service backed by /etc/group file.
pub const GroupService = struct {
    nss: *NSS,

    pub fn init(nss: *NSS) GroupService {
        return .{ .nss = nss };
    }

    /// Lookup group entry by name or GID.
    pub fn find(this: GroupService, key: []const u8) ?group.Entry {
        const buffer = this.nss.open_file("/etc/group") catch return null;
        const gid = fmt.parseInt(u32, key, 10) catch null;
        var it = GroupIterator.init(buffer);

        while (it.next()) |entry| {
            if (mem.eql(u8, entry.name, key)) return entry;
            if (gid) |id| if (entry.gid == id) return entry;
        }

        return null;
    }

    /// Lookup group entry by GID.
    pub fn findGid(this: GroupService, gid: u32) ?group.Entry {
        const buffer = this.nss.open_file("/etc/group") catch return null;
        var it = GroupIterator.init(buffer);

        while (it.next()) |entry| {
            if (entry.gid == gid) return entry;
        }

        return null;
    }

    /// Lookup group entry by name.
    pub fn findName(this: GroupService, name: []const u8) ?group.Entry {
        const buffer = this.nss.open_file("/etc/group") catch return null;
        var it = GroupIterator.init(buffer);

        while (it.next()) |entry| {
            if (mem.eql(u8, entry.name, name)) return entry;
        }

        return null;
    }
};

/// Iterate over entries in buffer read from /etc/group.
pub const GroupIterator = struct {
    inner: RecordIterator,

    pub fn init(buffer: []const u8) GroupIterator {
        return .{ .inner = RecordIterator.init(buffer) };
    }

    /// Return next entry.  Malformed entries are ignored.
    pub fn next(this: *GroupIterator) ?group.Entry {
        while (this.inner.next()) |line| {
            var entry: group.Entry = undefined;
            var field_it = FieldIterator.init(line);

            entry.name = field_it.next() orelse continue;
            entry.password = field_it.next() orelse continue;
            const gid = field_it.next() orelse continue;
            entry.users = field_it.next() orelse continue;

            if (field_it.next() != null) continue;

            entry.gid = fmt.parseInt(u32, gid, 10) catch continue;

            return entry;
        }

        return null;
    }
};

/// Provide passwd service backed by /etc/passwd file.
pub const PasswdService = struct {
    nss: *NSS,

    pub fn init(nss: *NSS) PasswdService {
        return .{ .nss = nss };
    }

    /// Lookup passwd entry by login or UID.
    pub fn find(this: PasswdService, key: []const u8) ?passwd.Entry {
        const buffer = this.nss.open_file("/etc/passwd") catch return null;
        const uid = fmt.parseInt(u32, key, 10) catch null;
        var it = PasswdIterator.init(buffer);

        while (it.next()) |entry| {
            if (mem.eql(u8, entry.login, key)) return entry;
            if (uid) |id| if (entry.uid == id) return entry;
        }

        return null;
    }

    /// Lookup passwd entry by login.
    pub fn findLogin(this: PasswdService, login: []const u8) ?passwd.Entry {
        const buffer = this.nss.open_file("/etc/passwd") catch return null;
        var it = PasswdIterator.init(buffer);

        while (it.next()) |entry| {
            if (mem.eql(u8, entry.login, login)) return entry;
        }

        return null;
    }

    /// Lookup group entry by UID.
    pub fn findUid(this: PasswdService, uid: u32) ?passwd.Entry {
        const buffer = this.nss.open_file("/etc/passwd") catch return null;
        var it = PasswdIterator.init(buffer);

        while (it.next()) |entry| {
            if (entry.uid == uid) return entry;
        }

        return null;
    }
};

/// Iterate over entries in buffer read from /etc/passwd.
pub const PasswdIterator = struct {
    inner: RecordIterator,

    pub fn init(buffer: []const u8) PasswdIterator {
        return .{ .inner = RecordIterator.init(buffer) };
    }

    /// Return next entry.  Malformed entries are ignored.
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

const RecordIterator = FilterBufferIterator(
    TrimBufferIterator(CutBufferIterator(DelimitedBufferIterator(u8, .{
        .delims = &.{'\n'},
        .delimit_mode = .terminator,
        .collapse = true,
    }), u8, .{
        .delims = &.{'#'},
        .cut_mode = .after,
        .scan_mode = .start,
        .include_delim = true,
    }), u8, .{
        .trim = &.{ ' ', '\t' },
    }),
    u8,
    non_empty,
);

const FieldIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{':'},
    .delimit_mode = .separator,
});

fn non_empty(buffer: []const u8) bool {
    return buffer.len > 0;
}
