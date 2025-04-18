const std = @import("std");
const ts = @import("tree-sitter");
const ts_util = @import("./ts_util.zig");
const strcase = @import("./strcase.zig");

pub const Arg = struct {
    name: []const u8,
    required: bool,
};

pub const ImageSpec = std.meta.Tuple(&.{ []const u8, ?[]const u8 });

// A tuple of key and value.
pub const Env = std.meta.Tuple(&.{ []const u8, []const u8 });

pub const Statement = union(enum) {
    // FROM <image>
    from: ImageSpec,
    // RUN <command>
    run: []const u8,
    // ENV <key> <value>
    env: Env,
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

    pub fn addStatement(self: *Target, statement: Statement) !void {
        try self.statements.append(statement);
    }
};

// Convert target node into Dagger function definition.
pub fn parseTarget(allocator: std.mem.Allocator, target_node: ts.Node, source_file: []const u8) !Target {
    var fun = Target.init(allocator);

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

fn parseArgStatement(allocator: std.mem.Allocator, fun: *Target, stmt_node: ts.Node, source_file: []const u8) !void {
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
        .env = .{ env_name, try strcase.toCamel(allocator, env_name) },
    });
}

fn parseFromStatement(fun: *Target, stmt_node: ts.Node, source_file: []const u8) !void {
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

fn parseRunStatement(fun: *Target, stmt_node: ts.Node, source_file: []const u8) !void {
    const shell_fragment_node = stmt_node.child(1).?;
    const sh = ts_util.content(shell_fragment_node, source_file);
    try fun.addStatement(Statement{
        .run = sh,
    });
}
