//! Document handle shared by the C ABI and WASM ABI: arena-owned AST + wire buffer.
const std = @import("std");
const lutez = @import("lutez.zig");
const wire = @import("ast/wire.zig");
const node = @import("ast/node.zig");

pub const Document = struct {
    doc: lutez.Doc,
    wire: []u8,

    /// `backing` owns the Document struct itself (c_allocator / wasm_allocator).
    pub fn create(backing: std.mem.Allocator, input: []const u8, options: lutez.Options) !*Document {
        const self = try backing.create(Document);
        errdefer backing.destroy(self);
        self.doc = try lutez.parseWith(backing, input, options);
        errdefer self.doc.deinit();
        self.wire = try wire.encode(self.doc.arena.allocator(), self.doc.root, &.{}, self.doc.source_map);
        return self;
    }

    pub fn destroy(self: *Document, backing: std.mem.Allocator) void {
        self.doc.deinit();
        backing.destroy(self);
    }

    pub fn ast(self: *const Document) []const u8 {
        return self.wire;
    }
};

/// Read-only view over a wire buffer for the ergonomic accessors.
pub const View = struct {
    buf: []const u8,
    count: u32,
    stride: u32,
    extras_off: usize,
    ext_len: u32,
    pool_off: usize,
    pool_len: u32,

    pub fn init(buf: []const u8) ?View {
        if (buf.len < wire.header_len) return null;
        if (!std.mem.eql(u8, buf[0..8], wire.magic)) return null;
        const version = std.mem.readInt(u32, buf[8..12], .little);
        if (version != wire.version) return null;
        const count = std.mem.readInt(u32, buf[16..20], .little);
        const stride = std.mem.readInt(u32, buf[20..24], .little);
        const input_len = std.mem.readInt(u32, buf[24..28], .little);
        const pool_len = std.mem.readInt(u32, buf[28..32], .little);
        const ext_len = std.mem.readInt(u32, buf[32..36], .little);
        const extras_off = (wire.header_len + @as(usize, count) * @as(usize, stride) + 7) & ~@as(usize, 7);
        const input_off = (extras_off + ext_len + 7) & ~@as(usize, 7);
        const pool_off = (input_off + input_len + 7) & ~@as(usize, 7);
        if (stride < wire.node_stride or pool_off + pool_len > buf.len) return null;
        return .{ .buf = buf, .count = count, .stride = stride, .extras_off = extras_off, .ext_len = ext_len, .pool_off = pool_off, .pool_len = pool_len };
    }

    fn rec(self: View, i: u32) ?[]const u8 {
        if (i >= self.count) return null;
        const off = wire.header_len + @as(usize, i) * self.stride;
        if (off + wire.node_stride > self.buf.len) return null;
        return self.buf[off .. off + wire.node_stride];
    }

    pub fn nodeType(self: View, i: u32) i32 {
        const r = self.rec(i) orelse return -1;
        return std.mem.readInt(u16, r[0..2], .little);
    }

    pub fn span(self: View, i: u32, normalized: bool) ?struct { start: u32, end: u32 } {
        const r = self.rec(i) orelse return null;
        const off: usize = if (normalized) 32 else 40;
        return .{
            .start = std.mem.readInt(u32, r[off..][0..4], .little),
            .end = std.mem.readInt(u32, r[off + 4 ..][0..4], .little),
        };
    }

    pub fn extKind(self: View, i: u32) i64 {
        const r = self.rec(i) orelse return -1;
        const typ = std.mem.readInt(u16, r[0..2], .little);
        if (typ != 500 and typ != 501) return -1;
        const ref = std.mem.readInt(u32, r[48..52], .little);
        const len = std.mem.readInt(u32, r[52..56], .little);
        if (ref == 0xFFFFFFFF or len < 8 or ref + len > self.ext_len) return -1;
        const e = self.buf[self.extras_off + ref .. self.extras_off + ref + len];
        return std.mem.readInt(u32, e[0..4], .little);
    }

    pub fn extFlags(self: View, i: u32) u16 {
        const r = self.rec(i) orelse return 0;
        const typ = std.mem.readInt(u16, r[0..2], .little);
        if (typ != 500 and typ != 501) return 0;
        const ref = std.mem.readInt(u32, r[48..52], .little);
        const len = std.mem.readInt(u32, r[52..56], .little);
        if (ref == 0xFFFFFFFF or len < 8 or ref + len > self.ext_len) return 0;
        const e = self.buf[self.extras_off + ref .. self.extras_off + ref + len];
        return std.mem.readInt(u16, e[4..6], .little);
    }

    pub fn derived(self: View, i: u32) bool {
        const r = self.rec(i) orelse return false;
        const flags = std.mem.readInt(u16, r[2..4], .little);
        return flags & (1 << 8) != 0;
    }

    pub fn child(self: View, i: u32, last: bool) u32 {
        const r = self.rec(i) orelse return wire.absent;
        return std.mem.readInt(u32, r[if (last) 12 else 8..][0..4], .little);
    }

    pub fn sibling(self: View, i: u32, next: bool) u32 {
        const r = self.rec(i) orelse return wire.absent;
        return std.mem.readInt(u32, r[if (next) 20 else 16..][0..4], .little);
    }

    pub fn parent(self: View, i: u32) u32 {
        const r = self.rec(i) orelse return wire.absent;
        return std.mem.readInt(u32, r[4..8], .little);
    }

    pub fn tokens(self: View, i: u32) []const u8 {
        const r = self.rec(i) orelse return &.{};
        const ref = std.mem.readInt(u32, r[24..28], .little);
        const len = std.mem.readInt(u32, r[28..32], .little);
        if (ref == wire.absent or ref + len > self.pool_len) return &.{};
        return self.buf[self.pool_off + ref .. self.pool_off + ref + len];
    }
};
