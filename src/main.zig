const std = @import("std");
const module = @import("./root.zig").module;

pub fn main() !void {
    // TODO: read content from file.
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
    // TODO: use gpa allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut();
    try module.generate(allocator, source_file, stdout.writer());
}

test {
    std.testing.refAllDecls(@This());
}
