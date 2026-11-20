//! Unicode helpers backed by generated tables (src/unicode/tables.zig).
const std = @import("std");
const t = @import("tables.zig");

fn inRanges(comptime ranges: anytype, r: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = ranges[mid];
        if (r < e.lo) hi = mid else if (r > e.hi) lo = mid + 1 else return true;
    }
    return false;
}

pub fn isSpace(r: u21) bool {
    return inRanges(&t.space_ranges, r);
}
pub fn isControl(r: u21) bool {
    return inRanges(&t.control_ranges, r);
}
pub fn isPunct(r: u21) bool {
    return inRanges(&t.punct_ranges, r);
}
pub fn isSymbol(r: u21) bool {
    return inRanges(&t.symbol_ranges, r);
}
pub fn isQuotationMark(r: u21) bool {
    return inRanges(&t.quotation_ranges, r);
}

pub fn simpleFold(r: u21) u21 {
    var lo: usize = 0;
    var hi: usize = t.simple_fold.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = t.simple_fold[mid];
        if (r < e.r) hi = mid else if (r > e.r) lo = mid + 1 else return e.to;
    }
    return r;
}

/// Full case folding (Go `cases.Fold`): appends the folded form of `r` to `out`.
pub fn foldAppend(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), r: u21) !void {
    var lo: usize = 0;
    var hi: usize = t.fold_entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = t.fold_entries[mid];
        if (r < e.r) {
            hi = mid;
        } else if (r > e.r) {
            lo = mid + 1;
        } else {
            var i: usize = 0;
            while (i < e.len) : (i += 1) {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(@intCast(t.fold_data[e.off + i]), &buf) catch unreachable;
                try out.appendSlice(allocator, buf[0..n]);
            }
            return;
        }
    }
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(r, &buf) catch {
        try out.appendSlice(allocator, "\u{FFFD}");
        return;
    };
    try out.appendSlice(allocator, buf[0..n]);
}

pub fn decodeLastRune(s: []const u8) u21 {
    if (s.len == 0) return 0xFFFD;
    var i: usize = s.len - 1;
    var back: usize = 0;
    while (i > 0 and back < 3 and s[i] & 0xC0 == 0x80) : (back += 1) i -= 1;
    return decodeRune(s[i..]).r;
}

pub fn decodeRune(s: []const u8) struct { r: u21, len: usize } {
    const n = std.unicode.utf8ByteSequenceLength(s[0]) catch return .{ .r = 0xFFFD, .len = 1 };
    if (n > s.len) return .{ .r = 0xFFFD, .len = 1 };
    const r = std.unicode.utf8Decode(s[0..n]) catch return .{ .r = 0xFFFD, .len = 1 };
    return .{ .r = r, .len = n };
}

test "unicode categories and folds" {
    try std.testing.expect(isSpace(' '));
    try std.testing.expect(isPunct('!'));
    try std.testing.expect(isPunct(0x3001));
    try std.testing.expect(isSymbol('$'));
    try std.testing.expect(isControl(0x7F));
    try std.testing.expect(isQuotationMark('"'));
    try std.testing.expectEqual(@as(u21, 'A'), simpleFold('a'));
    try std.testing.expectEqual(@as(u21, 'a'), simpleFold('A'));
    const a = std.testing.allocator;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(a);
    try foldAppend(a, &out, 0x00DF); // ß -> ss
    try std.testing.expectEqualStrings("ss", out.items);
}
