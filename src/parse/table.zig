//! GFM tables. Ported from lute/parse/table.go @ v1.7.8 (Mulan PSL v2).
//! Kramdown IAL / Protyle / math-code interactions are out of scope and stripped.
const std = @import("std");
const types = @import("../types.zig");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const tree = @import("tree.zig");

pub fn startFromSetext(t: *tree.Tree, p: *node.Node) !bool {
    const t0 = try parseTable0(t, p, p.tokens);
    if (t0) |table| {
        p.typ = .table;
        p.table_aligns = table.table_aligns;
        while (table.first_child) |tr| p.appendChild(tr);
        p.tokens = &.{};
        return true;
    }
    return false;
}

pub fn finalizeParagraph(ctx: *tree.Context, p: *node.Node) !bool {
    var tokens: []u8 = &.{};
    var line_cnt: usize = 0;
    var i: usize = 0;
    while (i < p.tokens.len) : (i += 1) {
        if (p.tokens[i] == lex.newline or i == 0) {
            tokens = if (i == 0) p.tokens[i..] else p.tokens[i + 1 ..];
            if (try parseTable0(ctx.tree, p, tokens)) |table| {
                var para_tokens: ?[]u8 = null;
                if (line_cnt > 0) para_tokens = p.tokens[0..i];
                if (para_tokens) |pt| {
                    p.tokens = pt;
                    table.tokens = tokens;
                    p.insertAfter(table);
                    table.close = true;
                    ctx.tip = table;
                    return true;
                } else {
                    p.typ = .table;
                    p.table_aligns = table.table_aligns;
                    while (table.first_child) |tr| p.appendChild(tr);
                    if (table.hasSpan()) p.setSpan(table.src_start, table.src_end);
                    return true;
                }
            }
        }
        line_cnt += 1;
    }
    return false;
}

fn parseTable0(t: *tree.Tree, p: *node.Node, tokens: []u8) !?*node.Node {
    if (std.mem.indexOfScalar(u8, tokens, lex.pipe) == null and !noPipeSingleColTable(tokens)) return null;
    const lines = try lex.split(t.allocator, tokens, lex.newline);
    if (lines.items.len < 2) return null;
    const delim_row = lex.trimWhitespace(lines.items[1]);
    if (delim_row.len < 2) return null;
    const aligns = (try parseTableDelimRow(t.allocator, @constCast(delim_row))) orelse return null;
    if (lines.items.len == 2 and aligns.len == 1 and aligns[0] == 0 and std.mem.indexOfScalar(u8, tokens, lex.pipe) == null) return null;
    const head_row = (try parseTableRow(t, p, @constCast(lex.trimWhitespace(lines.items[0])), aligns, true)) orelse return null;
    const table = try node.Node.create(t.allocator, .table);
    table.table_aligns = aligns;
    const buf = bufferOf(p);
    if (node.mapTokenSlice(buf, p.token_map, tokens)) |sp| table.setSpan(sp.start, sp.end) else table.setSpan(p.src_start, p.src_end);
    table.appendChild(try newTableHead(t, head_row));
    var i: usize = 2;
    while (i < lines.items.len) : (i += 1) {
        const row = (try parseTableRow(t, p, @constCast(lex.trimWhitespace(lines.items[i])), aligns, false)) orelse return null;
        table.appendChild(row);
    }
    return table;
}

fn newTableHead(t: *tree.Tree, head_row: *node.Node) !*node.Node {
    const ret = try node.Node.create(t.allocator, .table_head);
    const tr = try node.Node.create(t.allocator, .table_row);
    tr.setSpan(head_row.src_start, head_row.src_end);
    ret.setSpan(head_row.src_start, head_row.src_end);
    ret.appendChild(tr);
    while (head_row.first_child) |c| tr.appendChild(c);
    return ret;
}

fn bufferOf(p: *node.Node) []u8 {
    return if (p.token_buffer.len > 0) p.token_buffer else p.tokens;
}

fn inInline(tokens: []const u8, i: usize, marker: u8) bool {
    if (i + 1 >= tokens.len or i < 1) return false;
    const marker_pos = std.mem.indexOfScalar(u8, tokens[0..i], marker);
    var count: usize = 0;
    for (tokens[0..i]) |b| if (b == marker) {
        count += 1;
    };
    if (count % 2 == 0) return false;
    const end = std.mem.indexOfScalar(u8, tokens[i + 1 ..], marker);
    return marker_pos != null and end != null;
}

