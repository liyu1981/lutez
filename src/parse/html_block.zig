//! CommonMark HTML blocks types 1-7: lexical scanning only (raw text nodes).
//! Ported from lute/parse/html_block.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const tree = @import("tree.zig");

const tags1 = [_][]const u8{ "<script", "<pre", "<style", "<textarea" };
const close_tags1 = [_][]const u8{ "</script>", "</pre>", "</style>", "</textarea>" };

const tags6 = [_][]const u8{
    "<address",  "<article",  "<aside",     "<base",        "<basefont",  "<blockquote", "<body",     "<caption",   "<center",    "<col",
    "<colgroup", "<dd",       "<details",   "<dialog",      "<dir",       "<div",        "<dl",       "<dt",        "<fieldset",  "<figcaption",
    "<figure",   "<footer",   "<form",      "<frame",       "<frameset",  "<h1",         "<h2",       "<h3",        "<h4",        "<h5",
    "<h6",       "<head",     "<header",    "<hr",          "<html",      "<iframe",     "<legend",   "<li",        "<link",      "<main",
    "<menu",     "<menuitem", "<nav",       "<noframes",    "<ol",        "<optgroup",   "<option",   "<p",         "<param",     "<section",
    "<source",   "<summary",  "<table",     "<tbody",       "<td",        "<tfoot",      "<th",       "<thead",     "<title",     "<tr",
    "<track",    "<ul",       "<video",     "<audio",       "</address",  "</article",   "</aside",   "</base",     "</basefont", "</blockquote",
    "</body",    "</caption", "</center",   "</col",        "</colgroup", "</dd",        "</details", "</dialog",   "</dir",      "</div",
    "</dl",      "</dt",      "</fieldset", "</figcaption", "</figure",   "</footer",    "</form",    "</frame",    "</frameset", "</h1",
    "</h2",      "</h3",      "</h4",       "</h5",         "</h6",       "</head",      "</header",  "</hr",       "</html",     "</iframe",
    "</legend",  "</li",      "</link",     "</main",       "</menu",     "</menuitem",  "</nav",     "</noframes", "</ol",       "</optgroup",
    "</option",  "</p",       "</param",    "</section",    "</source",   "</summary",   "</table",   "</tbody",    "</td",       "</tfoot",
    "</th",      "</thead",   "</title",    "</tr",         "</track",    "</ul",        "</video",   "</audio",
};

pub fn start(t: *tree.Tree, container: *node.Node) !u8 {
    _ = container;
    const ctx = t.context;
    if (ctx.indented) return 0;
    if (lex.peek(ctx.current_line, ctx.next_nonspace) != lex.less) return 0;
    const tokens = ctx.current_line[ctx.next_nonspace..];
    const html_type = parseHTML(t, tokens);
    if (html_type == 0) return 0;
    const pos = ctx.abs(ctx.next_nonspace);
    ctx.closeUnmatchedBlocks();
    const block = try ctx.addChild(.html_block);
    block.html_block_type = html_type;
    block.setSpan(pos, ctx.line_trimmed_end_norm);
    return 2;
}

pub fn continueBlock(n: *node.Node, ctx: *tree.Context) u8 {
    if (ctx.blank and (n.html_block_type == 6 or n.html_block_type == 7)) return 1;
    return 0;
}

pub fn finalize(_: *tree.Context, n: *node.Node) void {
    n.tokens = @constCast(lex.trimRight(lex.replaceNewlineSpace(n.tokens)).remains);
}

pub fn isClose(block_type: u8, tokens: []const u8) bool {
    switch (block_type) {
        1 => return lex.acceptTokenss(tokens, &close_tags1) >= 0,
        2 => {
            var i: usize = 0;
            while (i + 3 <= tokens.len) : (i += 1) if (tokens[i] == '-' and tokens[i + 1] == '-' and tokens[i + 2] == '>') return true;
        },
        3 => {
            var i: usize = 0;
            while (i + 2 <= tokens.len) : (i += 1) if (tokens[i] == '?' and tokens[i + 1] == '>') return true;
        },
        4 => return std.mem.indexOfScalar(u8, tokens, '>') != null,
        5 => {
            var i: usize = 0;
            while (i + 2 <= tokens.len) : (i += 1) if (tokens[i] == ']' and tokens[i + 1] == ']') return true;
        },
        else => {},
    }
    return false;
}

