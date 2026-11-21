//! Arena-backed AST node and tree operations.
//! Ported from lute/ast/node.go @ v1.7.8 (Mulan PSL v2, (c) 2019-present b3log.org).
//! Scope: CommonMark/GFM subset only. Links are pointers into a per-document arena;
//! the serialized form uses node indices (doc/WIRE_FORMAT.md).

const std = @import("std");
const types = @import("../types.zig");
pub const source = @import("../source.zig");
const NodeType = types.NodeType;

/// Provenance for one appended token chunk: token-buffer offset -> normalized source offset.
/// `src_len` may differ from `tok_len` for tab-expanded synthetic spaces.
pub const TokenSeg = struct {
    tok_off: u32,
    tok_len: u32,
    src_off: u32,
    src_len: u32,
};

pub const Span = struct { start: u32, end: u32 };

/// Maps a token slice back to normalized source offsets using provenance segments.
/// Returns null when the slice is not contained in `buffer` (i.e. it is a synthesized
/// copy such as an entity decode or an encoded link destination).
pub fn mapTokenSlice(buffer: []const u8, map: []const TokenSeg, slice: []const u8) ?Span {
    if (slice.len == 0 or map.len == 0) return null;
    const base = @intFromPtr(buffer.ptr);
    const ptr = @intFromPtr(slice.ptr);
    if (ptr < base) return null;
    const off: u32 = @intCast(ptr - base);
    if (off + slice.len > buffer.len) return null;
    return mapTokenRange(buffer, map, off, off + @as(u32, @intCast(slice.len)));
}

pub fn mapTokenRange(buffer: []const u8, map: []const TokenSeg, start_off: u32, end_off: u32) ?Span {
    if (start_off > end_off or end_off > buffer.len) return null;
    if (map.len == 0) return .{ .start = start_off, .end = end_off };
    return .{
        .start = mapTokenOffset(map, start_off, false),
        .end = mapTokenOffset(map, end_off, true),
    };
}

/// Fills every descendant without a span from `span` (used for synthesized subtrees).
pub fn fillSubtreeSpan(n: *Node, span: Span) void {
    if (!n.hasSpan()) n.setSpan(span.start, span.end);
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) fillSubtreeSpan(ch, span);
}

fn mapTokenOffset(map: []const TokenSeg, off: u32, end_bias: bool) u32 {
    for (map) |s| {
        const s_end = s.tok_off + s.tok_len;
        if (off < s.tok_off) return s.src_off;
        if (off < s_end) {
            if (s.tok_len == s.src_len) return s.src_off + (off - s.tok_off);
            return if (end_bias) s.src_off + s.src_len else s.src_off;
        }
        if (off == s_end) return s.src_off + s.src_len;
    }
    const last = map[map.len - 1];
    return last.src_off + last.src_len;
}

pub const ListData = struct {
    typ: u8 = 0, // 0 unordered, 1 ordered, 3 task
    tight: bool = false,
    bullet_char: u8 = 0,
    start: i32 = 0,
    delimiter: u8 = 0,
    padding: u32 = 0,
    marker_offset: u32 = 0,
    checked: bool = false,
    marker: []u8 = &.{},
    num: i32 = 0,
};

