const std = @import("std");

const separator = "-_";

pub fn toPascal(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var words = std.ArrayList([]const u8).init(arena);
    defer words.deinit();

    var iter = std.mem.tokenizeAny(u8, s, separator);
    while (iter.next()) |word| {
        var ns = try arena.alloc(u8, word.len);
        ns = std.ascii.lowerString(ns, word);
        ns[0] = std.ascii.toUpper(word[0]);
        try words.append(ns);
    }

    return std.mem.join(allocator, "", words.items);
}

test toPascal {
    const allocator = std.testing.allocator;
    try testToPascal(allocator, "test", "Test");
    try testToPascal(allocator, "myModule", "Mymodule");
    try testToPascal(allocator, "my-module", "MyModule");
    try testToPascal(allocator, "my-Module", "MyModule");
    try testToPascal(allocator, "MY_MODULE", "MyModule");
}

fn testToPascal(allocator: std.mem.Allocator, input: []const u8, expected: []const u8) !void {
    const word = try toPascal(allocator, input);
    defer allocator.free(word);
    try std.testing.expectEqualStrings(expected, word);
}

pub fn toCamel(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var words = std.ArrayList([]const u8).init(arena);
    defer words.deinit();

    var iter = std.mem.tokenizeAny(u8, s, separator);
    if (iter.next()) |first_word| {
        var ns = try arena.alloc(u8, first_word.len);
        ns = std.ascii.lowerString(ns, first_word);
        try words.append(ns);
    }
    while (iter.next()) |word| {
        try words.append(try toPascal(arena, word));
    }

    return std.mem.join(allocator, "", words.items);
}

test toCamel {
    const allocator = std.testing.allocator;
    try testToCamel(allocator, "Mymodule", "mymodule");
    try testToCamel(allocator, "MyModule", "mymodule");
    try testToCamel(allocator, "my-module", "myModule");
    try testToCamel(allocator, "my_module", "myModule");
    try testToCamel(allocator, "my_module-mod", "myModuleMod");
    try testToCamel(allocator, "MY_MODULE", "myModule");
}

fn testToCamel(allocator: std.mem.Allocator, input: []const u8, expected: []const u8) !void {
    const word = try toCamel(allocator, input);
    defer allocator.free(word);
    try std.testing.expectEqualStrings(expected, word);
}