fn parseHTML(t: *tree.Tree, tokens_in: []const u8) u8 {
    const tokens = lex.trimLeft(tokens_in).remains;
    if (tokens.len < 3) return 0;
    if (tokens[0] != lex.less) return 0;
    if (lex.acceptTokenss(tokens, &tags1) >= 0) {
        const pos = lex.acceptTokenss(tokens, &tags1);
        if (pos >= 0) {
            const p: usize = @intCast(pos);
            if (p < tokens.len and (lex.isWhitespace(tokens[p]) or tokens[p] == lex.greater)) return 1;
        }
    }
    {
        const pos = lex.acceptTokenss(tokens, &tags6);
        if (pos >= 0) {
            const p: usize = @intCast(pos);
            if (p < tokens.len and (lex.isWhitespace(tokens[p]) or tokens[p] == lex.greater)) return 6;
            if (p + 1 < tokens.len and tokens[p] == lex.slash and tokens[p + 1] == lex.greater) return 6;
        }
    }
    const tag = lex.trimWhitespace(tokens);
    if ((isOpenTag(tag) or isCloseTag(tag)) and t.context.tip.typ != .paragraph) return 7;
    if (std.mem.startsWith(u8, tokens, "<!--")) return 2;
    if (std.mem.startsWith(u8, tokens, "<?")) return 3;
    if (tokens.len > 2 and tokens[0] == lex.less and tokens[1] == lex.bang) {
        const following = tokens[2..];
        if (following.len > 0 and following[0] >= 'A' and following[0] <= 'Z') return 4;
        if (std.mem.startsWith(u8, following, "[CDATA[")) return 5;
    }
    return 0;
}

fn isOpenTag(tokens_in: []const u8) bool {
    var tokens = tokens_in;
    if (tokens.len < 3 or tokens[0] != lex.less or tokens[tokens.len - 1] != lex.greater) return false;
    if (tokens[tokens.len - 2] == lex.slash) {
        tokens = tokens[1 .. tokens.len - 2];
    } else tokens = tokens[1 .. tokens.len - 1];
    if (tokens.len == 0 or lex.isWhitespace(tokens[0])) return false;

    var i: usize = 0;
    if (!lex.isASCIILetter(tokens[i])) return false;
    i += 1;
    while (i < tokens.len and lex.isASCIILetterNumHyphen(tokens[i])) i += 1;

    while (true) {
        const ws_start = i;
        while (i < tokens.len and lex.isWhitespace(tokens[i])) i += 1;
        if (i == ws_start) break; // attributes must be preceded by whitespace
        if (i >= tokens.len) break;
        if (!lex.isASCIILetter(tokens[i]) and tokens[i] != lex.underscore and tokens[i] != lex.colon) break;
        i += 1;
        while (i < tokens.len and (lex.isASCIILetter(tokens[i]) or lex.isDigit(tokens[i]) or tokens[i] == lex.underscore or tokens[i] == lex.dot or tokens[i] == lex.colon or tokens[i] == lex.hyphen)) i += 1;
        // optional value spec, allowing whitespace around '='
        var j = i;
        while (j < tokens.len and lex.isWhitespace(tokens[j])) j += 1;
        if (j < tokens.len and tokens[j] == lex.equal) {
            j += 1;
            while (j < tokens.len and lex.isWhitespace(tokens[j])) j += 1;
            if (j >= tokens.len) return false;
            const q = tokens[j];
            if (q == '\'' or q == '"') {
                j += 1;
                while (j < tokens.len and tokens[j] != q) j += 1;
                if (j >= tokens.len) return false;
                j += 1;
            } else {
                const vs = j;
                while (j < tokens.len and !lex.isWhitespace(tokens[j]) and tokens[j] != '"' and tokens[j] != '\'' and tokens[j] != '=' and tokens[j] != '<' and tokens[j] != '>' and tokens[j] != '`') j += 1;
                if (j == vs) return false;
            }
            i = j;
        }
    }
    return i == tokens.len;
}

fn isCloseTag(tokens_in: []const u8) bool {
    const tokens = lex.trimWhitespace(tokens_in);
    if (tokens.len < 4 or tokens[0] != lex.less or tokens[1] != lex.slash or tokens[tokens.len - 1] != lex.greater) return false;
    const name = tokens[2 .. tokens.len - 1];
    if (name.len == 0 or !lex.isASCIILetter(name[0])) return false;
    for (name[1..]) |n| if (!lex.isASCIILetterNumHyphen(n)) return false;
    return true;
}

fn splitWhitespace(tokens: []const u8) []const []const u8 {
    // Simple view (no allocation): fields of non-whitespace. Zig std has tokenizeAny.
    return std.mem.tokenizeAny(u8, tokens, " \t\n\r\x0b\x0c").?;
}
