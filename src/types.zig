//! lutez — shared types: node types, options, errors, version.
//
// Ported-from reference: lute/ast/node.go, lute/parse/parse.go @ v1.7.8 (Mulan PSL v2).
// Only the CommonMark/GFM subset is represented; see doc/AST_SCHEMA.md.

const std = @import("std");

/// Semantic version of the lutez library (not the ported upstream revision).
pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
pub const version_string = "0.1.0";

/// C ABI version. Bumped for any binary-incompatible change to include/lutez.h.
pub const abi_version: u32 = 1;

/// Wire-format version of the serialized AST. See doc/WIRE_FORMAT.md.
pub const wire_format_version: u32 = 1;

/// Upstream lute revision this port tracks. Must equal the `upstream/lute` submodule
/// gitlink; `tools/upstream.sh --verify` enforces this in CI.
pub const upstream_sha = "56b87cda10fb394981849aa8de19b8491aea62b4";

/// Sentinel node handle: "no node".
pub const null_node: u32 = 0xFFFF_FFFF;

/// Node types in scope, preserving upstream `ast.NodeType` numeric values.
/// Non-exhaustive so the wire decoder can reject unknown values safely.
pub const NodeType = enum(u16) {
    // CommonMark, 0..48
    document = 0,
    paragraph = 1,
    heading = 2,
    heading_c8h_marker = 3,
    thematic_break = 4,
    blockquote = 5,
    blockquote_marker = 6,
    list = 7,
    list_item = 8,
    html_block = 9,
    inline_html = 10,
    code_block = 11,
    code_block_fence_open_marker = 12,
    code_block_fence_close_marker = 13,
    code_block_fence_info_marker = 14,
    code_block_code = 15,
    text = 16,
    emphasis = 17,
    em_a6k_open_marker = 18,
    em_a6k_close_marker = 19,
    em_u8e_open_marker = 20,
    em_u8e_close_marker = 21,
    strong = 22,
    strong_a6k_open_marker = 23,
    strong_a6k_close_marker = 24,
    strong_u8e_open_marker = 25,
    strong_u8e_close_marker = 26,
    code_span = 27,
    code_span_open_marker = 28,
    code_span_content = 29,
    code_span_close_marker = 30,
    hard_break = 31,
    soft_break = 32,
    link = 33,
    image = 34,
    bang = 35,
    open_bracket = 36,
    close_bracket = 37,
    open_paren = 38,
    close_paren = 39,
    link_text = 40,
    link_dest = 41,
    link_title = 42,
    link_space = 43,
    html_entity = 44,
    link_ref_def_block = 45,
    link_ref_def = 46,
    less = 47,
    greater = 48,

    // GFM, 100..109
    task_list_item_marker = 100,
    strikethrough = 101,
    strikethrough1_open_marker = 102,
    strikethrough1_close_marker = 103,
    strikethrough2_open_marker = 104,
    strikethrough2_close_marker = 105,
    table = 106,
    table_head = 107,
    table_row = 108,
    table_cell = 109,

    // Backslash escapes, 400..401
    backslash = 400,
    backslash_content = 401,

    _,
};

/// Upstream stringer name (e.g. `"NodeParagraph"`), used by harness JSON only.
pub fn nodeTypeString(t: NodeType) []const u8 {
    return switch (t) {
        .document => "NodeDocument",
        .paragraph => "NodeParagraph",
        .heading => "NodeHeading",
        .heading_c8h_marker => "NodeHeadingC8hMarker",
        .thematic_break => "NodeThematicBreak",
        .blockquote => "NodeBlockquote",
        .blockquote_marker => "NodeBlockquoteMarker",
        .list => "NodeList",
        .list_item => "NodeListItem",
        .html_block => "NodeHTMLBlock",
        .inline_html => "NodeInlineHTML",
        .code_block => "NodeCodeBlock",
        .code_block_fence_open_marker => "NodeCodeBlockFenceOpenMarker",
        .code_block_fence_close_marker => "NodeCodeBlockFenceCloseMarker",
        .code_block_fence_info_marker => "NodeCodeBlockFenceInfoMarker",
        .code_block_code => "NodeCodeBlockCode",
        .text => "NodeText",
        .emphasis => "NodeEmphasis",
        .em_a6k_open_marker => "NodeEmA6kOpenMarker",
        .em_a6k_close_marker => "NodeEmA6kCloseMarker",
        .em_u8e_open_marker => "NodeEmU8eOpenMarker",
        .em_u8e_close_marker => "NodeEmU8eCloseMarker",
        .strong => "NodeStrong",
        .strong_a6k_open_marker => "NodeStrongA6kOpenMarker",
        .strong_a6k_close_marker => "NodeStrongA6kCloseMarker",
        .strong_u8e_open_marker => "NodeStrongU8eOpenMarker",
        .strong_u8e_close_marker => "NodeStrongU8eCloseMarker",
        .code_span => "NodeCodeSpan",
        .code_span_open_marker => "NodeCodeSpanOpenMarker",
        .code_span_content => "NodeCodeSpanContent",
        .code_span_close_marker => "NodeCodeSpanCloseMarker",
        .hard_break => "NodeHardBreak",
        .soft_break => "NodeSoftBreak",
        .link => "NodeLink",
        .image => "NodeImage",
        .bang => "NodeBang",
        .open_bracket => "NodeOpenBracket",
        .close_bracket => "NodeCloseBracket",
        .open_paren => "NodeOpenParen",
        .close_paren => "NodeCloseParen",
        .link_text => "NodeLinkText",
        .link_dest => "NodeLinkDest",
        .link_title => "NodeLinkTitle",
        .link_space => "NodeLinkSpace",
        .html_entity => "NodeHTMLEntity",
        .link_ref_def_block => "NodeLinkRefDefBlock",
        .link_ref_def => "NodeLinkRefDef",
        .less => "NodeLess",
        .greater => "NodeGreater",
        .task_list_item_marker => "NodeTaskListItemMarker",
        .strikethrough => "NodeStrikethrough",
        .strikethrough1_open_marker => "NodeStrikethrough1OpenMarker",
        .strikethrough1_close_marker => "NodeStrikethrough1CloseMarker",
        .strikethrough2_open_marker => "NodeStrikethrough2OpenMarker",
        .strikethrough2_close_marker => "NodeStrikethrough2CloseMarker",
        .table => "NodeTable",
        .table_head => "NodeTableHead",
        .table_row => "NodeTableRow",
        .table_cell => "NodeTableCell",
        .backslash => "NodeBackslash",
        .backslash_content => "NodeBackslashContent",
        else => "NodeUnknown",
    };
}

