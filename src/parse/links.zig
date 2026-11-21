//! Link label/destination/title scanning and reference definitions.
//! Ported from lute/parse/link.go, inline_link.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const uni = @import("../unicode/unicode.zig");
const html = @import("../html/escape.zig");
const tree = @import("tree.zig");
const blocks = @import("blocks.zig");

const Span = node.Span;

pub const Tree = tree.Tree;
pub const Context = tree.Context;

pub fn newLink(t: *Tree, typ: @import("../types.zig").NodeType, text: []const u8, dest: []const u8, title: ?[]const u8, link_type: u8) !*node.Node {
    const a = t.allocator;
    const decoded = try html.decodeDestination(a, text);
    const ret = try node.Node.create(a, typ);
    ret.link_type = link_type;
    if (typ == .image) ret.appendChild(try node.Node.create(a, .bang));
    ret.appendChild(try node.Node.create(a, .open_bracket));
    const lt = try node.Node.create(a, .link_text);
    lt.tokens = decoded;
    ret.appendChild(lt);
    ret.appendChild(try node.Node.create(a, .close_bracket));
    ret.appendChild(try node.Node.create(a, .open_paren));
    const ld = try node.Node.create(a, .link_dest);
    ld.tokens = @constCast(dest);
    ret.appendChild(ld);
    if (title) |ttl| {
        const ltl = try node.Node.create(a, .link_title);
        ltl.tokens = @constCast(ttl);
        ret.appendChild(ltl);
    }
    ret.appendChild(try node.Node.create(a, .close_paren));
    if (link_type == 1) ret.link_ref_label = @constCast(text);
    return ret;
}

const Label = struct { n: usize = 0, remains: []u8 = &.{}, label: []u8 = &.{} };

pub fn parseLinkLabel(allocator: std.mem.Allocator, tokens: []u8) !?Label {
    if (tokens.len < 2 or tokens[0] != lex.open_bracket) return null;
    var passed: std.ArrayListUnmanaged(u8) = .empty;
    try passed.append(allocator, tokens[0]);
    var label: std.ArrayListUnmanaged(u8) = .empty;
    var closed = false;
    var i: usize = 1;
    var remains: []u8 = &.{};
    while (i < tokens.len) {
        const b = tokens[i];
        try passed.append(allocator, b);
        const d = uni.decodeRune(tokens[i..]);
        var j: usize = 1;
        while (j < d.len) : (j += 1) try passed.append(allocator, tokens[i + j]);
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(d.r, &buf) catch blk: {
            buf[0] = 0xEF;
            buf[1] = 0xBF;
            buf[2] = 0xBD;
            break :blk 3;
        };
        try label.appendSlice(allocator, buf[0..n]);
        if (b == lex.close_bracket and !lex.isBackslashEscapePunct(tokens, i)) {
            closed = true;
            label.items.len -= 1;
            remains = tokens[i + 1 ..];
            break;
        }
        if (b == lex.open_bracket and !lex.isBackslashEscapePunct(tokens, i)) return null;
        i += d.len;
    }
    if (!closed or lex.trimWhitespace(label.items).len > 999) return null;
    var lab = try allocator.dupe(u8, lex.trimWhitespace(label.items));
    lab = lex.replaceAll(lab, lex.newline, lex.space);
    var k: usize = 0;
    while (k + 1 < lab.len) {
        if (lab[k] == lex.space and lab[k + 1] == lex.space) {
            _ = std.mem.copyForwards(u8, lab[k..], lab[k + 1 ..]);
            lab = lab[0 .. lab.len - 1];
        } else k += 1;
    }
    return .{ .n = passed.items.len, .remains = remains, .label = lab };
}

const Title = struct { valid: bool = false, passed: []u8 = &.{}, remains: []u8 = &.{}, title: []u8 = &.{}, src_start: usize = 0, src_end: usize = 0 };

pub fn parseLinkTitle(allocator: std.mem.Allocator, tokens: []u8) !Title {
    if (tokens.len < 1) return .{ .valid = true, .remains = tokens };
    if (tokens[0] == lex.open_bracket) return .{ .valid = true, .remains = tokens };
    var r = try parseLinkTitleMatch(allocator, lex.doublequote, lex.doublequote, tokens);
    if (!r.valid) {
        r = try parseLinkTitleMatch(allocator, lex.singlequote, lex.singlequote, tokens);
        if (!r.valid) r = try parseLinkTitleMatch(allocator, lex.open_paren, lex.close_paren, tokens);
    }
    if (r.title.len != 0) r.title = try blocks.unescapeBytes(allocator, r.title);
    return r;
}

