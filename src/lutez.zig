//! lutez — CommonMark 0.31.2 + GFM parser, Zig port of upstream lute.
//! Ported from: github.com/88250/lute @ v1.7.8 (Mulan PSL v2, (c) 2019-present b3log.org).
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

pub const lex = @import("lex/lexer.zig");
pub const lex_token = @import("lex/token.zig");
pub const ast_node = @import("ast/node.zig");
pub const ast_dump = @import("ast/dump.zig");
pub const ast_wire = @import("ast/wire.zig");
pub const document = @import("doc.zig");
pub const abi = @import("abi.zig");
pub const html = @import("html/escape.zig");
pub const unicode = @import("unicode/unicode.zig");
pub const parse_mod = @import("parse/parse.zig");

/// A parsed document. All memory is owned by the document arena.
pub const source = @import("source.zig");
pub const positions = @import("positions.zig");

pub const Doc = struct {
    arena: std.heap.ArenaAllocator,
    root: *ast_node.Node,
    /// Normalized input (CRLF/CR -> LF, NUL -> U+FFFD, trailing LF).
    input: []u8,
    /// Raw<->normalized offset map for source spans.
    source_map: source.SourceMap,

    pub fn deinit(self: *Doc) void {
        self.arena.deinit();
    }
};

const builtin = @import("builtin");

/// Default backing allocator: WASM heap in freestanding builds, SMP allocator natively.
pub const default_allocator: std.mem.Allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.smp_allocator;

/// Parse UTF-8 Markdown into a document. Malformed Markdown never errors; the input is
/// copied into the arena so the caller may free it immediately.
pub fn parse(input: []const u8, options: Options) !Doc {
    return parseWith(default_allocator, input, options);
}

pub fn parseWithPresets(backing: std.mem.Allocator, input: []const u8, options: Options, presets: u32) !Doc {
    var parsed_options = options;
    parsed_options.extensions = presets;
    return parseWith(backing, input, parsed_options);
}

pub fn parseWith(backing: std.mem.Allocator, input: []const u8, options: Options) !Doc {
    var arena = std.heap.ArenaAllocator.init(backing);
    errdefer arena.deinit();
    const a = arena.allocator();
    if (input.len > std.math.maxInt(u32)) return error.InputTooLarge;
    const t = try parse_mod.parse(a, input, options);
    return .{ .arena = arena, .root = t.root, .input = t.input, .source_map = t.source_map };
}

comptime {
    _ = @import("lex/lexer.zig");
    _ = @import("lex/token.zig");
    _ = @import("ast/node.zig");
    _ = @import("ast/dump.zig");
    _ = @import("source.zig");
    _ = @import("positions.zig");
    _ = @import("extensions_tests.zig");
    _ = @import("ast/wire.zig");
    _ = @import("doc.zig");
    _ = @import("abi.zig");
    _ = @import("html/escape.zig");
    _ = @import("unicode/unicode.zig");
    _ = @import("parse/parse.zig");
    _ = @import("parse/tree.zig");
    _ = @import("parse/blocks.zig");
    _ = @import("parse/table.zig");
    _ = @import("parse/links.zig");
    _ = @import("parse/delimiter.zig");
    _ = @import("parse/inline.zig");
    _ = @import("parse/inline_html.zig");
    _ = @import("parse/auto_link.zig");
    _ = @import("conformance.zig");
    _ = @import("fuzz.zig");
}

test "parse returns a document" {
    var doc = try parse("# hi\n", .{});
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.typ);
}
