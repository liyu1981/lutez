//! Inline HTML scanning (lexical only; emits NodeInlineHTML with raw tokens).
//! Ported from lute/parse/inline_html.go @ v1.7.8 (Mulan PSL v2), scope-trimmed.
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const tree = @import("tree.zig");
const inl = @import("inline.zig");

pub fn parseInlineHTML(t: *tree.Tree, ctx: *inl.InlineContext) !?*node.Node {
    const tokens = ctx.tokens;
    const start_pos = ctx.pos;
    if (tokens.len < 3 or tokens.len <= start_pos + 1) {
        return try failText(t, ctx, start_pos);
    }
    var tags: std.ArrayListUnmanaged(u8) = .empty;
    try tags.append(t.allocator, tokens[start_pos]);
    var idx: usize = start_pos + 1;
    if (tokens[idx] == lex.slash) {
        try tags.append(t.allocator, tokens[idx]);
        idx += 1;
        const nm = parseTagName(tokens[idx..]) orelse {
            return try failText(t, ctx, start_pos);
        };
        try tags.appendSlice(t.allocator, nm.name);
        idx += nm.consumed;
    } else if (parseTagName(tokens[idx..])) |nm| {
        try tags.appendSlice(t.allocator, nm.name);
        idx += nm.consumed;
        while (true) {
            const attr = TagAttr(tokens[idx..]) orelse {
                return try failText(t, ctx, start_pos);
            };
            idx += attr.consumed;
            try tags.appendSlice(t.allocator, attr.bytes);
            if (attr.bytes.len == 0) break;
        }
    } else {
        if (try parseSpecial(t, ctx, start_pos, &tags)) |n| return n;
        return try failText(t, ctx, start_pos);
    }
    const tr = lex.trimLeft(tokens[idx..]);
    idx += tr.whitespace.len;
    const rest = tr.remains;
    if (rest.len == 0) {
        return try failText(t, ctx, start_pos);
    }
    if (rest[0] == lex.greater) {
        try tags.appendSlice(t.allocator, tr.whitespace);
        try tags.append(t.allocator, lex.greater);
        idx += 1;
    } else if (rest.len > 1 and rest[0] == lex.slash and rest[1] == lex.greater) {
        try tags.appendSlice(t.allocator, tr.whitespace);
        try tags.appendSlice(t.allocator, "/>");
        idx += 2;
    } else {
        return try failText(t, ctx, start_pos);
    }
    const n = try node.Node.create(t.allocator, .inline_html);
    n.tokens = try tags.toOwnedSlice(t.allocator);
    ctx.pos = idx;
    return n;
}

fn failText(t: *tree.Tree, ctx: *inl.InlineContext, start_pos: usize) !*node.Node {
    ctx.pos = start_pos + 1;
    const n = try node.Node.create(t.allocator, .text);
    n.tokens = ctx.tokens[start_pos..ctx.pos];
    return n;
}

fn parseSpecial(t: *tree.Tree, ctx: *inl.InlineContext, start_pos: usize, tags: *std.ArrayListUnmanaged(u8)) !?*node.Node {
    const tokens = ctx.tokens;
    const idx = start_pos + 1;
    if (parseComment(tokens[idx..])) |c| {
        try tags.appendSlice(t.allocator, c.bytes);
        const n = try node.Node.create(t.allocator, .inline_html);
        n.tokens = try tags.toOwnedSlice(t.allocator);
        ctx.pos = idx + c.consumed;
        return n;
    }
    if (parsePI(tokens[idx..])) |p| {
        try tags.appendSlice(t.allocator, p.bytes);
        const n = try node.Node.create(t.allocator, .inline_html);
        n.tokens = try tags.toOwnedSlice(t.allocator);
        ctx.pos = idx + p.consumed;
        return n;
    }
    if (parseDecl(tokens[idx..])) |d| {
        try tags.appendSlice(t.allocator, d.bytes);
        const n = try node.Node.create(t.allocator, .inline_html);
        n.tokens = try tags.toOwnedSlice(t.allocator);
        ctx.pos = idx + d.consumed;
        return n;
    }
    if (parseCDATA(tokens[idx..])) |c| {
        try tags.appendSlice(t.allocator, c.bytes);
        const n = try node.Node.create(t.allocator, .inline_html);
        n.tokens = try tags.toOwnedSlice(t.allocator);
        ctx.pos = idx + c.consumed;
        return n;
    }
    return null;
}

