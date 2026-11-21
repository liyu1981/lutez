//! Extension preset tests (frontmatter, math, wikilinks, tags, outliner blocks).
const std = @import("std");
const lutez = @import("lutez.zig");
const node = @import("ast/node.zig");
const types = @import("types.zig");

fn walkCollect(allocator: std.mem.Allocator, n: *node.Node, out: *std.ArrayListUnmanaged(*node.Node)) !void {
    try out.append(allocator, n);
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) try walkCollect(allocator, ch, out);
}

fn collect(allocator: std.mem.Allocator, root: *node.Node) !std.ArrayListUnmanaged(*node.Node) {
    var out: std.ArrayListUnmanaged(*node.Node) = .empty;
    try walkCollect(allocator, root, &out);
    return out;
}

fn firstExt(allocator: std.mem.Allocator, root: *node.Node, kind: u32) !?*node.Node {
    var nodes = try collect(allocator, root);
    defer nodes.deinit(allocator);
    for (nodes.items) |n| {
        if ((n.typ == .inline_extension or n.typ == .block_extension) and n.ext_kind == kind) return n;
    }
    return null;
}

fn parseMask(md: []const u8, mask: u32) !lutez.Doc {
    return lutez.parse(md, .{ .extensions = mask });
}

test "frontmatter --- and ... fences, payload excludes them" {
    const md = "---\ntitle: hello\n...\nbody\n";
    var doc = try parseMask(md, types.ExtensionMask.frontmatter);
    defer doc.deinit();
    const ext = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.frontmatter)).?;
    try std.testing.expectEqual(types.NodeType.block_extension, ext.typ);
    try std.testing.expectEqualStrings("title: hello\n", ext.tokens);
    try std.testing.expectEqualStrings("---\ntitle: hello\n...", doc.input[ext.src_start..ext.src_end]);
    try std.testing.expectEqualStrings("body\n", doc.input[ext.src_end + 1 ..]);
}

test "unclosed frontmatter consumes EOF" {
    const md = "---\na: b\n";
    var doc = try parseMask(md, types.ExtensionMask.frontmatter);
    defer doc.deinit();
    const ext = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.frontmatter)).?;
    try std.testing.expectEqualStrings("a: b\n", ext.tokens);
    try std.testing.expectEqual(@as(usize, 1), countChildren(doc.root));
}

fn countChildren(n: *node.Node) usize {
    var count: usize = 0;
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) count += 1;
    return count;
}

test "logseq property block at root and in list item" {
    const md = "title:: Hello\n\n- key:: value\n";
    var doc = try parseMask(md, types.ExtensionMask.outliner_blocks);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    var props: usize = 0;
    for (nodes.items) |n| {
        if (n.typ == .block_extension and n.ext_kind == types.ExtensionKind.logseq_property) {
            props += 1;
            try std.testing.expect(std.mem.endsWith(u8, n.tokens, ":: Hello") or std.mem.endsWith(u8, n.tokens, ":: value"));
        }
    }
    try std.testing.expectEqual(@as(usize, 2), props);
}

test "inline math, wikilink, tag and obsidian block id" {
    const md = "a $x$ b $$y$$ [[Note|alias]] #topic ^block-1\n";
    var doc = try parseMask(md, types.ExtensionMask.math | types.ExtensionMask.wiki_links | types.ExtensionMask.tags | types.ExtensionMask.outliner_blocks);
    defer doc.deinit();
    const math = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.math)).?;
    try std.testing.expectEqualStrings("x", math.tokens);
    try std.testing.expectEqualStrings("$x$", doc.input[math.src_start..math.src_end]);
    const wiki = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.wiki_link)).?;
    try std.testing.expectEqualStrings("Note|alias", wiki.tokens);
    try std.testing.expectEqualStrings("[[Note|alias]]", doc.input[wiki.src_start..wiki.src_end]);
    const tag = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.tag)).?;
    try std.testing.expectEqualStrings("topic", tag.tokens);
    try std.testing.expectEqualStrings("#topic", doc.input[tag.src_start..tag.src_end]);
    const bid = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.obsidian_block_id)).?;
    try std.testing.expectEqualStrings("block-1", bid.tokens);
    try std.testing.expectEqualStrings("^block-1", doc.input[bid.src_start..bid.src_end]);
}

