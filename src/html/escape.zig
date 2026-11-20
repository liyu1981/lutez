//! Entity decoding and destination encoding.
//! Ported from lute/html/unesc_str.go, esc_str.go-ish helpers, escape.go and
//! escape_encode.go @ v1.7.8 (Mulan PSL v2). Entity payloads come from the generated
//! table (entity_tables.zig) so behavior matches the pinned upstream exactly.
const std = @import("std");
const tables = @import("entity_tables.zig");
const lex = @import("../lex/token.zig");
const uni = @import("../unicode/unicode.zig");

pub const rune_error: u21 = 0xFFFD;

fn lookupEntity(name: []const u8) ?[]const u8 {
    var lo: usize = 0;
    var hi: usize = tables.entities.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = tables.entities[mid];
        const ord = std.mem.order(u8, name, e.name);
        switch (ord) {
            .lt => hi = mid,
            .gt => lo = mid + 1,
            .eq => return e.value,
        }
    }
    return null;
}

fn isValidEntityCode(c: i64) bool {
    if (c < 0 or c > 0x10FFFF) return false;
    const r: u32 = @intCast(c);
    if (r >= 0xD800 and r <= 0xDFFF) return false;
    if (r >= 0xFDD0 and r <= 0xFDEF) return false;
    if (r & 0xFFFF == 0xFFFF or r & 0xFFFF == 0xFFFE) return false;
    if (r <= 0x08 or r == 0x0B or (r >= 0x0E and r <= 0x1F) or (r >= 0x7F and r <= 0x9F)) return false;
    return true;
}

const Entity = struct { text: []const u8, consumed: usize };

/// Returns the decoded entity text (pointing at the generated table or `buf` for numeric
/// entities) and the consumed length, or null. Never allocates.
fn parseEntity(buf: *[4]u8, s: []const u8) ?Entity {
    var st: u8 = 0;
    var n: usize = 0;
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        const b = s[i];
        switch (st) {
            0 => {
                if (b == '#') {
                    st = 1;
                } else if (lex.isASCIILetter(b)) {
                    n = 1;
                    st = 2;
                } else return null;
            },
            1 => {
                if (b == 'x' or b == 'X') {
                    st = 3;
                } else if (lex.isDigit(b)) {
                    n = 1;
                    st = 4;
                } else return null;
            },
            2 => {
                if (lex.isASCIILetterNum(b)) {
                    n += 1;
                    if (n > 31) return null;
                } else if (b == ';') {
                    const name = s[i - n .. i + 1];
                    if (lookupEntity(name)) |v| return .{ .text = v, .consumed = i + 1 };
                    return null;
                } else return null;
            },
            3 => {
                if (lex.isHexDigit(b)) {
                    n = 1;
                    st = 5;
                } else return null;
            },
            4, 5 => {
                const is_num = st == 4;
                if ((is_num and lex.isDigit(b)) or (!is_num and lex.isHexDigit(b))) {
                    n += 1;
                    if (n > 8) return null;
                } else if (b == ';') {
                    const c = std.fmt.parseInt(i64, s[i - n .. i], if (is_num) 10 else 16) catch {
                        return encodeRune(buf, rune_error, i + 1);
                    };
                    if (!isValidEntityCode(c)) return encodeRune(buf, rune_error, i + 1);
                    return encodeRune(buf, @intCast(c), i + 1);
                } else return null;
            },
            else => unreachable,
        }
    }
    return null;
}

fn encodeRune(buf: *[4]u8, r: u21, consumed: usize) Entity {
    const n = std.unicode.utf8Encode(r, buf) catch {
        buf[0] = 0xEF;
        buf[1] = 0xBF;
        buf[2] = 0xBD;
        return .{ .text = buf[0..3], .consumed = consumed };
    };
    return .{ .text = buf[0..n], .consumed = consumed };
}

