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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var functions = std.ArrayList(Function).init(allocator);

    const language = ts_earthfile.language();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const source_file =
        \\VERSION 0.7
        \\
        \\build:
        \\  ARG --required NAME
        \\  ARG TAG
        \\  RUN echo "Hello, World"
        \\
        \\test:
        \\  FROM alpine
    ;

    // Parse source file into tree.
    const tree = parser.parseString(source_file, null).?;
    defer tree.destroy();

    // !NOTE
    //
    // We need to looking into base `base_target` to construct a base container.

    // Write a query.
    var error_offset: u32 = 0;
    var query = try ts.Query.create(language, "(target) @target", &error_offset);
    defer query.destroy();

    // Querying...
    var query_cursor = ts.QueryCursor.create();
    defer query_cursor.destroy();

    query_cursor.exec(query, tree.rootNode());

    // Retrieve a result from query.
    while (query_cursor.nextMatch()) |match| {
        const captures = match.captures;
        for (captures) |capture| {
            try functions.append(try intoFunction(allocator, capture.node, source_file));
        }
    }

    // Has 2!
    std.debug.print("{any}\n", .{functions.items.len});

    // It's works!
    for (functions.items) |fun| {
        std.debug.print("{s}\n", .{fun.name});

        for (fun.args.items) |arg| {
            std.debug.print("- {s}\n", .{arg.name});
        }
    }

    // TODO: option.
    const source_code = try generateModule(allocator, functions);
    std.debug.print("{s}\n", source_code);
}

fn generateModule(allocator: std.mem.Allocator, functions: std.ArrayList(Function)) ![]u8 {
    var source_code = try std.fmt.allocPrint(allocator,
        \\package main
        \\
        \\type MyModule struct {s}
        \\
    , .{"{}"});
    for (functions.items) |fun| {
        source_code = try std.fmt.allocPrint(allocator,
            \\{s}
            \\func (m *MyModule) {s}(
        , .{ source_code, fun.name });
        for (fun.args.items) |arg| {
            std.debug.print("- {s}\n", .{arg.name});
        }
        source_code = try std.fmt.allocPrint(allocator,
            \\{s}) {s}
            \\{s}
            \\
        , .{ source_code, "{", "}" });
    }
    return source_code;
}

const Arg = struct {
    name: []const u8,
    required: bool,
};

// A function definition.
const Function = struct {
    const Self = @This();

    // A name of the target. Need to convert string case by the generator.
    name: []const u8,
    args: std.ArrayList(Arg),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .name = undefined, .args = std.ArrayList(Arg).init(allocator) };
    }
};

// Convert target node into Dagger function definition.
fn intoFunction(allocator: std.mem.Allocator, target_node: ts.Node, source_file: []const u8) !Function {
    var fun = Function.init(allocator);

    var name_node = target_node.childByFieldName("name").?;
    fun.name = source_file[name_node.startByte()..name_node.endByte()];

    // 0 is name node.
    // 1 is `:` node.
    var block_node = target_node.child(2).?;
    std.debug.print("{s}\n", .{block_node.toSexp()});
    for (0..block_node.childCount()) |child_index| {
        if (block_node.child(@intCast(child_index))) |stmt_node| {
            // ARG
            std.debug.print("{s}\n", .{stmt_node.kind()});
            if (std.mem.eql(u8, stmt_node.kind(), "arg_command")) {
                var var_node = stmt_node.childByFieldName("name").?;
                try fun.args.append(Arg{ .name = source_file[var_node.startByte()..var_node.endByte()], .required = false });
            }
        }
    }

    return fun;
}
