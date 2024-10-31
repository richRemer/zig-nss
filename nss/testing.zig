const NSS = @import("../nss.zig").NSS;

/// Mock a file in the NSS object.
pub fn mockFile(nss: *NSS, path: []const u8, data: []const u8) !void {
    const allocator = nss.allocator;
    const key = try allocator.dupe(u8, path);
    errdefer allocator.free(key);

    const val = try allocator.dupe(u8, data);
    errdefer allocator.free(val);

    try nss.files.put(key, val);
}
