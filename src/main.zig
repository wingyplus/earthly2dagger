const std = @import("std");
const ts = @import("tree-sitter");
const ts_earthfile = @import("tree-sitter-earthfile");
const Parser = @import("./parser.zig");
const go = @import("./languages/go.zig");
const ts_util = @import("./ts_util.zig");
const strcase = @import("./strcase.zig");

pub fn main() !void {
    const source_file =
        \\VERSION 0.7
        \\
        \\build:
        \\  ARG --required NAME
        \\  ARG TAG
        \\  FROM alpine
        \\  RUN echo "Hello, World ${NAME}"
        \\
        \\test:
        \\  FROM alpine
        \\
        \\dist:
        \\  FROM alpine:3.20
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut();
    try generate(allocator, source_file, stdout.writer());
}

fn generate(allocator: std.mem.Allocator, source_file: []const u8, writer: anytype) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();

    var functions = std.ArrayList(Function).init(arena_allocator.allocator());
    defer functions.deinit();

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
            try functions.append(try intoFunction(arena_allocator.allocator(), capture.node, source_file));
        }
    }

    try generateModule(arena_allocator.allocator(), writer, functions);
}

test generate {
    const source_file =
        \\VERSION 0.7
        \\
        \\build:
        \\  ARG --required NAME
        \\  ARG TAG
        \\  RUN echo "Hello, World ${TAG}"
        \\
        \\test:
        \\  FROM alpine
    ;

    const expected =
        \\package main
        \\
        \\import "dagger/my-module/internal/dagger"
        \\
        \\type MyModule struct {
        \\  Container *dagger.Container
        \\}
        \\
        \\func New(
        \\  // +optional
        \\  container *dagger.Container,
        \\) *MyModule {
        \\  if container == nil {
        \\    container = dag.Container()
        \\  }
        \\  return &MyModule{Container: container}
        \\}
        \\
        \\func (m *MyModule) Build(
        \\name string,
        \\// +optional
        \\tag string,
        \\) *dagger.Container {
        \\return m.Container.
        \\WithEnvVariable("NAME", name).
        \\WithEnvVariable("TAG", tag).
        \\WithExec([]string{"sh", "-c", `echo "Hello, World ${TAG}"`}, dagger.ContainerWithExecOpts{Expand: true})
        \\}
        \\
        \\func (m *MyModule) Test(
        \\) *dagger.Container {
        \\return m.Container.
        \\From("alpine")
        \\}
        \\
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
        \\import "dagger/my-module/internal/dagger"
        \\
        \\type MyModule struct {
        \\  Container *dagger.Container
        \\}
        \\
        \\func New(
        \\  // +optional
        \\  container *dagger.Container,
        \\) *MyModule {
        \\  if container == nil {
        \\    container = dag.Container()
        \\  }
        \\  return &MyModule{Container: container}
        \\}
        \\
        \\
    );
    //
    // Function rendering.
    //
    for (functions.items) |fun| {
        const name = try strcase.pascalize(allocator, fun.name);
        defer allocator.free(name);

        _ = try writer.print("func (m *MyModule) {s}(\n", .{name});
        // Arguments rendering.
        for (fun.args.items) |arg| {
            const arg_name = try strcase.downcase(allocator, arg.name);
            defer allocator.free(arg_name);
            if (!arg.required) {
                _ = try writer.write("// +optional\n");
            }
            _ = try writer.print("{s} string,\n", .{arg_name});
        }
        _ = try writer.write(")");
        if (fun.statements.items.len != 0) {
            _ = try writer.write(" *dagger.Container ");
        }
        _ = try writer.write("{\n");
        if (fun.statements.items.len != 0) {
            _ = try writer.write("return m.Container");
        }
        for (fun.statements.items) |stmt| {
            switch (stmt) {
                // Convert `FROM image_spec` to `From(addr)`.
                .from => |image_spec| {
                    const image, const tag = image_spec;
                    _ = try writer.write(".\n");
                    _ = try writer.write("From(\"");
                    _ = try writer.print("{s}", .{image});
                    if (tag) |t| {
                        _ = try writer.print(":{s}", .{t});
                    }
                    _ = try writer.write("\")");
                },
                .run => |sh| {
                    _ = try writer.write(".\n");
                    _ = try writer.write("WithExec([]string{\"sh\", \"-c\", ");
                    _ = try writer.print("`{s}`", .{sh});
                    _ = try writer.write("}, dagger.ContainerWithExecOpts{Expand: true})");
                },
                .env => |env| {
                    const env_name, const env_value = env;
                    _ = try writer.write(".\n");
                    _ = try writer.print("WithEnvVariable(\"{s}\", {s})", .{ env_name, env_value });
                },
            }
        }
        _ = try writer.write("\n}\n");
        _ = try writer.write("\n");
    }
}

