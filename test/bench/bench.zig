//! Parse benchmark over a committed corpus. Prints wall time and throughput.
const std = @import("std");
const lutez = @import("lutez");

fn readU32(data: []const u8, off: *usize) u32 {
    const v = std.mem.readInt(u32, data[off.*..][0..4], .little);
    off.* += 4;
    return v;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const path = "test/corpus/spec.lzc";
    const rounds: usize = 20;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const corpus = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(corpus);

    var off: usize = 4;
    const count = readU32(corpus, &off);
    var total_bytes: usize = 0;
    // First pass: locate slices (store into a page-allocated array).
    const docs = try allocator.alloc([]const u8, count);
    defer allocator.free(docs);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const nlen = readU32(corpus, &off);
        off += nlen;
        const md_len = readU32(corpus, &off);
        docs[i] = corpus[off .. off + md_len];
        total_bytes += md_len;
        off += md_len;
        const ast_len = readU32(corpus, &off);
        off += ast_len;
    }

    var sink: usize = 0;
    var best_ns: i128 = std.math.maxInt(i128);
    var round: usize = 0;
    while (round < rounds) : (round += 1) {
        const start = std.Io.Timestamp.now(io, .awake).nanoseconds;
        for (docs) |md| {
            var doc = try lutez.parse(md, .{});
            sink +%= doc.root.tokens.len + 1;
            doc.deinit();
        }
        const elapsed = std.Io.Timestamp.now(io, .awake).nanoseconds - start;
        if (elapsed < best_ns) best_ns = elapsed;
    }
    const ns_per_doc = @as(f64, @floatFromInt(best_ns)) / @as(f64, @floatFromInt(count));
    const mb_per_s = if (best_ns > 0) (@as(f64, @floatFromInt(total_bytes)) / 1e6) / (@as(f64, @floatFromInt(best_ns)) / 1e9) else 0;
    std.debug.print("corpus={s} docs={d} bytes={d} best={d:.2}ms ({d:.1}us/doc, {d:.1}MB/s) sink={d}\n", .{
        std.fs.path.basename(path), count, total_bytes, @as(f64, @floatFromInt(best_ns)) / 1e6, ns_per_doc / 1000.0, mb_per_s, sink,
    });
}