/// Parse a node type from its upstream numeric value; rejects out-of-scope types.
pub fn nodeTypeFromInt(v: u16) ?NodeType {
    const t: NodeType = @fromBackingInt(@intCast(v));
    return if (std.mem.eql(u8, nodeTypeString(t), "NodeUnknown")) null else t;
}

/// Parser options. Defaults mirror upstream `parse.NewOptions()` for the scoped subset.
pub const Options = struct {
    gfm_table: bool = true,
    gfm_task_list_item: bool = true,
    gfm_strikethrough: bool = true,
    gfm_strikethrough1: bool = true,
    gfm_auto_link: bool = true,
    inline_asterisk: bool = true,
    inline_underscore: bool = true,
    setext: bool = true,
    indent_code_block: bool = true,
    link_ref: bool = true,
    data_image: bool = true,

    pub const defaults: Options = .{};
};

/// Error codes exposed through the C ABI (`lutez_last_error_code`).
pub const Error = error{
    OutOfMemory,
    InvalidOptions,
    InputTooLarge,
    NotImplemented,
    Internal,
};

pub fn errorCode(e: anyerror) i32 {
    return switch (e) {
        error.OutOfMemory => 1,
        error.InvalidOptions => 2,
        error.InputTooLarge => 3,
        error.NotImplemented => 4,
        error.Internal => 5,
        else => 99,
    };
}

pub fn errorMessage(e: anyerror) [:0]const u8 {
    return switch (e) {
        error.OutOfMemory => "out of memory",
        error.InvalidOptions => "invalid options",
        error.InputTooLarge => "input too large (limit: 2 GiB - 1)",
        error.NotImplemented => "not implemented",
        error.Internal => "internal error",
        else => "unknown error",
    };
}

test "node type numeric values match upstream" {
    try std.testing.expectEqual(@as(u16, 0), @backingInt(NodeType.document));
    try std.testing.expectEqual(@as(u16, 48), @backingInt(NodeType.greater));
    try std.testing.expectEqual(@as(u16, 100), @backingInt(NodeType.task_list_item_marker));
    try std.testing.expectEqual(@as(u16, 109), @backingInt(NodeType.table_cell));
    try std.testing.expectEqual(@as(u16, 401), @backingInt(NodeType.backslash_content));
}

test "out-of-scope node types are rejected" {
    try std.testing.expectEqual(@as(?NodeType, null), nodeTypeFromInt(200)); // emoji
    try std.testing.expectEqual(@as(?NodeType, null), nodeTypeFromInt(300)); // math
    try std.testing.expectEqual(@as(?NodeType, null), nodeTypeFromInt(999));
    try std.testing.expectEqual(NodeType.table_cell, nodeTypeFromInt(109).?);
}

test "type strings are the upstream stringer names" {
    try std.testing.expectEqualStrings("NodeParagraph", nodeTypeString(.paragraph));
    try std.testing.expectEqualStrings("NodeTable", nodeTypeString(.table));
    try std.testing.expectEqualStrings("NodeUnknown", nodeTypeString(@fromBackingInt(@intCast(4242))));
}

test "default options are all-on for scoped flags" {
    const o = Options.defaults;
    try std.testing.expect(o.gfm_table and o.gfm_task_list_item and o.gfm_strikethrough);
    try std.testing.expect(o.gfm_strikethrough1 and o.gfm_auto_link);
    try std.testing.expect(o.inline_asterisk and o.inline_underscore and o.setext);
    try std.testing.expect(o.indent_code_block and o.link_ref and o.data_image);
}
