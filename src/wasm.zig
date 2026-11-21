//! lutez WASM ABI (wasm32-freestanding, zero imports).
//! Handles are u32 slots; the AST is returned as packed (ptr << 32) | len.
const std = @import("std");
const lutez = @import("lutez");
const types = lutez.types;
const abi = lutez.abi;
const doc_mod = lutez.document;

pub const max_docs: u32 = 1024;
pub const no_handle: u32 = 0xFFFF_FFFF;
const allocator = std.heap.wasm_allocator;

var slots: [max_docs]?*doc_mod.Document = @splat(null);
threadlocal var last_error: [:0]const u8 = "no error";

fn setError(e: anyerror) void {
    last_error = abi.errorMessage(e);
}

fn pack(ptr: [*]const u8, len: usize) u64 {
    return (@as(u64, @intCast(@intFromPtr(ptr))) << 32) | @as(u64, @intCast(len));
}

export fn lutez_version() u32 {
    const v = types.version;
    return (@as(u32, v.major) << 16) | (@as(u32, v.minor) << 8) | @as(u32, v.patch);
}

export fn lutez_abi_version() u32 {
    return types.abi_version;
}

export fn lutez_alloc(len: u32) u32 {
    const buf = allocator.alloc(u8, len) catch return 0;
    return @intCast(@intFromPtr(buf.ptr));
}

export fn lutez_free(ptr: u32, len: u32) void {
    if (ptr == 0) return;
    allocator.free(@as([*]u8, @ptrFromInt(ptr))[0..len]);
}

/// Reads the shared C-layout options struct at `opts_ptr` (0 = defaults).
fn readOpts(opts_ptr: u32) types.Error!types.Options {
    if (opts_ptr == 0) return abi.fromC(null);
    const p: *const abi.lutez_opts = @ptrFromInt(opts_ptr);
    return abi.fromC(p);
}

/// Parse markdown; returns a handle (1..max_docs) or `no_handle` on error.
export fn lutez_parse(md_ptr: u32, md_len: u32, opts_ptr: u32) u32 {
    const options = readOpts(opts_ptr) catch |e| {
        setError(e);
        return no_handle;
    };
    const input: []const u8 = if (md_len == 0) &.{} else @as([*]const u8, @ptrFromInt(md_ptr))[0..md_len];
    const d = doc_mod.Document.create(allocator, input, options) catch |e| {
        setError(e);
        return no_handle;
    };
    var i: u32 = 0;
    while (i < max_docs) : (i += 1) {
        if (slots[i] == null) {
            slots[i] = d;
            return i + 1;
        }
    }
    d.destroy(allocator);
    setError(error.OutOfMemory);
    return no_handle;
}

fn docFor(handle: u32) ?*doc_mod.Document {
    if (handle == 0 or handle > max_docs) return null;
    return slots[handle - 1];
}

/// Packed `(ptr << 32) | len` of the serialized AST; 0 when the handle is invalid.
export fn lutez_doc_ast(handle: u32) u64 {
    const d = docFor(handle) orelse return 0;
    return pack(d.ast().ptr, d.ast().len);
}

export fn lutez_doc_free(handle: u32) void {
    const d = docFor(handle) orelse return;
    d.destroy(allocator);
    slots[handle - 1] = null;
}

export fn lutez_node_count(handle: u32) u32 {
    const d = docFor(handle) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    return v.count;
}

export fn lutez_node_type(handle: u32, node: u32) i32 {
    const d = docFor(handle) orelse return -1;
    const v = doc_mod.View.init(d.ast()) orelse return -1;
    return v.nodeType(node);
}

/// Packed pointer/length of the thread-local last error message.
export fn lutez_last_error_ptr() u64 {
    return pack(last_error.ptr, last_error.len);
}

/// Entry symbol: Zig 0.17 cannot pass `-fno-entry`; JS never calls this.
pub fn main() void {}

export fn lutez_wire_format_version() u32 {
    return types.wire_format_version;
}

export fn lutez_node_span(handle: u32, node: u32, out_start: u32, out_end: u32) u32 {
    const d = docFor(handle) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    const sp = v.span(node, false) orelse return 0;
    if (out_start != 0) {
        const p: *u32 = @ptrFromInt(out_start);
        p.* = sp.start;
    }
    if (out_end != 0) {
        const p: *u32 = @ptrFromInt(out_end);
        p.* = sp.end;
    }
    return 1;
}

export fn lutez_node_span_norm(handle: u32, node: u32, out_start: u32, out_end: u32) u32 {
    const d = docFor(handle) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    const sp = v.span(node, true) orelse return 0;
    if (out_start != 0) {
        const p: *u32 = @ptrFromInt(out_start);
        p.* = sp.start;
    }
    if (out_end != 0) {
        const p: *u32 = @ptrFromInt(out_end);
        p.* = sp.end;
    }
    return 1;
}

export fn lutez_node_span_derived(handle: u32, node: u32) u32 {
    const d = docFor(handle) orelse return 0;
    const v = doc_mod.View.init(d.ast()) orelse return 0;
    return @intFromBool(v.derived(node));
}
