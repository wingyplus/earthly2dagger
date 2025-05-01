const builtin = @import("builtin");
const std = @import("std");
const module = @import("./root.zig").module;

const CliError = error{
    ArgumentError,
};

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    var da = std.heap.DebugAllocator(.{}){};
    defer {
        if (da.deinit() == .leak) {
            @panic("Found memory leak!!");
        }
    }

    var allocator: std.mem.Allocator = undefined;
    if (builtin.mode == std.builtin.OptimizeMode.Debug) {
        allocator = da.allocator();
    } else {
        allocator = std.heap.page_allocator;
    }

    var args = std.process.args();
    _ = args.next();
    const earthfile_path = args.next();
    // TODO: validate arguments below
    const dagger_mod_name = args.next().?;
    const go_mod_name = args.next().?;

    if (earthfile_path == null) {
        _ = try stderr.write("ERROR: Earthfile argument is missing.\n");
        _ = try stderr.write("help:\n");
        _ = try stderr.write("\te2d [EARTHFILE] [DAGGER_MOD_NAME] [GO_MOD_NAME]\n");
        return CliError.ArgumentError;
    }

    const earthfile = try std.fs.openFileAbsolute(earthfile_path.?, .{ .mode = .read_only });
    defer earthfile.close();

    const meta = try earthfile.metadata();
    const source_file = try earthfile.readToEndAlloc(allocator, meta.size());
    defer allocator.free(source_file);
    try module.generate(allocator, source_file, stdout.writer(), .{ .name = dagger_mod_name, .go_mod_name = go_mod_name });
}

test {
    std.testing.refAllDecls(@This());
}