test "extensions do not fire inside code spans or escapes" {
    const md = "`$x$ #tag [[w]]` \\#notag\n";
    var doc = try parseMask(md, types.ExtensionMask.math | types.ExtensionMask.wiki_links | types.ExtensionMask.tags);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    for (nodes.items) |n| {
        if (n.typ == .inline_extension) {
            try std.testing.expectEqual(types.ExtensionKind.math, n.ext_kind);
            try std.testing.expectEqualStrings("x", n.tokens);
        }
    }
}

test "fenced block math is a block extension" {
    const md = "$$\na + b\n$$\nafter\n";
    var doc = try parseMask(md, types.ExtensionMask.math);
    defer doc.deinit();
    const ext = (try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.math)).?;
    try std.testing.expectEqual(types.NodeType.block_extension, ext.typ);
    try std.testing.expectEqualStrings("a + b\n", ext.tokens);
    try std.testing.expect((ext.ext_flags & types.ExtensionFlags.block_math) != 0);
}

test "preset mask 0 leaves extension syntax as text" {
    const md = "#tag $x$ [[w]] ^id\n";
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    try std.testing.expect((try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.tag)) == null);
}

test "wire v2 preserves extension kinds and payloads" {
    const md = "---\na: 1\n...\n$x$ [[w]] #tag ^id\n\nTODO task\n";
    var doc = try parseMask(md, types.ExtensionMask.all);
    defer doc.deinit();
    const wire = try @import("ast/wire.zig").encode(std.testing.allocator, doc.root, &.{}, doc.source_map);
    defer std.testing.allocator.free(wire);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root2 = try @import("ast/wire.zig").decode(arena.allocator(), wire);
    var nodes = try collect(arena.allocator(), root2);
    defer nodes.deinit(arena.allocator());
    var kinds = std.AutoHashMapUnmanaged(u32, usize).empty;
    defer kinds.deinit(arena.allocator());
    for (nodes.items) |n| {
        if (n.typ == .block_extension or n.typ == .inline_extension) {
            const gop = try kinds.getOrPut(arena.allocator(), n.ext_kind);
            gop.value_ptr.* = (if (gop.found_existing) gop.value_ptr.* else 0) + 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), kinds.get(4).?); // frontmatter
    try std.testing.expectEqual(@as(usize, 1), kinds.get(1).?); // math
    try std.testing.expectEqual(@as(usize, 1), kinds.get(2).?); // wikilink
    try std.testing.expectEqual(@as(usize, 1), kinds.get(3).?); // tag
    try std.testing.expectEqual(@as(usize, 1), kinds.get(6).?); // obsidian block id
    try std.testing.expectEqual(@as(usize, 1), kinds.get(7).?); // outliner keyword
}

test "tags do not split URL fragments and survive merge" {
    const md = "see https://example.com/a#tag and #real\n";
    var doc = try parseMask(md, types.ExtensionMask.tags);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    var tags: usize = 0;
    var saw_url_link = false;
    for (nodes.items) |n| {
        if (n.typ == .inline_extension and n.ext_kind == 3) {
            tags += 1;
            try std.testing.expectEqualStrings("real", n.tokens);
        }
        if (n.typ == .link and n.link_type == 2) saw_url_link = true;
    }
    try std.testing.expectEqual(@as(usize, 1), tags);
    try std.testing.expect(saw_url_link);
}

test "tags are allowed in link text and math in emphasis" {
    const md = "[#tag](/u) *$x$*\n";
    var doc = try parseMask(md, types.ExtensionMask.tags | types.ExtensionMask.math);
    defer doc.deinit();
    try std.testing.expect((try firstExt(std.testing.allocator, doc.root, 3)) != null);
    try std.testing.expect((try firstExt(std.testing.allocator, doc.root, 1)) != null);
}