//
// String manipulation.
//

//
// Module
//

const Arg = struct {
    name: []const u8,
    required: bool,
};

const ImageSpec = std.meta.Tuple(&.{ []const u8, ?[]const u8 });

// A tuple of key and value.
const Env = std.meta.Tuple(&.{ []const u8, []const u8 });

const Statement = union(enum) {
    // FROM <image>
    from: ImageSpec,
    // RUN <command>
    run: []const u8,
    // ENV <key> <value>
    env: Env,
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

    pub fn addStatement(self: *Function, statement: Statement) !void {
        try self.statements.append(statement);
    }
};

//
// Earthfile
//

// Convert target node into Dagger function definition.
fn intoFunction(allocator: std.mem.Allocator, target_node: ts.Node, source_file: []const u8) !Function {
    var fun = Function.init(allocator);

    const name_node = target_node.childByFieldName("name").?;
    fun.name = ts_util.content(name_node, source_file);

    // 0 is name node.
    // 1 is `:` node.
    var block_node = target_node.child(2).?;
    for (0..block_node.childCount()) |child_index| {
        if (block_node.child(@intCast(child_index))) |stmt_node| {
            // ARG name
            if (std.mem.eql(u8, stmt_node.kind(), "arg_command")) {
                try parseArgStatement(allocator, &fun, stmt_node, source_file);
            }

            // FROM image
            //
            // image = target | image_spec | string
            if (std.mem.eql(u8, stmt_node.kind(), "from_command")) {
                try parseFromStatement(&fun, stmt_node, source_file);
            }

            // RUN command ...
            if (std.mem.eql(u8, stmt_node.kind(), "run_command")) {
                try parseRunStatement(&fun, stmt_node, source_file);
            }
        }
    }

    return fun;
}

fn parseArgStatement(allocator: std.mem.Allocator, fun: *Function, stmt_node: ts.Node, source_file: []const u8) !void {
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
    const env_name = ts_util.content(var_node, source_file);
    try fun.args.append(Arg{
        .name = env_name,
        .required = required,
    });
    try fun.statements.append(Statement{
        .env = .{ env_name, try strcase.downcase(allocator, env_name) },
    });
}

fn parseFromStatement(fun: *Function, stmt_node: ts.Node, source_file: []const u8) !void {
    var image: []const u8 = "";
    var tag: ?[]const u8 = null;

    var image_node = stmt_node.child(1).?;
    if (std.mem.eql(u8, image_node.kind(), "string")) {
        image = ts_util.content(image_node, source_file);
    } else if (std.mem.eql(u8, image_node.kind(), "image_spec")) {
        const image_name_node = image_node.childByFieldName("name").?;
        const image_tag_node = image_node.childByFieldName("tag");

        image = ts_util.content(image_name_node, source_file);
        if (image_tag_node) |node| {
            tag = ts_util.content(node, source_file);
        }
    } else {
        unreachable;
    }

    try fun.statements.append(Statement{
        .from = .{ image, tag },
    });
}

fn parseRunStatement(fun: *Function, stmt_node: ts.Node, source_file: []const u8) !void {
    const shell_fragment_node = stmt_node.child(1).?;
    const sh = ts_util.content(shell_fragment_node, source_file);
    try fun.addStatement(Statement{
        .run = sh,
    });
}
