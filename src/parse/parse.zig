//! Parse entry. Ported from lute/parse/parse.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const types = @import("../types.zig");
const node = @import("../ast/node.zig");
const tree = @import("tree.zig");

pub const Tree = tree.Tree;
pub const Context = tree.Context;

pub fn parse(allocator: std.mem.Allocator, markdown: []const u8, options: types.Options) !*Tree {
    // The lexer mutates input (CRLF, NUL); give it an arena copy with a trailing LF.
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    try buf.appendSlice(allocator, markdown);
    if (buf.items.len > 0 and buf.items[buf.items.len - 1] != '\n') try buf.append(allocator, '\n');
    const t = try allocator.create(Tree);
    try t.init(allocator, try buf.toOwnedSlice(allocator), options);
    try t.parseBlocks();
    try @import("inline.zig").parseInlines(t);
    return t;
}

test "parse empty document" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = try parse(a, "", .{});
    try std.testing.expectEqual(types.NodeType.document, t.root.typ);
    try std.testing.expect(t.root.first_child == null);
}

test "parse paragraph/heading/list blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = try parse(a, "# hi\n\npara\n\n- a\n- b\n", .{});
    var types_seen: std.ArrayListUnmanaged(types.NodeType) = .empty;
    var c = t.root.first_child;
    while (c) |n| : (c = n.next) try types_seen.append(a, n.typ);
    try std.testing.expectEqualSlices(types.NodeType, &.{ .heading, .paragraph, .list }, types_seen.items);
}
