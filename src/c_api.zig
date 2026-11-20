//! lutez C ABI v1 (draft).
//!
//! Status: M0 skeleton. Only the version/error surface is functional; `lutez_parse`
//! returns NULL with `LUTEZ_ERR_NOT_IMPLEMENTED` until M2/M5 (doc/PLAN.md §8).
//!
//! Rules (doc/PLAN.md §3.6):
//!   - no AST structs cross the boundary; documents are opaque handles;
//!   - no panic may escape an exported function: every entry point validates and
//!     returns NULL/0 with a thread-local error instead;
//!   - `lutez_last_error` returns static storage, never document memory.

const std = @import("std");
// The public module is imported by name so that a file belongs to exactly one module
// (`lutez`); this also keeps the C surface pinned to the documented Zig API.
const lutez = @import("lutez");
const types = lutez.types;

pub const LUTEZ_ABI_VERSION: u32 = types.abi_version;

pub const LUTEZ_OK: i32 = 0;
pub const LUTEZ_ERR_OOM: i32 = 1;
pub const LUTEZ_ERR_INVALID_OPTIONS: i32 = 2;
pub const LUTEZ_ERR_INPUT_TOO_LARGE: i32 = 3;
pub const LUTEZ_ERR_NOT_IMPLEMENTED: i32 = 4;
pub const LUTEZ_ERR_INTERNAL: i32 = 5;

/// Versioned options struct. `struct_size` must be set to `@sizeOf(lutez_opts)` by
/// callers (see `LUTEZ_OPTS_V1_SIZE`). Flags are `u8` 0/1, not C `bool`, for ABI
/// stability across compilers/architectures.
pub const lutez_opts = extern struct {
    struct_size: u32,
    gfm_table: u8,
    gfm_task_list_item: u8,
    gfm_strikethrough: u8,
    gfm_strikethrough1: u8,
    gfm_auto_link: u8,
    inline_asterisk: u8,
    inline_underscore: u8,
    setext: u8,
    indent_code_block: u8,
    link_ref: u8,
    data_image: u8,
    reserved: u8,
};

pub const LUTEZ_OPTS_V1_SIZE: u32 = @sizeOf(lutez_opts);

comptime {
    if (@sizeOf(lutez_opts) != 16) @compileError("lutez_opts v1 must stay 16 bytes");
    if (@offsetOf(lutez_opts, "struct_size") != 0) @compileError("struct_size must be first");
    if (@offsetOf(lutez_opts, "gfm_table") != 4) @compileError("flag layout changed");
}

/// Opaque document handle. Defined in `doc.zig` from M1 onward; intentionally has no
/// public definition so C consumers cannot depend on the layout.
pub const lutez_doc = opaque {};

threadlocal var last_error: [:0]const u8 = "no error";
threadlocal var last_code: i32 = LUTEZ_OK;

fn setError(err: anyerror) void {
    last_error = types.errorMessage(err);
    last_code = types.errorCode(err);
}

fn clearError() void {
    last_error = "no error";
    last_code = LUTEZ_OK;
}

fn parseOptions(opts: ?*const lutez_opts) types.Error!lutez.Options {
    var out: lutez.Options = .{};
    const o = opts orelse return out; // NULL = defaults
    if (o.struct_size < LUTEZ_OPTS_V1_SIZE) return error.InvalidOptions;
    if (o.reserved != 0) return error.InvalidOptions;
    out.gfm_table = 0 != o.gfm_table;
    out.gfm_task_list_item = 0 != o.gfm_task_list_item;
    out.gfm_strikethrough = 0 != o.gfm_strikethrough;
    out.gfm_strikethrough1 = 0 != o.gfm_strikethrough1;
    out.gfm_auto_link = 0 != o.gfm_auto_link;
    out.inline_asterisk = 0 != o.inline_asterisk;
    out.inline_underscore = 0 != o.inline_underscore;
    out.setext = 0 != o.setext;
    out.indent_code_block = 0 != o.indent_code_block;
    out.link_ref = 0 != o.link_ref;
    out.data_image = 0 != o.data_image;
    return out;
}

export fn lutez_version_string() [*:0]const u8 {
    return types.version_string ++ "";
}

