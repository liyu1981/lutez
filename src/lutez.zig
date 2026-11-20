//! lutez — CommonMark 0.31.2 + GFM parser, Zig port of upstream lute.
//!
//! Public Zig API. The C ABI lives in `c_api.zig`, the WASM ABI in `wasm.zig`.
//!
//! Ported from: github.com/88250/lute @ v1.7.8 (Mulan PSL v2, (c) 2019-present b3log.org).
//! Scope: CommonMark/GFM parsing only; no renderers, no SiYuan/Vditor extensions.
//! See doc/PLAN.md §1 and doc/ZIG_PORT_FEASIBILITY.md.
//!
//! Status: M0 skeleton. `parse` is not implemented yet; it returns
//! `error.NotImplemented` so that the parity/build plumbing can be validated.

const std = @import("std");

pub const types = @import("types.zig");
pub const Options = types.Options;
pub const NodeType = types.NodeType;
pub const Error = types.Error;
pub const null_node = types.null_node;
pub const version = types.version;
pub const version_string = types.version_string;
pub const abi_version = types.abi_version;
pub const wire_format_version = types.wire_format_version;
pub const upstream_sha = types.upstream_sha;

/// A parsed document: owns a document arena and the serialized AST buffer.
///
/// Slice fields (`input`, `wire`) point into memory owned by the document and stay
/// valid until `deinit`. The caller's markdown buffer is never referenced after
/// `parse` returns (the lexer needs a mutable copy; see doc/PLAN.md §3.3).
pub const Doc = struct {
    allocator: std.mem.Allocator,
    input: []u8 = &.{},
    wire: []u8 = &.{},
    node_count: u32 = 0,

    /// Serialized AST, `doc/WIRE_FORMAT.md` v1. Valid until `deinit`.
    pub fn ast(self: *const Doc) []const u8 {
        return self.wire;
    }

    pub fn nodeCount(self: *const Doc) u32 {
        return self.node_count;
    }

    pub fn deinit(self: *Doc) void {
        if (self.input.len != 0) self.allocator.free(self.input);
        if (self.wire.len != 0) self.allocator.free(self.wire);
        self.* = undefined;
    }
};

/// Parse UTF-8 Markdown bytes into `Doc`.
///
/// - `input` is copied and normalized (CRLF→LF, trailing newline, NUL→U+FFFD); the
///   caller may free it immediately after the call.
/// - Malformed Markdown never returns an error; it yields text nodes like upstream.
/// - Errors are limited to allocation failure, invalid options, oversized input, and
///   internal invariants.
pub fn parse(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: Options,
) (Error || std.mem.Allocator.Error)!Doc {
    _ = allocator;
    _ = input;
    _ = options;
    // M0 skeleton: the lexer/parser land in M1/M2 (doc/PLAN.md §8).
    return error.NotImplemented;
}

test "version and upstream pin are exposed" {
    try std.testing.expectEqualStrings("0.1.0", version_string);
    try std.testing.expectEqual(@as(u32, 1), abi_version);
    try std.testing.expectEqual(@as(u32, 1), wire_format_version);
    try std.testing.expectEqual(@as(usize, 40), upstream_sha.len);
}

test "parse is a declared stub in M0" {
    var doc = parse(std.testing.allocator, "# hi\n", .{}) catch |err| {
        try std.testing.expectEqual(error.NotImplemented, err);
        return;
    };
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 0), doc.ast().len);
}
