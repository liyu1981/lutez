//! Link reference definition parsing (ported from parse/linkrefdef_index.go later in M2).
const std = @import("std");
const tree = @import("tree.zig");
const links = @import("links.zig");

/// Returns the remaining tokens when a definition was consumed (may be empty).
pub fn parseLinkRefDef(ctx: *tree.Context, tokens: []u8) ?[]u8 {
    return links.parseLinkRefDef(ctx, tokens) catch null;
}
