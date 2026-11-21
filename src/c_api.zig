//! lutez C ABI v2: opaque documents, wire AST, ergonomic accessors, thread-local errors.
const std = @import("std");
const lutez = @import("lutez");
const types = lutez.types;
const abi = lutez.abi;
const doc_mod = lutez.document;

pub const LUTEZ_ABI_VERSION: u32 = types.abi_version;
pub const LUTEZ_WIRE_FORMAT_VERSION: u32 = types.wire_format_version;
pub const lutez_opts = abi.lutez_opts;
pub const LUTEZ_OPTS_V1_SIZE: u32 = abi.opts_v1_size;
pub const lutez_doc = opaque {};

pub const LUTEZ_OK = abi.LUTEZ_OK;
pub const LUTEZ_ERR_OOM = abi.LUTEZ_ERR_OOM;
pub const LUTEZ_ERR_INVALID_OPTIONS = abi.LUTEZ_ERR_INVALID_OPTIONS;
pub const LUTEZ_ERR_INPUT_TOO_LARGE = abi.LUTEZ_ERR_INPUT_TOO_LARGE;
pub const LUTEZ_ERR_NOT_IMPLEMENTED = abi.LUTEZ_ERR_NOT_IMPLEMENTED;
pub const LUTEZ_ERR_INTERNAL = abi.LUTEZ_ERR_INTERNAL;
pub const LUTEZ_ERR_BAD_WIRE = abi.LUTEZ_ERR_BAD_WIRE;

const backing = std.heap.c_allocator;

threadlocal var last_error: [:0]const u8 = "no error";
threadlocal var last_code: i32 = LUTEZ_OK;

fn setError(e: anyerror) void {
    last_error = abi.errorMessage(e);
    last_code = abi.errorCode(e);
}

fn clearError() void {
    last_error = "no error";
    last_code = LUTEZ_OK;
}

fn impl(doc: ?*const lutez_doc) ?*const doc_mod.Document {
    return @ptrCast(@alignCast(doc));
}

fn mutImpl(doc: ?*lutez_doc) ?*doc_mod.Document {
    return @ptrCast(@alignCast(doc));
}

export fn lutez_version_string() [*:0]const u8 {
    return types.version_string;
}

export fn lutez_abi_version() u32 {
    return LUTEZ_ABI_VERSION;
}

export fn lutez_wire_format_version() u32 {
    return LUTEZ_WIRE_FORMAT_VERSION;
}

export fn lutez_last_error() [*:0]const u8 {
    return last_error.ptr;
}

export fn lutez_last_error_code() i32 {
    return last_code;
}

/// Parse UTF-8 markdown. Returns NULL on failure (see lutez_last_error).
export fn lutez_parse(md: ?[*]const u8, len: usize, opts: ?*const lutez_opts) ?*lutez_doc {
    clearError();
    if (len > std.math.maxInt(u32)) {
        setError(error.InputTooLarge);
        return null;
    }
    if (len != 0 and md == null) {
        last_error = "NULL markdown pointer with non-zero length";
        last_code = LUTEZ_ERR_INVALID_OPTIONS;
        return null;
    }
    const options = abi.fromC(opts) catch |e| {
        setError(e);
        return null;
    };
    const input: []const u8 = if (len == 0) &.{} else md.?[0..len];
    const d = doc_mod.Document.create(backing, input, options) catch |e| {
        setError(e);
        return null;
    };
    return @ptrCast(d);
}

/// Serialized AST bytes (doc/WIRE_FORMAT.md). Valid until lutez_doc_free.
export fn lutez_doc_ast(doc: ?*const lutez_doc, out_len: ?*usize) ?[*]const u8 {
    if (out_len) |p| p.* = 0;
    const d = impl(doc) orelse return null;
    const w = d.ast();
    if (out_len) |p| p.* = w.len;
    return w.ptr;
}

export fn lutez_doc_abi_version(doc: ?*const lutez_doc) u32 {
    if (impl(doc) == null) return 0;
    return LUTEZ_ABI_VERSION;
}

export fn lutez_doc_free(doc: ?*lutez_doc) void {
    const d = mutImpl(doc) orelse return;
    d.destroy(backing);
}

