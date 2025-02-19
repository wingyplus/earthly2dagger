const std = @import("std");
const ts = @import("tree-sitter");
const Module = @import("../model.zig").Module;

pub fn generate(writer: anytype, module: Module) !void {
    _ = module;
    _ = try writer.writeAll("package main\n");
    _ = try writer.writeByte('\n');
}
