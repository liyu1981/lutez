//! Binary AST wire format v2 (doc/WIRE_FORMAT.md): little-endian, index-based,
//! single contiguous buffer owned by the document.
const std = @import("std");
const node = @import("node.zig");
const types = @import("../types.zig");
const source = @import("../source.zig");

pub const magic = "LUTEAST1";
pub const version: u32 = 2;
pub const header_len: usize = 40;
pub const node_stride: usize = 56;
pub const absent: u32 = 0xFFFF_FFFF;

fn align8(n: usize) usize {
    return (n + 7) & ~@as(usize, 7);
}

const Sections = struct { nodes: usize, extras: usize, input: usize, pool: usize, map: usize };

fn sections(node_count: u32, input_len: u32, pool_len: u32, ext_len: u32, map_len: u32) Sections {
    _ = map_len;
    const nodes_off = header_len;
    const extras_off = align8(nodes_off + @as(usize, node_count) * node_stride);
    const input_off = align8(extras_off + ext_len);
    const pool_off = align8(input_off + input_len);
    const map_off = align8(pool_off + pool_len);
    return .{ .nodes = nodes_off, .extras = extras_off, .input = input_off, .pool = pool_off, .map = map_off };
}

const Ctx = struct {
    allocator: std.mem.Allocator,
    index: std.AutoHashMapUnmanaged(*node.Node, u32) = .empty,
    nodes: std.ArrayListUnmanaged(*node.Node) = .empty,
};

fn collect(ctx: *Ctx, n: *node.Node) !void {
    try ctx.index.put(ctx.allocator, n, @intCast(ctx.nodes.items.len));
    try ctx.nodes.append(ctx.allocator, n);
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) try collect(ctx, ch);
}

fn flagsOf(n: *node.Node) u16 {
    var f: u16 = 1; // tokens_in_pool
    if (n.close) f |= 1 << 2;
    if (n.last_line_blank) f |= 1 << 3;
    if (n.last_line_checked) f |= 1 << 4;
    if (n.heading_setext) f |= 1 << 5;
    if (n.is_fenced_code_block) f |= 1 << 6;
    if (n.list_data.typ == 3 and n.list_data.checked) f |= 1 << 7;
    if (n.src_derived) f |= 1 << 8;
    return f;
}

fn putU8(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, v: u8) !void {
    try out.append(a, v);
}
fn putU32(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, v: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, v, .little);
    try out.appendSlice(a, &buf);
}
fn putI32(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, v: i32) !void {
    try putU32(out, a, @bitCast(v));
}
fn putBytes(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, bs: []const u8) !void {
    try putU32(out, a, @intCast(bs.len));
    try out.appendSlice(a, bs);
}

fn putExt(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), n: *node.Node) !void {
    switch (n.typ) {
        .heading => {
            try putU8(out, a, n.heading_level);
            try putU8(out, a, if (n.heading_setext) 1 else 0);
        },
        .code_block => {
            try putU8(out, a, n.code_block_fence_char);
            try putU8(out, a, @intCast(n.code_block_fence_len));
            try putU8(out, a, if (n.is_fenced_code_block) 1 else 0);
            try putU8(out, a, 0);
            try putU32(out, a, n.code_block_fence_offset);
            try putBytes(out, a, n.code_block_open_fence);
            try putBytes(out, a, n.code_block_info);
            try putBytes(out, a, n.code_block_close_fence);
        },
        .html_block => try putU8(out, a, n.html_block_type),
        .code_block_fence_info_marker => try putBytes(out, a, n.code_block_info),
        .code_block_fence_open_marker, .code_block_fence_close_marker => try putU32(out, a, n.code_block_fence_len),
        .list, .list_item => {
            const d = n.list_data;
            try putU8(out, a, d.typ);
            try putU8(out, a, if (d.tight) 1 else 0);
            try putU8(out, a, d.bullet_char);
            try putU8(out, a, d.delimiter);
            try putU8(out, a, if (d.checked) 1 else 0);
            try putU8(out, a, 0);
            try putU8(out, a, 0);
            try putU8(out, a, 0);
            try putI32(out, a, d.start);
            try putI32(out, a, d.num);
            try putU32(out, a, d.padding);
            try putU32(out, a, d.marker_offset);
            try putBytes(out, a, d.marker);
        },
        .link, .image => {
            try putU8(out, a, n.link_type);
            try putBytes(out, a, n.link_ref_label);
        },
        .table => {
            try putU32(out, a, @intCast(n.table_aligns.len));
            try out.appendSlice(a, n.table_aligns);
        },
        .table_cell => try putU8(out, a, n.table_cell_align),
        .task_list_item_marker => try putU8(out, a, n.task_marker),
        .code_span => try putU32(out, a, n.code_marker_len),
        else => {},
    }
}

