const std = @import("std");

// Returns a new string that convert the first letter to capital case.
pub fn pascalize(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) {
        return s;
    }

    var ns = try allocator.alloc(u8, s.len);
    std.mem.copyForwards(u8, ns, s);
    ns[0] = std.ascii.toUpper(s[0]);
    return ns;
}

test pascalize {
    const allocator = std.testing.allocator;
    var actual: []const u8 = undefined;
    actual = try pascalize(allocator, "test");
    try std.testing.expectEqualStrings("Test", actual);
    allocator.free(actual);
}

// Lower all characters in the string.
pub fn downcase(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return std.ascii.allocLowerString(allocator, s);
}

test downcase {
    const allocator = std.testing.allocator;
    var actual: []const u8 = undefined;
    actual = try downcase(allocator, "TEST");
    try std.testing.expectEqualStrings("test", actual);
    allocator.free(actual);
}