const Part = struct { bytes: []const u8, consumed: usize };

fn parseTagName(tokens: []const u8) ?struct { name: []const u8, consumed: usize } {
    if (tokens.len == 0 or !lex.isASCIILetter(tokens[0])) return null;
    var i: usize = 1;
    while (i < tokens.len and lex.isASCIILetterNumHyphen(tokens[i])) i += 1;
    return .{ .name = tokens[0..i], .consumed = i };
}

const Attr = struct { bytes: []const u8, consumed: usize };

fn TagAttr(tokens: []const u8) ?Attr {
    var i: usize = 0;
    while (i < tokens.len and lex.isWhitespace(tokens[i])) i += 1;
    if (i == 0) return .{ .bytes = tokens[0..0], .consumed = 0 }; // attributes need leading whitespace
    if (i >= tokens.len) return .{ .bytes = tokens[0..0], .consumed = 0 };
    if (!lex.isASCIILetter(tokens[i]) and tokens[i] != lex.underscore and tokens[i] != lex.colon) {
        return .{ .bytes = tokens[0..0], .consumed = 0 };
    }
    i += 1;
    while (i < tokens.len and (lex.isASCIILetter(tokens[i]) or lex.isDigit(tokens[i]) or tokens[i] == lex.underscore or tokens[i] == lex.dot or tokens[i] == lex.colon or tokens[i] == lex.hyphen)) i += 1;
    const name_end = i;
    var j = i;
    while (j < tokens.len and lex.isWhitespace(tokens[j])) j += 1;
    if (j < tokens.len and tokens[j] == lex.equal) {
        j += 1;
        while (j < tokens.len and lex.isWhitespace(tokens[j])) j += 1;
        if (j >= tokens.len) return null;
        const q = tokens[j];
        if (q == '\'' or q == '"') {
            j += 1;
            while (j < tokens.len and tokens[j] != q) j += 1;
            if (j >= tokens.len) return null;
            j += 1;
        } else {
            const vs = j;
            while (j < tokens.len and !lex.isWhitespace(tokens[j]) and tokens[j] != '"' and tokens[j] != '\'' and tokens[j] != '=' and tokens[j] != '<' and tokens[j] != '>' and tokens[j] != '`') j += 1;
            if (j == vs) return null;
        }
        return .{ .bytes = tokens[0..j], .consumed = j };
    }
    return .{ .bytes = tokens[0..name_end], .consumed = name_end };
}

fn parseComment(tokens: []const u8) ?Part {
    if (tokens.len < 4 or !std.mem.startsWith(u8, tokens, "!--")) return null;
    var i: usize = 0;
    while (i + 3 <= tokens.len) : (i += 1) {
        if (tokens[i] == '-' and tokens[i + 1] == '-' and tokens[i + 2] == '>') {
            return .{ .bytes = tokens[0 .. i + 3], .consumed = i + 3 };
        }
    }
    return null;
}

fn parsePI(tokens: []const u8) ?Part {
    if (tokens.len < 3 or tokens[0] != lex.question) return null;
    var i: usize = 1;
    while (i + 2 <= tokens.len) : (i += 1) {
        if (tokens[i] == lex.question and tokens[i + 1] == lex.greater) {
            return .{ .bytes = tokens[0 .. i + 2], .consumed = i + 2 };
        }
    }
    return null;
}

fn parseDecl(tokens: []const u8) ?Part {
    if (tokens.len < 3 or tokens[0] != lex.bang or !(tokens[1] >= 'A' and tokens[1] <= 'Z')) return null;
    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i] == lex.greater) return .{ .bytes = tokens[0 .. i + 1], .consumed = i + 1 };
    }
    return null;
}

fn parseCDATA(tokens: []const u8) ?Part {
    if (tokens.len < 9 or !std.mem.startsWith(u8, tokens, "![CDATA[")) return null;
    var i: usize = 8;
    while (i + 3 <= tokens.len) : (i += 1) {
        if (tokens[i] == ']' and tokens[i + 1] == ']' and tokens[i + 2] == '>') {
            return .{ .bytes = tokens[0 .. i + 3], .consumed = i + 3 };
        }
    }
    return null;
}