export fn lutez_abi_version() u32 {
    return LUTEZ_ABI_VERSION;
}

export fn lutez_last_error() [*:0]const u8 {
    return last_error.ptr;
}

export fn lutez_last_error_code() i32 {
    return last_code;
}

/// Parse UTF-8 markdown. Returns NULL on failure (see `lutez_last_error`).
export fn lutez_parse(
    md: ?[*]const u8,
    len: usize,
    opts: ?*const lutez_opts,
) ?*lutez_doc {
    clearError();
    const options = parseOptions(opts) catch |err| {
        setError(err);
        return null;
    };
    _ = options;
    if (len != 0 and md == null) {
        last_error = "NULL markdown pointer with non-zero length";
        last_code = LUTEZ_ERR_INVALID_OPTIONS;
        return null;
    }
    if (len > std.math.maxInt(u32)) {
        setError(error.InputTooLarge);
        return null;
    }
    // M0 skeleton: M5 wires this to lutez.parse + doc.zig.
    setError(error.NotImplemented);
    return null;
}

/// Serialized AST bytes (doc/WIRE_FORMAT.md). Valid until `lutez_doc_free`.
export fn lutez_doc_ast(doc: ?*const lutez_doc, out_len: ?*usize) ?[*]const u8 {
    if (out_len) |p| p.* = 0;
    if (doc == null) return null;
    return null;
}

export fn lutez_doc_abi_version(doc: ?*const lutez_doc) u32 {
    if (doc == null) return 0;
    return LUTEZ_ABI_VERSION;
}

export fn lutez_doc_free(doc: ?*lutez_doc) void {
    if (doc != null) {
        // M5: release the document arena; documents are never allocated in M0.
    }
}

// Ergonomic accessors — drafts, implemented in M5.

export fn lutez_node_count(doc: ?*const lutez_doc) u32 {
    _ = doc;
    return 0;
}

export fn lutez_node_type(doc: ?*const lutez_doc, node: u32) i32 {
    _ = doc;
    _ = node;
    return -1;
}

export fn lutez_node_first_child(doc: ?*const lutez_doc, node: u32) u32 {
    _ = doc;
    _ = node;
    return types.null_node;
}

export fn lutez_node_next(doc: ?*const lutez_doc, node: u32) u32 {
    _ = doc;
    _ = node;
    return types.null_node;
}

export fn lutez_node_data(doc: ?*const lutez_doc, node: u32, out_len: ?*usize) ?[*]const u8 {
    _ = doc;
    _ = node;
    if (out_len) |p| p.* = 0;
    return null;
}

test "opts struct layout is ABI-frozen" {
    try std.testing.expectEqual(@as(u32, 16), LUTEZ_OPTS_V1_SIZE);
    var o = std.mem.zeroes(lutez_opts);
    o.struct_size = LUTEZ_OPTS_V1_SIZE;
    const parsed = try parseOptions(&o);
    try std.testing.expect(!parsed.gfm_table); // zero-filled = all off
}

test "NULL options mean upstream defaults" {
    const parsed = try parseOptions(null);
    try std.testing.expect(parsed.gfm_table);
    try std.testing.expect(parsed.setext);
    try std.testing.expect(parsed.link_ref);
}

test "undersized opts are rejected" {
    var o = std.mem.zeroes(lutez_opts);
    o.struct_size = 4;
    try std.testing.expectError(error.InvalidOptions, parseOptions(&o));
}

test "exported error surface is thread-local and resets" {
    clearError();
    try std.testing.expectEqualStrings("no error", std.mem.span(lutez_last_error()));
    try std.testing.expectEqual(LUTEZ_OK, lutez_last_error_code());
    try std.testing.expectEqual(@as(?*lutez_doc, null), lutez_parse(null, 1, null));
    try std.testing.expectEqualStrings("invalid options", std.mem.span(lutez_last_error()));
}

test "stub parse reports not implemented" {
    const md = "# hi\n";
    try std.testing.expectEqual(@as(?*lutez_doc, null), lutez_parse(md.ptr, md.len, null));
    try std.testing.expectEqual(LUTEZ_ERR_NOT_IMPLEMENTED, lutez_last_error_code());
}
