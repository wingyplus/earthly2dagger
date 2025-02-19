const std = @import("std");
const mem = std.mem;
const ts = @import("tree-sitter");

pub const Arg = struct {
    name: []const u8,
    type: []const u8,
    optional: bool,
    default: []const u8,
};

pub const Function = struct {
    name: []const u8,
    // args: std.ArrayList(Arg),
};

pub const Module = struct {
    const Self = @This();

    // constructor: Function,
    functions: std.ArrayList(Function),

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .functions = std.ArrayList(Function).init(allocator),
        };
    }
};
