//! Inline parser: text, escapes, breaks, code spans, links/images, entities.
//! Ported from lute/parse/inline.go, inline_link.go, text.go, code_span.go,
//! inlines.go @ v1.7.8 (Mulan PSL v2); SiYuan/Vditor branches stripped.
const std = @import("std");
const types = @import("../types.zig");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const uni = @import("../unicode/unicode.zig");
const html = @import("../html/escape.zig");
const tree = @import("tree.zig");
const delim = @import("delimiter.zig");
const links = @import("links.zig");
const blocks = @import("blocks.zig");

pub const InlineContext = delim.InlineContext;

const Ctx = struct {
    t: *tree.Tree,
    ctx: *InlineContext,
    fn a(self: Ctx) std.mem.Allocator {
        return self.t.allocator;
    }
    fn dctx(self: Ctx) delim.DelimCtx {
        return .{ .allocator = self.t.allocator, .options = self.t.context.options, .ictx = self.ctx };
    }
};

pub fn parseInlines(t: *tree.Tree) !void {
    try walkParseInline(t, t.root);
}

fn walkParseInline(t: *tree.Tree, n: *node.Node) !void {
    const typ = n.typ;
    if (typ == .paragraph or typ == .heading or typ == .table_cell) {
        if (typ == .paragraph and n.tokens.len == 0 and n.first_child == null) {
            n.unlink();
            return;
        }
        if (n.tokens.len == 0) return;
        var ictx = InlineContext{ .tokens = n.tokens, .tokens_len = n.tokens.len };
        try parseInline(t, n, &ictx);
        try delim.processEmphasis(.{ .allocator = t.allocator, .options = t.context.options, .ictx = &ictx }, null);
        try mergeText(t.allocator, n);
        if (t.context.options.gfm_auto_link) {
            try @import("auto_link.zig").parseGFMAutoEmailLink(t, n);
            try @import("auto_link.zig").parseGFMAutoLink(t, n);
        }
        return;
    } else if (typ == .code_block) {
        if (n.is_fenced_code_block) {
            const open = try node.Node.create(t.allocator, .code_block_fence_open_marker);
            open.tokens = n.code_block_open_fence;
            open.code_block_fence_len = n.code_block_fence_len;
            n.prependChild(open);
            const info = try node.Node.create(t.allocator, .code_block_fence_info_marker);
            info.code_block_info = n.code_block_info;
            n.appendChild(info);
            const code = try node.Node.create(t.allocator, .code_block_code);
            code.tokens = n.tokens;
            n.appendChild(code);
            if (n.code_block_close_fence.len == 0) n.code_block_close_fence = n.code_block_open_fence;
            const close = try node.Node.create(t.allocator, .code_block_fence_close_marker);
            close.tokens = n.code_block_close_fence;
            close.code_block_fence_len = n.code_block_fence_len;
            n.appendChild(close);
        } else {
            const code = try node.Node.create(t.allocator, .code_block_code);
            code.tokens = n.tokens;
            n.appendChild(code);
        }
        n.tokens = &.{};
    }
    var child = n.first_child;
    while (child) |c| : (child = c.next) try walkParseInline(t, c);
}

pub fn parseInline(t: *tree.Tree, block: *node.Node, ctx: *InlineContext) !void {
    const c = Ctx{ .t = t, .ctx = ctx };
    while (ctx.pos < ctx.tokens_len) {
        const tok = ctx.tokens[ctx.pos];
        var n: ?*node.Node = null;
        switch (tok) {
            lex.backslash => n = try parseBackslash(c, block),
            lex.backtick => n = try parseCodeSpan(c, block),
            lex.asterisk, lex.underscore, lex.tilde => try delim.handleDelim(c.dctx(), block),
            lex.newline => n = try parseNewline(c, block),
            lex.less => n = try @import("auto_link.zig").parseAutolink(c, block),
            lex.open_bracket => n = try parseOpenBracket(c, ctx),
            lex.close_bracket => n = try parseCloseBracket(c, block),
            lex.ampersand => n = try parseEntity(c),
            lex.bang => n = try parseBang(c, block),
            else => n = try parseText(c),
        }
        if (n) |nn| {
            if (nn.prev == null and nn.next == null) {
                block.appendChild(nn);
                continue;
            }
            var first = nn;
            while (first.prev) |p| first = p;
            var cur: ?*node.Node = first;
            while (cur) |x| {
                const next = x.next;
                block.appendChild(x);
                cur = next;
            }
        }
    }
    block.tokens = &.{};
}

