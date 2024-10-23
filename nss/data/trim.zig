const std = @import("std");

pub fn ltrim(comptime T: type, buffer: []const T, vals: []const T) []const T {
    const index = idx: for (buffer, 0..) |val, i| {
        for (vals) |v| if (val == v) continue :idx;
        break :idx i;
    } else buffer.len;

    return buffer[index..];
}

pub fn rtrim(comptime T: type, buffer: []const T, vals: []const T) []const T {
    var i = buffer.len;

    const index = idx: while (i > 0) {
        i -= 1;
        for (vals) |v| if (buffer[i] == v) continue :idx;
        break i + 1;
    } else 0;

    return buffer[0..index];
}

pub fn since(comptime T: type, buffer: []const T, vals: []const T) []const T {
    var i = buffer.len;

    while (i > 0) {
        i -= 1;
        for (vals) |v| if (buffer[i] == v) return buffer[i + 1 ..];
    }

    return buffer;
}

pub fn trim(comptime T: type, buffer: []const T, vals: []const T) []const T {
    return rtrim(u8, ltrim(u8, buffer, vals), vals);
}

pub fn until(comptime T: type, buffer: []const T, vals: []const T) []const T {
    for (buffer, 0..) |val, i| {
        for (vals) |v| if (val == v) return buffer[0..i];
    }

    return buffer;
}

test "trim variants" {
    const buffer = "xyfoo baryx";
    const left = ltrim(u8, buffer, &.{ 'x', 'y' });
    const right = rtrim(u8, buffer, &.{ 'x', 'y' });
    const both = trim(u8, buffer, &.{ 'x', 'y' });

    try std.testing.expectEqualStrings("foo baryx", left);
    try std.testing.expectEqualStrings("xyfoo bar", right);
    try std.testing.expectEqualStrings("foo bar", both);
}

test "trim variants resulting in empty string" {
    const buffer = "xyx";
    const left = ltrim(u8, buffer, &.{ 'x', 'y' });
    const right = rtrim(u8, buffer, &.{ 'x', 'y' });
    const both = trim(u8, buffer, &.{ 'x', 'y' });

    try std.testing.expectEqualStrings("", left);
    try std.testing.expectEqualStrings("", right);
    try std.testing.expectEqualStrings("", both);
}

test "trim until/since" {
    const buffer = "foo bar,baz";
    const until_comma = until(u8, buffer, &.{','});
    const until_f = until(u8, buffer, &.{ 'f', 'F' });
    const until_x = until(u8, buffer, &.{ 'x', 'X' });
    const since_comma = since(u8, buffer, &.{','});
    const since_z = since(u8, buffer, &.{ 'z', 'Z' });
    const since_x = since(u8, buffer, &.{ 'x', 'X' });

    try std.testing.expectEqualStrings("foo bar", until_comma);
    try std.testing.expectEqualStrings("", until_f);
    try std.testing.expectEqualStrings("foo bar,baz", until_x);
    try std.testing.expectEqualStrings("baz", since_comma);
    try std.testing.expectEqualStrings("", since_z);
    try std.testing.expectEqualStrings("foo bar,baz", since_x);
}
