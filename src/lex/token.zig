//! Byte/token helpers. Ported from lute/lex/token.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const uni = @import("../unicode/unicode.zig");

pub const backtick = '`';
pub const tilde = '~';
pub const bang = '!';
pub const crosshatch = '#';
pub const asterisk = '*';
pub const open_paren = '(';
pub const close_paren = ')';
pub const hyphen = '-';
pub const underscore = '_';
pub const plus = '+';
pub const equal = '=';
pub const tab = '\t';
pub const open_bracket = '[';
pub const close_bracket = ']';
pub const doublequote = '"';
pub const singlequote = '\'';
pub const less = '<';
pub const greater = '>';
pub const space = ' ';
pub const newline = '\n';
pub const carriage_return = '\r';
pub const backslash = '\\';
pub const slash = '/';
pub const dot = '.';
pub const colon = ':';
pub const question = '?';
pub const ampersand = '&';
pub const semicolon = ';';
pub const pipe = '|';
pub const dollar = '$';
pub const caret = '^';
pub const open_brace = '{';
pub const close_brace = '}';

pub fn isWhitespace(b: u8) bool {
    return b == space or b == newline or b == tab or b == 0x0B or b == 0x0C or b == '\r';
}
pub fn isUnicodeWhitespace(r: u21) bool {
    return uni.isSpace(r);
}
pub fn isDigit(b: u8) bool {
    return '0' <= b and b <= '9';
}
pub fn isHexDigit(b: u8) bool {
    return isDigit(b) or ('a' <= b and b <= 'f') or ('A' <= b and b <= 'F');
}
pub fn tokenToUpper(b: u8) u8 {
    return if (b >= 'a' and b <= 'z') b - 'a' + 'A' else b;
}
pub fn isASCIIPunct(b: u8) bool {
    return (0x21 <= b and b <= 0x2F) or (0x3A <= b and b <= 0x40) or (0x5B <= b and b <= 0x60) or (0x7B <= b and b <= 0x7E);
}
pub fn isASCIILetter(b: u8) bool {
    return ('A' <= b and b <= 'Z') or ('a' <= b and b <= 'z');
}
pub fn isASCIILetterNum(b: u8) bool {
    return isASCIILetter(b) or isDigit(b);
}
pub fn isASCIILetterNums(bs: []const u8) bool {
    for (bs) |b| if (!isASCIILetterNum(b)) return false;
    return true;
}
pub fn isASCIILetterNumHyphen(b: u8) bool {
    return isASCIILetterNum(b) or b == '-';
}
pub fn isControl(b: u8) bool {
    return uni.isControl(b);
}
pub fn isBlank(bs: []const u8) bool {
    for (bs) |b| if (b != space) return false;
    return true;
}
pub fn isBlankLine(bs: []const u8) bool {
    for (bs) |b| if (b != space and b != tab and b != newline) return false;
    return true;
}

/// Splits on separator, keeping trailing empty fields (Go lex.Split behavior).
pub fn split(allocator: std.mem.Allocator, tokens: []const u8, separator: u8) !std.ArrayListUnmanaged([]const u8) {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    var start: usize = 0;
    for (tokens, 0..) |b, i| {
        if (b == separator) {
            try out.append(allocator, tokens[start..i]);
            start = i + 1;
        }
    }
    if (start <= tokens.len) try out.append(allocator, tokens[start..]);
    return out;
}

/// Splits on separator, ignoring separators escaped by an odd backslash run.
pub fn splitWithoutBackslashEscape(allocator: std.mem.Allocator, tokens: []const u8, separator: u8) !std.ArrayListUnmanaged([]const u8) {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    var start: usize = 0;
    var bs: usize = 0;
    for (tokens, 0..) |b, i| {
        if (b == separator and bs % 2 == 0) {
            try out.append(allocator, tokens[start..i]);
            start = i + 1;
        }
        bs = if (b == backslash) bs + 1 else 0;
    }
    if (start <= tokens.len) try out.append(allocator, tokens[start..]);
    return out;
}

pub fn replaceAll(tokens: []u8, old: u8, new: u8) []u8 {
    for (tokens) |*b| if (b.* == old) {
        b.* = new;
    };
    return tokens;
}