/// Encodes `root` into one contiguous buffer owned by `allocator`.
pub fn encode(allocator: std.mem.Allocator, root: *node.Node, input: []const u8, map: source.SourceMap) ![]u8 {
    var ctx = Ctx{ .allocator = allocator };
    defer ctx.index.deinit(allocator);
    defer ctx.nodes.deinit(allocator);
    try collect(&ctx, root);
    const count: u32 = @intCast(ctx.nodes.items.len);

    var pool: std.ArrayListUnmanaged(u8) = .empty;
    defer pool.deinit(allocator);
    var extras: std.ArrayListUnmanaged(u8) = .empty;
    defer extras.deinit(allocator);
    var tok_refs = try allocator.alloc(u32, count);
    defer allocator.free(tok_refs);
    var tok_lens = try allocator.alloc(u32, count);
    defer allocator.free(tok_lens);
    var ext_refs = try allocator.alloc(u32, count);
    defer allocator.free(ext_refs);
    var ext_lens = try allocator.alloc(u32, count);
    defer allocator.free(ext_lens);

    for (ctx.nodes.items, 0..) |n, i| {
        if (n.tokens.len == 0) {
            tok_refs[i] = absent;
            tok_lens[i] = 0;
        } else {
            tok_refs[i] = @intCast(pool.items.len);
            tok_lens[i] = @intCast(n.tokens.len);
            try pool.appendSlice(allocator, n.tokens);
        }
        const ext_start = extras.items.len;
        try putExt(allocator, &extras, n);
        if (extras.items.len == ext_start) {
            ext_refs[i] = absent;
            ext_lens[i] = 0;
        } else {
            ext_refs[i] = @intCast(ext_start);
            ext_lens[i] = @intCast(extras.items.len - ext_start);
        }
    }

    const map_entry_len: usize = 20;
    const map_len: u32 = @intCast(4 + map.segs.len * map_entry_len);
    const secs = sections(count, @intCast(input.len), @intCast(pool.items.len), @intCast(extras.items.len), map_len);
    const total = align8(secs.map + map_len);
    const buf = try allocator.alloc(u8, total);
    @memset(buf, 0);
    @memcpy(buf[0..8], magic);
    std.mem.writeInt(u32, buf[8..12], version, .little);
    std.mem.writeInt(u32, buf[12..16], 1, .little); // little-endian flag
    std.mem.writeInt(u32, buf[16..20], count, .little);
    std.mem.writeInt(u32, buf[20..24], @intCast(node_stride), .little);
    std.mem.writeInt(u32, buf[24..28], @intCast(input.len), .little);
    std.mem.writeInt(u32, buf[28..32], @intCast(pool.items.len), .little);
    std.mem.writeInt(u32, buf[32..36], @intCast(extras.items.len), .little);
    std.mem.writeInt(u32, buf[36..40], map_len, .little);

    @memcpy(buf[secs.extras .. secs.extras + extras.items.len], extras.items);
    @memcpy(buf[secs.input .. secs.input + input.len], input);
    @memcpy(buf[secs.pool .. secs.pool + pool.items.len], pool.items);
    std.mem.writeInt(u32, buf[secs.map..][0..4], @intCast(map.segs.len), .little);
    for (map.segs, 0..) |seg, si| {
        const off = secs.map + 4 + si * map_entry_len;
        const e = buf[off .. off + map_entry_len];
        std.mem.writeInt(u32, e[0..4], seg.norm_start, .little);
        std.mem.writeInt(u32, e[4..8], seg.norm_len, .little);
        std.mem.writeInt(u32, e[8..12], seg.raw_start, .little);
        std.mem.writeInt(u32, e[12..16], seg.raw_len, .little);
        e[16] = @backingInt(seg.kind);
        @memset(e[17..20], 0);
    }

    for (ctx.nodes.items, 0..) |n, i| {
        const off = secs.nodes + i * node_stride;
        const rec = buf[off .. off + node_stride];
        std.mem.writeInt(u16, rec[0..2], @backingInt(n.typ), .little);
        std.mem.writeInt(u16, rec[2..4], flagsOf(n), .little);
        std.mem.writeInt(u32, rec[4..8], if (n.parent) |p| ctx.index.get(p).? else absent, .little);
        std.mem.writeInt(u32, rec[8..12], if (n.first_child) |c| ctx.index.get(c).? else absent, .little);
        std.mem.writeInt(u32, rec[12..16], if (n.last_child) |c| ctx.index.get(c).? else absent, .little);
        std.mem.writeInt(u32, rec[16..20], if (n.prev) |p| ctx.index.get(p).? else absent, .little);
        std.mem.writeInt(u32, rec[20..24], if (n.next) |p| ctx.index.get(p).? else absent, .little);
        std.mem.writeInt(u32, rec[24..28], tok_refs[i], .little);
        std.mem.writeInt(u32, rec[28..32], tok_lens[i], .little);
        const has = n.hasSpan();
        const ns = if (has) n.src_start else 0;
        const ne = if (has) n.src_end else 0;
        const rs = if (has) map.normToRawStart(ns) else 0;
        var re = if (has) map.normToRawEnd(ne) else 0;
        if (n.typ == .document and has) {
            // The document span covers the whole raw input, including a stripped BOM.
            re = map.raw_len;
            std.mem.writeInt(u32, rec[40..44], 0, .little);
        }
        std.mem.writeInt(u32, rec[32..36], ns, .little);
        std.mem.writeInt(u32, rec[36..40], ne, .little);
        if (n.typ != .document) std.mem.writeInt(u32, rec[40..44], rs, .little);
        std.mem.writeInt(u32, rec[44..48], re, .little);
        std.mem.writeInt(u32, rec[48..52], ext_refs[i], .little);
        std.mem.writeInt(u32, rec[52..56], ext_lens[i], .little);
    }
    return buf;
}

