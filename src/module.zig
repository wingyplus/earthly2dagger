const std = @import("std");

const Earthfile = @import("./Earthfile.zig");
const strcase = @import("./strcase.zig");

const ModuleConfig = struct {
    name: []const u8,
    go_mod_name: []const u8,
};

pub fn generate(allocator: std.mem.Allocator, source_file: []const u8, writer: anytype, module_config: ModuleConfig) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var earthfile = Earthfile.init(arena, source_file);
    defer earthfile.deinit();
    try earthfile.parse();

    try generateModule(arena, writer, &earthfile, module_config);
}

test generate {
    const allocator = std.testing.allocator;

    try testGenerate(allocator, "simple");
    try testGenerate(allocator, "simple-multi-target");
    try testGenerate(allocator, "simple-args");
    try testGenerate(allocator, "expose-port");
    try testGenerate(allocator, "workdir");
    try testGenerate(allocator, "cmd");
    try testGenerate(allocator, "entrypoint");
}

fn testGenerate(allocator: std.mem.Allocator, comptime fixture: []const u8) !void {
    const dir = std.fs.cwd();
    try dir.makePath("tmp");

    const input = "fixtures/" ++ fixture ++ ".earth";
    const output = "fixtures/" ++ fixture ++ ".go";
    const tmp = "tmp/" ++ fixture ++ ".go";

    const source_file = try readAllAlloc(allocator, dir, input);
    defer allocator.free(source_file);

    const expected_module_source_file = try readAllAlloc(allocator, dir, output);
    defer allocator.free(expected_module_source_file);

    const out = try dir.createFile(tmp, .{ .read = false });
    defer out.close();

    try generate(allocator, source_file, out.writer(), .{ .name = "my-module", .go_mod_name = "dagger/my-module" });

    const formatted_source_file = try gofmt(allocator, tmp);
    defer allocator.free(formatted_source_file);
    try std.testing.expectEqualStrings(expected_module_source_file, formatted_source_file);
}

fn readAllAlloc(allocator: std.mem.Allocator, dir: std.fs.Dir, sub_path: []const u8) ![]u8 {
    const fixture = try dir.openFile(sub_path, .{ .mode = .read_only });
    defer fixture.close();
    return try fixture.readToEndAlloc(allocator, 3 * 1024 * 1024);
}

fn gofmt(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const run_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gofmt", path },
    });
    defer allocator.free(run_result.stderr);
    return run_result.stdout;
}

fn generateModule(allocator: std.mem.Allocator, writer: anytype, earthfile: *Earthfile, module_config: ModuleConfig) !void {
    const dagger_mod_name = module_config.name;
    const go_mod_name = module_config.go_mod_name;
    const struct_name = try strcase.toPascal(allocator, dagger_mod_name);

    _ = try writer.print(
        \\package main
        \\
        \\import "{s}/internal/dagger"
        \\
    , .{go_mod_name});
    _ = try writer.print("type {s}", .{struct_name});
    _ = try writer.write(
        \\ struct {
        \\  Container *dagger.Container
        \\}
        \\
    );
    _ = try writer.print(
        \\func New(
        \\  // +optional
        \\  container *dagger.Container,
        \\) *{s}
    , .{struct_name});
    _ = try writer.write(
        \\ {
        \\  if container == nil {
        \\    container = dag.Container()
        \\  }
        \\
    );
    _ = try writer.print(" return &{s}", .{struct_name});
    _ = try writer.write(
        \\{Container: container}
        \\}
        \\
        \\
    );
    //
    // Target rendering.
    //
    for (earthfile.targets.items) |fun| {
        const fn_name = try strcase.toPascal(allocator, fun.name);
        defer allocator.free(fn_name);

        _ = try writer.print("func (m *{s}) {s}(\n", .{ struct_name, fn_name });
        // Arguments rendering.
        for (fun.args.items) |arg| {
            const arg_name = try strcase.toCamel(allocator, arg.name);
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
                .expose => |port| {
                    _ = try writer.write(".\n");
                    _ = try writer.print("WithExposedPort({s})", .{port});
                },
                .workdir => |path| {
                    _ = try writer.write(".\n");
                    _ = try writer.print("WithWorkdir(\"{s}\")", .{path});
                },
                .cmd => |cmd| {
                    _ = try writer.write(".\n");
                    _ = try writer.write("WithDefaultArgs(");
                    switch (cmd) {
                        .shell => |sh| {
                            _ = try writer.write("[]string{\"sh\", \"-c\", ");
                            _ = try writer.print("`{s}`", .{sh});
                            _ = try writer.write("}");
                        },
                        .exec => |args| {
                            _ = try writer.write("[]string{");
                            _ = try writer.write(try std.mem.join(allocator, ",", args));
                            _ = try writer.write("}");
                        },
                    }
                    _ = try writer.write(")");
                },
                .entrypoint => |entrypoint| {
                    _ = try writer.write(".\n");
                    _ = try writer.write("WithEntrypoint(");
                    switch (entrypoint) {
                        .shell => |sh| {
                            _ = try writer.write("[]string{\"sh\", \"-c\", ");
                            _ = try writer.print("`{s}`", .{sh});
                            _ = try writer.write("}");
                        },
                        .exec => |args| {
                            _ = try writer.write("[]string{");
                            _ = try writer.write(try std.mem.join(allocator, ",", args));
                            _ = try writer.write("}");
                        },
                    }
                    _ = try writer.write(")");
                },
            }
        }
        _ = try writer.write("\n}\n\n");
    }
}
