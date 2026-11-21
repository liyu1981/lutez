//! Input normalization and raw↔normalized offset mapping.
//!
//! The lexer/parser work on a normalized buffer: CRLF and lone CR become LF, NUL
//! becomes U+FFFD, and a trailing newline is appended. Source spans are recorded against
//! this buffer; this map converts them back to offsets in the caller's original bytes.
const std = @import("std");

pub const no_pos: u32 = std.math.maxInt(u32);

pub const SegKind = enum(u8) {
    identity = 0,
    crlf = 1,
    nul = 2,
    synthetic = 3,
};

pub const Seg = struct {
    norm_start: u32,
    norm_len: u32,
    raw_start: u32,
    raw_len: u32,
    kind: SegKind,
};

pub const SourceMap = struct {
    segs: []const Seg,
    raw_len: u32,
    norm_len: u32,

    /// Maps a normalized start offset to the first raw byte of the construct containing it.
    pub fn normToRawStart(self: SourceMap, off: u32) u32 {
        if (off >= self.norm_len) return self.raw_len;
        const seg = self.segAt(off) orelse return off;
        return switch (seg.kind) {
            .identity => seg.raw_start + (off - seg.norm_start),
            .crlf, .nul => seg.raw_start,
            .synthetic => seg.raw_start,
        };
    }

    /// Maps a normalized end offset (exclusive) to the matching exclusive raw offset.
    pub fn normToRawEnd(self: SourceMap, off: u32) u32 {
        if (off == 0) return 0;
        if (off >= self.norm_len) return self.raw_len;
        const seg = self.segAt(off - 1) orelse return off;
        return switch (seg.kind) {
            .identity => seg.raw_start + (off - seg.norm_start),
            .crlf, .nul, .synthetic => seg.raw_start + seg.raw_len,
        };
    }

    pub fn normSpanToRaw(self: SourceMap, start: u32, end: u32) struct { start: u32, end: u32 } {
        return .{ .start = self.normToRawStart(start), .end = self.normToRawEnd(end) };
    }

    fn segAt(self: SourceMap, off: u32) ?Seg {
        var lo: usize = 0;
        var hi: usize = self.segs.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const s = self.segs[mid];
            if (off < s.norm_start) {
                hi = mid;
            } else if (off >= s.norm_start + s.norm_len) {
                lo = mid + 1;
            } else return s;
        }
        return null;
    }
};

pub const Normalized = struct {
    bytes: []u8,
    map: SourceMap,
};

/// Builds the normalized buffer and its source map. The returned bytes/map are allocated
/// from `allocator` and remain valid for the document lifetime.
pub fn normalize(allocator: std.mem.Allocator, input: []const u8) !Normalized {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var segs: std.ArrayListUnmanaged(Seg) = .empty;
    try out.ensureTotalCapacity(allocator, input.len + 8);

    var raw_pos: usize = 0;
    var norm_pos: usize = 0;
    while (raw_pos < input.len) {
        const b = input[raw_pos];
        if (b == '\r' or b == 0) {
            const consumed: usize = if (b == '\r' and raw_pos + 1 < input.len and input[raw_pos + 1] == '\n') 2 else 1;
            try segs.append(allocator, .{
                .norm_start = @intCast(norm_pos),
                .norm_len = if (b == 0) 3 else 1,
                .raw_start = @intCast(raw_pos),
                .raw_len = @intCast(consumed),
                .kind = if (b == 0) .nul else .crlf,
            });
            if (b == 0) {
                try out.appendSlice(allocator, "\u{FFFD}");
                norm_pos += 3;
                raw_pos += 1;
            } else {
                try out.append(allocator, '\n');
                norm_pos += 1;
                raw_pos += consumed;
            }
            continue;
        }
        const start_raw = raw_pos;
        const start_norm = norm_pos;
        while (raw_pos < input.len and input[raw_pos] != '\r' and input[raw_pos] != 0) : (raw_pos += 1) {}
        const run = input[start_raw..raw_pos];
        try out.appendSlice(allocator, run);
        norm_pos += run.len;
        try segs.append(allocator, .{
            .norm_start = @intCast(start_norm),
            .norm_len = @intCast(run.len),
            .raw_start = @intCast(start_raw),
            .raw_len = @intCast(run.len),
            .kind = .identity,
        });
    }

    // The lexer expects a trailing newline for non-empty input (upstream Lute behaviour).
    if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') {
        try segs.append(allocator, .{
            .norm_start = @intCast(norm_pos),
            .norm_len = 1,
            .raw_start = @intCast(input.len),
            .raw_len = 0,
            .kind = .synthetic,
        });
        try out.append(allocator, '\n');
        norm_pos += 1;
    }

    return .{
        .bytes = try out.toOwnedSlice(allocator),
        .map = .{
            .segs = try segs.toOwnedSlice(allocator),
            .raw_len = @intCast(input.len),
            .norm_len = @intCast(norm_pos),
        },
    };
}

pub fn isEmptyInput(input: []const u8) bool {
    return input.len == 0;
}

test "normalize identity and trailing newline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = try normalize(a, "a\nb");
    try std.testing.expectEqualStrings("a\nb\n", n.bytes);
    try std.testing.expectEqual(@as(u32, 0), n.map.normToRawStart(0));
    try std.testing.expectEqual(@as(u32, 3), n.map.normToRawEnd(3));
    const s = n.map.normSpanToRaw(0, 3);
    try std.testing.expectEqual(@as(u32, 0), s.start);
    try std.testing.expectEqual(@as(u32, 3), s.end);
}

test "normalize CRLF and lone CR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = try normalize(a, "a\r\nb\rc");
    try std.testing.expectEqualStrings("a\nb\nc\n", n.bytes);
    // second line starts at raw 3, normalized 2
    try std.testing.expectEqual(@as(u32, 3), n.map.normToRawStart(2));
    // first line ends after raw CRLF (raw 3), normalized 2
    try std.testing.expectEqual(@as(u32, 3), n.map.normToRawEnd(2));
    try std.testing.expectEqual(@as(u32, 5), n.map.normToRawStart(4));
}

test "normalize NUL to U+FFFD and map boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = try normalize(a, "a\x00b");
    try std.testing.expectEqualStrings("a\u{FFFD}b\n", n.bytes);
    try std.testing.expectEqual(@as(u32, 1), n.map.normToRawStart(1));
    try std.testing.expectEqual(@as(u32, 2), n.map.normToRawEnd(4));
    try std.testing.expectEqual(@as(u32, 2), n.map.normToRawStart(4));
}

test "synthetic trailing newline has zero raw width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = try normalize(a, "abc");
    try std.testing.expectEqual(@as(u32, 3), n.map.normToRawStart(3));
    try std.testing.expectEqual(@as(u32, 3), n.map.normToRawEnd(4));
    try std.testing.expectEqual(@as(u32, 3), n.map.raw_len);
}
