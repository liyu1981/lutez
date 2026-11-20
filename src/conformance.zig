//! Go-free conformance runner over the committed corpora (test/corpus/*.lzc).
//! Each case stores markdown and the canonical AST dump produced by the pinned upstream
//! parser; lutez must produce the same dump.
const std = @import("std");
const lutez = @import("lutez.zig");
const dump = @import("ast/dump.zig");

const Case = struct { name: []const u8, md: []const u8, ast: []const u8 };

fn readU32(data: []const u8, off: *usize) u32 {
    const v = std.mem.readInt(u32, data[off.*..][0..4], .little);
    off.* += 4;
    return v;
}

fn readBytes(data: []const u8, off: *usize) []const u8 {
    const len = readU32(data, off);
    const out = data[off.* .. off.* + len];
    off.* += len;
    return out;
}

fn runCorpus(allocator: std.mem.Allocator, path: []const u8, label: []const u8, options: lutez.Options) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const corpus = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(corpus);
    var off: usize = 0;
    if (!std.mem.eql(u8, corpus[0..4], "LZC2")) return error.BadCorpus;
    off = 4;
    const count = readU32(corpus, &off);
    var failures: usize = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const c = Case{ .name = readBytes(corpus, &off), .md = readBytes(corpus, &off), .ast = readBytes(corpus, &off) };
        var doc = lutez.parse(c.md, options) catch {
            failures += 1;
            std.debug.print("FAIL {s} {s}: parse error\n", .{ label, c.name });
            continue;
        };
        defer doc.deinit();
        const got = try dump.dump(allocator, doc.root);
        defer allocator.free(got);
        if (std.mem.eql(u8, got, c.ast)) continue;
        failures += 1;
        if (failures <= 25) {
            var gl = std.mem.splitScalar(u8, got, '\n');
            var wl = std.mem.splitScalar(u8, c.ast, '\n');
            var ln: usize = 0;
            while (true) : (ln += 1) {
                const g = gl.next();
                const w = wl.next();
                if (g == null and w == null) break;
                if (g == null or w == null or !std.mem.eql(u8, g.?, w.?)) {
                    std.debug.print("FAIL {s} {s} line {d}\n  got:  [{s}]\n  want: [{s}]\n", .{ label, c.name, ln, g orelse "-", w orelse "-" });
                    break;
                }
            }
        }
    }
    std.debug.print("{s}: {d}/{d} cases passed\n", .{ label, count - failures, count });
    if (failures != 0) return error.ConformanceFailed;
}

test "CommonMark corpus: 652/652 AST parity" {
    try runCorpus(std.testing.allocator, "test/corpus/spec.lzc", "cm", .{
        .gfm_table = false,
        .gfm_task_list_item = false,
        .gfm_strikethrough = false,
        .gfm_strikethrough1 = false,
        .gfm_auto_link = false,
    });
}

test "GFM corpus: AST parity" {
    try runCorpus(std.testing.allocator, "test/corpus/gfm.lzc", "gfm", .{});
}