pub const Node = struct {
    typ: NodeType = .document,
    parent: ?*Node = null,
    prev: ?*Node = null,
    next: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    tokens: []u8 = &.{},

    /// Source span in normalized input bytes (see src/source.zig). `no_pos` = unset.
    src_start: u32 = source.no_pos,
    src_end: u32 = source.no_pos,
    src_derived: bool = false,

    /// In-memory only: token provenance for inline position mapping.
    token_map: []TokenSeg = &.{},
    /// Buffer that `token_map` offsets refer to (usually `tokens`, or a table paragraph).
    token_buffer: []u8 = &.{},

    /// In-memory only: code block positions for child marker/content spans.
    code_info_start: u32 = source.no_pos,
    code_info_end: u32 = source.no_pos,
    code_content_start: u32 = source.no_pos,
    code_content_end: u32 = source.no_pos,
    code_close_start: u32 = source.no_pos,
    code_close_end: u32 = source.no_pos,

    close: bool = false,
    last_line_blank: bool = false,
    last_line_checked: bool = false,

    heading_level: u8 = 0,
    heading_setext: bool = false,

    is_fenced_code_block: bool = false,
    code_block_fence_char: u8 = 0,
    code_block_fence_len: u32 = 0,
    code_block_fence_offset: u32 = 0,
    code_block_open_fence: []u8 = &.{},
    code_block_info: []u8 = &.{},
    code_block_close_fence: []u8 = &.{},
    code_marker_len: u32 = 0,

    html_block_type: u8 = 0,

    list_data: ListData = .{},

    table_aligns: []u8 = &.{},
    table_cell_align: u8 = 0,

    task_marker: u8 = 0,

    link_type: u8 = 0,
    link_ref_label: []u8 = &.{},

    /// Extension nodes (type 500/501). Payload is in `tokens`.
    ext_kind: u32 = 0,
    ext_flags: u16 = 0,
    /// Block extension that accepts continuation lines (fenced block math).
    ext_accepts_lines: bool = false,

    pub fn setSpan(self: *Node, start: u32, end: u32) void {
        self.src_start = start;
        self.src_end = end;
        self.src_derived = false;
    }

    pub fn setDerivedSpan(self: *Node, at: u32) void {
        self.src_start = at;
        self.src_end = at;
        self.src_derived = true;
    }

    pub fn hasSpan(self: *const Node) bool {
        return self.src_start != source.no_pos and self.src_end != source.no_pos;
    }

    pub fn create(allocator: std.mem.Allocator, typ: NodeType) !*Node {
        const n = try allocator.create(Node);
        n.* = .{ .typ = typ };
        return n;
    }

    pub fn init(typ: NodeType) Node {
        return .{ .typ = typ };
    }

    pub fn unlink(self: *Node) void {
        if (self.prev) |p| {
            p.next = self.next;
        } else if (self.parent) |p| {
            p.first_child = self.next;
        }
        if (self.next) |n| {
            n.prev = self.prev;
        } else if (self.parent) |p| {
            p.last_child = self.prev;
        }
        self.parent = null;
        self.next = null;
        self.prev = null;
    }

    pub fn appendChild(self: *Node, child: *Node) void {
        child.unlink();
        child.parent = self;
        if (self.last_child) |last| {
            last.next = child;
            child.prev = last;
            self.last_child = child;
        } else {
            self.first_child = child;
            self.last_child = child;
        }
    }

    pub fn prependChild(self: *Node, child: *Node) void {
        child.unlink();
        child.parent = self;
        if (self.first_child) |first| {
            first.prev = child;
            child.next = first;
            self.first_child = child;
        } else {
            self.first_child = child;
            self.last_child = child;
        }
    }

    pub fn insertAfter(self: *Node, sibling: *Node) void {
        sibling.unlink();
        sibling.next = self.next;
        if (sibling.next) |n| n.prev = sibling;
        sibling.prev = self;
        self.next = sibling;
        sibling.parent = self.parent;
        if (sibling.parent) |p| {
            if (sibling.next == null and p.last_child != null) p.last_child = sibling;
        }
    }

    pub fn insertBefore(self: *Node, sibling: *Node) void {
        sibling.unlink();
        sibling.prev = self.prev;
        if (sibling.prev) |p| p.next = sibling;
        sibling.next = self;
        self.prev = sibling;
        sibling.parent = self.parent;
        if (sibling.parent) |p| {
            if (sibling.prev == null) p.first_child = sibling;
        }
    }

    pub fn childByType(self: *const Node, t: NodeType) ?*Node {
        var c = self.first_child;
        while (c) |n| : (c = n.next) if (n.typ == t) return n;
        return null;
    }

    pub fn childrenByType(self: *Node, allocator: std.mem.Allocator, t: NodeType) !std.ArrayListUnmanaged(*Node) {
        var out: std.ArrayListUnmanaged(*Node) = .empty;
        try walkAlloc(allocator, self, t, &out);
        return out;
    }

    fn walkAlloc(allocator: std.mem.Allocator, n: *Node, t: NodeType, out: *std.ArrayListUnmanaged(*Node)) !void {
        if (n.typ == t) try out.append(allocator, n);
        var c = n.first_child;
        while (c) |ch| : (c = ch.next) try walkAlloc(allocator, ch, t, out);
    }

    pub fn lastDeepestChild(self: *Node) *Node {
        var n = self;
        while (n.last_child) |c| n = c;
        return n;
    }

    pub fn firstDeepestChild(self: *Node) *Node {
        var n = self;
        while (n.first_child) |c| n = c;
        return n;
    }

    pub fn tokensStr(self: *const Node) []const u8 {
        return self.tokens;
    }

    pub fn textLen(self: *const Node) usize {
        var buf: [1]u8 = undefined;
        _ = &buf;
        var len: usize = 0;
        var stack: [256]*Node = undefined;
        var sp: usize = 0;
        stack[sp] = @constCast(self);
        sp += 1;
        while (sp > 0) {
            sp -= 1;
            const n = stack[sp];
            switch (n.typ) {
                .text, .link_text => len += n.tokens.len,
                else => {},
            }
            // push children in reverse for document order (order irrelevant for length)
            var c = n.last_child;
            while (c) |ch| : (c = ch.prev) {
                if (sp < stack.len) {
                    stack[sp] = ch;
                    sp += 1;
                }
            }
        }
        return len;
    }

    pub fn text(self: *const Node, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        var stack: [1024]*Node = undefined;
        var sp: usize = 0;
        stack[sp] = @constCast(self);
        sp += 1;
        while (sp > 0) {
            sp -= 1;
            const n = stack[sp];
            switch (n.typ) {
                .text, .link_text => try out.appendSlice(allocator, n.tokens),
                else => {},
            }
            var c = n.last_child;
            while (c) |ch| : (c = ch.prev) {
                if (sp < stack.len) {
                    stack[sp] = ch;
                    sp += 1;
                }
            }
        }
        return out.toOwnedSlice(allocator);
    }

    /// Content(): like text(), but also includes code spans/blocks, entities, escaped
    /// backslash content, and separates blocks with '\n' (upstream behavior).
    pub fn content(self: *const Node, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        try contentWalk(allocator, @constCast(self), &out);
        return out.toOwnedSlice(allocator);
    }

    fn contentWalk(allocator: std.mem.Allocator, n: *Node, out: *std.ArrayListUnmanaged(u8)) !void {
        switch (n.typ) {
            .text, .link_text, .code_span_content, .code_block_code, .html_entity, .backslash_content => {
                try out.appendSlice(allocator, n.tokens);
            },
            else => {},
        }
        var c = n.first_child;
        while (c) |ch| : (c = ch.next) {
            try contentWalk(allocator, ch, out);
            if (ch.next != null and ch.next.?.next != null and ch.isBlock() and out.items.len > 0 and out.items[out.items.len - 1] != '\n') {
                try out.append(allocator, '\n');
            }
        }
    }

    pub fn canContain(self: *const Node, t: NodeType) bool {
        return switch (self.typ) {
            .code_block, .html_block, .paragraph, .thematic_break, .table, .inline_extension, .block_extension => false,
            .list => t == .list_item,
            else => t != .list_item,
        };
    }

    pub fn isBlock(self: *const Node) bool {
        return switch (self.typ) {
            .document, .paragraph, .heading, .thematic_break, .blockquote, .list, .list_item, .html_block, .code_block, .table, .block_extension => true,
            else => false,
        };
    }

    pub fn isContainerBlock(self: *const Node) bool {
        return switch (self.typ) {
            .document, .blockquote, .list, .list_item => true,
            else => false,
        };
    }

    pub fn isMarker(self: *const Node) bool {
        return switch (self.typ) {
            .heading_c8h_marker, .blockquote_marker, .code_block_fence_open_marker, .code_block_fence_close_marker, .code_block_fence_info_marker, .em_a6k_open_marker, .em_a6k_close_marker, .em_u8e_open_marker, .em_u8e_close_marker, .strong_a6k_open_marker, .strong_a6k_close_marker, .strong_u8e_open_marker, .strong_u8e_close_marker, .code_span_open_marker, .code_span_close_marker, .task_list_item_marker, .strikethrough1_open_marker, .strikethrough1_close_marker, .strikethrough2_open_marker, .strikethrough2_close_marker => true,
            else => false,
        };
    }

    pub fn isCloseMarker(self: *const Node) bool {
        return switch (self.typ) {
            .heading_c8h_marker, .blockquote_marker, .code_block_fence_close_marker, .em_a6k_close_marker, .em_u8e_close_marker, .strong_a6k_close_marker, .strong_u8e_close_marker, .code_span_close_marker, .strikethrough1_close_marker, .strikethrough2_close_marker => true,
            else => false,
        };
    }

    pub fn acceptLines(self: *const Node) bool {
        return switch (self.typ) {
            .paragraph, .code_block, .html_block => true,
            .block_extension => self.ext_accepts_lines,
            else => false,
        };
    }

    pub fn parentIs(self: *const Node, t: NodeType) bool {
        var p = self.parent;
        var deep: usize = 0;
        while (p) |node| : (p = node.parent) {
            if (node.typ == t) return true;
            deep += 1;
            if (deep > 128) break;
        }
        return false;
    }

    pub fn parentIsIn(self: *const Node, ts: []const NodeType) bool {
        var p = self.parent;
        var deep: usize = 0;
        while (p) |node| : (p = node.parent) {
            for (ts) |t| if (node.typ == t) return true;
            deep += 1;
            if (deep > 128) break;
        }
        return false;
    }

    pub fn marker(self: *const Node, entering: bool) []const u8 {
        return switch (self.typ) {
            .em_a6k_open_marker, .em_u8e_open_marker, .strong_a6k_open_marker, .strong_u8e_open_marker, .heading_c8h_marker => if (entering) "*" else "",
            else => "",
        };
    }
};

