//! Emphasis/strong/strikethrough delimiter stack.
//! Ported from lute/parse/delimiter.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const uni = @import("../unicode/unicode.zig");

pub const Delimiter = struct {
    node: *node.Node,
    typ: u8,
    num: usize,
    original_num: usize,
    unit_len: usize,
    can_open: bool,
    can_close: bool,
    previous: ?*Delimiter = null,
    next: ?*Delimiter = null,
    active: bool = true,
    image: bool = false,
    bracket_after: bool = false,
    index: usize = 0,
    previous_delimiter: ?*Delimiter = null,
};

pub const InlineContext = struct {
    tokens: []u8,
    tokens_len: usize,
    pos: usize = 0,
    delimiters: ?*Delimiter = null,
    brackets: ?*Delimiter = null,

    /// Inline position provenance (see `Node.token_map`).
    token_buffer: []u8 = &.{},
    token_map: []const node.TokenSeg = &.{},

    pub fn spanFor(self: *InlineContext, start: usize, end: usize) ?node.Span {
        if (start >= end or end > self.tokens.len) return null;
        return node.mapTokenSlice(self.token_buffer, self.token_map, self.tokens[start..end]);
    }

    pub fn setSpanFor(self: *InlineContext, n: *node.Node, start: usize, end: usize) void {
        if (self.spanFor(start, end)) |sp| n.setSpan(sp.start, sp.end) else n.setDerivedSpan(self.sourcePos(start));
    }

    pub fn sourcePos(self: *InlineContext, pos: usize) u32 {
        if (self.token_map.len == 0 or self.tokens.len == 0) return 0;
        const p = @min(pos, self.tokens.len);
        if (p < self.tokens.len) {
            if (node.mapTokenSlice(self.token_buffer, self.token_map, self.tokens[p .. p + 1])) |sp| return sp.start;
        }
        if (node.mapTokenSlice(self.token_buffer, self.token_map, self.tokens[self.tokens.len - 1 ..])) |sp| return sp.end;
        return 0;
    }
};

const Ctx = struct {
    allocator: std.mem.Allocator,
    options: @import("../types.zig").Options,
    ictx: *InlineContext,
};

pub fn handleDelim(c: Ctx, block: *node.Node) !void {
    const start_pos = c.ictx.pos;
    const marker = c.ictx.tokens[start_pos];
    const scanned = scanDelims(c, marker);
    const text = c.ictx.tokens[start_pos..c.ictx.pos];
    const n = try node.Node.create(c.allocator, .text);
    n.tokens = text;
    c.ictx.setSpanFor(n, start_pos, c.ictx.pos);
    block.appendChild(n);
    if (scanned.can_open or scanned.can_close) {
        const d = try c.allocator.create(Delimiter);
        d.* = .{
            .node = n,
            .typ = marker,
            .num = scanned.count,
            .original_num = scanned.count,
            .unit_len = 1,
            .can_open = scanned.can_open,
            .can_close = scanned.can_close,
            .previous = c.ictx.delimiters,
        };
        if (c.ictx.delimiters) |prev| prev.next = d;
        c.ictx.delimiters = d;
    }
}

const Scan = struct { count: usize = 0, can_open: bool = false, can_close: bool = false };

fn scanDelims(c: Ctx, typ: u8) Scan {
    const ctx = c.ictx;
    const start_pos = ctx.pos;
    var count: usize = 0;
    while (ctx.pos < ctx.tokens_len and ctx.tokens[ctx.pos] == typ) : (ctx.pos += 1) count += 1;

    var before: u21 = lex.newline;
    var after: u21 = lex.newline;
    if (start_pos > 0) {
        const d = uni.decodeLastRune(ctx.tokens[0..start_pos]);
        before = d;
    }
    if (ctx.tokens_len > ctx.pos) {
        after = uni.decodeRune(ctx.tokens[ctx.pos..]).r;
    }
    const after_ws = uni.isSpace(after);
    var after_punct = uni.isPunct(after) or uni.isSymbol(after);
    const before_ws = uni.isSpace(before);
    var before_punct = uni.isPunct(before) or uni.isSymbol(before);
    if ((typ == lex.asterisk and after == '~') or (typ == lex.tilde and after == '*') or
        (typ == lex.tilde and (after == '+' or after == '-')))
    {
        after_punct = false;
    }
    if ((typ == lex.asterisk and before == '~') or (typ == lex.tilde and before == '*') or
        (typ == lex.tilde and (before == '+' or before == '-')))
    {
        before_punct = false;
    }
    const left = !after_ws and (!after_punct or before_ws or before_punct);
    const right = !before_ws and (!before_punct or after_ws or after_punct);
    var can_open = left;
    var can_close = right;
    if (typ == lex.underscore) {
        can_open = left and (!right or before_punct);
        can_close = right and (!left or after_punct);
    } else if (typ == lex.tilde) {
        if (c.options.gfm_strikethrough) {
            if (count == 1) {
                if (!c.options.gfm_strikethrough1) {
                    can_open = false;
                    can_close = false;
                }
            }
        }
        // When GFM strikethrough is off, delimiters still enter the stack but are
        // never matched in processEmphasis (mirrors upstream).
    }
    return .{ .count = count, .can_open = can_open, .can_close = can_close };
}

fn removeDelimiter(delim: *Delimiter, ctx: *InlineContext) void {
    if (delim.previous) |p| p.next = delim.next;
    if (delim.next) |n| {
        n.previous = delim.previous;
    } else {
        ctx.delimiters = delim.previous;
    }
}

