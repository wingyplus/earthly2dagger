const ts = @import("tree-sitter");

/// Get the content of node from source file.
pub fn content(node: ts.Node, source_file: []const u8) []const u8 {
    return source_file[node.startByte()..node.endByte()];
}
