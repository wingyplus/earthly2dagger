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

    var output = std.ArrayList(u8).init(allocator);
    const writer = output.writer();

    // TODO: option.
    try generateModule(allocator, writer, functions);
    var stdout_writer = std.io.getStdOut().writer();
    try stdout_writer.print("{s}\n", .{output.items});
}

fn generateModule(allocator: std.mem.Allocator, writer: anytype, functions: std.ArrayList(Function)) !void {
    _ = try writer.write(
        \\package main
        \\
        \\type MyModule struct {
        \\}
        \\
    );
    for (functions.items) |fun| {
        const name = try pascalize(allocator, fun.name);
        defer allocator.free(name);

        _ = try writer.print("func (m *MyModule) {s}(\n", .{name});
        for (fun.args.items) |arg| {
            const arg_name = try downcase(allocator, arg.name);
            defer allocator.free(name);
            if (!arg.required) {
                _ = try writer.write("// +optional\n");
            }
            _ = try writer.print("{s} string,\n", .{arg_name});
        }
        _ = try writer.write(")");
        _ = try writer.write("{");
        _ = try writer.write("}");
        _ = try writer.write("\n\n");
    }
}

// Returns a new string that convert the first letter to capital case.
fn pascalize(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) {
        return s;
    }

    var ns = try allocator.alloc(u8, s.len);
    std.mem.copyForwards(u8, ns, s);
    ns[0] = std.ascii.toUpper(s[0]);
    return ns;
}

// Lower all characters in the string.
fn downcase(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return std.ascii.allocLowerString(allocator, s);
}

test downcase {
    const allocator = std.testing.allocator;
    var actual: []const u8 = undefined;
    actual = try downcase(allocator, "TEST");
    try std.testing.expectEqualStrings("test", actual);
    allocator.free(actual);
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
    for (0..block_node.childCount()) |child_index| {
        if (block_node.child(@intCast(child_index))) |stmt_node| {
            // ARG
            if (std.mem.eql(u8, stmt_node.kind(), "arg_command")) {
                const var_node = stmt_node.childByFieldName("name").?;
                var required = false;
                const options_node = stmt_node.childByFieldName("options");
                if (options_node) |node| {
                    if (node.child(0)) |opt_node| {
                        if (std.mem.eql(u8, opt_node.kind(), "required")) {
                            required = true;
                        }
                    }
                }
                try fun.args.append(Arg{
                    .name = source_file[var_node.startByte()..var_node.endByte()],
                    .required = required,
                });
            }
        }
    }

    return fun;
}
