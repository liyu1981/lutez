//! Block starts, continuation checks and finalizers (scoped subset).
//! Ported from lute/parse/{block_start,blockquote,paragraph,heading,thematic_break,
//! code_block,list,html_block,table}.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const types = @import("../types.zig");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const html = @import("../html/escape.zig");
const Tree = @import("tree.zig").Tree;
const Context = @import("tree.zig").Context;
const refdef = @import("refdef.zig");

pub const StartFn = *const fn (*Tree, *node.Node) anyerror!u8;

pub const starts = [_]StartFn{
    blockquoteStart,
    atxHeadingStart,
    fenceCodeBlockStart,
    setextHeadingStart,
    htmlBlockStart,
    thematicBreakStart,
    listStart,
    indentCodeBlockStart,
};

pub fn continueBlock(n: *node.Node, ctx: *Context) anyerror!u8 {
    return switch (n.typ) {
        .code_block => codeBlockContinue(n, ctx),
        .html_block => htmlBlockContinue(n, ctx),
        .paragraph => if (ctx.blank) 1 else 0,
        .list_item => listItemContinue(n, ctx),
        .blockquote => blockquoteContinue(n, ctx),
        .heading, .thematic_break, .table, .link_ref_def_block => 1,
        else => 0,
    };
}

// ---- paragraph ------------------------------------------------------------

pub fn paragraphFinalize(ctx: *Context, p: *node.Node) bool {
    p.tokens = @constCast(lex.trimWhitespace(p.tokens));

    var has_ref_defs = false;
    while (p.tokens.len > 0 and p.tokens[0] == lex.open_bracket) {
        if (refdef.parseLinkRefDef(ctx, p.tokens)) |remains| {
            p.tokens = remains;
            has_ref_defs = true;
        } else break;
    }
    if (has_ref_defs and lex.isBlankLine(p.tokens)) p.unlink();

    if (ctx.options.gfm_task_list_item) {
        if (p.parent) |list_item| {
            if (list_item.typ == .list_item and list_item.first_child == p) {
                if (list_item.list_data.typ == 3) {
                    const toks = p.tokens;
                    if (toks.len >= 3 and toks[0] == lex.open_bracket and toks[2] == lex.close_bracket and toks[1] != lex.close_bracket) {
                        const marker = toks[1];
                        if (marker == ' ' or marker == 'x' or marker == 'X') {
                            const tm = node.Node.create(ctx.tree.allocator, .task_list_item_marker) catch return false;
                            tm.tokens = toks[0..3];
                            tm.task_marker = marker;
                            p.prependChild(tm);
                            p.tokens = toks[3..];
                        }
                    }
                }
            }
        }
    }

    if (ctx.options.gfm_table) {
        if (tableFinalizeParagraph(ctx, p) catch false) return false;
    }
    return false;
}

// ---- ATX / setext headings ------------------------------------------------

fn atxHeadingStart(t: *Tree, container: *node.Node) anyerror!u8 {
    _ = container;
    if (t.context.indented) return 0;
    const parsed = try parseATXHeading(t);
    if (!parsed.ok) return 0;
    const ctx = t.context;
    ctx.advanceNextNonspace();
    ctx.advanceOffset(parsed.content.len, false);
    ctx.closeUnmatchedBlocks();
    const heading = try ctx.addChild(.heading);
    heading.heading_level = parsed.level;
    heading.tokens = parsed.content;
    const marker = try node.Node.create(t.allocator, .heading_c8h_marker);
    marker.tokens = parsed.markers;
    heading.appendChild(marker);
    ctx.advanceOffset(ctx.current_line_len - ctx.offset, false);
    return 2;
}

const Atx = struct { ok: bool = false, markers: []u8 = &.{}, content: []u8 = &.{}, level: u8 = 0 };

