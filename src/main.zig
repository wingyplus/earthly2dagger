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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut();
    try generate(allocator, source_file, stdout.writer());
}

fn generate(allocator: std.mem.Allocator, source_file: []const u8, writer: anytype) !void {
    var functions = std.ArrayList(Function).init(allocator);

    const language = ts_earthfile.language();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

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

    try generateModule(allocator, writer, functions);
}

test generate {
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

    const expected =
        \\package main
        \\
        \\import "dagger/mod/internal/dagger"
        \\
        \\type MyModule struct {
        \\        Container *dagger.Container
        \\}
        \\
        \\func New(
        \\        // +optional
        \\        container *dagger.Container,
        \\) *MyModule {
        \\        return &MyModule{Container: container}
        \\}
        \\func (m *MyModule) Build(
        \\        name string,
        \\        // +optional
        \\        tag string,
        \\) {
        \\}
        \\
        \\func (m *MyModule) Test() {
        \\}
        \\
    ;

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try generate(std.testing.allocator, source_file, out.writer());
    try std.testing.expectEqualStrings(expected, out.items);
}

//
// Generator (go)
//

fn generateModule(allocator: std.mem.Allocator, writer: anytype, functions: std.ArrayList(Function)) !void {
    _ = try writer.write(
        \\package main
        \\
        \\import "dagger/mod/internal/dagger"
        \\
        \\type MyModule struct {
        \\  Container *dagger.Container
        \\}
        \\
        \\func New(
        \\  // +optional
        \\  container *dagger.Container,
        \\) *MyModule {
        \\  return &MyModule{Container: container}
        \\}
        \\
    );
    //
    // Function rendering.
    //
    for (functions.items) |fun| {
        const name = try pascalize(allocator, fun.name);
        defer allocator.free(name);

        _ = try writer.print("func (m *MyModule) {s}(\n", .{name});
        // Arguments rendering.
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

//
// String manipulation.
//

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

//
// Module
//

const Arg = struct {
    name: []const u8,
    required: bool,
};

const Statement = union(enum) {
    // FROM <image>
    from: []const u8,
};

// A function definition.
const Function = struct {
    const Self = @This();

    // A name of the target. Need to convert string case by the generator.
    name: []const u8,
    args: std.ArrayList(Arg),
    statements: std.ArrayList(Statement),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .name = undefined,
            .args = std.ArrayList(Arg).init(allocator),
            .statements = std.ArrayList(Statement).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.args.deinit();
        self.statements.deinit();
    }
};

//
// Earthfile
//

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

            // FROM image | location
            if (std.mem.eql(u8, stmt_node.kind(), "from_command")) {
                var from_node = stmt_node.child(0);
                var addr = from_node.?.child(0).?.childByFieldName("name").?;

                // TODO: use name from `from` node.
                try fun.statements.append(Statement{ .from = source_file[addr.startByte()..addr.endByte()] });
            }
        }
    }

    return fun;
}
