const std = @import("std");

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

    // Public Zig module: `@import("lutez")` for Zig consumers.
    const lutez_mod = b.addModule("lutez", .{
        .root_source_file = b.path("src/lutez.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const test_step = b.step("test", "Run unit tests");
    const c_api_mod = b.addModule("lutez_c_api", .{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "lutez", .module = lutez_mod }},
    });
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lutez", .module = lutez_mod },
                .{ .name = "lutez_c_api", .module = c_api_mod },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

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

    // ---- aggregate CI gate ------------------------------------------------

    const check_step = b.step("check", "CI gate: tests + wasm + C smoke");
    check_step.dependOn(test_step);
    check_step.dependOn(wasm_step);
    check_step.dependOn(smoke_step);
}
