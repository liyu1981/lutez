# Benchmarks (M4)

Reference environment: Linux x86-64, Zig 0.17.0, Go 1.27.1.
Corpus: the 652 CommonMark 0.31.2 examples (`test/corpus/spec.lzc`), 14,919 bytes
total. Scoped options (no footnotes/math/emoji/YAML), best of 20 rounds.

| Implementation | Build | Best total | Per doc | Relative |
|---|---|---:|---:|---:|
| lutez (Zig, arena AST) | `zig build bench` (ReleaseFast) | **0.91 ms** | 1.4 µs | **3.9× faster** |
| upstream lute (Go) | `cd parity/go && go run ./cmd/bench` | 3.54 ms | 5.4 µs | baseline |

Gate (doc/PLAN.md §2 D7): ≥ 1.2× faster than the Go baseline — **met** (3.9×).

## Parity and robustness evidence

| Check | Result |
|---|---|
| CommonMark corpus (GFM extensions off, as the spec requires) | **652/652** AST parity |
| GFM corpus (tables, strikethrough, task lists, extended autolinks) | **672/672** AST parity |
| L2 live differential (upstream Go oracle vs lutez C ABI) | 652/652 match |
| L3 HTML oracle (upstream renderer over lutez AST vs spec HTML) | **652/652 byte-identical** |
| Go dual-run fuzz (CommonMark options, 3000 valid-UTF-8 cases) | 3000/3000 match |
| Zig crash fuzz (2000 random byte inputs + 120 mutated corpus cases) | no panics/OOB |
| Thread stress | 8 threads × 300 parses; TSan clean |
| Sanitizers | `zig build test -Dsanitize=thread` and `-Dsanitize=c` pass |
| WASM | 243 KB, zero imports, Node + browser smoke |

Commands:

```sh
zig build check
zig build test -Dsanitize=thread
zig build test -Dsanitize=c
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
cd parity/go
CC="zig cc" go run ./cmd/diff --dashboard
CC="zig cc" go run ./cmd/html-oracle
CC="zig cc" go run ./cmd/fuzz -n 3000
go run ./cmd/check-schema
```

Fuzzing note: Zig 0.17 has no `-fsanitize=fuzzer`, and AFL++/libFuzzer are not installed in
this environment. Coverage-guided fuzzing is therefore substituted by (a) the committed
652+672-case differential corpora, (b) the Go dual-implementation fuzzer
(`parity/go/cmd/fuzz`, corpus-seeded mutations), and (c) the Zig mutation/random crash
fuzzer. The planned libFuzzer-on-C-ABI target remains a follow-up when a toolchain with
libFuzzer support is pinned.

Environment note: Valgrind and ASan are not installed here; leak checking uses Zig's
`std.testing.allocator` (all tests), and `-Dsanitize=thread` / `-Dsanitize=c` provide
TSan and C-UB coverage. CI runs the same commands.

Note: arbitrary **invalid UTF-8** inputs are covered for crash/leak robustness by the Zig
fuzzer; AST parity is defined on valid UTF-8 Markdown (the CommonMark/GFM corpora).

Notes:

- The first measurement used `std.heap.page_allocator` as the arena backing and was
  4.5× slower than Go; switching to `std.heap.smp_allocator` (and `wasm_allocator` in
  WASM builds) removed per-node mmap churn.
- WAsm artifact: **243 KB**, zero imports (`zig build wasm`).

Reproduce:

```sh
zig build bench
cd parity/go && go run ./cmd/bench
```
