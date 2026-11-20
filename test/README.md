# test/ — all test material

Everything that tests `lutez` lives here: Zig test roots, fixtures, conformance corpora,
regression cases, and benchmarks. Nothing test-related lives at the repository root.

```
test/
├── root.zig              # `zig build test` root (imports lutez + lutez_c_api)
├── conformance.zig       # Go-free binary corpus runner (M0.6)
├── roundtrip.zig         # wire encode/decode + corruption tests (M0.4)
├── spec/
│   └── commonmark-spec.json   # 652 CM 0.31.2 examples, copied from upstream (pinned)
├── corpus/               # committed generated *.lzc fixtures (Go-free CI)
├── gfm/                  # generated GFM fixtures (tables, strikethrough, task lists,
│                         #   extended autolinks)
├── cases/                # upstream-derived regression fixtures (M4.6)
├── wasm/smoke.mjs        # Node smoke test: zero imports, exports, ABI
└── bench/                # parse benchmarks + Go baseline harness (M4.4)
```

## Layers (doc/PLAN.md §7)

| Layer | Where | Needs |
|---|---|---|
| L0 unit | `src/**` tests via `test/root.zig` | Zig only |
| L1 lexer golden | `test/cases/lexer/` + Zig tests | Zig only |
| L2 AST differential | `parity/go/cmd/diff` | Go + `upstream/lute` submodule |
| L3 HTML oracle | `parity/go/cmd/html-oracle` | Go + submodule |
| L4 conformance | `test/conformance.zig` over `test/corpus/` | Zig only |
| L5 robustness | fuzz harnesses (`test/fuzz/`, M4) | Zig + Go for dual fuzz |
| L6 performance | `test/bench/` + Go baseline | Zig (+ Go for baseline) |

`test/wasm/smoke.mjs` is the L1 WASM gate:   `zig build wasm && node test/wasm/smoke.mjs`.

## Rules

- `test/corpus/*.lzc` is **committed** so `zig build check` needs neither Go nor the
  submodule. Regenerate with `cd parity/go && go run ./cmd/gencorpus` (a reviewed commit
  of its own; the generator must be byte-identical).
- `test/spec/commonmark-spec.json` is copied verbatim from the pinned submodule; see
  `test/spec/README.md`. Do not hand-edit.
- Fixtures derived from upstream tests keep the upstream case name so a failure maps back
  to `upstream/lute/test/...`.
- No test may link `liblutez` dynamically in CI; use the static library (same as the
  parity harness).
