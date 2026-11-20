//! Canonical AST text dump used by the parity corpus and conformance runner.
//! The Go side (parity/go/corpus) emits exactly the same format, one line per node:
//!     <depth>|<TypeString>|<hex tokens>|<k=v>,...
//! Only in-scope fields are emitted, in a fixed order (absent = not present).
//! This is a test/debug format, not the wire format.

const std = @import("std");
const node_mod = @import("node.zig");
const types = @import("../types.zig");

pub fn dump(allocator: std.mem.Allocator, root: *node_mod.Node) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try writeNode(allocator, root, 0, &out);
    return out.toOwnedSlice(allocator);
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), comptime fmt: []const u8, args: anytype) !void {
    var buf: [96]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, fmt, args);
    try out.appendSlice(allocator, s);
}

fn hexAppend(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), bytes: []const u8) !void {
    if (bytes.len == 0) {
        try out.append(allocator, '-');
        return;
    }
    try out.ensureUnusedCapacity(allocator, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes) |b| {
        out.appendAssumeCapacity(digits[b >> 4]);
        out.appendAssumeCapacity(digits[b & 0xf]);
    }
}

fn fieldInt(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), name: []const u8, v: anytype) !void {
    try out.append(allocator, '|');
    try out.appendSlice(allocator, name);
    try out.append(allocator, '=');
    try appendFmt(allocator, out, "{d}", .{v});
}

fn fieldHex(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), name: []const u8, bytes: []const u8) !void {
    try out.append(allocator, '|');
    try out.appendSlice(allocator, name);
    try out.append(allocator, '=');
    try hexAppend(allocator, out, bytes);
}

fn fieldBool(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), name: []const u8, v: bool) !void {
    try out.append(allocator, '|');
    try out.appendSlice(allocator, name);
    try out.append(allocator, '=');
    try out.append(allocator, if (v) '1' else '0');
}

fn writeNode(allocator: std.mem.Allocator, n: *node_mod.Node, depth: usize, out: *std.ArrayListUnmanaged(u8)) !void {
    try appendFmt(allocator, out, "{d}|{s}|", .{ depth, types.nodeTypeString(n.typ) });
    try hexAppend(allocator, out, n.tokens);

    switch (n.typ) {
        .heading => {
            if (n.heading_level != 0) try fieldInt(allocator, out, "level", n.heading_level);
            if (n.heading_setext) try fieldBool(allocator, out, "setext", true);
        },
        .code_block => {
            if (n.is_fenced_code_block) try fieldBool(allocator, out, "fenced", true);
            if (n.code_block_fence_char != 0) try fieldInt(allocator, out, "fence_char", n.code_block_fence_char);
            if (n.code_block_fence_len != 0) try fieldInt(allocator, out, "fence_len", n.code_block_fence_len);
            if (n.code_block_fence_offset != 0) try fieldInt(allocator, out, "fence_offset", n.code_block_fence_offset);
            if (n.code_block_open_fence.len != 0) try fieldHex(allocator, out, "open_fence", n.code_block_open_fence);
            if (n.code_block_info.len != 0) try fieldHex(allocator, out, "info", n.code_block_info);
            if (n.code_block_close_fence.len != 0) try fieldHex(allocator, out, "close_fence", n.code_block_close_fence);
        },
        .html_block => {
            if (n.html_block_type != 0) try fieldInt(allocator, out, "html_type", n.html_block_type);
        },
        .list, .list_item => {
            const d = n.list_data;
            try fieldInt(allocator, out, "list_typ", d.typ);
            if (d.tight) try fieldBool(allocator, out, "tight", true);
            if (d.bullet_char != 0) try fieldInt(allocator, out, "bullet", d.bullet_char);
            if (d.start != 0) try fieldInt(allocator, out, "start", d.start);
            if (d.delimiter != 0) try fieldInt(allocator, out, "delim", d.delimiter);
            if (d.padding != 0) try fieldInt(allocator, out, "padding", d.padding);
            if (d.marker_offset != 0) try fieldInt(allocator, out, "marker_offset", d.marker_offset);
            if (d.checked) try fieldBool(allocator, out, "checked", true);
            if (d.marker.len != 0) try fieldHex(allocator, out, "marker", d.marker);
            if (d.num != 0) try fieldInt(allocator, out, "num", d.num);
        },
        .table => {
            if (n.table_aligns.len != 0) {
                try out.append(allocator, '|');
                try out.appendSlice(allocator, "aligns=");
                for (n.table_aligns, 0..) |a, i| {
                    if (i != 0) try out.append(allocator, ',');
                    try appendFmt(allocator, out, "{d}", .{a});
                }
            }
        },
        .table_cell => {
            if (n.table_cell_align != 0) try fieldInt(allocator, out, "align", n.table_cell_align);
        },
        .link, .image => {
            try fieldInt(allocator, out, "link_type", n.link_type);
            if (n.link_ref_label.len != 0) try fieldHex(allocator, out, "label", n.link_ref_label);
        },
        .task_list_item_marker => {
            if (n.task_marker != 0) try fieldInt(allocator, out, "marker", n.task_marker);
        },
        .code_span => {
            if (n.code_marker_len != 0) try fieldInt(allocator, out, "code_marker_len", n.code_marker_len);
        },
        else => {},
    }
    try out.append(allocator, '\n');

    var c = n.first_child;
    while (c) |ch| : (c = ch.next) try writeNode(allocator, ch, depth + 1, out);
}