fn noPipeSingleColTable(tokens: []const u8) bool {
    const line0 = std.mem.indexOfScalar(u8, tokens, lex.newline) orelse return false;
    if (line0 < 1 or lex.isBlank(tokens[0..line0])) return false;
    const line1 = if (std.mem.indexOfScalar(u8, tokens[line0 + 1 ..], lex.newline)) |v| v else tokens.len - line0 - 1;
    if (line1 < 1) return false;
    const delim = lex.trimWhitespace(tokens[line0 + 1 .. line0 + 1 + line1]);
    if (delim.len < 2) return false;
    for (delim) |c| if (c != lex.hyphen and c != lex.colon and c != lex.space) return false;
    return true;
}

fn parseTableRow(t: *tree.Tree, p: *node.Node, line_in: []u8, aligns: []u8, is_head: bool) !?*node.Node {
    var line = line_in;
    if (std.mem.indexOf(u8, line, "\\|")) |idx| {
        if (idx > 0 and inInline(line, idx, lex.backtick)) line = try replaceAll(t.allocator, line, "\\|", "\\&#124;");
    }
    const cols = try lex.splitWithoutBackslashEscape(t.allocator, line, lex.pipe);
    var first: usize = 0;
    var end: usize = cols.items.len;
    if (end < 1) return null;
    if (lex.isBlank(cols.items[0])) first = 1;
    if (end > first and lex.isBlank(cols.items[end - 1])) end -= 1;
    const cols_len = end - first;
    if (is_head and cols_len > aligns.len) return null;
    const ret = try node.Node.create(t.allocator, .table_row);
    ret.table_aligns = aligns;
    const buf = bufferOf(p);
    if (node.mapTokenSlice(buf, p.token_map, line)) |sp| ret.setSpan(sp.start, sp.end) else ret.setSpan(p.src_start, p.src_end);
    var i: usize = 0;
    while (i < cols_len and i < aligns.len) : (i += 1) {
        var col = lex.trimWhitespace(cols.items[first + i]);
        if (std.mem.indexOf(u8, col, "&#124;")) |_| col = try replaceAll(t.allocator, col, "&#124;", "|");
        const cell = try node.Node.create(t.allocator, .table_cell);
        cell.table_cell_align = aligns[i];
        cell.tokens = @constCast(col);
        cell.token_buffer = buf;
        cell.token_map = p.token_map;
        if (node.mapTokenSlice(buf, p.token_map, col)) |sp| cell.setSpan(sp.start, sp.end) else cell.setSpan(ret.src_start, ret.src_end);
        ret.appendChild(cell);
    }
    while (i < aligns.len) : (i += 1) {
        const cell = try node.Node.create(t.allocator, .table_cell);
        cell.table_cell_align = aligns[i];
        cell.setDerivedSpan(ret.src_end);
        ret.appendChild(cell);
    }
    return ret;
}

fn replaceAll(allocator: std.mem.Allocator, s: []const u8, needle: []const u8, repl: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, s, i, needle)) |idx| {
        try out.appendSlice(allocator, s[i..idx]);
        try out.appendSlice(allocator, repl);
        i = idx + needle.len;
    }
    try out.appendSlice(allocator, s[i..]);
    return out.toOwnedSlice(allocator);
}

fn parseTableDelimRow(allocator: std.mem.Allocator, line_in: []u8) !?[]u8 {
    if (line_in.len < 1) return null;
    for (line_in) |b| if (b != lex.pipe and b != lex.hyphen and b != lex.colon and b != lex.space) return null;
    var line = line_in;
    if (std.mem.indexOf(u8, line, "\\|")) |idx| {
        if (idx > 0 and inInline(line, idx, lex.backtick)) line = try replaceAll(allocator, line, "\\|", "\\&#124;");
    }
    const cols = try lex.splitWithoutBackslashEscape(allocator, line, lex.pipe);
    var first: usize = 0;
    var end: usize = cols.items.len;
    if (lex.isBlank(cols.items[0])) first = 1;
    if (end > first and lex.isBlank(cols.items[end - 1])) end -= 1;
    var aligns: std.ArrayListUnmanaged(u8) = .empty;
    var i = first;
    while (i < end) : (i += 1) {
        var col = lex.trimWhitespace(cols.items[i]);
        if (std.mem.indexOf(u8, col, "&#124;")) |_| col = try replaceAll(allocator, col, "&#124;", "|");
        if (col.len == 0) return null;
        const a = tableDelimAlign(col);
        if (a == 0xFF) return null;
        try aligns.append(allocator, a);
    }
    return try aligns.toOwnedSlice(allocator);
}

fn tableDelimAlign(col: []const u8) u8 {
    if (col.len < 1) return 0xFF;
    const left = col[0] == lex.colon;
    const right = col[col.len - 1] == lex.colon;
    var i: usize = 1;
    while (i + 1 < col.len) : (i += 1) if (col[i] != lex.hyphen) return 0xFF;
    if (left and right) return 2;
    if (left) return 1;
    if (right) return 3;
    return 0;
}
