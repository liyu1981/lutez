//! Block parsing context and main loop.
//! Ported from lute/parse/parse.go, blocks.go @ v1.7.8 (Mulan PSL v2).
//! Scope: CommonMark/GFM blocks only; Project/Vditor/SiYuan branches stripped.
const std = @import("std");
const types = @import("../types.zig");
const node = @import("../ast/node.zig");
const lex = @import("../lex/lexer.zig");
const token = @import("../lex/token.zig");
const blocks = @import("blocks.zig");
const source = @import("../source.zig");

pub const Options = types.Options;

pub const RefDef = struct {
    label: []u8,
    dest: []u8,
    title: []u8,
};

pub const Context = struct {
    tree: *Tree,
    options: Options,

    tip: *node.Node,
    oldtip: *node.Node,
    current_line: []u8 = &.{},
    current_line_len: usize = 0,
    offset: usize = 0,
    column: usize = 0,
    next_nonspace: usize = 0,
    next_nonspace_column: usize = 0,
    indent: usize = 0,
    indented: bool = false,
    blank: bool = false,
    partially_consumed_tab: bool = false,
    all_closed: bool = false,
    last_matched_container: *node.Node,

    refs: std.StringHashMapUnmanaged(RefDef) = .empty,

    /// Absolute offsets of the line currently being incorporated.
    line_norm_start: u32 = 0,
    line_raw_start: u32 = 0,
    line_end_norm: u32 = 0, // excludes the trailing newline
    line_trimmed_end_norm: u32 = 0, // excludes trailing spaces/tabs and newline
    line_no: u32 = 0,

    pub fn abs(self: *Context, rel: usize) u32 {
        return self.line_norm_start + @as(u32, @intCast(rel));
    }

    pub fn currentAbs(self: *Context) u32 {
        return self.abs(self.offset);
    }

    pub fn advanceOffset(self: *Context, count: usize, columns: bool) void {
        var remaining = count;
        while (remaining > 0) {
            const c = self.current_line[self.offset];
            if (c == token.tab) {
                const chars_to_tab = 4 - (self.column % 4);
                if (columns) {
                    self.partially_consumed_tab = chars_to_tab > remaining;
                    if (self.partially_consumed_tab) {
                        const adv = remaining;
                        self.column += adv;
                        remaining -= adv;
                    } else {
                        self.column += chars_to_tab;
                        self.offset += 1;
                        remaining -= chars_to_tab;
                    }
                } else {
                    self.partially_consumed_tab = false;
                    self.column += chars_to_tab;
                    self.offset += 1;
                    remaining -= 1;
                }
            } else {
                self.partially_consumed_tab = false;
                self.offset += 1;
                self.column += 1;
                remaining -= 1;
            }
        }
    }

    pub fn advanceNextNonspace(self: *Context) void {
        self.offset = self.next_nonspace;
        self.column = self.next_nonspace_column;
        self.partially_consumed_tab = false;
    }

    pub fn findNextNonspace(self: *Context) void {
        var i = self.offset;
        var cols = self.column;
        while (true) {
            const c = if (i < self.current_line.len) self.current_line[i] else token.newline;
            if (c == token.space) {
                i += 1;
                cols += 1;
            } else if (c == token.tab) {
                i += 1;
                cols += 4 - (cols % 4);
            } else break;
        }
        const c = if (i < self.current_line.len) self.current_line[i] else token.newline;
        self.blank = c == token.newline;
        self.next_nonspace = i;
        self.next_nonspace_column = cols;
        self.indent = self.next_nonspace_column - self.column;
        self.indented = self.indent >= 4;
    }

    pub fn closeUnmatchedBlocks(self: *Context) void {
        if (!self.all_closed) {
            while (self.oldtip != self.last_matched_container) {
                const parent = self.oldtip.parent.?;
                self.finalize(self.oldtip);
                self.oldtip = parent;
            }
            self.all_closed = true;
        }
    }

    pub fn finalize(self: *Context, block: *node.Node) void {
        const parent = block.parent;
        block.close = true;
        switch (block.typ) {
            .code_block => blocks.codeBlockFinalize(self, block),
            .html_block => blocks.htmlBlockFinalize(self, block),
            .paragraph => {
                if (blocks.paragraphFinalize(self, block)) return;
            },
            .list => blocks.listFinalize(self, block),
            .blockquote => blocks.blockquoteFinalize(self, block),
            .heading, .thematic_break, .table, .link_ref_def_block => {},
            else => {},
        }
        if (parent) |p| self.tip = p else self.tip = self.tree.root;
    }

    pub fn addChild(self: *Context, t: types.NodeType) !*node.Node {
        while (!self.tip.canContain(t)) self.finalize(self.tip);
        const n = try node.Node.create(self.tree.allocator, t);
        n.setSpan(self.currentAbs(), self.line_trimmed_end_norm);
        self.tip.appendChild(n);
        self.tip = n;
        return n;
    }

    pub fn addChildMarker(self: *Context, t: types.NodeType, tokens: []u8) !*node.Node {
        const n = try node.Node.create(self.tree.allocator, t);
        n.tokens = tokens;
        n.close = true;
        n.setSpan(self.currentAbs(), self.line_trimmed_end_norm);
        self.tip.appendChild(n);
        return n;
    }
};

