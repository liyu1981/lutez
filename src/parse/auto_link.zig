//! Autolinks: CommonMark `<scheme:...>` / `<mailto>` and GFM extended links.
//! Ported from lute/parse/auto_link.go @ v1.7.8 (Mulan PSL v2).
const std = @import("std");
const node = @import("../ast/node.zig");
const lex = @import("../lex/token.zig");
const html = @import("../html/escape.zig");
const tree = @import("tree.zig");
const inl = @import("inline.zig");
const links = @import("links.zig");
const tlds = @import("tlds.zig");

const Ctx = struct { t: *tree.Tree, ctx: *inl.InlineContext };

pub fn parseAutolink(c: anytype, block: *node.Node) !?*node.Node {
    _ = block;
    const t: *tree.Tree = c.t;
    const ctx: *inl.InlineContext = c.ctx;
    if (try parseAutoEmailLink(c)) |n| return n;
    var schemed = false;
    var scheme_len: usize = 0;
    var dest: std.ArrayListUnmanaged(u8) = .empty;
    var i = ctx.pos + 1;
    while (i < ctx.tokens_len and ctx.tokens[i] != lex.greater) : (i += 1) {
        const tok = ctx.tokens[i];
        if (tok == lex.space) return try @import("inline_html.zig").parseInlineHTML(t, ctx);
        try dest.append(t.allocator, tok);
        if (!schemed) {
            if (tok != lex.colon) {
                scheme_len += 1;
            } else schemed = true;
        }
    }
    if (!schemed or scheme_len < 3 or i == ctx.tokens_len) return try @import("inline_html.zig").parseInlineHTML(t, ctx);
    if (ctx.tokens[i] != lex.greater) return try @import("inline_html.zig").parseInlineHTML(t, ctx);
    const start = ctx.pos;
    ctx.pos = 1 + i;
    const encoded = try html.encodeDestination(t.allocator, dest.items);
    const link = try links.newLink(t, .link, dest.items, encoded, null, 2);
    if (ctx.spanFor(start, ctx.pos)) |sp| {
        link.setSpan(sp.start, sp.end);
        node.fillSubtreeSpan(link, sp);
    }
    return link;
}

fn parseAutoEmailLink(c: anytype) !?*node.Node {
    const t: *tree.Tree = c.t;
    const ctx: *inl.InlineContext = c.ctx;
    const tokens = ctx.tokens[1..];
    var dest: std.ArrayListUnmanaged(u8) = .empty;
    var passed: usize = 0;
    var i: usize = 0;
    var at = false;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        try dest.append(t.allocator, tok);
        passed += 1;
        if (tok == '@') {
            at = true;
            break;
        }
        if (!lex.isASCIILetterNumHyphen(tok) and std.mem.indexOfScalar(u8, ".!#$%&'*+/=?^_`{|}~-", tok) == null) return null;
    }
    if (i < 1 or !at) return null;
    const domain = tokens[i + 1 ..];
    var closed = false;
    var j: usize = 0;
    while (j < domain.len) : (j += 1) {
        const tok = domain[j];
        passed += 1;
        if (tok == lex.greater) {
            closed = true;
            break;
        }
        try dest.append(t.allocator, tok);
        if (!lex.isASCIILetterNumHyphen(tok) and tok != lex.dot) return null;
        if (j > 63) return null;
    }
    if (j < 1 or !closed) return null;
    const start = ctx.pos;
    ctx.pos += passed + 1;
    const mailto = try std.mem.concat(t.allocator, u8, &.{ "mailto:", dest.items });
    const link = try links.newLink(t, .link, dest.items, mailto, null, 2);
    if (ctx.spanFor(start, ctx.pos)) |sp| {
        link.setSpan(sp.start, sp.end);
        node.fillSubtreeSpan(link, sp);
    }
    return link;
}

pub fn parseGFMAutoEmailLink(t: *tree.Tree, n: *node.Node) !void {
    var child = n.first_child;
    while (child) |ch| {
        const next = ch.next;
        if (ch.typ == .text and ch.parent != null and ch.parent.?.typ != .link) {
            try parseGFMAutoEmailLink0(t, ch);
        } else try parseGFMAutoEmailLink(t, ch);
        child = next;
    }
}

