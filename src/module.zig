const std = @import("std");
const ts = @import("tree-sitter");
const ts_earthfile = @import("tree-sitter-earthfile");
const earthfile = @import("./earthfile.zig");
const strcase = @import("./strcase.zig");

pub fn generate(allocator: std.mem.Allocator, source_file: []const u8, writer: anytype) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();

    var functions = std.ArrayList(earthfile.Target).init(arena_allocator.allocator());
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
            try functions.append(try earthfile.parseTarget(arena_allocator.allocator(), capture.node, source_file));
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

fn generateModule(allocator: std.mem.Allocator, writer: anytype, functions: std.ArrayList(earthfile.Target)) !void {
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
    // Target rendering.
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
