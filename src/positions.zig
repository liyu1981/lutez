//! Source-position tests and invariants (wire v2 spans).
const std = @import("std");
const lutez = @import("lutez.zig");
const node_mod = @import("ast/node.zig");
const source = @import("source.zig");

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), comptime fmt: []const u8, args: anytype) !void {
    var buf: [512]u8 = undefined;
    try out.appendSlice(allocator, try std.fmt.bufPrint(&buf, fmt, args));
}

fn dumpNode(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), n: *node_mod.Node, depth: usize, input: []const u8, map: source.SourceMap) !void {
    const raw_start = if (n.hasSpan()) map.normToRawStart(n.src_start) else 0;
    const raw_end = if (n.hasSpan()) map.normToRawEnd(n.src_end) else 0;
    const slice = if (n.hasSpan() and raw_end <= input.len and raw_start <= raw_end) input[raw_start..raw_end] else "";
    const kind = if (n.src_derived) "derived" else "span";
    const shown = slice[0..@min(slice.len, 120)];
    var d: usize = 0;
    while (d < depth) : (d += 1) try out.appendSlice(allocator, "  ");
    try appendFmt(allocator, out, "{s: <34} {s} raw=[{},{}] norm=[{},{}] {s}\n", .{
        @tagName(n.typ), kind, raw_start, raw_end, n.src_start, n.src_end, shown,
    });
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) try dumpNode(allocator, out, ch, depth + 1, input, map);
}

pub fn dumpSpans(allocator: std.mem.Allocator, doc: *const lutez.Doc) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try dumpNode(allocator, &out, doc.root, 0, doc.input, doc.source_map);
    return out.toOwnedSlice(allocator);
}

const Check = struct {
    missing: usize = 0,
    bad_range: usize = 0,
    not_contained: usize = 0,
    sibling_order: usize = 0,
    first_bad: ?[]const u8 = null,
    first_type: ?[]const u8 = null,
    first_parent: ?[]const u8 = null,
};

fn checkTree(n: *node_mod.Node, parent: ?*node_mod.Node, norm_len: u32, c: *Check, path: []const u8) void {
    if (!n.hasSpan()) {
        c.missing += 1;
        if (c.first_bad == null) {
            c.first_bad = path;
            c.first_type = @tagName(n.typ);
            c.first_parent = if (parent) |p| @tagName(p.typ) else null;
        }
    } else {
        if (n.src_start > n.src_end or n.src_end > norm_len) {
            c.bad_range += 1;
            if (c.first_bad == null) c.first_bad = path;
        }
        if (parent) |p| {
            if (p.hasSpan() and (n.src_start < p.src_start or n.src_end > p.src_end)) {
                c.not_contained += 1;
                if (c.first_bad == null) {
                    c.first_bad = path;
                    c.first_type = @tagName(n.typ);
                    c.first_parent = @tagName(p.typ);
                }
            }
        }
    }
    var prev: ?*node_mod.Node = null;
    var ch = n.first_child;
    while (ch) |x| : (ch = x.next) {
        if (prev) |p| {
            if (p.hasSpan() and x.hasSpan() and x.src_start < p.src_start) {
                c.sibling_order += 1;
                if (c.first_bad == null) {
                    c.first_bad = path;
                    c.first_type = @tagName(x.typ);
                    c.first_parent = @tagName(n.typ);
                }
            }
        }
        prev = x;
        checkTree(x, n, norm_len, c, path);
    }
}

test "span invariants on both corpora" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    for ([_][]const u8{ "test/corpus/spec.lzc", "test/corpus/gfm.lzc" }) |path| {
        const corpus = try std.Io.Dir.cwd().readFileAlloc(io, path, std.testing.allocator, .limited(64 * 1024 * 1024));
        defer std.testing.allocator.free(corpus);
        var off: usize = 8;
        const count = std.mem.readInt(u32, corpus[4..8], .little);
        var i: u32 = 0;
        var failures: usize = 0;
        while (i < count) : (i += 1) {
            const nlen = std.mem.readInt(u32, corpus[off..][0..4], .little);
            off += 4;
            const case_name = corpus[off .. off + nlen];
            off += nlen;
            const md_len = std.mem.readInt(u32, corpus[off..][0..4], .little);
            off += 4;
            const md = corpus[off .. off + md_len];
            off += md_len;
            const ast_len = std.mem.readInt(u32, corpus[off..][0..4], .little);
            off += 4 + ast_len;

            var doc = try lutez.parse(md, .{});
            defer doc.deinit();
            var c = Check{};
            checkTree(doc.root, null, @intCast(doc.input.len), &c, md[0..@min(md.len, 40)]);
            if (c.missing + c.bad_range + c.not_contained + c.sibling_order > 0) {
                failures += 1;
                if (failures <= 5) {
                    std.debug.print("span issue in {s} {s}: missing={d} bad={d} outside={d} order={d} type={?s} parent={?s} md={s}\n", .{
                        path, case_name, c.missing, c.bad_range, c.not_contained, c.sibling_order, c.first_type, c.first_parent, md,
                    });
                }
            }
        }
        try std.testing.expectEqual(@as(usize, 0), failures);
    }
}