pub const Tree = struct {
    allocator: std.mem.Allocator,
    root: *node.Node,
    context: *Context,
    lexer: lex.Lexer = undefined,
    name: []const u8 = "",
    input: []u8 = &.{},
    source_map: source.SourceMap = .{ .segs = &.{}, .raw_len = 0, .norm_len = 0 },

    /// Initializes in place so `Context.tree` holds a stable pointer.
    pub fn init(self: *Tree, allocator: std.mem.Allocator, input: []u8, options: Options, map: source.SourceMap) !void {
        const root = try node.Node.create(allocator, .document);
        const ctx = try allocator.create(Context);
        self.* = .{ .allocator = allocator, .root = root, .context = ctx, .input = input, .source_map = map };
        ctx.* = .{ .tree = self, .options = options, .tip = root, .oldtip = root, .last_matched_container = root };
        self.lexer = lex.Lexer.init(input);
    }

    pub fn parseBlocks(self: *Tree) !void {
        const ctx = self.context;
        ctx.tip = self.root;
        self.root.setSpan(0, @intCast(self.input.len));
        var line_no: u32 = 0;
        while (try self.lexer.nextLine(self.allocator)) |line| {
            const norm_start: u32 = @intCast(@intFromPtr(line.ptr) - @intFromPtr(self.input.ptr));
            ctx.line_norm_start = norm_start;
            ctx.line_raw_start = self.source_map.normToRawStart(norm_start);
            const has_newline = line.len > 0 and line[line.len - 1] == '\n';
            ctx.line_end_norm = norm_start + @as(u32, @intCast(line.len - @intFromBool(has_newline)));
            const line_body = line[0 .. line.len - @intFromBool(has_newline)];
            const trimmed = token.trimRight(line_body).remains;
            ctx.line_trimmed_end_norm = norm_start + @as(u32, @intCast(trimmed.len));
            ctx.line_no = line_no;
            line_no += 1;
            try self.incorporateLine(line);
        }
        while (true) {
            self.context.finalize(self.context.tip);
            if (self.context.tip == self.root) break;
        }
    }

    pub fn incorporateLine(self: *Tree, line: []u8) !void {
        const ctx = self.context;
        ctx.oldtip = ctx.tip;
        ctx.offset = 0;
        ctx.column = 0;
        ctx.blank = false;
        ctx.partially_consumed_tab = false;
        ctx.current_line = line;
        ctx.current_line_len = line.len;

        var all_matched = true;
        var container: *node.Node = self.root;
        var last_child = container.last_child;
        while (last_child != null and !last_child.?.close) {
            container = last_child.?;
            ctx.findNextNonspace();
            switch (try blocks.continueBlock(container, ctx)) {
                0 => {},
                1 => {
                    all_matched = false;
                },
                2 => return,
                else => return,
            }
            if (!all_matched) {
                container = container.parent.?;
                break;
            }
            last_child = container.last_child;
        }

        ctx.all_closed = container == ctx.oldtip;
        ctx.last_matched_container = container;
        var matched_leaf = container.typ != .paragraph and container.acceptLines();
        const starts = blocks.starts;

        while (!matched_leaf) {
            ctx.findNextNonspace();
            const maybe_marker: u8 = if (ctx.next_nonspace < ctx.current_line.len) ctx.current_line[ctx.next_nonspace] else token.newline;
            if (!ctx.indented and maybe_marker != token.hyphen and maybe_marker != token.asterisk and
                maybe_marker != token.plus and !token.isDigit(maybe_marker) and
                maybe_marker != token.backtick and maybe_marker != token.tilde and
                maybe_marker != token.crosshatch and maybe_marker != token.greater and
                maybe_marker != token.less and maybe_marker != token.underscore and
                maybe_marker != token.equal and maybe_marker != token.open_bracket)
            {
                ctx.advanceNextNonspace();
                break;
            }

            var i: usize = 0;
            var matched = false;
            while (i < starts.len) : (i += 1) {
                const res = try starts[i](self, container);
                if (res == 3) return;
                if (res == 1) {
                    container = ctx.tip;
                    matched = true;
                    break;
                } else if (res == 2) {
                    container = ctx.tip;
                    matched_leaf = true;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                ctx.advanceNextNonspace();
                break;
            }
        }

        if (!ctx.all_closed and !ctx.blank and ctx.tip.typ == .paragraph) {
            try self.addLine();
        } else {
            ctx.closeUnmatchedBlocks();
            if (ctx.blank) {
                if (container.last_child) |lc| lc.last_line_blank = true;
            }
            const is_fenced = container.typ == .code_block and container.is_fenced_code_block;
            const last_line_blank = ctx.blank and !(container.typ == .blockquote or is_fenced or (container.typ == .list_item and container.first_child == null));
            var cont: ?*node.Node = container;
            while (cont) |c| : (cont = c.parent) c.last_line_blank = last_line_blank;

            if (container.acceptLines()) {
                try self.addLine();
                if (container.typ == .html_block) {
                    const tokens = ctx.current_line[ctx.offset..];
                    if (container.html_block_type >= 1 and container.html_block_type <= 5) {
                        if (blocks.isHTMLBlockClose(container.html_block_type, tokens)) ctx.finalize(container);
                    }
                }
            } else if (ctx.offset < ctx.current_line_len and !ctx.blank) {
                const p = try ctx.addChild(.paragraph);
                ctx.advanceNextNonspace();
                p.setSpan(ctx.currentAbs(), ctx.line_trimmed_end_norm);
                try self.addLine();
            }
        }

        if (!ctx.blank) {
            var c: ?*node.Node = container;
            while (c) |n| : (c = n.parent) {
                switch (n.typ) {
                    .blockquote, .list, .list_item => n.src_end = ctx.line_end_norm,
                    else => {},
                }
            }
            // Lazy continuation lines extend a paragraph (and its ancestors) beyond the
            // container marker; keep ancestor spans enclosing the child.
            c = ctx.tip;
            while (c) |n| : (c = n.parent) {
                switch (n.typ) {
                    .blockquote, .list, .list_item => {
                        if (ctx.line_end_norm > n.src_end) n.src_end = ctx.line_end_norm;
                    },
                    else => {},
                }
            }
        }
    }

    pub fn addLine(self: *Tree) !void {
        const ctx = self.context;
        if (ctx.partially_consumed_tab) {
            const tab_src = ctx.currentAbs();
            ctx.offset += 1; // skip over tab
            const chars_to_tab = 4 - (ctx.column % 4);
            var i: usize = 0;
            while (i < chars_to_tab) : (i += 1) try appendTokensAt(self.allocator, ctx.tip, " ", tab_src, 1);
        }
        const src_start = ctx.currentAbs();
        const remainder = ctx.current_line[ctx.offset..];
        try appendTokensAt(self.allocator, ctx.tip, remainder, src_start, @intCast(remainder.len));

        const blank = token.isBlankLine(remainder);
        if (!blank) {
            const end = switch (ctx.tip.typ) {
                .code_block, .html_block => ctx.line_end_norm,
                else => ctx.line_trimmed_end_norm,
            };
            if (end > ctx.tip.src_start) ctx.tip.src_end = end;
            if (ctx.tip.typ == .code_block) {
                if (ctx.tip.code_content_start == source.no_pos) ctx.tip.code_content_start = src_start;
                ctx.tip.code_content_end = end;
            }
        }
    }
};

pub fn appendTokensAt(allocator: std.mem.Allocator, n: *node.Node, bytes: []const u8, src_off: u32, src_len: u32) !void {
    if (bytes.len == 0) return;
    const tok_off: u32 = @intCast(n.tokens.len);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(allocator, n.tokens);
    try out.appendSlice(allocator, bytes);
    n.tokens = try out.toOwnedSlice(allocator);

    var map: std.ArrayListUnmanaged(node.TokenSeg) = .empty;
    try map.appendSlice(allocator, n.token_map);
    if (map.items.len > 0) {
        const last = &map.items[map.items.len - 1];
        if (last.tok_off + last.tok_len == tok_off and last.src_off + last.src_len == src_off) {
            last.tok_len += @intCast(bytes.len);
            last.src_len += src_len;
            n.token_map = try map.toOwnedSlice(allocator);
            return;
        }
    }
    try map.append(allocator, .{
        .tok_off = tok_off,
        .tok_len = @intCast(bytes.len),
        .src_off = src_off,
        .src_len = src_len,
    });
    n.token_map = try map.toOwnedSlice(allocator);
}

pub fn appendTokens(allocator: std.mem.Allocator, n: *node.Node, bytes: []const u8) !void {
    try appendTokensAt(allocator, n, bytes, 0, @intCast(bytes.len));
}