export fn lutez_node_count(doc: ?*const lutez_doc) u32 {
    const d = impl(doc) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    return v.count;
}

export fn lutez_node_type(doc: ?*const lutez_doc, node: u32) i32 {
    const d = impl(doc) orelse return -1;
    const v = doc_mod.View.init(d.ast()) orelse return -1;
    return v.nodeType(node);
}

export fn lutez_node_parent(doc: ?*const lutez_doc, node: u32) u32 {
    const d = impl(doc) orelse return types.null_node;
    const v = doc_mod.View.init(d.ast()) orelse return types.null_node;
    return v.parent(node);
}

export fn lutez_node_first_child(doc: ?*const lutez_doc, node: u32) u32 {
    const d = impl(doc) orelse return types.null_node;
    const v = doc_mod.View.init(d.ast()) orelse return types.null_node;
    return v.child(node, false);
}

export fn lutez_node_next(doc: ?*const lutez_doc, node: u32) u32 {
    const d = impl(doc) orelse return types.null_node;
    const v = doc_mod.View.init(d.ast()) orelse return types.null_node;
    return v.sibling(node, true);
}

export fn lutez_node_span(doc: ?*const lutez_doc, node: u32, out_start: ?*u32, out_end: ?*u32) u32 {
    if (out_start) |p| p.* = 0;
    if (out_end) |p| p.* = 0;
    const d = impl(doc) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    const sp = v.span(node, false) orelse return 0;
    if (out_start) |p| p.* = sp.start;
    if (out_end) |p| p.* = sp.end;
    return 1;
}

export fn lutez_node_span_norm(doc: ?*const lutez_doc, node: u32, out_start: ?*u32, out_end: ?*u32) u32 {
    if (out_start) |p| p.* = 0;
    if (out_end) |p| p.* = 0;
    const d = impl(doc) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    const sp = v.span(node, true) orelse return 0;
    if (out_start) |p| p.* = sp.start;
    if (out_end) |p| p.* = sp.end;
    return 1;
}

export fn lutez_node_span_derived(doc: ?*const lutez_doc, node: u32) u32 {
    const d = impl(doc) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    return @intFromBool(v.derived(node));
}

export fn lutez_node_data(doc: ?*const lutez_doc, node: u32, out_len: ?*usize) ?[*]const u8 {
    if (out_len) |p| p.* = 0;
    const d = impl(doc) orelse return null;
    const v = doc_mod.View.init(d.ast()) orelse return null;
    const toks = v.tokens(node);
    if (out_len) |p| p.* = toks.len;
    return toks.ptr;
}

test "C ABI parses and exposes the wire AST" {
    const md = "# hi *em*\n";
    const doc = lutez_parse(md.ptr, md.len, null).?;
    defer lutez_doc_free(doc);
    try std.testing.expect(lutez_doc_abi_version(doc) == 2);
    try std.testing.expect(lutez_node_count(doc) >= 3);
    try std.testing.expectEqual(@as(i32, 0), lutez_node_type(doc, 0));
    var len: usize = 0;
    const ast = lutez_doc_ast(doc, &len).?;
    try std.testing.expect(len > 40);
    try std.testing.expectEqualStrings("LUTEAST1", ast[0..8]);
    var s0: u32 = 1;
    var e0: u32 = 2;
    try std.testing.expectEqual(@as(u32, 1), lutez_node_span(doc, 0, &s0, &e0));
    try std.testing.expectEqual(@as(u32, 0), s0);
    try std.testing.expect(e0 >= 6);
    try std.testing.expectEqual(types.null_node, lutez_node_parent(doc, 0));
}

test "C ABI reports invalid options and NULL input" {
    clearError();
    try std.testing.expectEqual(@as(?*lutez_doc, null), lutez_parse(null, 1, null));
    try std.testing.expectEqual(LUTEZ_ERR_INVALID_OPTIONS, lutez_last_error_code());
    var o = std.mem.zeroes(lutez_opts);
    o.struct_size = 2;
    try std.testing.expectEqual(@as(?*lutez_doc, null), lutez_parse(null, 0, &o));
    try std.testing.expectEqual(LUTEZ_ERR_INVALID_OPTIONS, lutez_last_error_code());
}