test "tag boundary allows a closing paren, rejects digits and stops at dots" {
    const md = ")#hg #123 #a.b\n";
    var doc = try parseMask(md, types.ExtensionMask.tags);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    var tags: usize = 0;
    var saw_hg = false;
    var saw_a = false;
    for (nodes.items) |n| {
        if (n.typ == .inline_extension and n.ext_kind == types.ExtensionKind.tag) {
            tags += 1;
            if (std.mem.eql(u8, n.tokens, "hg")) saw_hg = true;
            if (std.mem.eql(u8, n.tokens, "a")) saw_a = true;
            try std.testing.expect(!std.mem.eql(u8, n.tokens, "123"));
        }
    }
    try std.testing.expectEqual(@as(usize, 2), tags);
    try std.testing.expect(saw_hg and saw_a);
}

test "tags are capped at 64 characters" {
    var ok_buf: [66]u8 = undefined;
    ok_buf[0] = '#';
    @memset(ok_buf[1..65], 'a');
    ok_buf[65] = '\n';
    var ok_doc = try parseMask(&ok_buf, types.ExtensionMask.tags);
    defer ok_doc.deinit();
    const ok = (try firstExt(std.testing.allocator, ok_doc.root, types.ExtensionKind.tag)).?;
    try std.testing.expectEqual(@as(usize, 64), ok.tokens.len);

    var bad_buf: [67]u8 = undefined;
    bad_buf[0] = '#';
    @memset(bad_buf[1..66], 'a');
    bad_buf[66] = '\n';
    var bad_doc = try parseMask(&bad_buf, types.ExtensionMask.tags);
    defer bad_doc.deinit();
    try std.testing.expect((try firstExt(std.testing.allocator, bad_doc.root, types.ExtensionKind.tag)) == null);
}

test "logseq TODO and DOING keywords start a paragraph" {
    const md = "TODO task\n\nDOING other\n\n# TODO heading\n\nx TODO text\n";
    var doc = try parseMask(md, types.ExtensionMask.outliner_keywords);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    var keywords: usize = 0;
    var saw_todo = false;
    var saw_doing = false;
    for (nodes.items) |n| {
        if (n.typ == .inline_extension and n.ext_kind == types.ExtensionKind.outliner_keyword) {
            keywords += 1;
            if (std.mem.eql(u8, n.tokens, "TODO")) saw_todo = true;
            if (std.mem.eql(u8, n.tokens, "DOING")) saw_doing = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), keywords);
    try std.testing.expect(saw_todo and saw_doing);
}

test "outliner keywords stay off without their preset bit" {
    const md = "- TODO task\n";
    var doc = try parseMask(md, types.ExtensionMask.outliner_blocks);
    defer doc.deinit();
    try std.testing.expect((try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.outliner_keyword)) == null);
}

test "hash runs before a tag are not tag starts" {
    const md = "##tag\n";
    var doc = try parseMask(md, types.ExtensionMask.tags);
    defer doc.deinit();
    try std.testing.expect((try firstExt(std.testing.allocator, doc.root, types.ExtensionKind.tag)) == null);
}

test "obsidian block id only matches at block end" {
    const md = "a ^id b\nc ^ok\n";
    var doc = try parseMask(md, types.ExtensionMask.outliner_blocks);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    var ids: usize = 0;
    for (nodes.items) |n| {
        if (n.typ == .inline_extension and n.ext_kind == 6) {
            ids += 1;
            try std.testing.expectEqualStrings("ok", n.tokens);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ids);
}

test "block math spans stay inside list items" {
    const md = "- item\n  $$\n  x\n  $$\n";
    var doc = try parseMask(md, types.ExtensionMask.math);
    defer doc.deinit();
    var nodes = try collect(std.testing.allocator, doc.root);
    defer nodes.deinit(std.testing.allocator);
    for (nodes.items) |n| {
        if (!n.hasSpan()) continue;
        if (n.parent) |p| {
            if (p.hasSpan()) {
                try std.testing.expect(n.src_start >= p.src_start and n.src_end <= p.src_end);
            }
        }
    }
}