fn parseLinkTitleMatch(allocator: std.mem.Allocator, opener: u8, closer: u8, tokens: []u8) !Title {
    if (tokens.len < 2 or tokens[0] != opener) return .{ .remains = tokens };
    var passed: std.ArrayListUnmanaged(u8) = .empty;
    var title: std.ArrayListUnmanaged(u8) = .empty;
    var closed = false;
    var i: usize = 1;
    while (i < tokens.len) {
        const b = tokens[i];
        try passed.append(allocator, b);
        const d = uni.decodeRune(tokens[i..]);
        var j: usize = 1;
        while (j < d.len) : (j += 1) try passed.append(allocator, tokens[i + j]);
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(d.r, &buf) catch 0;
        if (n != 0) try title.appendSlice(allocator, buf[0..n]);
        if (closer == b and !lex.isBackslashEscapePunct(tokens, i)) {
            closed = true;
            if (title.items.len > 0) title.items.len -= 1;
            break;
        }
        i += d.len;
    }
    if (!closed) return .{ .remains = tokens };
    return .{
        .valid = true,
        .passed = try passed.toOwnedSlice(allocator),
        .remains = tokens[i + 1 ..],
        .title = try title.toOwnedSlice(allocator),
        .src_start = 0,
        .src_end = i + 1,
    };
}

const Dest = struct { ret: ?[]u8 = null, remains: []u8 = &.{}, destination: []u8 = &.{} };

pub fn parseLinkDest(ctx: *Context, tokens: []u8) !Dest {
    var r = try parseLinkDest1(ctx.tree.allocator, tokens);
    if (r.ret == null) r = try parseLinkDest2(ctx.tree.allocator, tokens);
    if (r.ret != null) {
        const un = try blocks.unescapeBytes(ctx.tree.allocator, r.destination);
        r.destination = try html.encodeDestination(ctx.tree.allocator, un);
    }
    return r;
}

fn parseLinkDest2(allocator: std.mem.Allocator, tokens: []u8) !Dest {
    if (tokens.len < 1) return .{};
    var ret: std.ArrayListUnmanaged(u8) = .empty;
    var dest: std.ArrayListUnmanaged(u8) = .empty;
    var open_parens: i32 = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        const b = tokens[i];
        try ret.append(allocator, b);
        const d = uni.decodeRune(tokens[i..]);
        var j: usize = 1;
        while (j < d.len) : (j += 1) try ret.append(allocator, tokens[i + j]);
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(d.r, &buf) catch 0;
        if (n != 0) try dest.appendSlice(allocator, buf[0..n]);
        if (lex.isWhitespace(b) or lex.isControl(b)) {
            if (dest.items.len > 0) dest.items.len -= 1;
            if (ret.items.len > 0) ret.items.len -= 1;
            break;
        }
        if (b == lex.open_paren and !lex.isBackslashEscapePunct(tokens, i)) open_parens += 1;
        if (b == lex.close_paren and !lex.isBackslashEscapePunct(tokens, i)) {
            open_parens -= 1;
            if (open_parens < 1) {
                i += 1;
                break;
            }
        }
        i += d.len;
    }
    const remains = tokens[i..];
    if (tokens.len > i and !lex.isWhitespace(tokens[i])) return .{};
    return .{ .ret = try ret.toOwnedSlice(allocator), .remains = remains, .destination = try dest.toOwnedSlice(allocator) };
}

fn parseLinkDest1(allocator: std.mem.Allocator, tokens: []u8) !Dest {
    if (tokens.len < 2 or tokens[0] != lex.less) return .{};
    var ret: std.ArrayListUnmanaged(u8) = .empty;
    var dest: std.ArrayListUnmanaged(u8) = .empty;
    var closed = false;
    var i: usize = 0;
    while (i < tokens.len) {
        const b = tokens[i];
        try ret.append(allocator, b);
        var size: usize = 1;
        if (i > 0) {
            const d = uni.decodeRune(tokens[i..]);
            size = d.len;
            var j: usize = 1;
            while (j < size) : (j += 1) try ret.append(allocator, tokens[i + j]);
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(d.r, &buf) catch 0;
            if (n != 0) try dest.appendSlice(allocator, buf[0..n]);
            if (b == lex.less and !lex.isBackslashEscapePunct(tokens, i)) return .{};
        }
        if (b == lex.greater and !lex.isBackslashEscapePunct(tokens, i)) {
            closed = true;
            if (dest.items.len > 0) dest.items.len -= 1;
            break;
        }
        i += size;
    }
    if (!closed) return .{ .remains = tokens };
    return .{ .ret = try ret.toOwnedSlice(allocator), .remains = tokens[i + 1 ..], .destination = try dest.toOwnedSlice(allocator) };
}

