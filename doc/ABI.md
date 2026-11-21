# ABI guide (C, WASM, JS, Zig)

`lutez` parses UTF-8 Markdown (CommonMark 0.31.2 + GFM) into a serialized AST. It does not
render. The document owns all memory; callers receive opaque handles and wire bytes.

## C API (`include/lutez.h`)

```c
#include "lutez.h"

lutez_opts opts;
memset(&opts, 0, sizeof opts);
opts.struct_size = sizeof opts;   /* NULL opts = upstream defaults */
opts.gfm_table = opts.setext = 1;

lutez_doc *doc = lutez_parse((const uint8_t *)md, md_len, &opts);
if (!doc) { fprintf(stderr, "%s\n", lutez_last_error()); return 1; }

size_t len;
const uint8_t *ast = lutez_doc_ast(doc, &len);   /* wire format v2 */
uint32_t n = lutez_node_count(doc);
int32_t root_type = lutez_node_type(doc, 0);     /* 0 = NodeDocument */

lutez_doc_free(doc);
```

Rules:

- **Ownership.** `lutez_parse` copies the input into the document arena; the caller may
  free its buffer immediately. `lutez_doc_ast` is valid until `lutez_doc_free`.
- **Errors.** `NULL`/`0`/`-1` plus `lutez_last_error()` and `lutez_last_error_code()`
  (thread-local). Messages are static storage.
- **Options.** Versioned struct (`struct_size` first, 16 bytes in ABI v2, `uint8_t`
  flags). The final byte is `strip_bom` (default 1 when `opts == NULL`; set to 0 to keep
  a leading UTF-8 BOM as content). Unknown trailing bytes are ignored only when
  `struct_size >= sizeof(v2)`; a smaller struct is rejected.
- **Threading.** Parsing is reentrant; there are no mutable globals. Each thread has its
  own last-error state.
- **Accessors.** Node handles are `uint32_t` indices (`LUTEZ_NULL_NODE` = absent).
  `lutez_node_data` returns the node's token bytes. Out-of-range nodes yield
  `-1`/`LUTEZ_NULL_NODE`/`NULL`; they never crash.
- **Source spans.** `lutez_node_span()` returns raw byte offsets into the caller's original
  Markdown; `lutez_node_span_norm()` returns offsets into the normalized buffer;
  `lutez_node_span_derived()` marks synthesized zero-width nodes. All are half-open
  `[start, end)` and valid until `lutez_doc_free`. Line/column and UTF-16 columns are
  derived by the caller (or the JS glue) from the raw text.

## Wire format

`lutez_doc_ast` returns the little-endian AST described in
[`WIRE_FORMAT.md`](./WIRE_FORMAT.md): 40-byte header (`LUTEAST1`), 56-byte node records
with raw + normalized spans, extras/input/pool/source-map sections. Offsets are `u32`
(WASM32-safe). The buffer is self-contained; consumers may copy it and free the document.

## WASM

Built with `zig build wasm` → `zig-out/lib/lutez.wasm` (wasm32-freestanding,
**zero imports**, ~230 KB ReleaseSmall).

Exports:

| Export | Meaning |
|---|---|
| `lutez_version() -> u32` | `major<<16 \| minor<<8 \| patch` |
| `lutez_wire_format_version() -> u32` | wire format (2) |
| `lutez_abi_version() -> u32` | C ABI version (2) |
| `lutez_alloc(len) -> u32` | allocate in WASM heap (0 = OOM) |
| `lutez_free(ptr, len)` | free a buffer from `lutez_alloc` |
| `lutez_parse(md_ptr, md_len, opts_ptr) -> u32` | document handle (1..1024) or `0xFFFFFFFF` |
| `lutez_doc_ast(handle) -> u64` | packed `(ptr << 32) \| len` |
| `lutez_doc_free(handle)` | release the document |
| `lutez_node_count(handle) -> u32` | node count |
| `lutez_node_type(handle, node) -> i32` | upstream `NodeType` number or `-1` |
| `lutez_node_span(handle, node, s_ptr, e_ptr) -> u32` | raw span (1 = ok) |
| `lutez_node_span_norm(...)` | normalized span |
| `lutez_last_error_ptr() -> u64` | packed pointer/length of the last error |

`opts_ptr` points at the same 16-byte options struct as C. Any call may grow memory;
re-create `Uint8Array` views afterwards. Handles index a 1024-slot table; a handle is
reusable after `lutez_doc_free`.

## JavaScript (`js/lutez.mjs`)

```js
import { Lutez } from "./lutez.mjs";
const lutez = await Lutez.load("zig-out/lib/lutez.wasm");
const doc = lutez.parse("# hi *em*\n", { gfmTable: true });
const ast = doc.ast();            // Uint8Array, wire format v2
doc.span(1);                      // [rawStart, rawEnd] or null
console.log(doc.nodeCount(), doc.nodeType(0));
doc.free();
```

`Lutez.load` accepts a path, URL, or `Uint8Array`, asserts the module is import-free and
the ABI matches. Parse errors throw with the library message. TypeScript definitions live
in `js/lutez.d.ts`; `test/wasm/browser.html` is a minimal browser smoke page.

## Zig

```zig
const lutez = @import("lutez");
var doc = try lutez.parse("# hi\n", .{});
defer doc.deinit();
// doc.root: *ast_node.Node (arena), doc.arena
// ast_wire.encode(doc.arena.allocator(), doc.root, &.{}) for the binary AST
```

## Versioning

- `LUTEZ_ABI_VERSION` (C/WASM) — currently **2** (spans, v2 options tail).
- `wire_format_version` — currently **2** (56-byte records, source map).
- `lutez_version_string()` — library semver.

Generated artifacts and release layout: see [`RELEASE.md`](./RELEASE.md).
