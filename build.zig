const std = @import("std");

fn applySanitize(m: *std.Build.Module, mode: []const u8) void {
    if (std.mem.eql(u8, mode, "thread")) {
        m.sanitize_thread = true;
    } else if (std.mem.eql(u8, mode, "c")) {
        m.sanitize_c = .full;
    }
}

// lutez build graph.
//
//   zig build                  native static + shared liblutez, header installed
//   zig build test             unit tests (src/ + test/root.zig)
//   zig build wasm             wasm32-freestanding module, zero imports
//   zig build smoke-c          build + run the C sample against liblutez
//   zig build check            test + wasm + smoke-c (CI gate)
//   zig build -Doptimize=ReleaseSafe   release artifacts (recommended)
//
// Zig 0.17.0 is pinned (see doc/PLAN.md §12): std/build APIs move quickly.
// WASM is built through the Build API. Zig 0.17 cannot pass `-fno-entry`, so
// `src/wasm.zig` defines an empty `main` to satisfy the linker; the module stays
// import-free (verified by `zig build wasm` + the Node smoke test).

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sanitize = b.option([]const u8, "sanitize", "sanitize mode: off|thread|c") orelse "off";

    // Public Zig module: `@import("lutez")` for Zig consumers.
    const lutez_mod = b.addModule("lutez", .{
        .root_source_file = b.path("src/lutez.zig"),
        .target = target,
        .optimize = optimize,
    });
    applySanitize(lutez_mod, sanitize);

    // ---- native libraries -------------------------------------------------
    //
    // Windows: the DLL import library and a static library would both be named
    // `lutez.lib`, so the static archive is `lutez_static.lib` there.

    const is_windows = target.result.os.tag == .windows;
    const static_name: []const u8 = if (is_windows) "lutez_static" else "lutez";

    const static_lib = b.addLibrary(.{
        .name = static_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
        }),
        .linkage = .static,
    });
    static_lib.bundle_compiler_rt = true;
    static_lib.installHeader(b.path("include/lutez.h"), "lutez.h");
    b.installArtifact(static_lib);

    const shared_lib = b.addLibrary(.{
        .name = "lutez",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
        }),
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    shared_lib.installHeader(b.path("include/lutez.h"), "lutez.h");
    b.installArtifact(shared_lib);

    // Variant install steps used by tools/build-release.sh: one linkage per prefix.
    const static_only_step = b.step("lib-static", "Install only static liblutez (+ header)");
    static_only_step.dependOn(&b.addInstallArtifact(static_lib, .{}).step);
    const dynamic_only_step = b.step("lib-dynamic", "Install only shared liblutez (+ header)");
    dynamic_only_step.dependOn(&b.addInstallArtifact(shared_lib, .{}).step);

    // ---- tests ------------------------------------------------------------

    const test_step = b.step("test", "Run unit tests (library + C ABI)");
    const unit_tests_root = b.createModule(.{
        .root_source_file = b.path("src/lutez.zig"),
        .target = target,
        .optimize = optimize,
    });
    applySanitize(unit_tests_root, sanitize);
    const unit_tests = b.addTest(.{ .root_module = unit_tests_root });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.setCwd(b.path("."));
    test_step.dependOn(&run_unit_tests.step);

    const capi_tests_root = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
    });
    applySanitize(capi_tests_root, sanitize);
    const capi_tests = b.addTest(.{ .root_module = capi_tests_root });
    const run_capi_tests = b.addRunArtifact(capi_tests);
    run_capi_tests.setCwd(b.path("."));
    test_step.dependOn(&run_capi_tests.step);

    // ---- WASM -------------------------------------------------------------
    //
    // wasm32-freestanding, zero imports. `rdynamic` keeps exported symbols alive;
    // `export_memory` makes the module self-contained so JS reads the AST through
    // memory views. See the `main` comment in src/wasm.zig for the `-fno-entry`
    // workaround.

    const wasm_step = b.step("wasm", "Build the wasm32-freestanding module");
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm = b.addExecutable(.{
        .name = "lutez",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
        }),
    });
    wasm.rdynamic = true;
    wasm.import_memory = false;
    wasm.export_memory = true;
    const wasm_install = b.addInstallLibFile(wasm.getEmittedBin(), "lutez.wasm");
    wasm_step.dependOn(&wasm_install.step);

    // ---- C sample ---------------------------------------------------------

    const smoke_step = b.step("smoke-c", "Build and run the C ABI sample");
    const smoke = b.addExecutable(.{
        .name = "lutez-smoke",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    smoke.root_module.addCSourceFile(.{
        .file = b.path("samples/c/smoke.c"),
        .flags = &.{ "-std=c99", "-Wall", "-Wextra", "-Werror" },
    });
    smoke.root_module.addIncludePath(b.path("include"));
    smoke.root_module.linkLibrary(static_lib);
    const run_smoke = b.addRunArtifact(smoke);
    smoke_step.dependOn(&run_smoke.step);

    // ---- benchmark -------------------------------------------------------

    const bench_step = b.step("bench", "Run the parse benchmark over test/corpus/spec.lzc");
    const bench_exe = b.addExecutable(.{
        .name = "lutez-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/bench/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.setCwd(b.path("."));
    bench_step.dependOn(&run_bench.step);

    // ---- aggregate CI gate ------------------------------------------------

    const check_step = b.step("check", "CI gate: tests + wasm + C smoke");
    check_step.dependOn(test_step);
    check_step.dependOn(wasm_step);
    check_step.dependOn(smoke_step);
}
