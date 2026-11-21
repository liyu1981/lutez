# lutez

CommonMark 0.31.2 + GFM **parser** in Zig, ported from
[`88250/lute`](https://github.com/88250/lute) (@ `v1.7.8`), exposed as a reentrant
C ABI library, a self-contained WASM module, and a JS wrapper. Rendering is out of scope:
`lutez` turns Markdown bytes into a versioned binary AST.

> Status: **v0.3.0.** CommonMark **652/652** AST parity, GFM **672/672** (tables,
> strikethrough, task lists, extended autolinks), live differential **652/652**, HTML oracle
> **652/652 byte-identical**, 8-thread TSan-clean, WASM **243 KB / zero imports**, parse
> **3.9× faster** than upstream Go on the spec corpus. See
> [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) and [`doc/PORTING_NOTES.md`](doc/PORTING_NOTES.md).

## Quick start

### C

```c
#include "lutez.h"
lutez_doc *doc = lutez_parse((const uint8_t *)md, len, NULL); /* NULL = defaults */
size_t n;
const uint8_t *ast = lutez_doc_ast(doc, &n);  /* wire format v2 */
lutez_doc_free(doc);
```

Build: `zig build` → `zig-out/lib/liblutez.a`, `liblutez.so`, `include/lutez.h`.

### Extensions (optional presets)

Dialect constructs are opt-in and never affect the default AST:

```c
/* frontmatter, math, wikilinks, tags, Logseq/Obsidian blocks, TODO/DOING */
lutez_doc *doc = lutez_parse_presets(md, len, NULL, LUTEZ_EXT_FRONTMATTER |
                                    LUTEZ_EXT_MATH | LUTEZ_EXT_WIKILINKS |
                                    LUTEZ_EXT_TAGS | LUTEZ_EXT_OUTLINER_BLOCKS |
                                    LUTEZ_EXT_OUTLINER_KEYWORDS);
```

```js
const doc = lutez.parse(md, null, ["opal-note"]);
doc.extension(node);   // { kind, flags } or null
```

Extension nodes are `NodeBlockExtension`/`NodeInlineExtension` with raw payloads and
source spans; see [`doc/EXTENSIONS_DESIGN.md`](doc/EXTENSIONS_DESIGN.md).

### WASM + JS

```js
import { Lutez } from "./js/lutez.mjs";
const lutez = await Lutez.load("zig-out/lib/lutez.wasm");
const doc = lutez.parse("# hi *em*\n");
const ast = doc.ast();            // Uint8Array (wire format v2)
doc.free();
```

Build: `zig build wasm` → `zig-out/lib/lutez.wasm` (wasm32-freestanding, no imports).

### Zig

```zig
const lutez = @import("lutez");
var doc = try lutez.parse("# hi\n", .{});
defer doc.deinit();
```

## Build and test

Requires Zig **0.17.0** (pinned; no other build dependencies).

```sh
zig build                    # static + shared liblutez, header
zig build check              # CI gate: tests + conformance + fuzz + wasm + C smoke
zig build bench              # parse benchmark (ReleaseFast)
zig build wasm               # WASM module
zig build smoke-c            # build + run the C sample
```

The upstream Go tree is a pinned git submodule at `upstream/lute`, used only by the parity
tooling and generators:

```sh
git submodule update --init --recursive
tools/upstream.sh --verify
cd parity/go
CC="zig cc" go run ./cmd/diff --dashboard   # L2 differential
CC="zig cc" go run ./cmd/html-oracle        # L3 HTML oracle
CC="zig cc" go run ./cmd/fuzz -n 3000       # dual-implementation fuzz
go run ./cmd/check-schema                   # schema/whitelist drift
```

## Release artifacts

```sh
tools/build-release.sh                                  # all targets x {static,dynamic} + wasm
tools/build-release.sh --targets native,wasm            # fast local build
tools/build-release.sh --targets x86_64-linux-dynamic   # one variant
```

`dist/` contains per-target tarballs, the WASM package (`lutez.wasm` + `lutez.mjs`) and
`SHA256SUMS`; archives are reproducible. See [`doc/RELEASE.md`](doc/RELEASE.md).

## Website

The project site lives in `site/`: a landing page, generated documentation and a
WASM-powered AST playground. It is a structured static build (no single-page monolith) and
publishes to GitHub Pages via `.github/workflows/deploy-pages.yml`.

```sh
cd site
pnpm install
pnpm dev           # build + serve http://localhost:8080
pnpm build         # zig build wasm + static site into site/dist
pnpm check         # syntax check browser JS
pnpm check:links   # verify internal links
```

The site toolchain is pinned with pnpm 12.4.2 (`packageManager` in `site/package.json`).

Docs are generated from `site/content/docs/` and `doc/*.md`; the demo decodes the wire AST
in the browser and renders an interactive tree. Set `LUTEZ_REPO_URL` at build time to enable
source links and the GitHub nav item.

## Documentation

| Document | Contents |
|---|---|
| [`doc/PLAN.md`](doc/PLAN.md) | scope, architecture, milestones, gates, risks, decisions |
| [`doc/ABI.md`](doc/ABI.md) | C / WASM / JS / Zig API, ownership, errors, threading |
| [`doc/WIRE_FORMAT.md`](doc/WIRE_FORMAT.md) | binary AST v2 |
| [`doc/AST_SCHEMA.md`](doc/AST_SCHEMA.md) | scoped node types, flags, ext layouts |
| [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) | performance vs Go |
| [`doc/RELEASE.md`](doc/RELEASE.md) | release checklist and verification |
| [`doc/PORTING_NOTES.md`](doc/PORTING_NOTES.md) | deviations and known simplifications |
| [`doc/EXTENSIONS_DESIGN.md`](doc/EXTENSIONS_DESIGN.md) | optional dialect extension presets and payloads |
| [`doc/UPSTREAM.md`](doc/UPSTREAM.md) | pinned submodule and tag-bump procedure |
| [`doc/ZIG_PORT_FEASIBILITY.md`](doc/ZIG_PORT_FEASIBILITY.md) | original feasibility study |

## Layout

- `src/{lex,parse,ast,html,unicode}` — the port; `src/{lutez,c_api,wasm,doc,abi}.zig` — API.
- `test/` — test roots, fixtures, corpora (`spec.lzc`, `gfm.lzc`), WASM smoke, benchmarks.
- `parity/` — Go oracle, cgo bridge, corpus generator, schema checker.
- `tools/` — table generators, submodule helper, release script.
- `site/` — website source (landing, docs generator, WASM playground) → `site/dist`.
- `upstream/lute` — pinned git submodule, never edited.

## License

Mulan PSL v2, same as upstream Lute. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

- Project copyright: Copyright (c) 2026 Yu Li and lutez contributors.
- Derived work: parser semantics from Lute, Copyright (c) 2019-present b3log.org.
- `LICENSE` contains the filled-in Mulan PSL v2 application statement (software name,
  first-publication year, copyright holder); the license terms themselves are unchanged.