pub fn processEmphasis(c: Ctx, stack_bottom: ?*Delimiter) !void {
    const ctx = c.ictx;
    if (ctx.delimiters == null) return;
    var openers_bottom: [128]?*Delimiter = @splat(null);
    openers_bottom[lex.underscore] = stack_bottom;
    openers_bottom[lex.asterisk] = stack_bottom;
    openers_bottom[lex.tilde] = stack_bottom;

    var closer: ?*Delimiter = ctx.delimiters;
    while (closer) |cl| {
        if (cl.previous == stack_bottom) break;
        closer = cl.previous;
    }
    while (closer) |cl| {
        if (!cl.can_close) {
            closer = cl.next;
            continue;
        }
        const cc = cl.typ;
        var opener: ?*Delimiter = cl.previous;
        var opener_found = false;
        var odd_match = false;
        while (opener) |op| {
            if (op == stack_bottom) break;
            if (openers_bottom[cc]) |ob| if (op == ob) break;
            odd_match = (cl.can_open or op.can_close) and cl.original_num % 3 != 0 and (op.original_num + cl.original_num) % 3 == 0;
            if (op.typ == cc and op.can_open and !odd_match) {
                opener_found = true;
                break;
            }
            opener = op.previous;
        }
        const old_closer = cl;
        if (!opener_found) {
            closer = cl.next;
        } else {
            const op = opener.?;
            var use_delims: usize = if (cl.num >= 2 and op.num >= 2) 2 else 1;
            if (cc == lex.tilde and c.options.gfm_strikethrough and op.num != cl.num) {
                closer = cl.next;
                continue;
            }
            if (cc == lex.asterisk and !c.options.inline_asterisk) {
                closer = cl.next;
                continue;
            }
            if (cc == lex.underscore and !c.options.inline_underscore) {
                closer = cl.next;
                continue;
            }
            if (cc == lex.tilde and !c.options.gfm_strikethrough) {
                closer = cl.next;
                continue;
            }
            if (cc == lex.tilde and use_delims == 1 and !c.options.gfm_strikethrough1) {
                closer = cl.next;
                continue;
            }
            if (op.num < use_delims or cl.num < use_delims) use_delims = @min(op.num, cl.num);

            op.num -= use_delims;
            cl.num -= use_delims;
            const opener_tokens = op.node.tokens[op.node.tokens.len - use_delims * op.unit_len ..];
            op.node.tokens = op.node.tokens[0 .. op.node.tokens.len - use_delims * op.unit_len];
            const closer_tokens = cl.node.tokens[cl.node.tokens.len - use_delims * cl.unit_len ..];
            cl.node.tokens = cl.node.tokens[0 .. cl.node.tokens.len - use_delims * cl.unit_len];

            var em_type: @import("../types.zig").NodeType = .document;
            var open_type: @import("../types.zig").NodeType = .document;
            var close_type: @import("../types.zig").NodeType = .document;
            if (use_delims == 1) {
                switch (cc) {
                    lex.asterisk => {
                        em_type = .emphasis;
                        open_type = .em_a6k_open_marker;
                        close_type = .em_a6k_close_marker;
                    },
                    lex.underscore => {
                        em_type = .emphasis;
                        open_type = .em_u8e_open_marker;
                        close_type = .em_u8e_close_marker;
                    },
                    lex.tilde => if (c.options.gfm_strikethrough and c.options.gfm_strikethrough1) {
                        em_type = .strikethrough;
                        open_type = .strikethrough1_open_marker;
                        close_type = .strikethrough1_close_marker;
                    },
                    else => {},
                }
            } else {
                switch (cc) {
                    lex.asterisk => {
                        em_type = .strong;
                        open_type = .strong_a6k_open_marker;
                        close_type = .strong_a6k_close_marker;
                    },
                    lex.underscore => {
                        em_type = .strong;
                        open_type = .strong_u8e_open_marker;
                        close_type = .strong_u8e_close_marker;
                    },
                    lex.tilde => if (c.options.gfm_strikethrough) {
                        em_type = .strikethrough;
                        open_type = .strikethrough2_open_marker;
                        close_type = .strikethrough2_close_marker;
                    },
                    else => {},
                }
            }
            if (em_type == .document) {
                closer = cl.next;
                continue;
            }
            const em = try node.Node.create(c.allocator, em_type);
            var tmp = op.node.next;
            while (tmp) |nn| {
                if (nn == cl.node) break;
                const nxt = nn.next;
                em.appendChild(nn);
                tmp = nxt;
            }
            const open_marker = try node.Node.create(c.allocator, open_type);
            open_marker.tokens = @constCast(opener_tokens);
            open_marker.close = true;
            em.prependChild(open_marker);
            const close_marker = try node.Node.create(c.allocator, close_type);
            close_marker.tokens = @constCast(closer_tokens);
            close_marker.close = true;
            em.appendChild(close_marker);
            op.node.insertAfter(em);

            if (op.next != cl) {
                op.next = cl;
                cl.previous = op;
            }
            if (op.num == 0) {
                op.node.unlink();
                removeDelimiter(op, ctx);
            }
            if (cl.num == 0) {
                cl.node.unlink();
                const next = cl.next;
                removeDelimiter(cl, ctx);
                closer = next;
            }
            // If delimiters remain, stay on this closer so it can match again.
        }
        if (!opener_found and !odd_match) {
            openers_bottom[cc] = old_closer.previous;
            if (!old_closer.can_open) removeDelimiter(old_closer, ctx);
        }
    }
    while (ctx.delimiters) |d| {
        if (d == stack_bottom) break;
        removeDelimiter(d, ctx);
    }
}

pub const DelimCtx = Ctx;
