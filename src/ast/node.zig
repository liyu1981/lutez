//! Arena-backed AST node and tree operations.
//! Ported from lute/ast/node.go @ v1.7.8 (Mulan PSL v2, (c) 2019-present b3log.org).
//! Scope: CommonMark/GFM subset only. Links are pointers into a per-document arena;
//! the serialized form uses node indices (doc/WIRE_FORMAT.md).

const std = @import("std");
const types = @import("../types.zig");
const NodeType = types.NodeType;

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
            .code_block, .html_block, .paragraph, .thematic_break, .table => false,
            .list => t == .list_item,
            else => t != .list_item,
        };
    }

    pub fn isBlock(self: *const Node) bool {
        return switch (self.typ) {
            .document, .paragraph, .heading, .thematic_break, .blockquote, .list, .list_item, .html_block, .code_block, .table => true,
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
