const std = @import("std");
const ts = @import("tree-sitter");

const strcase = @import("./strcase.zig");
const ts_earthfile = @import("tree-sitter-earthfile");
const ts_util = @import("./ts_util.zig");

const Earthfile = @This();

allocator: std.mem.Allocator,

// `Earthfile` source file.
source_file: []const u8,

// All the targets in `Earthfile`.
targets: std.ArrayList(Target),

pub const Arg = struct {
    name: []const u8,
    required: bool,
};

pub const ImageSpec = std.meta.Tuple(&.{ []const u8, ?[]const u8 });

// A tuple of key and value.
pub const Env = std.meta.Tuple(&.{ []const u8, []const u8 });

pub const ShellArg = union(enum) {
    shell: []const u8,
    exec: [][]const u8,
};

pub const Statement = union(enum) {
    // FROM <image>
    from: ImageSpec,
    // RUN <command>
    // TODO: support `--no-cache` option.
    run: []const u8,
    // ENV <key> <value>
    env: Env,
    // EXPOSE <port>
    expose: []const u8,
    // WORKDIR <path>
    workdir: []const u8,
    // CMD command arg1 arg2...
    // CMD ["command", "arg1", "arg2"...]
    cmd: ShellArg,
    // ENTRYPOINT command arg1 arg2...
    // ENTRYPOINT ["command", "arg1", "arg2"...]
    entrypoint: ShellArg,
};

// A target definition.
pub const Target = struct {
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

    pub fn addStatement(self: *Self, statement: Statement) !void {
        try self.statements.append(statement);
    }
};

pub fn init(allocator: std.mem.Allocator, source_file: []const u8) Earthfile {
    return .{
        .allocator = allocator,
        .source_file = source_file,
        .targets = std.ArrayList(Target).init(allocator),
    };
}

pub fn deinit(self: *Earthfile) void {
    self.targets.deinit();
}

pub fn parse(self: *Earthfile) !void {
    const language = ts_earthfile.language();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    // Parse source file into tree.
    const tree = parser.parseString(self.source_file, null).?;
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
            try self.targets.append(try self.parseTarget(capture.node));
        }
    }
}

// Convert target node into Dagger function definition.
pub fn parseTarget(self: *Earthfile, target_node: ts.Node) !Target {
    var fun = Target.init(self.allocator);

    const name_node = target_node.childByFieldName("name").?;
    fun.name = ts_util.content(name_node, self.source_file);

    // 0 is name node.
    // 1 is `:` node.
    var block_node = target_node.child(2).?;
    for (0..block_node.childCount()) |child_index| {
        if (block_node.child(@intCast(child_index))) |stmt_node| {
            if (std.mem.eql(u8, stmt_node.kind(), "arg_command")) {
                try self.parseArgStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "from_command")) {
                try self.parseFromStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "run_command")) {
                try self.parseRunStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "expose_command")) {
                try self.parseExposeStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "workdir_command")) {
                try self.parseWorkdirStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "cmd_command")) {
                try self.parseCmdStatement(&fun, stmt_node);
            }

            if (std.mem.eql(u8, stmt_node.kind(), "entrypoint_command")) {
                try self.parseEntrypointStatement(&fun, stmt_node);
            }
        }
    }

    return fun;
}

fn parseArgStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
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
    const env_name = ts_util.content(var_node, self.source_file);
    try fun.args.append(Arg{
        .name = env_name,
        .required = required,
    });
    try fun.statements.append(Statement{
        .env = .{ env_name, try strcase.toCamel(self.allocator, env_name) },
    });
}

fn parseFromStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    var image: []const u8 = "";
    var tag: ?[]const u8 = null;

    var image_node = stmt_node.child(1).?;
    if (std.mem.eql(u8, image_node.kind(), "string")) {
        image = ts_util.content(image_node, self.source_file);
    } else if (std.mem.eql(u8, image_node.kind(), "image_spec")) {
        const image_name_node = image_node.childByFieldName("name").?;
        const image_tag_node = image_node.childByFieldName("tag");

        image = ts_util.content(image_name_node, self.source_file);
        if (image_tag_node) |node| {
            tag = ts_util.content(node, self.source_file);
        }
    } else {
        unreachable;
    }

    try fun.statements.append(Statement{
        .from = .{ image, tag },
    });
}

fn parseRunStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    const shell_fragment_node = stmt_node.child(1).?;
    const sh = ts_util.content(shell_fragment_node, self.source_file);
    try fun.addStatement(Statement{
        .run = sh,
    });
}

fn parseExposeStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    const port_node = stmt_node.child(1).?;
    const port = ts_util.content(port_node, self.source_file);
    try fun.addStatement(Statement{
        .expose = port,
    });
}

fn parseWorkdirStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    const path_node = stmt_node.child(1).?;
    const path = ts_util.content(path_node, self.source_file);
    try fun.addStatement(Statement{
        .workdir = path,
    });
}

fn parseCmdStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    const node = stmt_node.child(1).?;
    if (std.mem.eql(u8, node.kind(), "shell_fragment")) {
        try fun.addStatement(Statement{ .cmd = ShellArg{ .shell = ts_util.content(node, self.source_file) } });
        return;
    }
    if (std.mem.eql(u8, node.kind(), "string_array")) {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        for (0..node.childCount()) |idx| {
            const s_node = node.child(@intCast(idx)).?;
            if (std.mem.eql(u8, s_node.kind(), "double_quoted_string")) {
                // `"` + <string> + `"`
                try args.append(ts_util.content(s_node, self.source_file));
            }
        }
        try fun.addStatement(Statement{ .cmd = ShellArg{ .exec = try args.toOwnedSlice() } });
        return;
    }
    // This line should not be reach here.
    unreachable;
}

fn parseEntrypointStatement(self: *Earthfile, fun: *Target, stmt_node: ts.Node) !void {
    const node = stmt_node.child(1).?;
    if (std.mem.eql(u8, node.kind(), "shell_fragment")) {
        try fun.addStatement(Statement{ .entrypoint = ShellArg{ .shell = ts_util.content(node, self.source_file) } });
        return;
    }
    if (std.mem.eql(u8, node.kind(), "string_array")) {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        for (0..node.childCount()) |idx| {
            const s_node = node.child(@intCast(idx)).?;
            if (std.mem.eql(u8, s_node.kind(), "double_quoted_string")) {
                // `"` + <string> + `"`
                try args.append(ts_util.content(s_node, self.source_file));
            }
        }
        try fun.addStatement(Statement{ .entrypoint = ShellArg{ .exec = try args.toOwnedSlice() } });
        return;
    }
    // This line should not be reach here.
    unreachable;
}
