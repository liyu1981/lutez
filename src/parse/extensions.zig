//! Inline extension presets (math, wikilinks, tags, Obsidian block IDs).
//! See doc/EXTENSIONS_DESIGN.md. Block-level presets live in tree/blocks.zig.
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const uni = @import("../unicode/unicode.zig");
const types = @import("../types.zig");
const delim = @import("delimiter.zig");

pub fn isTrigger(mask: u32, b: u8) bool {
    if (mask == 0) return false;
    if (b == '$' and mask & types.ExtensionMask.math != 0) return true;
    if (b == '[' and mask & types.ExtensionMask.wiki_links != 0) return true;
    if (b == '#' and mask & types.ExtensionMask.tags != 0) return true;
    if (b == '^' and mask & types.ExtensionMask.outliner_blocks != 0) return true;
    return false;
}

/// Tries an inline extension at `ctx.pos`. On success consumes it and returns the node.
pub fn tryInline(allocator: std.mem.Allocator, mask: u32, ctx: *delim.InlineContext) !?*node.Node {
    const tok = ctx.tokens[ctx.pos];
    if (tok == '$' and mask & types.ExtensionMask.math != 0) return tryInlineMath(allocator, ctx);
    if (tok == '[' and mask & types.ExtensionMask.wiki_links != 0) return tryWikiLink(allocator, ctx);
    if (tok == '#' and mask & types.ExtensionMask.tags != 0) return tryTag(allocator, ctx);
    if (tok == '^' and mask & types.ExtensionMask.outliner_blocks != 0) return tryObsidianBlockId(allocator, ctx);
    return null;
}

fn finish(allocator: std.mem.Allocator, ctx: *delim.InlineContext, typ: types.NodeType, kind: u32, flags: u16, start: usize, end: usize, payload_start: usize, payload_end: usize) !*node.Node {
    const n = try node.Node.create(allocator, typ);
    n.ext_kind = kind;
    n.ext_flags = flags;
    n.tokens = ctx.tokens[payload_start..payload_end];
    if (ctx.spanFor(start, end)) |sp| n.setSpan(sp.start, sp.end) else n.setDerivedSpan(ctx.sourcePos(start));
    ctx.pos = end;
    return n;
}

fn tryInlineMath(allocator: std.mem.Allocator, ctx: *delim.InlineContext) !?*node.Node {
    const start = ctx.pos;
    var count: usize = 0;
    while (start + count < ctx.tokens_len and ctx.tokens[start + count] == '$') count += 1;
    if (count == 0 or count > 2) return null;
    if (start + count >= ctx.tokens_len) return null;
    const first = ctx.tokens[start + count];
    if (lex.isWhitespace(first)) return null;

    var i = start + count;
    while (i < ctx.tokens_len) {
        const b = ctx.tokens[i];
        if (b == '\\' and i + 1 < ctx.tokens_len) {
            i += 2;
            continue;
        }
        if (b == '\n') return null;
        if (b == '$') {
            var run: usize = 0;
            while (i + run < ctx.tokens_len and ctx.tokens[i + run] == '$') run += 1;
            if (run == count and i > start + count and !lex.isWhitespace(ctx.tokens[i - 1])) {
                const flags: u16 = if (count == 2) types.ExtensionFlags.display_math else 0;
                return try finish(allocator, ctx, .inline_extension, types.ExtensionKind.math, flags, start, i + run, start + count, i);
            }
            i += run;
            continue;
        }
        i += 1;
    }
    return null;
}

fn tryWikiLink(allocator: std.mem.Allocator, ctx: *delim.InlineContext) !?*node.Node {
    const start = ctx.pos;
    if (start + 1 >= ctx.tokens_len or ctx.tokens[start + 1] != '[') return null;
    var i = start + 2;
    while (i + 1 < ctx.tokens_len) {
        const b = ctx.tokens[i];
        if (b == '\n') return null;
        if (b == '[' and ctx.tokens[i + 1] == '[') return null; // no nesting
        if (b == ']' and ctx.tokens[i + 1] == ']') {
            if (i == start + 2) return null;
            return try finish(allocator, ctx, .inline_extension, types.ExtensionKind.wiki_link, 0, start, i + 2, start + 2, i);
        }
        i += 1;
    }
    return null;
}

fn tryTag(allocator: std.mem.Allocator, ctx: *delim.InlineContext) !?*node.Node {
    const start = ctx.pos;
    if (start > 0) {
        const prev = uni.decodeLastRune(ctx.tokens[0..start]);
        if (uni.isAlnum(prev) or prev == '_' or prev == '/' or prev == '.' or prev == ':' or prev == '#') return null;
    }
    var i = start + 1;
    var all_digits = true;
    var chars: usize = 0;
    while (i < ctx.tokens_len) {
        const d = uni.decodeRune(ctx.tokens[i..]);
        if (uni.isLetter(d.r) or uni.isDigit(d.r) or d.r == '_' or d.r == '-' or d.r == '/') {
            if (!uni.isDigit(d.r)) all_digits = false;
            chars += 1;
            i += d.len;
            continue;
        }
        break;
    }
    if (chars == 0 or all_digits) return null;
    return try finish(allocator, ctx, .inline_extension, types.ExtensionKind.tag, 0, start, i, start + 1, i);
}

fn tryObsidianBlockId(allocator: std.mem.Allocator, ctx: *delim.InlineContext) !?*node.Node {
    const start = ctx.pos;
    if (start > 0 and !lex.isWhitespace(ctx.tokens[start - 1])) return null;
    var i = start + 1;
    while (i < ctx.tokens_len) {
        const b = ctx.tokens[i];
        if (lex.isASCIILetterNumHyphen(b)) {
            i += 1;
            continue;
        }
        break;
    }
    if (i == start + 1) return null;
    var j = i;
    while (j < ctx.tokens_len and lex.isWhitespace(ctx.tokens[j])) j += 1;
    if (j != ctx.tokens_len) return null; // must end the block
    return try finish(allocator, ctx, .inline_extension, types.ExtensionKind.obsidian_block_id, 0, start, i, start + 1, i);
}