fn parseText(c: Ctx) !*node.Node {
    const ctx = c.ctx;
    const start = ctx.pos;
    while (ctx.pos < ctx.tokens_len) : (ctx.pos += 1) {
        if (lex.isMarker(ctx.tokens[ctx.pos])) break;
    }
    const n = try node.Node.create(c.a(), .text);
    n.tokens = ctx.tokens[start..ctx.pos];
    return n;
}

fn parseBackslash(c: Ctx, block: *node.Node) !?*node.Node {
    const ctx = c.ctx;
    if (ctx.pos == ctx.tokens_len - 1) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .text);
        n.tokens = ctx.tokens[ctx.pos - 1 .. ctx.pos];
        return n;
    }
    ctx.pos += 1;
    const tok = ctx.tokens[ctx.pos];
    if (tok == lex.newline) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .hard_break);
        n.tokens = ctx.tokens[ctx.pos - 1 .. ctx.pos];
        return n;
    }
    if (lex.isASCIIPunct(tok)) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .backslash);
        block.appendChild(n);
        const content = try node.Node.create(c.a(), .backslash_content);
        content.tokens = ctx.tokens[ctx.pos - 1 .. ctx.pos];
        n.appendChild(content);
        return null;
    }
    const n = try node.Node.create(c.a(), .text);
    n.tokens = ctx.tokens[ctx.pos - 1 .. ctx.pos];
    return n;
}

fn parseNewline(c: Ctx, block: *node.Node) !*node.Node {
    const ctx = c.ctx;
    const pos = ctx.pos;
    ctx.pos += 1;
    var is_hard = false;
    if (block.last_child) |lastc| {
        if (lastc.typ == .text and lastc.tokens.len > 0) {
            const orig = lastc.tokens;
            if (orig[orig.len - 1] == lex.space) {
                lastc.tokens = @constCast(lex.trimRight(orig).remains);
                if (orig.len > 1) is_hard = orig[orig.len - 2] == lex.space;
            }
        }
    }
    const ret = try node.Node.create(c.a(), if (is_hard) .hard_break else .soft_break);
    ret.tokens = ctx.tokens[pos .. pos + 1];
    return ret;
}

fn parseEntity(c: Ctx) !*node.Node {
    const ctx = c.ctx;
    const amp = ctx.tokens[ctx.pos .. ctx.pos + 1];
    if (ctx.tokens_len < 2 or ctx.tokens_len <= ctx.pos + 1) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .text);
        n.tokens = amp;
        return n;
    }
    const start = ctx.pos;
    const numeric = ctx.tokens_len > 3 and ctx.tokens[start + 1] == lex.crosshatch;
    var i = ctx.pos;
    var end_semicolon = false;
    while (i < ctx.tokens_len) : (i += 1) {
        const tok = ctx.tokens[i];
        if (lex.isWhitespace(tok)) break;
        if (tok == lex.semicolon) {
            i += 1;
            end_semicolon = true;
            break;
        }
    }
    if (!end_semicolon) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .text);
        n.tokens = amp;
        return n;
    }
    const entity_name = ctx.tokens[start..i];
    if (numeric) {
        if (entity_name.len > 10 or entity_name.len < 4) {
            ctx.pos += 1;
            const n = try node.Node.create(c.a(), .text);
            n.tokens = amp;
            return n;
        }
        if ((entity_name[2] == 'x' or entity_name[2] == 'X') and entity_name.len < 5) {
            ctx.pos += 1;
            const n = try node.Node.create(c.a(), .text);
            n.tokens = amp;
            return n;
        }
    }
    const v = try html.unescapeString(c.a(), entity_name);
    if (std.mem.eql(u8, v, entity_name)) {
        ctx.pos += 1;
        const n = try node.Node.create(c.a(), .text);
        n.tokens = amp;
        return n;
    }
    ctx.pos += i - start;
    const n = try node.Node.create(c.a(), .html_entity);
    n.tokens = v;
    return n;
}

fn parseOpenBracket(c: Ctx, ctx: *InlineContext) !*node.Node {
    const start = ctx.pos;
    ctx.pos += 1;
    const n = try node.Node.create(c.a(), .text);
    n.tokens = ctx.tokens[start..ctx.pos];
    addBracket(c, n, ctx.pos - 1, false, ctx);
    return n;
}