fn findFirst(n: *node_mod.Node, typ: @import("types.zig").NodeType) ?*node_mod.Node {
    if (n.typ == typ) return n;
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) if (findFirst(ch, typ)) |hit| return hit;
    return null;
}

fn allNodes(allocator: std.mem.Allocator, n: *node_mod.Node, out: *std.ArrayListUnmanaged(*node_mod.Node)) !void {
    try out.append(allocator, n);
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) try allNodes(allocator, ch, out);
}

test "golden spans for representative markdown" {
    const md = "# hi\n\npara *em*\n\n- [x] b\n\n```zig\ncode\n```\n";
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    const root = doc.root;
    try std.testing.expectEqual(@as(u32, 0), root.src_start);
    try std.testing.expectEqual(@as(u32, @intCast(doc.input.len)), root.src_end);

    const heading = findFirst(root, .heading).?;
    try std.testing.expectEqual(@as(u32, 0), heading.src_start);
    try std.testing.expectEqual(@as(u32, 4), heading.src_end);
    const marker = findFirst(heading, .heading_c8h_marker).?;
    try std.testing.expectEqual(@as(u32, 0), marker.src_start);
    try std.testing.expectEqual(@as(u32, 1), marker.src_end);
    const htext = findFirst(heading, .text).?;
    try std.testing.expectEqual(@as(u32, 2), htext.src_start);
    try std.testing.expectEqual(@as(u32, 4), htext.src_end);

    const para = findFirst(root, .paragraph).?;
    try std.testing.expectEqual(@as(u32, 6), para.src_start);
    try std.testing.expectEqual(@as(u32, 15), para.src_end);

    const task = findFirst(root, .task_list_item_marker).?;
    try std.testing.expectEqualStrings("[x]", doc.input[task.src_start..task.src_end]);

    const code = findFirst(root, .code_block).?;
    const code_content = findFirst(code, .code_block_code).?;
    try std.testing.expectEqualStrings("code", doc.input[code_content.src_start..code_content.src_end]);
}

test "CRLF and NUL spans map back to raw bytes" {
    const md = "x\r\n\r\ny\x00z\n";
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    var nodes: std.ArrayListUnmanaged(*node_mod.Node) = .empty;
    defer nodes.deinit(std.testing.allocator);
    try allNodes(std.testing.allocator, doc.root, &nodes);
    var saw_nul = false;
    for (nodes.items) |n| {
        if (!n.hasSpan()) continue;
        const rs = doc.source_map.normToRawStart(n.src_start);
        const re = doc.source_map.normToRawEnd(n.src_end);
        try std.testing.expect(rs <= re and re <= md.len);
        const text = md[rs..re];
        if (n.typ == .text and std.mem.eql(u8, n.tokens, "y\u{FFFD}z")) {
            saw_nul = true;
            try std.testing.expectEqualStrings("y\x00z", text);
        }
    }
    try std.testing.expect(saw_nul);
}

test "wire v2 roundtrip preserves spans" {
    const md = "# hi *em*\n\n| a | b |\n|---|---|\n| c | d |\n\n- [x] task\n\n> quote\n";
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    var before: std.ArrayListUnmanaged(*node_mod.Node) = .empty;
    defer before.deinit(std.testing.allocator);
    try allNodes(std.testing.allocator, doc.root, &before);

    const wire = try @import("ast/wire.zig").encode(std.testing.allocator, doc.root, &.{}, doc.source_map);
    defer std.testing.allocator.free(wire);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root2 = try @import("ast/wire.zig").decode(arena.allocator(), wire);
    var after: std.ArrayListUnmanaged(*node_mod.Node) = .empty;
    defer after.deinit(std.testing.allocator);
    try allNodes(std.testing.allocator, root2, &after);
    try std.testing.expectEqual(before.items.len, after.items.len);
    for (before.items, after.items) |a, b| {
        try std.testing.expectEqual(a.typ, b.typ);
        try std.testing.expectEqual(a.src_start, b.src_start);
        try std.testing.expectEqual(a.src_end, b.src_end);
        try std.testing.expectEqual(a.src_derived, b.src_derived);
    }
}