/// Go html.UnescapeString equivalent (Lute flavor, semicolon required).
pub fn unescapeString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, s, '&') == null) return allocator.dupe(u8, s);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (parseEntity(&buf, s[i..])) |e| {
                try out.appendSlice(allocator, e.text);
                i += e.consumed;
                continue;
            }
        }
        try out.append(allocator, s[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

pub fn escapeHTML(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.ensureTotalCapacity(allocator, html.len + 32);
    for (html) |b| {
        switch (b) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            else => try out.append(allocator, b),
        }
    }
    return out.toOwnedSlice(allocator);
}

const hexdigit = "0123456789ABCDEF";

pub fn encodeDestination(allocator: std.mem.Allocator, rawurl: []const u8) ![]u8 {
    var ret: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (i < rawurl.len) {
        const d = uni.decodeRune(rawurl[i..]);
        const r = d.r;
        const rlen = d.len;
        if (r >= 0x80) {
            var j = i;
            const end = i + rlen;
            while (j < end) : (j += 1) {
                const b = rawurl[j];
                try ret.append(allocator, '%');
                try ret.append(allocator, hexdigit[(b >> 4) & 0xf]);
                try ret.append(allocator, hexdigit[b & 0xf]);
            }
        } else if (r == '%') {
            if (i + 2 < rawurl.len and lex.isHexDigit(rawurl[i + 1]) and lex.isHexDigit(rawurl[i + 2])) {
                try ret.append(allocator, '%');
                try ret.append(allocator, lex.tokenToUpper(rawurl[i + 1]));
                try ret.append(allocator, lex.tokenToUpper(rawurl[i + 2]));
                i += 2;
            } else {
                try ret.appendSlice(allocator, "%25");
            }
        } else if (std.mem.indexOfScalar(u8, "!#$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~", @intCast(r)) == null) {
            const b: u8 = @intCast(r);
            try ret.append(allocator, '%');
            try ret.append(allocator, hexdigit[(b >> 4) & 0xf]);
            try ret.append(allocator, hexdigit[b & 0xf]);
        } else {
            try ret.append(allocator, @intCast(r));
        }
        i += rlen;
    }
    return ret.toOwnedSlice(allocator);
}

fn unhex(b: u8) u8 {
    return if (lex.isDigit(b)) b - '0' else if (b >= 'a' and b <= 'f') b - 'a' + 10 else b - 'A' + 10;
}

fn advance(s: []const u8, pos: usize) struct { b: u8, pos: usize } {
    if (pos >= s.len) return .{ .b = 0, .pos = s.len + 1 };
    if (s[pos] != '%') return .{ .b = s[pos], .pos = pos + 1 };
    if (pos + 2 < s.len and lex.isHexDigit(s[pos + 1]) and lex.isHexDigit(s[pos + 2])) {
        return .{ .b = unhex(s[pos + 1]) << 4 | unhex(s[pos + 2]), .pos = pos + 3 };
    }
    return .{ .b = '%', .pos = pos + 1 };
}

pub fn decodeDestination(allocator: std.mem.Allocator, rawurl: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    outer: while (i < rawurl.len) {
        const d = uni.decodeRune(rawurl[i..]);
        const r = d.r;
        if (r == '%' and i + 2 < rawurl.len and lex.isHexDigit(rawurl[i + 1]) and lex.isHexDigit(rawurl[i + 2])) {
            const b = unhex(rawurl[i + 1]) << 4 | unhex(rawurl[i + 2]);
            if (b < 0x80) {
                try out.append(allocator, b);
                i += 3;
                continue;
            }
            var n: usize = 0;
            if (b & 0xe0 == 0xc0) n = 1 else if (b & 0xf0 == 0xe0) n = 2 else if (b & 0xf8 == 0xf0) n = 3;
            if (n == 0) {
                try out.appendSlice(allocator, "\u{FFFD}");
                i += 3;
                continue;
            }
            var rb: [4]u8 = undefined;
            rb[0] = b;
            var j = i + 3;
            var k: usize = 0;
            while (k < n) : (k += 1) {
                const ad = advance(rawurl, j);
                j = ad.pos;
                if (j > rawurl.len or ad.b & 0xc0 != 0x80) {
                    try out.appendSlice(allocator, "\u{FFFD}");
                    i += 3;
                    continue :outer;
                }
                rb[k + 1] = ad.b;
            }
            const dec = uni.decodeRune(rb[0 .. n + 1]);
            var buf: [4]u8 = undefined;
            const nn = std.unicode.utf8Encode(dec.r, &buf) catch unreachable;
            try out.appendSlice(allocator, buf[0..nn]);
            i = j;
            continue;
        }
        try out.appendSlice(allocator, rawurl[i .. i + d.len]);
        i += d.len;
    }
    return out.toOwnedSlice(allocator);
}

test "named and numeric entities" {
    const a = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "&amp;", "&" },
        .{ "&#35;", "#" },
        .{ "&#x22;", "\"" },
        .{ "&copy;", "\u{00A9}" },
        .{ "&nope;", "&nope;" },
        .{ "&amp", "&amp" },
        .{ "&#0;", "\u{FFFD}" },
        .{ "&#x110000;", "\u{FFFD}" },
    };
    for (cases) |c| {
        const got = try unescapeString(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test "destination encode/decode roundtrip" {
    const a = std.testing.allocator;
    const enc = try encodeDestination(a, "a b?x=1&y=é#f");
    defer a.free(enc);
    try std.testing.expectEqualStrings("a%20b?x=1&y=%C3%A9#f", enc);
    const dec = try decodeDestination(a, enc);
    defer a.free(dec);
    try std.testing.expectEqualStrings("a b?x=1&y=é#f", dec);
    const sparse = try encodeDestination(a, "50%");
    defer a.free(sparse);
    try std.testing.expectEqualStrings("50%25", sparse);
}

test "every entity in the table decodes to its value" {
    const a = std.testing.allocator;
    for (tables.entities) |e| {
        var buf: [64]u8 = undefined;
        const src = try std.fmt.bufPrint(&buf, "&{s}", .{e.name});
        const got = try unescapeString(a, src);
        defer a.free(got);
        try std.testing.expectEqualStrings(e.value, got);
    }
}

test "invalid UTF-8 destination bytes are percent-encoded per byte" {
    const a = std.testing.allocator;
    const enc = try encodeDestination(a, "\xff");
    defer a.free(enc);
    try std.testing.expectEqualStrings("%FF", enc);
}
