const std = @import("std");
const ts = @import("tree-sitter");
const ts_earthfile = @import("tree-sitter-earthfile");
const Parser = @import("./parser.zig");
const go = @import("./languages/go.zig");

// - Map a target into function.
//   - Map `ARG` into function argument.
//     - Map `--required` into required argument.
//     - Otherwise, optional.

pub fn main() !void {
    const language = ts_earthfile.language();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source =
        \\VERSION 0.7
        \\
        \\test:
        \\  ARG --required NAME
        \\  ARG TAG
        \\  RUN echo "Hello, World"
    ;
    _ = source; // autofix

    // const tree = parser.parseString(source, null);

    // var list = std.ArrayList(u8).init(std.heap.page_allocator);
    // defer list.deinit();
    //
    // if (parser.parseString(source, null)) |tree| {
    //     defer tree.destroy();
    //
    //     const module = try Parser.parse(std.heap.page_allocator, source, tree);
    //     std.debug.print("{any}", .{module.functions});
    //     // try go.generate(list.writer(), module);
    // }
    //
    // var stdout = std.io.getStdOut().writer();
    // try stdout.writeAll(list.items);
}