pub const InlineDest = struct {
    passed: ?[]u8 = null,
    remains: []u8 = &.{},
    destination: []u8 = &.{},
    /// Source range of the destination inside the tokens passed to parseInlineLinkDest.
    src_start: usize = 0,
    src_end: usize = 0,
};

pub fn parseInlineLinkDest(alloc: std.mem.Allocator, options: @import("../types.zig").Options, tokens: []u8) !InlineDest {
    if (tokens.len < 2) return .{};
    var passed: std.ArrayListUnmanaged(u8) = .empty;
    var dest: std.ArrayListUnmanaged(u8) = .empty;
    var remains: []u8 = &.{};
    const pointy = tokens[1] == lex.less;
    var src_start: usize = 0;
    var src_end: usize = 0;
    if (pointy) {
        var matched = false;
        try passed.append(alloc, tokens[0]);
        try passed.append(alloc, tokens[1]);
        var i: usize = 2;
        while (i < tokens.len) {
            const b = tokens[i];
            if (b == lex.newline) return .{};
            try passed.append(alloc, b);
            const d = uni.decodeRune(tokens[i..]);
            var j: usize = 1;
            while (j < d.len) : (j += 1) try passed.append(alloc, tokens[i + j]);
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(d.r, &buf) catch 0;
            if (n != 0) try dest.appendSlice(alloc, buf[0..n]);
            if (b == lex.greater and !lex.isBackslashEscapePunct(tokens, i)) {
                if (dest.items.len > 0) dest.items.len -= 1;
                src_start = 2;
                src_end = i;
                matched = true;
                break;
            }
            i += d.len;
        }
        if (!matched or tokens.len <= i + 1) return .{};
        if (tokens[i + 1] == lex.greater or tokens[i + 1] == lex.close_paren) {
            try passed.append(alloc, tokens[i + 1]);
            remains = tokens[i + 2 ..];
        } else remains = tokens[i + 1 ..];
    } else {
        var open_parens: i32 = 0;
        var dest_started = false;
        var i: usize = 0;
        while (i < tokens.len) {
            const b = tokens[i];
            try passed.append(alloc, b);
            const d = uni.decodeRune(tokens[i..]);
            var j: usize = 1;
            while (j < d.len) : (j += 1) try passed.append(alloc, tokens[i + j]);
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(d.r, &buf) catch 0;
            if (n != 0) try dest.appendSlice(alloc, buf[0..n]);
            if (!dest_started and !lex.isWhitespace(b) and i > 0) {
                dest_started = true;
                src_start = i;
                const trimmed = lex.trimWhitespace(dest.items[1..]);
                std.mem.copyForwards(u8, dest.items[0..trimmed.len], trimmed);
                dest.items.len = trimmed.len;
            }
            if (dest_started and (lex.isWhitespace(b) or lex.isControl(b))) {
                src_end = i;
                if (dest.items.len >= d.len) dest.items.len -= d.len;
                if (passed.items.len > 0) passed.items.len -= 1;
                open_parens -= 1;
                break;
            }
            if (b == lex.open_paren and !lex.isBackslashEscapePunct(tokens, i)) open_parens += 1;
            if (b == lex.close_paren and !lex.isBackslashEscapePunct(tokens, i)) {
                open_parens -= 1;
                if (open_parens < 1) {
                    src_end = i;
                    if (dest.items.len > 0 and dest.items[0] == lex.open_paren) _ = dest.orderedRemove(0);
                    if (dest.items.len > 0) dest.items.len -= 1;
                    break;
                }
            }
            i += d.len;
        }
        remains = tokens[i..];
        if (tokens.len > i and tokens[i] != lex.close_paren and tokens[i] != lex.space and tokens[i] != lex.newline) return .{};
        if (open_parens != 0) return .{};
    }
    if (!options.data_image and std.ascii.startsWithIgnoreCase(dest.items, "data:image")) return .{};
    var destination = dest.items;
    if (destination.len != 0) {
        const un = try blocks.unescapeBytes(alloc, destination);
        destination = try html.encodeDestination(alloc, un);
    }
    return .{ .passed = try passed.toOwnedSlice(alloc), .remains = remains, .destination = destination, .src_start = src_start, .src_end = src_end };
}