pub const WalkStatus = enum { stop, skip_children, continue_ };

pub fn Walk(comptime Ctx: type, n: *Node, ctx: Ctx, comptime f: fn (Ctx, *Node, bool) WalkStatus) WalkStatus {
    return walkRec(Ctx, n, ctx, f);
}

fn walkRec(comptime Ctx: type, n: *Node, ctx: Ctx, comptime f: fn (Ctx, *Node, bool) WalkStatus) WalkStatus {
    const ret = f(ctx, n, true);
    if (ret == .stop) return .stop;
    if (ret != .skip_children) {
        var c = n.first_child;
        while (c) |ch| : (c = ch.next) {
            const r = walkRec(Ctx, ch, ctx, f);
            if (r == .stop) return .stop;
        }
    }
    _ = f(ctx, n, false);
    return .continue_;
}

test "tree ops maintain sibling/parent invariants" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try Node.create(a, .document);
    const p1 = try Node.create(a, .paragraph);
    const p2 = try Node.create(a, .paragraph);
    root.appendChild(p1);
    root.appendChild(p2);
    try std.testing.expectEqual(p1, root.first_child.?);
    try std.testing.expectEqual(p2, root.last_child.?);
    try std.testing.expectEqual(p2, p1.next.?);
    try std.testing.expectEqual(p1, p2.prev.?);
    try std.testing.expectEqual(root, p1.parent.?);
    p1.unlink();
    try std.testing.expectEqual(p2, root.first_child.?);
    try std.testing.expectEqual(p2, root.last_child.?);
    try std.testing.expectEqual(@as(?*Node, null), p2.prev);
}

test "text and content walk leaf tokens" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try Node.create(a, .paragraph);
    const t = try Node.create(a, .text);
    t.tokens = try a.dupe(u8, "hi");
    root.appendChild(t);
    try std.testing.expectEqualStrings("hi", try root.text(a));
    try std.testing.expectEqualStrings("hi", try root.content(a));
}
