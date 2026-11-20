# parity/ — proving behavioral parity with upstream Lute

Everything in this directory compares `lutez` against the pinned upstream tree in
`upstream/lute`. The port in `src/` never depends on it; `zig build check` stays Go-free.
If a tool needs the upstream tree, the upstream Go oracle, or the upstream HTML renderer,
it belongs here (not in `tools/`).

```
parity/
├── README.md
└── go/                        # one Go module; replace lute => ../../upstream/lute
    ├── go.mod                 # module lutez/parity (created in M0.5)
    ├── astmodel/              # neutral AST structs (wire AST decoded into these)
    ├── mask.go                # out-of-scope fields zeroed before comparison
    ├── lute/                  # oracle: upstream parse (imports the submodule)
    ├── lutez/                 # cgo bridge: liblutez.a, static link
    └── cmd/
        ├── lute-ast/          # markdown → canonical JSON (upstream)
        ├── lutez-ast/         # markdown → wire AST → same JSON (lutez)
        ├── diff/              # corpus runner; --dashboard, --fail-on-diff, --filter
        ├── html-oracle/       # lutez AST → upstream HTML renderer → HTML (L3)
        ├── gencorpus/         # writes committed test/corpus/*.lzc
        └── check-schema/      # upstream in-scope Node fields vs doc/AST_SCHEMA.md
```

## Commands (target state, M0.5)

```sh
git submodule update --init --recursive
zig build -Doptimize=ReleaseSafe              # zig-out/lib/liblutez.a

cd parity/go
go run ./cmd/diff --corpus ../../test/spec/commonmark-spec.json --dashboard
go run ./cmd/diff --filter emphasis --verbose
go run ./cmd/html-oracle --corpus ../../test/spec/commonmark-spec.json --check
go run ./cmd/gencorpus --out ../../test/corpus/spec.lzc
go run ./cmd/check-schema
```

## Rules

- Compare **decoded ASTs** with `reflect.DeepEqual` after `mask.Apply`, never raw bytes.
- The mask list is data (`go/mask.go`), derived from `doc/AST_SCHEMA.md` §6; review it on
  every schema change.
- Every diff prints: example number/section, first divergent path, expected vs actual.
- Never import `lutez`'s Zig sources directly: go through the C ABI so the boundary is
  exercised on every run. Link the static library to keep CI loader-path-free.
- The oracle is the upstream Go parser **and** the upstream HTML renderer; both come from
  the submodule, so a pin bump moves the oracle and the fixture generator together.

Status: not implemented yet (M0.5). Until then `lutez_parse` returns
`LUTEZ_ERR_NOT_IMPLEMENTED`, and `diff` is expected to report every case as
“not implemented” — that run proves the plumbing end to end.