fn parseATXHeading(t: *Tree) !Atx {
    const ctx = t.context;
    var tokens = ctx.current_line[ctx.next_nonspace..];
    if (tokens.len == 0 or tokens[0] != lex.crosshatch) return .{};
    const level = lex.accept(tokens, lex.crosshatch);
    if (level > 6) return .{};
    if (level < tokens.len and !lex.isWhitespace(tokens[level])) return .{};
    const markers = ctx.current_line[ctx.next_nonspace .. ctx.next_nonspace + level + 1];
    _ = lex.trimLeft(tokens); // strip leading whitespace (none in practice)
    tokens = @constCast(lex.trimLeft(tokens[level..]).remains);
    var content: std.ArrayListUnmanaged(u8) = .empty;
    for (tokens) |b| {
        if (b == lex.newline) break;
        try content.append(t.allocator, b);
    }
    var c = lex.trimRight(content.items).remains;
    var idx: isize = @as(isize, @intCast(c.len)) - 1;
    while (idx >= 0) : (idx -= 1) {
        const ch = c[@intCast(idx)];
        if (ch == lex.crosshatch) continue;
        if (ch == lex.space) break;
        idx = @intCast(c.len);
        break;
    }
    if (idx <= 0) {
        c = c[0..0];
    } else if (idx < @as(isize, @intCast(c.len))) {
        c = lex.trimRight(c[0..@intCast(idx)]).remains;
    }
    c = lex.trimRight(c).remains;
    return .{ .ok = true, .markers = markers, .content = try t.allocator.dupe(u8, c), .level = @intCast(level) };
}

fn setextHeadingStart(t: *Tree, container: *node.Node) anyerror!u8 {
    if (t.context.indented or container.typ != .paragraph or !t.context.options.setext) return 0;
    const level = parseSetextHeading(t);
    if (level == 0) return 0;
    if (t.context.options.gfm_table) {
        if (try tableStartFromSetext(t, container)) return 0;
    }
    const ctx = t.context;
    ctx.closeUnmatchedBlocks();
    while (container.tokens.len > 0 and container.tokens[0] == lex.open_bracket) {
        if (refdef.parseLinkRefDef(ctx, container.tokens)) |remains| {
            container.tokens = remains;
        } else break;
    }
    if (container.tokens.len > 0) {
        const heading = try node.Node.create(t.allocator, .heading);
        heading.heading_level = level;
        heading.heading_setext = true;
        heading.tokens = @constCast(lex.trimWhitespace(container.tokens));
        container.insertAfter(heading);
        container.unlink();
        ctx.tip = heading;
        ctx.advanceOffset(ctx.current_line_len - ctx.offset, false);
        return 2;
    }
    return 0;
}

fn parseSetextHeading(t: *Tree) u8 {
    const ln = lex.trimWhitespace(t.context.current_line);
    if (ln.len == 0) return 0;
    const marker = ln[0];
    if (marker != lex.equal and marker != lex.hyphen) return 0;
    for (ln) |b| {
        if (b != marker) return 0;
    }
    return if (marker == lex.hyphen) 2 else 1;
}

// ---- thematic break -------------------------------------------------------

fn thematicBreakStart(t: *Tree, container: *node.Node) anyerror!u8 {
    _ = container;
    if (t.context.indented) return 0;
    if (!parseThematicBreak(t)) return 0;
    const ctx = t.context;
    ctx.closeUnmatchedBlocks();
    _ = try ctx.addChild(.thematic_break);
    ctx.advanceOffset(ctx.current_line_len - ctx.offset, false);
    return 2;
}

fn parseThematicBreak(t: *Tree) bool {
    const ctx = t.context;
    var marker: u8 = 0;
    var count: usize = 0;
    var i = ctx.next_nonspace;
    while (i + 1 < ctx.current_line.len) : (i += 1) {
        const b = ctx.current_line[i];
        if (b == lex.space or b == lex.tab) continue;
        if (b != lex.hyphen and b != lex.underscore and b != lex.asterisk) return false;
        if (marker != 0 and marker != b) return false;
        marker = b;
        count += 1;
    }
    return count >= 3;
}

// ---- blockquote -----------------------------------------------------------

fn blockquoteStart(t: *Tree, container: *node.Node) anyerror!u8 {
    _ = container;
    const ctx = t.context;
    if (ctx.indented) return 0;
    if (lex.peek(ctx.current_line, ctx.next_nonspace) != lex.greater) return 0;
    var markers: std.ArrayListUnmanaged(u8) = .empty;
    try markers.append(t.allocator, lex.greater);
    ctx.advanceNextNonspace();
    ctx.advanceOffset(1, false);
    const ws = lex.peek(ctx.current_line, ctx.offset);
    if (ws == lex.space or ws == lex.tab) {
        ctx.advanceOffset(1, true);
        try markers.append(t.allocator, ws);
    }
    ctx.closeUnmatchedBlocks();
    _ = try ctx.addChild(.blockquote);
    _ = try ctx.addChildMarker(.blockquote_marker, try markers.toOwnedSlice(t.allocator));
    return 1;
}

