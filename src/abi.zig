//! Shared C-layout options ABI (used by c_api.zig and wasm.zig).
const std = @import("std");
const types = @import("types.zig");

pub const LUTEZ_OK: i32 = 0;
pub const LUTEZ_ERR_OOM: i32 = 1;
pub const LUTEZ_ERR_INVALID_OPTIONS: i32 = 2;
pub const LUTEZ_ERR_INPUT_TOO_LARGE: i32 = 3;
pub const LUTEZ_ERR_NOT_IMPLEMENTED: i32 = 4;
pub const LUTEZ_ERR_INTERNAL: i32 = 5;
pub const LUTEZ_ERR_BAD_WIRE: i32 = 6;

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
    strip_bom: u8,
};

pub const opts_v1_size: u32 = @sizeOf(lutez_opts);

comptime {
    if (@sizeOf(lutez_opts) != 16) @compileError("lutez_opts v1 must stay 16 bytes");
}

pub fn fromC(opts: ?*const lutez_opts) types.Error!types.Options {
    var out: types.Options = .{};
    const o = opts orelse return out; // NULL = upstream defaults
    if (o.struct_size < opts_v1_size) return error.InvalidOptions;
    out.gfm_table = o.gfm_table != 0;
    out.gfm_task_list_item = o.gfm_task_list_item != 0;
    out.gfm_strikethrough = o.gfm_strikethrough != 0;
    out.gfm_strikethrough1 = o.gfm_strikethrough1 != 0;
    out.gfm_auto_link = o.gfm_auto_link != 0;
    out.inline_asterisk = o.inline_asterisk != 0;
    out.inline_underscore = o.inline_underscore != 0;
    out.setext = o.setext != 0;
    out.indent_code_block = o.indent_code_block != 0;
    out.link_ref = o.link_ref != 0;
    out.data_image = o.data_image != 0;
    out.strip_bom = o.strip_bom != 0;
    return out;
}

pub fn errorCode(e: anyerror) i32 {
    return switch (e) {
        error.OutOfMemory => LUTEZ_ERR_OOM,
        error.InvalidOptions => LUTEZ_ERR_INVALID_OPTIONS,
        error.InputTooLarge => LUTEZ_ERR_INPUT_TOO_LARGE,
        error.BadWire => LUTEZ_ERR_BAD_WIRE,
        else => LUTEZ_ERR_INTERNAL,
    };
}

pub fn errorMessage(e: anyerror) [:0]const u8 {
    return switch (e) {
        error.OutOfMemory => "out of memory",
        error.InvalidOptions => "invalid options",
        error.InputTooLarge => "input too large (limit: 2 GiB - 1)",
        error.BadWire => "invalid wire buffer",
        else => "internal error",
    };
}

test "options ABI" {
    var o = std.mem.zeroes(lutez_opts);
    o.struct_size = opts_v1_size;
    const p = try fromC(&o);
    try std.testing.expect(!p.gfm_table);
    const d = try fromC(null);
    try std.testing.expect(d.gfm_table and d.setext and d.link_ref and d.strip_bom);
    o.struct_size = 4;
    try std.testing.expectError(error.InvalidOptions, fromC(&o));
}
