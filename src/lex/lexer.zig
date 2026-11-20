//! Line lexer. Ported from lute/lex/lexer.go @ v1.7.8 (Mulan PSL v2).
//! The input is copied by the caller into the document arena; CRLF is normalized in
//! place and NUL bytes become U+FFFD.
const std = @import("std");
const token = @import("token.zig");

pub const Lexer = struct {
    input: []u8,
    length: usize,
    offset: usize,

    /// Appends a trailing '\n' if missing (Go NewLexer behavior).
    pub fn init(input: []u8) Lexer {
        return .{ .input = input, .length = input.len, .offset = 0 };
    }

    pub fn nextLine(self: *Lexer, allocator: std.mem.Allocator) !?[]u8 {
        if (self.offset >= self.length) return null;
        const start = self.offset;
        var i = self.offset;
        var has_nul = false;
        var end = i;
        while (i < self.length) : (i += 1) {
            const b = self.input[i];
            if (b == token.newline) {
                i += 1;
                end = i;
                break;
            } else if (b == token.carriage_return) {
                self.input[i] = token.newline;
                i += 1;
                end = i;
                if (i < self.length and self.input[i] == token.newline) i += 1;
                break;
            } else if (b == 0) {
                has_nul = true;
            }
        }
        if (end == start and i > start) end = i;
        var ret = self.input[start..end];
        if (has_nul) {
            var out: std.ArrayListUnmanaged(u8) = .empty;
            try out.ensureTotalCapacity(allocator, ret.len + 8);
            for (ret) |b| {
                if (b == 0) try out.appendSlice(allocator, "\u{FFFD}") else try out.append(allocator, b);
            }
            ret = try out.toOwnedSlice(allocator);
        }
        self.offset = i;
        return ret;
    }
};

test "lexer normalizes CRLF and appends nothing itself" {
    var buf = [_]u8{ 'a', '\r', '\n', 'b' };
    var lx = Lexer.init(&buf);
    const a = (try lx.nextLine(std.testing.allocator)).?;
    try std.testing.expectEqualStrings("a\n", a);
    const b = (try lx.nextLine(std.testing.allocator)).?;
    try std.testing.expectEqualStrings("b", b);
    try std.testing.expect((try lx.nextLine(std.testing.allocator)) == null);
}

test "lexer replaces NUL with U+FFFD" {
    var buf = [_]u8{ 'a', 0, 'b' };
    var lx = Lexer.init(&buf);
    const line = (try lx.nextLine(std.testing.allocator)).?;
    defer std.testing.allocator.free(line); // NUL replacement allocates
    try std.testing.expectEqualStrings("a\u{FFFD}b", line);
}