pub fn replaceNewlineSpace(tokens: []u8) []u8 {
    var i: isize = @intCast(tokens.len);
    var n = tokens.len;
    while (i > 0) {
        i -= 1;
        const b = tokens[@intCast(i)];
        if (b != newline and b != space) break;
        if (i > 0 and tokens[@intCast(i - 1)] == newline and (b == space or b == newline)) n = @intCast(i);
    }
    return tokens[0..n];
}

pub const Trim = struct { left: []const u8, right: []const u8, remains: []const u8 };

pub fn trim(tokens: []const u8) Trim {
    const len = tokens.len;
    if (len == 0) return .{ .left = tokens[0..0], .right = tokens[0..0], .remains = tokens };
    var start: usize = 0;
    while (start < len and isWhitespace(tokens[start])) start += 1;
    const left = tokens[0..start];
    if (start == len) start -= 1;
    var end: isize = @as(isize, @intCast(len)) - 1;
    while (end >= 0 and isWhitespace(tokens[@intCast(end)])) end -= 1;
    if (end < @as(isize, @intCast(start))) end = @as(isize, @intCast(start)) - 1;
    const right = if (end > 0) tokens[@intCast(end + 1)..] else tokens[0..0];
    const remains = tokens[start..@intCast(end + 1)];
    return .{ .left = left, .right = right, .remains = remains };
}

pub fn trimWhitespace(tokens: []const u8) []const u8 {
    return trim(tokens).remains;
}

pub fn trimRight(tokens: []const u8) struct { whitespace: []const u8, remains: []const u8 } {
    if (tokens.len == 0) return .{ .whitespace = tokens[0..0], .remains = tokens };
    var i: isize = @as(isize, @intCast(tokens.len)) - 1;
    while (i >= 0 and isWhitespace(tokens[@intCast(i)])) i -= 1;
    const n: usize = @intCast(i + 1);
    return .{ .whitespace = tokens[n..], .remains = tokens[0..n] };
}

pub fn trimLeft(tokens: []const u8) struct { whitespace: []const u8, remains: []const u8 } {
    var i: usize = 0;
    while (i < tokens.len and isWhitespace(tokens[i])) i += 1;
    return .{ .whitespace = tokens[0..i], .remains = tokens[i..] };
}

pub fn accept(tokens: []const u8, token: u8) usize {
    var pos: usize = 0;
    while (pos < tokens.len and tokens[pos] == token) pos += 1;
    return pos;
}

pub fn acceptTokens(remains: []const u8, some: []const u8) isize {
    if (some.len > remains.len) return -1;
    for (some, 0..) |b, i| if (remains[i] != b) return -1;
    return @intCast(some.len);
}

/// Matches any of `some` at any position; returns the matched length or -1.
pub fn acceptTokenss(remains: []const u8, some: []const []const u8) isize {
    var i: usize = 0;
    while (i < remains.len) : (i += 1) {
        for (some) |s| {
            const p = acceptTokens(remains[i..], s);
            if (p >= 0) return p;
        }
    }
    return -1;
}

pub fn isBackslashEscapePunct(tokens: []const u8, pos: usize) bool {
    if (pos >= tokens.len or !isASCIIPunct(tokens[pos])) return false;
    var backslashes: usize = 0;
    var i = pos;
    while (i > 0) {
        i -= 1;
        if (tokens[i] != backslash) break;
        backslashes += 1;
    }
    return backslashes % 2 != 0;
}

pub const WhitespaceStat = struct { newlines: usize = 0, spaces: usize = 0, tabs: usize = 0 };

pub fn statWhitespace(tokens: []const u8) WhitespaceStat {
    var r = WhitespaceStat{};
    for (tokens) |b| {
        if (b == newline) r.newlines += 1 else if (b == space) r.spaces += 1 else if (b == tab) r.tabs += 1;
    }
    return r;
}

pub fn spnl(tokens: []const u8) bool {
    const tr = trimLeft(tokens);
    const st = statWhitespace(tr.whitespace);
    return st.newlines <= 1;
}

pub fn peek(tokens: []const u8, pos: usize) u8 {
    return if (pos < tokens.len) tokens[pos] else 0;
}

pub fn isMarker(b: u8) bool {
    return b == asterisk or b == underscore or b == open_bracket or b == bang or b == newline or
        b == backslash or b == backtick or b == less or b == close_bracket or b == ampersand or b == tilde;
}