fn blockquoteContinue(_: *node.Node, ctx: *Context) u8 {
    const ln = ctx.current_line;
    if (!ctx.indented and lex.peek(ln, ctx.next_nonspace) == lex.greater) {
        ctx.advanceNextNonspace();
        ctx.advanceOffset(1, false);
        const b = lex.peek(ln, ctx.offset);
        if (b == lex.space or b == lex.tab) ctx.advanceOffset(1, true);
        return 0;
    }
    return 1;
}

pub fn blockquoteFinalize(_: *Context, _: *node.Node) void {}

// ---- code blocks ----------------------------------------------------------

fn fenceCodeBlockStart(t: *Tree, container: *node.Node) anyerror!u8 {
    _ = container;
    if (t.context.indented) return 0;
    const parsed = try parseFencedCode(t);
    if (!parsed.ok) return 0;
    const ctx = t.context;
    ctx.closeUnmatchedBlocks();
    const cb = try ctx.addChild(.code_block);
    cb.is_fenced_code_block = true;
    cb.code_block_fence_char = parsed.fence_char;
    cb.code_block_fence_len = parsed.fence_len;
    cb.code_block_fence_offset = parsed.fence_offset;
    cb.code_block_open_fence = parsed.open_fence;
    cb.code_block_info = parsed.info;
    ctx.advanceNextNonspace();
    ctx.advanceOffset(parsed.fence_len, false);
    return 2;
}

const Fence = struct {
    ok: bool = false,
    fence_char: u8 = 0,
    fence_len: u32 = 0,
    fence_offset: u32 = 0,
    open_fence: []u8 = &.{},
    info: []u8 = &.{},
};

fn parseFencedCode(t: *Tree) !Fence {
    const ctx = t.context;
    const marker = ctx.current_line[ctx.next_nonspace];
    if (marker != lex.backtick and marker != lex.tilde) return .{};
    var len: u32 = 0;
    var i = ctx.next_nonspace;
    while (i < ctx.current_line_len and ctx.current_line[i] == marker) : (i += 1) len += 1;
    if (len < 3) return .{};
    const open_fence = ctx.current_line[ctx.next_nonspace .. ctx.next_nonspace + len];
    const info_tokens = ctx.current_line[ctx.next_nonspace + len ..];
    if (marker == lex.backtick and std.mem.indexOfScalar(u8, info_tokens, lex.backtick) != null) return .{};
    var info = lex.trimWhitespace(info_tokens);
    info = lex.trimWhitespace(try unescapeBytes(t.allocator, info));
    if (std.mem.indexOfScalar(u8, info, ' ')) |idx| info = info[0..idx];
    return .{
        .ok = true,
        .fence_char = marker,
        .fence_len = len,
        .fence_offset = @intCast(ctx.indent),
        .open_fence = open_fence,
        .info = try t.allocator.dupe(u8, info),
    };
}

pub fn replaceAll(allocator: std.mem.Allocator, s: []const u8, needle: []const u8, repl: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, s, i, needle)) |idx| {
        try out.appendSlice(allocator, s[i..idx]);
        try out.appendSlice(allocator, repl);
        i = idx + needle.len;
    }
    try out.appendSlice(allocator, s[i..]);
    return out.toOwnedSlice(allocator);
}

pub fn unescapeBytes(allocator: std.mem.Allocator, tokens: []const u8) ![]u8 {
    const unescaped = try html.unescapeString(allocator, tokens);
    if (std.mem.indexOfScalar(u8, unescaped, '\\') == null) return unescaped;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (unescaped, 0..) |b, i| {
        if (lex.isBackslashEscapePunct(unescaped, i)) {
            if (out.items.len > 0) out.items.len -= 1; // drop the backslash, keep the punctuation
        }
        try out.append(allocator, b);
    }
    return out.toOwnedSlice(allocator);
}

fn indentCodeBlockStart(t: *Tree, container: *node.Node) anyerror!u8 {
    _ = container;
    const ctx = t.context;
    if (!ctx.options.indent_code_block or !ctx.indented) return 0;
    if (ctx.tip.typ != .paragraph and !ctx.blank) {
        ctx.advanceOffset(4, true);
        ctx.closeUnmatchedBlocks();
        _ = try ctx.addChild(.code_block);
        return 2;
    }
    return 0;
}

