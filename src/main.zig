const std = @import("std");
const module = @import("./root.zig").module;

const CliError = error{
    ArgumentError,
};

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    // TODO: use gpa allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next();
    const earthfile_path = args.next();

    if (earthfile_path == null) {
        _ = try stderr.write("ERROR: Earthfile argument is missing.\n");
        _ = try stderr.write("help:\n");
        _ = try stderr.write("\te2d [EARTHFILE]\n");
        return CliError.ArgumentError;
    }

    const earthfile = try std.fs.openFileAbsolute(earthfile_path.?, .{ .mode = .read_only });
    defer earthfile.close();

    const source_file = try earthfile.readToEndAlloc(allocator, 3 * 1024 * 1024);
    try module.generate(allocator, source_file, stdout.writer());
}

test {
    std.testing.refAllDecls(@This());
}
