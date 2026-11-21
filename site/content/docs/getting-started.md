# Getting started

## Requirements

- **Zig 0.17.0** (pinned; no other build dependencies).
- Node 24 only for the website and the Node smoke tests.
- Go 1.27 + the `upstream/lute` submodule only for regeneration and live parity runs.

```sh
git clone <your-fork> lutez && cd lutez
zig build            # static + shared liblutez + include/lutez.h
zig build check      # tests + conformance + fuzz + wasm + C smoke
```

Artifacts land in `zig-out/`:

```
zig-out/lib/liblutez.a
zig-out/lib/liblutez.so*
zig-out/include/lutez.h
zig-out/lib/lutez.wasm      # after: zig build wasm
```

## Parse from C

```c
#include <string.h>
#include "lutez.h"

int main(void) {
  const char *md = "# hello *world*\n\n- a\n- b\n";
  lutez_opts opts;
  memset(&opts, 0, sizeof opts);
  opts.struct_size = sizeof opts;
  opts.setext = 1;

  lutez_doc *doc = lutez_parse((const uint8_t *)md, strlen(md), &opts);
  if (!doc) { fprintf(stderr, "%s\n", lutez_last_error()); return 1; }

  size_t len;
  const uint8_t *ast = lutez_doc_ast(doc, &len);   /* wire format v1 */
  printf("%u nodes, %zu AST bytes\n", lutez_node_count(doc), len);
  lutez_doc_free(doc);
}
```

Compile against the release package:

```sh
zig cc -std=c99 -Iinclude samples/c/smoke.c lib/liblutez.a -o smoke
```

Ownership: the input is copied, so you may free it immediately. The AST pointer is valid
until `lutez_doc_free`. Callbacks never escape a panic. See the [ABI guide](./abi.md).

## Parse from JavaScript (WASM)

```js
import { Lutez } from "./js/lutez.mjs";

const lutez = await Lutez.load("zig-out/lib/lutez.wasm");
const doc = lutez.parse("# hi *em*\n", { gfmTable: true });
const ast = doc.ast();            // Uint8Array, wire format v1
console.log(doc.nodeCount(), doc.nodeType(0));
doc.free();
```

The module is import-free, so `fetch` + `WebAssembly.instantiate` is enough; the included
glue adds typed arrays, options marshalling and error messages. TypeScript definitions are
in `js/lutez.d.ts`. A minimal browser page lives at `test/wasm/browser.html`.

## Parse from Zig

```zig
const std = @import("std");
const lutez = @import("lutez");

pub fn main() !void {
    var doc = try lutez.parse("# hi\n", .{});
    defer doc.deinit();
    // doc.root is *ast_node.Node; the arena owns every node and token.
}
```

The module is installable via `build.zig.zon`; `lutez.parseWith(allocator, ...)` lets you
choose the arena backing allocator explicitly.

## Options

All eleven scoped flags default to the upstream values (on). Pass `NULL`/`null`/`.{}` for
defaults. Disable GFM to get strict CommonMark behavior:

```c
opts.gfm_table = 0;
opts.gfm_strikethrough = 0;
opts.gfm_auto_link = 0;
```

## Verify

```sh
zig build test                       # 31 tests: 29 library + 2 C ABI
zig build test -Dsanitize=thread     # 8-thread stress under TSan
zig build check                      # full CI gate
node test/wasm/smoke.mjs             # WASM parse + AST assertions
```

The committed corpora (`test/corpus/spec.lzc`, `gfm.lzc`) make conformance runs Go-free.
To regenerate them:

```sh
git submodule update --init --recursive
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
cd parity/go
go run ./cmd/gencorpus --gfm-spec ../../upstream/lute/test/gfm-spec.md
CC="zig cc" go run ./cmd/diff --dashboard
CC="zig cc" go run ./cmd/html-oracle
```

## Release artifacts

```sh
tools/build-release.sh                                  # full matrix + wasm
tools/build-release.sh --targets native,wasm           # fast local build
```

Per-target tarballs, the WASM package (`lutez.wasm`, `lutez.mjs`, `lutez.d.ts`) and
`SHA256SUMS` land in `dist/`. See [release](./release.md) for the checklist.

## Website

This site is a small static build in `site/`:

```sh
cd site
npm install
npm run dev        # build + serve on http://localhost:8080
npm run build      # dist/ for GitHub Pages
```

Set `LUTEZ_REPO_URL=https://github.com/you/lutez` when building to enable source links and
the GitHub nav item.