fn codeBlockContinue(cb: *node.Node, ctx: *Context) u8 {
    const ln = ctx.current_line;
    if (cb.is_fenced_code_block) {
        if (ctx.indent <= 3) {
            if (isFencedCodeClose(ln[ctx.next_nonspace..], cb.code_block_fence_char, cb.code_block_fence_len)) |close| {
                cb.code_block_close_fence = close;
                ctx.finalize(cb);
                return 2;
            }
        }
        var i = cb.code_block_fence_offset;
        while (i > 0) {
            const b = lex.peek(ln, ctx.offset);
            if (b != lex.space and b != lex.tab) break;
            ctx.advanceOffset(1, true);
            i -= 1;
        }
    } else {
        if (ctx.indent >= 4) {
            ctx.advanceOffset(4, true);
        } else if (ctx.blank) {
            ctx.advanceNextNonspace();
        } else return 1;
    }
    return 0;
}

fn isFencedCodeClose(tokens: []const u8, open_marker: u8, num: u32) ?[]u8 {
    if (tokens.len == 0 or tokens[0] != open_marker) return null;
    if (num > lex.accept(tokens, open_marker)) return null;
    const t = lex.trimWhitespace(tokens);
    for (t) |b| if (b != open_marker) return null;
    return @constCast(t);
}

pub fn codeBlockFinalize(_: *Context, cb: *node.Node) void {
    if (cb.is_fenced_code_block) {
        if (cb.tokens.len == 0) return;
        var i: usize = 0;
        while (i < cb.tokens.len and cb.tokens[i] != lex.newline) : (i += 1) {}
        cb.tokens = if (i + 1 <= cb.tokens.len) cb.tokens[i + 1 ..] else cb.tokens[0..0];
    } else {
        cb.tokens = lex.replaceNewlineSpace(cb.tokens);
    }
}

// ---- lists ----------------------------------------------------------------

fn listStart(t: *Tree, container: *node.Node) anyerror!u8 {
    const ctx = t.context;
    if (container.typ != .list and ctx.indented) return 0;
    const data = try parseListMarker(t, container) orelse return 0;
    ctx.closeUnmatchedBlocks();
    const lists_match = container.typ == .list and listsMatch(container.list_data, data);
    if (ctx.tip.typ != .list or !lists_match) {
        const list = try ctx.addChild(.list);
        list.list_data = data;
    }
    const item = try ctx.addChild(.list_item);
    item.list_data = data;
    item.tokens = data.marker;
    if (data.typ == 1 or (data.typ == 3 and data.bullet_char == 0)) {
        if (item.prev) |prev| {
            item.list_data.num = prev.list_data.num + 1;
        } else {
            item.list_data.num = data.start;
        }
        if (item.prev == null) {
            if (item.parent) |p| p.list_data.num = item.list_data.num;
        }
    }
    return 1;
}

fn listsMatch(a: node.ListData, b: node.ListData) bool {
    return a.typ == b.typ and
        ((a.delimiter == 0 and b.delimiter == 0) or a.delimiter == b.delimiter) and
        a.bullet_char == b.bullet_char;
}

fn listItemContinue(item: *node.Node, ctx: *Context) u8 {
    if (ctx.blank) {
        if (item.first_child == null) return 1;
        ctx.advanceNextNonspace();
    } else if (ctx.indent >= item.list_data.marker_offset + item.list_data.padding) {
        ctx.advanceOffset(item.list_data.marker_offset + item.list_data.padding, true);
    } else return 1;
    return 0;
}

pub fn listFinalize(_: *Context, list: *node.Node) void {
    var item = list.first_child;
    outer: while (item) |it| : (item = it.next) {
        if (endsWithBlankLine(it) and it.next != null) {
            list.list_data.tight = false;
            break;
        }
        var sub = it.first_child;
        while (sub) |s| : (sub = s.next) {
            if (endsWithBlankLine(s) and (it.next != null or s.next != null)) {
                list.list_data.tight = false;
                break :outer;
            }
        }
    }
    // Upstream ListData is shared between the list and its *first* item (later items
    // get fresh data that stays Tight=true), so mirror only the first item here.
    if (list.first_child) |first| first.list_data.tight = list.list_data.tight;
}

fn endsWithBlankLine(start: *node.Node) bool {
    var block: ?*node.Node = start;
    while (block) |b| {
        if (b.last_line_blank) return true;
        if (!b.last_line_checked and (b.typ == .list or b.typ == .list_item)) {
            b.last_line_checked = true;
            block = b.last_child;
        } else {
            b.last_line_checked = true;
            break;
        }
    }
    return false;
}