fn parseGFMAutoEmailLink0(t: *tree.Tree, n: *node.Node) !void {
    const tokens = n.tokens;
    if (std.mem.indexOfScalar(u8, tokens, '@') == null or std.mem.indexOfScalar(u8, tokens, '@').? == 0) return;
    var i: usize = 0;
    while (i < tokens.len) {
        const group_start = i;
        var j = i;
        var group: std.ArrayListUnmanaged(u8) = .empty;
        var at_index: usize = 0;
        while (j < tokens.len) : (j += 1) {
            const tok = tokens[j];
            if (!lex.isWhitespace(tok)) {
                try group.append(t.allocator, tok);
                if (tok == '@') at_index = j - i;
                continue;
            }
            break;
        }
        if (i == j) {
            if (j < tokens.len) try addPreviousText(t, n, tokens[j .. j + 1]);
            i += 1;
            continue;
        }
        i = j;
        const group_end = i;
        if (at_index == 0) {
            try addPreviousText(t, n, group.items);
            continue;
        }
        var k: usize = 0;
        var valid = true;
        while (k < at_index) : (k += 1) {
            if (!isValidEmailSegment1(group.items[k])) {
                valid = false;
                break;
            }
        }
        k += 1;
        while (valid and k < group.items.len) : (k += 1) {
            if (!isValidEmailSegment2(group.items[k])) valid = false;
        }
        if (!valid) {
            try addPreviousText(t, n, group.items);
            continue;
        }
        const last = group.items[group.items.len - 1];
        if (last == lex.dot) {
            const g = group.items[0 .. group.items.len - 1];
            const mailto = try std.mem.concat(t.allocator, u8, &.{ "mailto:", g });
            const link = try links.newLink(t, .link, g, mailto, null, 2);
            if (subSpan(n, group_start, group_end - 1)) |sp| {
                link.setSpan(sp.start, sp.end);
                node.fillSubtreeSpan(link, sp);
            }
            n.insertBefore(link);
            try addPreviousText(t, n, group.items[group.items.len - 1 ..]);
        } else if (last == lex.hyphen or last == lex.underscore) {
            try addPreviousText(t, n, group.items);
            continue;
        } else {
            const link = try node.Node.create(t.allocator, .link);
            link.link_type = 2;
            const lt = try node.Node.create(t.allocator, .link_text);
            lt.tokens = try t.allocator.dupe(u8, group.items);
            link.appendChild(lt);
            const ld = try node.Node.create(t.allocator, .link_dest);
            ld.tokens = try std.mem.concat(t.allocator, u8, &.{ "mailto:", group.items });
            link.appendChild(ld);
            if (subSpan(n, group_start, group_end)) |sp| {
                link.setSpan(sp.start, sp.end);
                node.fillSubtreeSpan(link, sp);
            }
            n.insertBefore(link);
        }
    }
    n.unlink();
}

fn isValidEmailSegment1(b: u8) bool {
    return lex.isASCIILetterNumHyphen(b) or b == lex.dot or b == lex.plus or b == lex.underscore;
}
fn isValidEmailSegment2(b: u8) bool {
    return lex.isASCIILetterNumHyphen(b) or b == lex.dot or b == lex.underscore;
}

fn addPreviousText(t: *tree.Tree, n: *node.Node, tokens: []const u8) !void {
    if (n.prev) |p| {
        if (p.typ == .text) {
            var out: std.ArrayListUnmanaged(u8) = .empty;
            try out.appendSlice(t.allocator, p.tokens);
            try out.appendSlice(t.allocator, tokens);
            p.tokens = try out.toOwnedSlice(t.allocator);
            return;
        }
    }
    const text = try node.Node.create(t.allocator, .text);
    text.tokens = try t.allocator.dupe(u8, tokens);
    n.insertBefore(text);
}

pub fn parseGFMAutoLink(t: *tree.Tree, n: *node.Node) !void {
    var child = n.first_child;
    while (child) |ch| {
        const next = ch.next;
        if (ch.typ == .text) {
            try parseGFMAutoLink0(t, ch);
        } else try parseGFMAutoLink(t, ch);
        child = next;
    }
}

fn isValidDomain(domain: []const u8) bool {
    if (domain.len == 0) return false;
    var total: usize = 1;
    for (domain) |b| if (b == '.') {
        total += 1;
    };
    if (domain[domain.len - 1] == '.') total -= 1;
    if (total < 2) return false;
    var segments: usize = 0;
    var i: usize = 0;
    while (true) {
        const start = i;
        while (i < domain.len and domain[i] != '.') i += 1;
        const seg = domain[start..i];
        if (seg.len > 0) {
            for (seg) |ch| if (!lex.isASCIILetterNumHyphen(ch)) return false;
        }
        if (segments == total - 1) {
            var all_digits = seg.len > 0;
            for (seg) |ch| if (!lex.isDigit(ch)) {
                all_digits = false;
                break;
            };
            if (!all_digits and !tldAllowed(seg)) return false;
        }
        segments += 1;
        if (i >= domain.len) break;
        i += 1; // skip '.'
    }
    return true;
}

fn tldAllowed(suffix: []const u8) bool {
    var lo: usize = 0;
    var hi: usize = tlds.tlds.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const ord = std.mem.order(u8, suffix, tlds.tlds[mid]);
        switch (ord) {
            .lt => hi = mid,
            .gt => lo = mid + 1,
            .eq => return true,
        }
    }
    return false;
}

fn subSpan(n: *node.Node, start_off: usize, end_off: usize) ?node.Span {
    if (n.tokens.len == 0 or !n.hasSpan() or start_off > end_off or end_off > n.tokens.len) return null;
    const buffer = if (n.token_buffer.len > 0) n.token_buffer else n.tokens;
    if (n.token_map.len > 0) {
        if (node.mapTokenSlice(buffer, n.token_map, n.tokens[start_off..end_off])) |sp| return sp;
    }
    const total_src = n.src_end - n.src_start;
    const total_tok = n.tokens.len;
    const s = n.src_start + @as(u32, @intCast((start_off * total_src) / total_tok));
    const e = n.src_start + @as(u32, @intCast((end_off * total_src) / total_tok));
    return .{ .start = s, .end = e };
}