/// parseLinkRefDef returns the remaining tokens when a definition was consumed.
pub fn parseLinkRefDef(ctx: *Context, tokens: []u8) !?[]u8 {
    if (!ctx.options.link_ref) return null;
    const toks: []u8 = @constCast(lex.trimLeft(tokens).remains);
    if (toks.len < 1) return null;
    const lab = try parseLinkLabel(ctx.tree.allocator, toks) orelse return null;
    if (lab.n < 2 or lab.label.len < 1) return null;
    var remains = lab.remains;
    if (remains.len < 1 or remains[0] != lex.colon) return null;
    remains = remains[1..];
    const wl = lex.trimLeft(remains);
    const nl = lex.statWhitespace(wl.whitespace).newlines;
    if (nl > 1) return null;
    const dest = try parseLinkDest(ctx, @constCast(wl.remains));
    if (dest.ret == null) return null;
    remains = dest.remains;
    const wl2 = lex.trimLeft(remains);
    if (wl2.whitespace.len == 0 and remains.len > 0) return null;
    const ws = lex.statWhitespace(wl2.whitespace);
    if (ws.newlines > 1) return null;
    const title_tokens: []u8 = @constCast(lex.trimLeft(remains).remains);
    var title = try parseLinkTitle(ctx.tree.allocator, title_tokens);
    if (!title.valid and ws.newlines < 1) return null;
    if (ws.spaces + ws.tabs > 0 and !lex.isBlankLine(title.remains) and title.remains.len > 0 and title.remains[0] != lex.newline) return null;
    const title_line = title_tokens;
    const wl3 = lex.trimLeft(title.remains);
    const ws2 = lex.statWhitespace(wl3.whitespace);
    var final_remains: []u8 = @constCast(wl3.remains);
    if (!lex.isBlankLine(wl3.remains) and ws2.spaces + ws2.tabs > 0) final_remains = title_line;
    if (!title.valid) title.title = &.{};

    const link = try newLink(ctx.tree, .link, lab.label, dest.destination, if (title.title.len != 0) title.title else null, 1);
    const def = try node.Node.create(ctx.tree.allocator, .link_ref_def);
    def.tokens = lab.label;
    def.appendChild(link);

    const holder = ctx.tip;
    const buffer = if (holder.token_buffer.len > 0) holder.token_buffer else holder.tokens;
    const start_off: u32 = @intCast(@intFromPtr(tokens.ptr) - @intFromPtr(buffer.ptr));
    const end_off: u32 = @intCast(@intFromPtr(final_remains.ptr) - @intFromPtr(buffer.ptr));
    const span = node.mapTokenRange(buffer, holder.token_map, start_off, end_off) orelse
        Span{ .start = holder.src_start, .end = holder.src_end };
    def.setSpan(span.start, span.end);
    link.setSpan(span.start, span.end);
    node.fillSubtreeSpan(link, span);

    var def_block = holder;
    if (def_block.typ != .link_ref_def_block) {
        def_block = try node.Node.create(ctx.tree.allocator, .link_ref_def_block);
    }
    def_block.appendChild(def);
    if (!def_block.hasSpan()) {
        def_block.setSpan(span.start, span.end);
    } else {
        def_block.setSpan(@min(def_block.src_start, span.start), @max(def_block.src_end, span.end));
    }
    if (holder.parent) |p| p.appendChild(def_block);

    // Register in the label index for inline resolution.
    const folded = try foldLabel(ctx.tree.allocator, lab.label);
    if (ctx.refs.getPtr(folded)) |existing| {
        _ = existing;
    } else {
        try ctx.refs.put(ctx.tree.allocator, folded, .{
            .label = lab.label,
            .dest = dest.destination,
            .title = title.title,
        });
    }
    return final_remains;
}

pub fn foldLabel(allocator: std.mem.Allocator, label: []u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (i < label.len) {
        const d = uni.decodeRune(label[i..]);
        try uni.foldAppend(allocator, &out, d.r);
        i += d.len;
    }
    return out.toOwnedSlice(allocator);
}

test "inline link dest with escaped star and title" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const buf = try a.dupe(u8, "(/bar\\* \"ti\\*tle\")");
    const r = try parseInlineLinkDest(a, .{}, buf);
    try std.testing.expect(r.passed != null);
    try std.testing.expectEqualStrings("/bar*", r.destination);
}

test "inline link dest with spaces and newline title" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const buf = try a.dupe(u8, "(   /uri\n  \"title\"  )");
    const r = try parseInlineLinkDest(a, .{}, buf);
    if (r.passed) |p| std.debug.print("\npassed=[{s}] dest=[{s}] remains=[{s}]\n", .{ p, r.destination, r.remains });
    try std.testing.expect(r.passed != null);
    try std.testing.expectEqualStrings("/uri", r.destination);
}

test "link title double quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const buf = try a.dupe(u8, "\"title\"  )");
    const r = try parseLinkTitle(a, buf);
    std.debug.print("\nvalid={} passed=[{s}] title=[{s}] remains=[{s}]\n", .{ r.valid, r.passed, r.title, r.remains });
    try std.testing.expect(r.valid);
}