pub const Error = error{ BadWire, OutOfMemory };

const Reader = struct {
    buf: []const u8,
    off: usize,
    fn u8_(r: *Reader) Error!u8 {
        if (r.off + 1 > r.buf.len) return error.BadWire;
        const v = r.buf[r.off];
        r.off += 1;
        return v;
    }
    fn u32_(r: *Reader) Error!u32 {
        if (r.off + 4 > r.buf.len) return error.BadWire;
        const v = std.mem.readInt(u32, r.buf[r.off..][0..4], .little);
        r.off += 4;
        return v;
    }
    fn bytes(r: *Reader, a: std.mem.Allocator) Error![]u8 {
        const len = try r.u32_();
        if (r.off + len > r.buf.len) return error.BadWire;
        const out = try a.dupe(u8, r.buf[r.off .. r.off + len]);
        r.off += len;
        return out;
    }
};

/// Decodes a wire buffer into an arena-backed tree.
pub fn decode(allocator: std.mem.Allocator, buf: []const u8) Error!*node.Node {
    if (buf.len < header_len) return error.BadWire;
    if (!std.mem.eql(u8, buf[0..8], magic)) return error.BadWire;
    const ver = std.mem.readInt(u32, buf[8..12], .little);
    if (ver != version) return error.BadWire;
    const count = std.mem.readInt(u32, buf[16..20], .little);
    const stride = std.mem.readInt(u32, buf[20..24], .little);
    if (stride != node_stride or count == 0) return error.BadWire;
    const input_len = std.mem.readInt(u32, buf[24..28], .little);
    const pool_len = std.mem.readInt(u32, buf[28..32], .little);
    const ext_len = std.mem.readInt(u32, buf[32..36], .little);
    const map_len = std.mem.readInt(u32, buf[36..40], .little);
    const secs = sections(count, input_len, pool_len, ext_len, map_len);
    if (secs.map + map_len > buf.len) return error.BadWire;

    const nodes = try allocator.alloc(*node.Node, count);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const off = secs.nodes + i * node_stride;
        if (off + node_stride > buf.len) return error.BadWire;
        const rec = buf[off .. off + node_stride];
        const t = std.mem.readInt(u16, rec[0..2], .little);
        const n = try node.Node.create(allocator, types.nodeTypeFromInt(t) orelse return error.BadWire);
        const flags = std.mem.readInt(u16, rec[2..4], .little);
        n.close = flags & (1 << 2) != 0;
        n.last_line_blank = flags & (1 << 3) != 0;
        n.last_line_checked = flags & (1 << 4) != 0;
        n.heading_setext = flags & (1 << 5) != 0;
        n.is_fenced_code_block = flags & (1 << 6) != 0;
        n.src_derived = flags & (1 << 8) != 0;
        n.src_start = std.mem.readInt(u32, rec[32..36], .little);
        n.src_end = std.mem.readInt(u32, rec[36..40], .little);
        const tok_ref = std.mem.readInt(u32, rec[24..28], .little);
        const tok_len = std.mem.readInt(u32, rec[28..32], .little);
        if (tok_ref != absent) {
            if (tok_ref + tok_len > pool_len) return error.BadWire;
            n.tokens = try allocator.dupe(u8, buf[secs.pool + tok_ref .. secs.pool + tok_ref + tok_len]);
        }
        const ext_ref = std.mem.readInt(u32, rec[48..52], .little);
        const ext_len2 = std.mem.readInt(u32, rec[52..56], .little);
        if (ext_ref != absent) {
            if (ext_ref + ext_len2 > ext_len) return error.BadWire;
            var r = Reader{ .buf = buf[secs.extras + ext_ref .. secs.extras + ext_ref + ext_len2], .off = 0 };
            try decodeExt(allocator, n, &r);
            if (r.off != r.buf.len) return error.BadWire;
        }
        nodes[i] = n;
    }
    i = 0;
    while (i < count) : (i += 1) {
        const rec = buf[secs.nodes + i * node_stride ..][0..node_stride];
        const parent = std.mem.readInt(u32, rec[4..8], .little);
        const fc = std.mem.readInt(u32, rec[8..12], .little);
        const lc = std.mem.readInt(u32, rec[12..16], .little);
        const prev = std.mem.readInt(u32, rec[16..20], .little);
        const next = std.mem.readInt(u32, rec[20..24], .little);
        if (parent != absent) nodes[i].parent = nodes[parent];
        if (fc != absent) nodes[i].first_child = nodes[fc];
        if (lc != absent) nodes[i].last_child = nodes[lc];
        if (prev != absent) nodes[i].prev = nodes[prev];
        if (next != absent) nodes[i].next = nodes[next];
    }
    return nodes[0];
}