fn isTrailingPunct(b: u8) bool {
    return b == '?' or b == '!' or b == '.' or b == ',' or b == ':' or b == '*' or b == '_' or b == '~';
}

fn parseGFMAutoLink0(t: *tree.Tree, n: *node.Node) !void {
    const tokens = n.tokens;
    var i: usize = 0;
    while (i < tokens.len) {
        var start: ?usize = null;
        var is_www = false;
        if (startsWithAt(tokens, i, "http://") or startsWithAt(tokens, i, "https://") or startsWithAt(tokens, i, "ftp://")) {
            start = i;
        } else if (startsWithAt(tokens, i, "www.")) {
            start = i;
            is_www = true;
        }
        if (start == null) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < tokens.len) : (end += 1) {
            const b = tokens[end];
            if (lex.isWhitespace(b) or b == '<') break;
        }
        var dest_end = end;
        if (dest_end <= i + 4) {
            i += 1;
            continue;
        }
        var url = tokens[i..dest_end];
        if (is_www and std.mem.indexOfScalar(u8, url, '.') == null) {
            i += 1;
            continue;
        }
        const path_start = blk: {
            if (is_www) break :blk std.mem.indexOfScalar(u8, url, '/') orelse url.len;
            const scheme_end = std.mem.indexOf(u8, url, "://") orelse 0;
            break :blk if (std.mem.indexOfScalarPos(u8, url, scheme_end + 3, '/')) |p| p else url.len;
        };
        // Domain validation (upstream isValidDomain): public-suffix allow-list for the
        // known protocols; custom schemes are not produced by this scanner.
        const domain_start = if (is_www) 0 else (std.mem.indexOf(u8, url, "://") orelse 0) + 3;
        if (domain_start > url.len) {
            i = dest_end;
            continue;
        }
        const domain_port = url[domain_start..path_start];
        const domain = if (std.mem.indexOfScalar(u8, domain_port, ':')) |ci| domain_port[0..ci] else domain_port;
        if (!isValidDomain(domain)) {
            i = dest_end;
            continue;
        }
        const path = url[path_start..];
        var cut = url.len;
        if (path.len > 0) {
            const last = path[path.len - 1];
            if (last == ')') {
                var opens: usize = 0;
                var closes: usize = 0;
                for (path) |b| {
                    if (b == '(') opens += 1;
                    if (b == ')') closes += 1;
                }
                if (closes > opens) {
                    var un = closes - opens;
                    while (un > 0 and cut > 0 and url[cut - 1] == ')') : (un -= 1) cut -= 1;
                }
            } else if (last == ';') {
                if (std.mem.lastIndexOfScalar(u8, path, '&')) |amp| {
                    const ent = path[amp..];
                    if (ent.len >= 3) {
                        var ok = true;
                        for (ent[1 .. ent.len - 1]) |ch| {
                            if (!lex.isASCIILetterNum(ch)) {
                                ok = false;
                                break;
                            }
                        }
                        if (ok) cut = path_start + amp;
                    }
                }
                if (cut == url.len and isTrailingPunct(last)) cut -= 1;
            } else if (isTrailingPunct(last)) {
                cut -= 1;
            }
        } else {
            if (url.len > 0 and lex.isASCIIPunct(url[url.len - 1])) cut -= 1;
        }
        url = url[0..cut];
        dest_end = i + cut;
        const dest_src = if (is_www) try std.mem.concat(t.allocator, u8, &.{ "http://", url }) else url;
        const encoded = try html.encodeDestination(t.allocator, dest_src);
        const link = try links.newLink(t, .link, url, encoded, null, 2);
        const bounds = subSpan(n, i, dest_end);
        if (bounds) |sp| {
            link.setSpan(sp.start, sp.end);
            node.fillSubtreeSpan(link, sp);
        }
        const before = try t.allocator.dupe(u8, tokens[0..i]);
        const after = try t.allocator.dupe(u8, tokens[dest_end..]);
        if (before.len > 0) {
            const pre = try node.Node.create(t.allocator, .text);
            pre.tokens = before;
            if (subSpan(n, 0, i)) |sp| pre.setSpan(sp.start, sp.end);
            n.insertBefore(pre);
        }
        n.insertBefore(link);
        if (after.len > 0) {
            const post = try node.Node.create(t.allocator, .text);
            post.tokens = after;
            if (subSpan(n, dest_end, tokens.len)) |sp| post.setSpan(sp.start, sp.end);
            n.insertAfter(post);
        }
        n.unlink();
        return;
    }
}

fn startsWithAt(tokens: []const u8, i: usize, needle: []const u8) bool {
    return i + needle.len <= tokens.len and std.mem.eql(u8, tokens[i .. i + needle.len], needle);
}
