const std = @import("std");
const mem = std.mem;
const ts = @import("tree-sitter");
const model = @import("./model.zig");

/// Parse the earthfile source.
pub fn parse(allocator: mem.Allocator, source: []const u8, tree: *ts.Tree) !model.Module {
    var mod = model.Module.init(allocator);

    var root_node = tree.rootNode();
    for (0..root_node.childCount()) |idx| {
        if (root_node.child(@intCast(idx))) |node| {
            if (std.mem.eql(u8, node.kind(), "target")) {
                var name = node.childByFieldName("name").?;

                std.debug.print("Parse: {d}, {d}, {s}\n", .{ name.startByte(), name.endByte(), source[name.startByte()..name.endByte()] });
                try mod.functions.append(.{ .name = source[name.startByte()..name.endByte()] });
            }
        }
    }

    return mod;
}