fn parseBang(c: Ctx, block: *node.Node) !?*node.Node {
    const ctx = c.ctx;
    const start = ctx.pos;
    if (ctx.pos + 1 < ctx.tokens_len and ctx.tokens[ctx.pos + 1] == lex.open_bracket) {
        ctx.pos += 2;
        const txt = ctx.tokens[start..ctx.pos];
        const n = try node.Node.create(c.a(), .text);
        n.tokens = txt;
        addBracket(c, n, ctx.pos - 1, true, ctx);
        return n;
    }
    ctx.pos += 1;
    const n = try node.Node.create(c.a(), .text);
    n.tokens = ctx.tokens[start..ctx.pos];
    _ = block;
    return n;
}

fn addBracket(c: Ctx, n: *node.Node, index: usize, image: bool, ctx: *InlineContext) void {
    if (ctx.brackets) |b| b.bracket_after = true;
    const d = c.a().create(delim.Delimiter) catch return;
    d.* = .{
        .node = n,
        .previous = ctx.brackets,
        .previous_delimiter = ctx.delimiters,
        .index = index,
        .image = image,
        .active = true,
        .typ = 0,
        .num = 0,
        .original_num = 0,
        .unit_len = 1,
        .can_open = false,
        .can_close = false,
    };
    ctx.brackets = d;
}

fn removeBracket(ctx: *InlineContext) void {
    if (ctx.brackets) |b| ctx.brackets = b.previous;
}