fn decodeExt(allocator: std.mem.Allocator, n: *node.Node, r: *Reader) Error!void {
    switch (n.typ) {
        .heading => {
            n.heading_level = try r.u8_();
            n.heading_setext = (try r.u8_()) != 0;
        },
        .code_block => {
            n.code_block_fence_char = try r.u8_();
            n.code_block_fence_len = try r.u8_();
            n.is_fenced_code_block = (try r.u8_()) != 0;
            _ = try r.u8_();
            n.code_block_fence_offset = try r.u32_();
            n.code_block_open_fence = try r.bytes(allocator);
            n.code_block_info = try r.bytes(allocator);
            n.code_block_close_fence = try r.bytes(allocator);
        },
        .html_block => n.html_block_type = try r.u8_(),
        .code_block_fence_info_marker => n.code_block_info = try r.bytes(allocator),
        .code_block_fence_open_marker, .code_block_fence_close_marker => n.code_block_fence_len = try r.u32_(),
        .list, .list_item => {
            var d = node.ListData{};
            d.typ = try r.u8_();
            d.tight = (try r.u8_()) != 0;
            d.bullet_char = try r.u8_();
            d.delimiter = try r.u8_();
            d.checked = (try r.u8_()) != 0;
            _ = try r.u8_();
            _ = try r.u8_();
            _ = try r.u8_();
            d.start = @bitCast(try r.u32_());
            d.num = @bitCast(try r.u32_());
            d.padding = try r.u32_();
            d.marker_offset = try r.u32_();
            d.marker = try r.bytes(allocator);
            n.list_data = d;
        },
        .link, .image => {
            n.link_type = try r.u8_();
            n.link_ref_label = try r.bytes(allocator);
        },
        .table => {
            const len = try r.u32_();
            if (r.off + len > r.buf.len) return error.BadWire;
            n.table_aligns = try allocator.dupe(u8, r.buf[r.off .. r.off + len]);
            r.off += len;
        },
        .table_cell => n.table_cell_align = try r.u8_(),
        .task_list_item_marker => n.task_marker = try r.u8_(),
        .code_span => n.code_marker_len = try r.u32_(),
        else => {},
    }
}

test "wire roundtrip preserves the canonical AST dump" {
    const lutez = @import("../lutez.zig");
    const dump = @import("dump.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const md = "# hi *em*\n\n- a\n- b [l](/u \"t\")\n\n```zig\ncode\n```\n\n| a | b |\n|:-:|--:|\n| 1 | 2 |\n";
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    const before = try dump.dump(std.testing.allocator, doc.root);
    defer std.testing.allocator.free(before);
    const wire = try encode(a, doc.root, md, doc.source_map);
    const root2 = try decode(a, wire);
    const after = try dump.dump(std.testing.allocator, root2);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "wire decoder rejects corrupt buffers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.BadWire, decode(allocator, ""));
    try std.testing.expectError(error.BadWire, decode(allocator, "LUTEAST1"));
    var junk: [64]u8 = @splat(0xAA);
    @memcpy(junk[0..8], magic);
    try std.testing.expectError(error.BadWire, decode(allocator, &junk));
}
