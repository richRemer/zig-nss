const DelimitedBufferIterator = @import("flatdb").DelimitedBufferIterator;

/// Entry for group database.
pub const Entry = struct {
    name: []const u8,
    password: []const u8,
    gid: u32,
    users: []const u8,

    pub fn iterateUsers(this: Entry) UsersIterator {
        return UsersIterator.init(this.users);
    }
};

/// Iterate over comma-separated group users.
pub const UsersIterator = DelimitedBufferIterator(u8, .{
    .delims = &.{','},
    .delimit_mode = .separator,
});