fn parseCloseBracket(c: Ctx, block: *node.Node) !?*node.Node {
    const ctx = c.ctx;
    const close_bracket = ctx.tokens[ctx.pos .. ctx.pos + 1];
    ctx.pos += 1;
    const start_pos = ctx.pos;
    const opener = ctx.brackets orelse {
        const n = try node.Node.create(c.a(), .text);
        n.tokens = close_bracket;
        return n;
    };
    if (!opener.active) {
        removeBracket(ctx);
        const n = try node.Node.create(c.a(), .text);
        n.tokens = close_bracket;
        return n;
    }
    const is_image = opener.image;
    var open_paren: []u8 = &.{};
    var dest: []u8 = &.{};
    var space: []u8 = &.{};
    var title: []u8 = &.{};
    var close_paren: []u8 = &.{};
    const savepos = ctx.pos;
    var matched = false;
    var link_type: u8 = 0;
    var reflabel: []u8 = &.{};

    if (ctx.pos + 1 < ctx.tokens_len and ctx.tokens[ctx.pos] == lex.open_paren) {
        var remains: []u8 = ctx.tokens[ctx.pos..];
        outer: while (true) {
            const sp = spnl(remains);
            if (!sp.ok) break;
            remains = sp.remains;
            const id = try links.parseInlineLinkDest(c.a(), c.t.context.options, remains);
            if (id.passed == null) break;
            const passed = id.passed.?;
            remains = id.remains;
            dest = id.destination;
            if (passed.len == 0) break;
            open_paren = passed[0..1];
            close_paren = passed[passed.len - 1 ..];
            matched = passed[passed.len - 1] == lex.close_paren;
            if (matched and remains.len > 1) {
                matched = !lex.isWhitespace(remains[0]) and remains[1] != lex.doublequote;
            }
            if (matched) break;
            if (remains.len < 1 or !lex.isWhitespace(remains[0])) break;
            const sp2 = spnl(remains);
            if (!sp2.ok) break;
            space = sp2.passed;
            remains = sp2.remains;
            if (remains.len == 0) break;
            matched = remains[0] == lex.close_paren;
            close_paren = remains[0..1];
            if (matched) break;
            const tt = try links.parseLinkTitle(c.a(), remains);
            if (!tt.valid) break;
            title = tt.title;
            remains = tt.remains;
            const sp3 = spnl(remains);
            remains = sp3.remains;
            matched = sp3.ok and remains.len > 0;
            if (remains.len > 0) close_paren = remains;
            if (matched) matched = remains[0] == lex.close_paren;
            break :outer;
        }
        if (matched) {
            var end_ptr = remains.ptr;
            if (remains.len > 0 and remains[0] == lex.close_paren) end_ptr += 1;
            ctx.pos = @intFromPtr(end_ptr) - @intFromPtr(ctx.tokens.ptr);
        } else {
            ctx.pos = savepos;
        }
    }
    if (!matched) {
        const beforelabel = ctx.pos;
        var n: usize = 0;
        if (try links.parseLinkLabel(c.a(), ctx.tokens[beforelabel..])) |lab| {
            n = lab.n;
            if (lab.n > 2) {
                reflabel = lab.label;
                ctx.pos += lab.n;
            }
        }
        if (n <= 2) {
            if (!opener.bracket_after) {
                var start = opener.index;
                if (ctx.tokens[start] == lex.open_bracket) start += 1;
                reflabel = ctx.tokens[start .. start_pos - 1];
                ctx.pos += 2;
            }
            if (n == 0) ctx.pos = start_pos;
        }
        if (reflabel.len != 0) {
            const folded = try links.foldLabel(c.a(), reflabel);
            if (c.t.context.refs.get(folded)) |ref| {
                dest = ref.dest;
                if (ref.title.len != 0) title = ref.title;
                matched = true;
                link_type = 3;
            }
        }
    }
    if (matched) {
        const link = try node.Node.create(c.a(), if (is_image) .image else .link);
        link.link_type = link_type;
        link.link_ref_label = reflabel;
        if (is_image) {
            const bang = try node.Node.create(c.a(), .bang);
            bang.tokens = opener.node.tokens[0..1];
            opener.node.tokens = opener.node.tokens[1..];
            link.appendChild(bang);
        }
        const ob = try node.Node.create(c.a(), .open_bracket);
        ob.tokens = opener.node.tokens;
        link.appendChild(ob);
        var tmp = opener.node.next;
        while (tmp) |x| {
            const next = x.next;
            x.unlink();
            if (x.typ == .text) x.typ = .link_text;
            link.appendChild(x);
            tmp = next;
        }
        const cb = try node.Node.create(c.a(), .close_bracket);
        cb.tokens = close_bracket;
        link.appendChild(cb);
        const op = try node.Node.create(c.a(), .open_paren);
        op.tokens = open_paren;
        link.appendChild(op);
        const ld = try node.Node.create(c.a(), .link_dest);
        ld.tokens = dest;
        link.appendChild(ld);
        if (space.len != 0) {
            const sp = try node.Node.create(c.a(), .link_space);
            sp.tokens = space;
            link.appendChild(sp);
        }
        if (title.len != 0) {
            const lt = try node.Node.create(c.a(), .link_title);
            lt.tokens = title;
            link.appendChild(lt);
        }
        const cp = try node.Node.create(c.a(), .close_paren);
        cp.tokens = close_paren;
        link.appendChild(cp);
        try delim.processEmphasis(c.dctx(), opener.previous_delimiter);
        removeBracket(ctx);
        opener.node.unlink();
        if (!is_image) {
            var b = ctx.brackets;
            while (b) |bb| : (b = bb.previous) if (!bb.image) {
                bb.active = false;
            };
        }
        _ = block;
        return link;
    } else {
        removeBracket(ctx);
        ctx.pos = start_pos;
        const n = try node.Node.create(c.a(), .text);
        n.tokens = close_bracket;
        return n;
    }
}

const Spnl = struct { ok: bool = false, passed: []u8 = &.{}, remains: []u8 = &.{} };

fn spnl(tokens: []u8) Spnl {
    const tr = lex.trimLeft(tokens);
    const st = lex.statWhitespace(tr.whitespace);
    if (st.newlines > 1) return .{};
    return .{ .ok = true, .passed = @constCast(tr.whitespace), .remains = @constCast(tr.remains) };
}

