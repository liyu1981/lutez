//! lutez WASM ABI (draft).
//!
//! Built with:
//!   zig build-exe src/wasm.zig -target wasm32-freestanding -fno-entry -rdynamic \
//!     -O ReleaseSmall -femit-bin=zig-out/lib/lutez.wasm
//!
//! Zero imports, no libc. Handles are `u32` slots; no pointers cross the boundary
//! except the packed `(ptr << 32) | len` returns, which JS splits and wraps in a
//! Uint8Array. Any call may grow memory: re-create views afterwards.
//!
//! Status: M0 skeleton — allocation and parsing land in M1/M5.

const std = @import("std");
const types = @import("lutez").types;

pub const max_docs: u32 = 1024;
pub const no_handle: u32 = 0xFFFF_FFFF;

/// Slot table: 0 = free. Documents are allocated in M5 (`doc.zig` + arena).
var doc_slots: [max_docs]u32 = @splat(0);

threadlocal var last_error: [:0]const u8 = "no error";

fn setError(msg: [:0]const u8) void {
    last_error = msg;
}

/// Pack a slice into `(ptr << 32) | len` for JS.
fn pack(ptr: [*]const u8, len: usize) u64 {
    return (@as(u64, @intCast(@intFromPtr(ptr))) << 32) | @as(u64, @intCast(len));
}

export fn lutez_version() u32 {
    const v = types.version;
    return (@as(u32, v.major) << 16) | (@as(u32, v.minor) << 8) | @as(u32, v.patch);
}

/// Allocate `len` bytes in the WASM heap; returns 0 on failure.
export fn lutez_alloc(len: u32) u32 {
    _ = len;
    // M1: std.heap.wasm_allocator.alloc(u8, len)
    return 0;
}

export fn lutez_free(ptr: u32) void {
    _ = ptr;
}

/// Returns a document handle, or `no_handle` on error (see `lutez_last_error_ptr`).
export fn lutez_parse(md_ptr: u32, md_len: u32, opts_ptr: u32) u32 {
    _ = md_ptr;
    _ = md_len;
    _ = opts_ptr;
    setError("not implemented");
    return no_handle;
}

/// Packed `(ptr << 32) | len` of the serialized AST; ptr = 0 when `handle` is invalid.
export fn lutez_doc_ast(handle: u32) u64 {
    if (handle >= max_docs) return 0;
    return 0;
}

export fn lutez_doc_free(handle: u32) void {
    if (handle >= max_docs) return;
    doc_slots[handle] = 0;
}

/// Packed `(ptr << 32) | len` of the thread-local last error message.
export fn lutez_last_error_ptr() u64 {
    return pack(last_error.ptr, last_error.len);
}

export fn lutez_abi_version() u32 {
    return types.abi_version;
}

/// Zig 0.17's Build API cannot pass `-fno-entry` (the flag exists only on the CLI),
/// and the WASM linker requires an entry symbol. An empty `main` supplies `_start`
/// without adding imports or startup dependencies; JS glue never calls it.
pub fn main() void {}
