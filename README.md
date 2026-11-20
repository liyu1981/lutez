# lutez

CommonMark 0.31.2 + GFM **parser** in Zig, ported from
[`88250/lute`](https://github.com/88250/lute) (@ `61eb27b`), exposed as a reentrant
C ABI library and a self-contained WASM module.

> Status: **planning / M0 skeleton.** `lutez_parse()` is not implemented yet; the
> build, ABI, and test plumbing exist to validate the toolchain and the contract.

## Why

Lute is a Go Markdown engine. `lutez` ports only its CommonMark/GFM parser, keeping
Lute's AST shape, so existing Lute-shaped consumers can run it from C, C++, Rust, or
the browser without a Go runtime. No renderers, no SiYuan/Vditor extensions, no HTML5
parser, no regex, no GC.

## Read first

| Document | Contents |
|---|---|
| [`doc/PLAN.md`](doc/PLAN.md) | milestones, architecture, gates, risks, open decisions |
| [`doc/ZIG_PORT_FEASIBILITY.md`](doc/ZIG_PORT_FEASIBILITY.md) | scope + feasibility study (authority for what is in/out) |
| [`doc/AST_SCHEMA.md`](doc/AST_SCHEMA.md) | scoped node types and fields (draft) |
| [`doc/WIRE_FORMAT.md`](doc/WIRE_FORMAT.md) | binary AST format v1 (draft) |
| [`doc/UPSTREAM.md`](doc/UPSTREAM.md) | pinned upstream revision and bump procedure |

## Build

Requires Zig **0.17.0** (pinned; no other dependencies).

```sh
zig build                    # static + shared liblutez, include/lutez.h
zig build test               # unit tests
zig build wasm               # zig-out/lib/lutez.wasm (wasm32-freestanding)
zig build smoke-c            # build + run samples/c/smoke.c
zig build check              # CI gate
node test/wasm/smoke.mjs     # WASM smoke test (after zig build wasm)
```

The upstream Go tree is a pinned git submodule at `upstream/lute`. It is only needed
for the parity harness and corpus/table regeneration:

```sh
git submodule update --init --recursive   # fetch the pinned upstream tree
tools/upstream.sh --status                # submodule HEAD vs the pin copies
tools/upstream.sh --verify                # CI gate: pin copies must agree
```

`zig build check` works on a plain checkout; it never reads `upstream/`.

## Release artifacts (`dist/`)

```sh
tools/build-release.sh                              # all matrix targets x {static,dynamic} + wasm
tools/build-release.sh --targets native             # host only, static + dynamic
tools/build-release.sh --targets native-static      # one variant only
tools/build-release.sh --targets x86_64-linux-gnu-dynamic,aarch64-macos-static,wasm
tools/build-release.sh --targets all-static         # all targets, static only
tools/build-release.sh --skip-tests --no-archive --optimize ReleaseFast
```

Each package is self-contained and reproducible (deterministic `.tar.gz`, `SHA256SUMS`):

```
dist/lutez-0.1.0-<target>-static/    include/lutez.h  lib/liblutez.a   [+ lib/lutez_static.lib on Windows]
dist/lutez-0.1.0-<target>-dynamic/   include/lutez.h  lib/liblutez.so* [+ bin/lutez.dll on Windows]
dist/lutez-0.1.0-wasm32-freestanding/lutez.wasm
dist/SHA256SUMS
```

Windows note: `lutez.lib` is the DLL import library; the static archive is
`lutez_static.lib` (they would otherwise collide). Every package also carries
`VERSION`, `LICENSE`, and `NOTICE`.

## Layout

See [`doc/PLAN.md` §4](doc/PLAN.md). Short version:

- `src/{lex,parse,ast,html,unicode}` — the port; `src/{lutez,c_api,wasm}.zig` — API surface.
- `test/` — every test root, fixture, corpus, and benchmark (nothing test-related at root).
- `parity/` — the Go differential harness, HTML oracle, corpus generator, schema checker.
- `tools/` — table generators and the submodule helper.
- `upstream/lute` — pinned git submodule, never edited.

## License

Mulan PSL v2, same as upstream Lute. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
Derived work: nodes/parser semantics from Lute, Copyright (c) 2019-present b3log.org.