fn parseCodeSpan(c: Ctx, block: *node.Node) !?*node.Node {
    const ctx = c.ctx;
    const start_pos = ctx.pos;
    var n: usize = 0;
    while (start_pos + n < ctx.tokens_len and ctx.tokens[start_pos + n] == lex.backtick) n += 1;
    const backticks = ctx.tokens[start_pos .. start_pos + n];
    if (ctx.tokens_len <= start_pos + n) {
        ctx.pos += n;
        const t = try node.Node.create(c.a(), .text);
        t.tokens = backticks;
        return t;
    }
    const open_marker = try node.Node.create(c.a(), .code_span_open_marker);
    open_marker.tokens = backticks;
    const end_pos = matchCodeSpanEnd(ctx.tokens[start_pos + n ..], n);
    if (end_pos < 1) {
        ctx.pos += n;
        const t = try node.Node.create(c.a(), .text);
        t.tokens = backticks;
        return t;
    }
    const end_abs: usize = start_pos + @as(usize, @intCast(end_pos)) + n;
    const close_marker = try node.Node.create(c.a(), .code_span_close_marker);
    close_marker.tokens = ctx.tokens[end_abs .. end_abs + n];
    var text_tokens = ctx.tokens[start_pos + n .. end_abs];
    text_tokens = lex.replaceAll(text_tokens, lex.newline, lex.space);
    if (text_tokens.len > 2 and text_tokens[0] == lex.space and text_tokens[text_tokens.len - 1] == lex.space and !lex.isBlankLine(text_tokens)) {
        open_marker.tokens = try std.mem.concat(c.a(), u8, &.{ open_marker.tokens, text_tokens[0..1] });
        close_marker.tokens = ctx.tokens[end_abs - 1 .. end_abs + n];
        text_tokens = text_tokens[1 .. text_tokens.len - 1];
    }
    if (c.t.context.options.gfm_table and block.typ == .table_cell) {
        if (std.mem.indexOf(u8, text_tokens, "\\|")) |_| text_tokens = try blocks.replaceAll(c.a(), text_tokens, "\\|", "|");
    }
    const ret = try node.Node.create(c.a(), .code_span);
    ret.code_marker_len = @intCast(n);
    ret.appendChild(open_marker);
    const content = try node.Node.create(c.a(), .code_span_content);
    content.tokens = text_tokens;
    ret.appendChild(content);
    ret.appendChild(close_marker);
    ctx.pos = end_abs + n;
    return ret;
}

fn matchCodeSpanEnd(tokens: []const u8, num: usize) isize {
    var pos: usize = 0;
    while (pos < tokens.len) {
        const l = lex.accept(tokens[pos..], lex.backtick);
        if (num == l) {
            const next = pos + l;
            if (tokens.len > next + 1 and tokens[next] == lex.backtick) {
                pos += l;
                continue;
            }
            return @intCast(pos);
        }
        if (l > 0) pos += l else pos += 1;
    }
    return -1;
}

pub fn mergeText(allocator: std.mem.Allocator, n: *node.Node) !void {
    var child = n.first_child;
    while (child) |ch| {
        if (ch.typ == .text) {
            if (ch.next) |nx| {
                if (nx.typ == .text) {
                    var total = ch.tokens.len;
                    var x: ?*node.Node = nx;
                    while (x) |xx| {
                        if (xx.typ != .text) break;
                        total += xx.tokens.len;
                        x = xx.next;
                    }
                    var merged: std.ArrayListUnmanaged(u8) = .empty;
                    try merged.ensureTotalCapacity(allocator, total);
                    try merged.appendSlice(allocator, ch.tokens);
                    var cur: ?*node.Node = nx;
                    while (cur) |xx| {
                        if (xx.typ != .text) break;
                        try merged.appendSlice(allocator, xx.tokens);
                        const nxt = xx.next;
                        xx.unlink();
                        cur = nxt;
                    }
                    ch.tokens = try merged.toOwnedSlice(allocator);
                }
            }
        } else if (ch.typ == .link_text) {
            if (ch.next) |nx| {
                if (nx.typ == .link_text) {
                    var merged: std.ArrayListUnmanaged(u8) = .empty;
                    try merged.appendSlice(allocator, ch.tokens);
                    var cur: ?*node.Node = nx;
                    while (cur) |xx| {
                        if (xx.typ != .link_text) break;
                        try merged.appendSlice(allocator, xx.tokens);
                        const nxt = xx.next;
                        xx.unlink();
                        cur = nxt;
                    }
                    ch.tokens = try merged.toOwnedSlice(allocator);
                }
            }
        } else {
            try mergeText(allocator, ch);
        }
        child = ch.next;
    }
}

test "mergeText merges adjacent text nodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p = try node.Node.create(a, .paragraph);
    for ([_][]const u8{ "a", "b", "c" }) |s| {
        const t = try node.Node.create(a, .text);
        t.tokens = try a.dupe(u8, s);
        p.appendChild(t);
    }
    try mergeText(a, p);
    try std.testing.expectEqualStrings("abc", p.first_child.?.tokens);
    try std.testing.expect(p.first_child.?.next == null);
}
