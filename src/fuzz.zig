//! Deterministic robustness tests: random bytes and mutated corpus inputs must parse
//! without panics, leaks, or OOB (ReleaseSafe/Debug both trap on violations).
const std = @import("std");
const lutez = @import("lutez.zig");

fn parseAndFree(md: []const u8) !void {
    var doc = try lutez.parse(md, .{});
    defer doc.deinit();
    const d = try @import("ast/dump.zig").dump(std.testing.allocator, doc.root);
    defer std.testing.allocator.free(d);
    try std.testing.expect(d.len > 0);
}

test "fuzz: random bytes never crash" {
    var prng = std.Random.DefaultPrng.init(0x5eed_1234_abcd_9876);
    const rand = prng.random();
    var buf: [4096]u8 = undefined;
    var iter: usize = 0;
    while (iter < 2000) : (iter += 1) {
        const len = rand.intRangeAtMost(usize, 0, 512);
        rand.bytes(buf[0..len]);
        try parseAndFree(buf[0..len]);
    }
}

test "fuzz: corpus mutations and truncations never crash" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const corpus = try std.Io.Dir.cwd().readFileAlloc(threaded.io(), "test/corpus/spec.lzc", std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(corpus);
    var off: usize = 8; // magic + count
    var prng = std.Random.DefaultPrng.init(0xc0ff_ee00_1234_5678);
    const rand = prng.random();
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        const name_len = std.mem.readInt(u32, corpus[off..][0..4], .little);
        off += 4 + name_len;
        const md_len = std.mem.readInt(u32, corpus[off..][0..4], .little);
        off += 4;
        const md = corpus[off .. off + md_len];
        off += md_len;
        const ast_len = std.mem.readInt(u32, corpus[off..][0..4], .little);
        off += 4 + ast_len;

        try parseAndFree(md);
        if (md.len > 0) {
            const cut = rand.intRangeAtMost(usize, 0, md.len);
            try parseAndFree(md[0..cut]);
            const mut = try std.testing.allocator.dupe(u8, md);
            defer std.testing.allocator.free(mut);
            var k: usize = 0;
            const mutations = rand.intRangeAtMost(usize, 1, 8);
            while (k < mutations) : (k += 1) {
                const pos = rand.intRangeAtMost(usize, 0, mut.len - 1);
                mut[pos] = rand.int(u8);
            }
            try parseAndFree(mut);
        }
    }
}

test "threads: concurrent parsing is reentrant" {
    const Worker = struct {
        fn run(ok: *std.atomic.Value(bool)) void {
            const md = "# heading\n\n- a\n- b *em* `code`\n\n> quote [l](/u)\n\n| a | b |\n|---|---|\n| 1 | 2 |\n";
            var i: usize = 0;
            while (i < 300) : (i += 1) {
                var doc = lutez.parse(md, .{}) catch {
                    ok.store(false, .seq_cst);
                    return;
                };
                doc.deinit();
            }
        }
    };
    var ok = std.atomic.Value(bool).init(true);
    var threads: [8]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Worker.run, .{&ok});
    for (threads) |t| t.join();
    try std.testing.expect(ok.load(.seq_cst));
}

test "upstream regression fixtures parse" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const manifest = try std.Io.Dir.cwd().readFileAlloc(io, "test/cases/manifest.txt", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(manifest);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    var count: usize = 0;
    while (lines.next()) |name| {
        const trimmed = std.mem.trim(u8, name, " \r\n");
        if (trimmed.len == 0) continue;
        const path = try std.fmt.allocPrint(std.testing.allocator, "test/cases/{s}", .{trimmed});
        defer std.testing.allocator.free(path);
        const md = try std.Io.Dir.cwd().readFileAlloc(io, path, std.testing.allocator, .limited(8 * 1024 * 1024));
        defer std.testing.allocator.free(md);
        var cm = try lutez.parse(md, .{ .gfm_table = false, .gfm_auto_link = false, .gfm_strikethrough = false, .gfm_strikethrough1 = false, .gfm_task_list_item = false });
        defer cm.deinit();
        try std.testing.expect(cm.root.first_child != null);
        var gfm = try lutez.parse(md, .{});
        defer gfm.deinit();
        try std.testing.expect(gfm.root.first_child != null);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);
}