fn parseListMarker(t: *Tree, container: *node.Node) !?node.ListData {
    const ctx = t.context;
    if (ctx.indent >= 4) return null;
    const ln = ctx.current_line;
    var tokens = ln[ctx.next_nonspace..];
    if (tokens.len == 0) return null;
    var data = node.ListData{ .typ = 0, .tight = true, .marker_offset = @intCast(ctx.indent), .num = -1 };
    var marker_len: usize = 1;
    var marker: []u8 = @constCast(tokens[0..1]);
    if (tokens[0] == lex.plus or tokens[0] == lex.hyphen or tokens[0] == lex.asterisk) {
        data.bullet_char = tokens[0];
    } else if (try parseOrderedListMarker(t, tokens)) |om| {
        if (container.typ != .paragraph or std.mem.eql(u8, "1", om.marker)) {
            data.typ = 1;
            data.start = std.fmt.parseInt(i32, om.marker, 10) catch 0;
            marker_len = om.marker.len + 1;
            data.delimiter = om.delimiter;
            marker = om.marker;
        } else return null;
    } else return null;
    data.marker = marker;
    if (data.typ == 1) data.marker = try std.mem.concat(t.allocator, u8, &.{ marker, "." });
    const idx = ctx.next_nonspace + marker_len;
    const b = if (idx < ln.len) ln[idx] else lex.newline;
    if (!lex.isWhitespace(b)) return null;
    if (container.typ == .paragraph and b == lex.newline) return null;

    ctx.advanceNextNonspace();
    ctx.advanceOffset(marker_len, true);
    const spaces_start_col = ctx.column;
    const spaces_start_offset = ctx.offset;
    while (true) {
        ctx.advanceOffset(1, true);
        const tk = lex.peek(ln, ctx.offset);
        if (ctx.column - spaces_start_col >= 5 or tk == 0 or (tk != lex.space and tk != lex.tab)) break;
    }
    const tk = lex.peek(ln, ctx.offset);
    const is_blank_item = tk == 0 or tk == lex.newline;
    const spaces_after_marker = ctx.column - spaces_start_col;
    if (spaces_after_marker >= 5 or spaces_after_marker < 1 or is_blank_item) {
        data.padding = @intCast(marker_len + 1);
        ctx.column = spaces_start_col;
        ctx.offset = spaces_start_offset;
        const t2 = lex.peek(ln, ctx.offset);
        if (t2 == lex.space or t2 == lex.tab) ctx.advanceOffset(1, true);
    } else {
        data.padding = @intCast(marker_len + spaces_after_marker);
    }
    if (!is_blank_item) {
        const rest = ln[ctx.offset..];
        if (rest.len >= 3 and rest[0] == lex.open_bracket and rest[1] != lex.close_bracket and rest[2] == lex.close_bracket and
            (rest.len == 3 or lex.isWhitespace(rest[3])))
        {
            const m = rest[1];
            if (m == ' ' or m == 'x' or m == 'X') {
                data.typ = 3;
                data.checked = m != ' ';
            }
        }
    }
    return data;
}

const OrderedMarker = struct { marker: []u8, delimiter: u8 };

fn parseOrderedListMarker(t: *Tree, tokens: []const u8) !?OrderedMarker {
    var marker: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    var delim: u8 = 0;
    while (i < tokens.len) : (i += 1) {
        const b = tokens[i];
        if (!lex.isDigit(b) or i > 8) {
            delim = b;
            break;
        }
        try marker.append(t.allocator, b);
    }
    if (marker.items.len < 1 or (delim != lex.dot and delim != lex.close_paren)) return null;
    return .{ .marker = try marker.toOwnedSlice(t.allocator), .delimiter = delim };
}

// ---- HTML blocks (implemented in html_block.zig) --------------------------

pub const html_block = @import("html_block.zig");
fn htmlBlockStart(t: *Tree, container: *node.Node) anyerror!u8 {
    return html_block.start(t, container);
}
fn htmlBlockContinue(n: *node.Node, ctx: *Context) u8 {
    return html_block.continueBlock(n, ctx);
}
pub fn htmlBlockFinalize(ctx: *Context, n: *node.Node) void {
    html_block.finalize(ctx, n);
}
pub fn isHTMLBlockClose(block_type: u8, tokens: []const u8) bool {
    return html_block.isClose(block_type, tokens);
}

// ---- tables (implemented in table.zig) ------------------------------------

const table = @import("table.zig");
fn tableStartFromSetext(t: *Tree, p: *node.Node) !bool {
    return table.startFromSetext(t, p);
}
fn tableFinalizeParagraph(ctx: *Context, p: *node.Node) !bool {
    return table.finalizeParagraph(ctx, p);
}
