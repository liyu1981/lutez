//! Test root: pulls in every native module so `zig build test` discovers all tests.
//! `src/wasm.zig` is excluded: it targets wasm32-freestanding and is exercised by
//! `zig build wasm` + the Node smoke test (M5).

test {
    _ = @import("lutez");
    _ = @import("lutez_c_api");
}
