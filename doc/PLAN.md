# lutez — implementation plan

**Status:** draft v0.1, 2026-11-20, awaiting sign-off (see §12).
**Progress:** M0.1 (skeleton, `zig build check` green) and M0.2 (upstream pin fetched and
verified) are done. Next: M0.3 schema freeze, then M0.4 wire format and M0.5 harness.
**Scope authority:** [`doc/ZIG_PORT_FEASIBILITY.md`](./ZIG_PORT_FEASIBILITY.md) (frozen)
**Upstream:** [`88250/lute`](https://github.com/88250/lute) pinned at `61eb27b6d43418b79ee91d8618f7acbccdcd1ba5`
(see [`UPSTREAM.md`](./UPSTREAM.md))
**Target toolchain:** Zig 0.17.0 (pinned), no external Zig dependencies

`lutez` is a Zig port of Lute's CommonMark 0.31.2 + GFM **parser only**, exposed as a
reentrant C ABI library and a self-contained WASM module. Input is UTF-8 Markdown bytes
plus options; output is a versioned little-endian binary AST owned by an opaque document
handle. Rendering is not ported and not in scope.

---

## 1. Scope contract

### 1.1 In scope

| Area | Owner module | Source of truth (upstream) |
|---|---|---|
| Lexer (line splitting, CRLF/NUL normalization) | `src/lex/` | `lex/lexer.go`, `lex/token.go` |
| Block parser: paragraph, ATX/setext heading, thematic break, blockquote, list/item, indented + fenced code, HTML block (types 1–7), GFM table, link-ref-def block, document | `src/parse/` | `parse/blocks.go`, `block_start.go`, `paragraph.go`, `heading.go`, `thematic_break.go`, `blockquote.go`, `list.go`, `code_block.go`, `html_block.go`, `table.go`, `parse.go` |
| Inline parser: text, escapes, code spans, emphasis/strong delimiter stack, links, images, link reference resolution, autolinks (CM + GFM), inline HTML, entities, hard/soft breaks, GFM strikethrough, task list markers | `src/parse/` | `parse/inline.go`, `inlines.go`, `delimiter.go`, `text.go`, `code_span.go`, `link.go`, `inline_link.go`, `image.go`, `auto_link.go`, `inline_html.go`, `linkrefdef_index.go`, `linkrefdef_case_fold.go` |
| AST subset (arena tree, walk, tree ops) | `src/ast/` | `ast/node.go` (subset), `ast/walk.go` |
| Unicode semantics (spaces, punctuation/symbols, quotation marks, simple + full case folding) | `src/unicode/` | `unicode.*`, `golang.org/x/text/cases` |
| HTML entities + destination encode/decode + HTML escape | `src/html/` | `html/entity.go`, `html/unesc_str.go`, `html/escape.go`, `html/escape_encode.go` |
| C ABI, WASM ABI | `src/c_api.zig`, `src/wasm.zig`, `include/lutez.h` | — (new) |
| Binary AST wire format | `src/ast/wire.zig` | — (new) |

### 1.2 Out of scope (hard exclusions)

Everything the feasibility report excludes: all SiYuan/Protyle/Vditor extensions
(BlockRef, FileAnnotationRef, TextMark, Callout, Tabs, SuperBlock, CustomBlock,
TableRich, DocumentTitle, GitConflict, Kramdown IAL, Spin, Tag, Mark, Sup/Sub, TOC,
Emoji aliases, Footnotes, math, YAML front matter, heading IDs, paragraph-beginning-space),
all rendering (`render/*`, `protyle*.go`, `vditor*.go`, `h2m.go`, `latex_math.go`),
the HTML5 tokenizer/parser (`html/parse.go`, `html/token.go`, `html/atom`), the `Lute`
wrapper API, JSON decoding of document titles, node IDs, base64, `time`/`rand`,
`net/url`, `regexp`, `sync`, and code-syntax highlighting (chroma).

CommonMark **HTML blocks and inline HTML stay in scope as lexical scanning only**;
their content is stored as raw text. Entity decoding and link-destination percent
encoding stay in scope because they are grammar, not HTML parsing.

### 1.3 Parity target

Parity means: for the same input bytes and options, `lutez` produces an AST that is
**semantically identical** to upstream Lute restricted to in-scope node types and
fields. Byte-identical AST serialization is *not* required across implementations;
upstream's HTML rendering of `lutez`'s AST must be byte-identical for the scoped corpus
(this is the end-to-end oracle, §7.3).

---

## 2. Deliverables and acceptance gates

| # | Deliverable | Acceptance gate |
|---|---|---|
| D1 | Zig library (static + shared) `liblutez` | builds on Linux/macOS/Windows x86-64 + aarch64 from one machine |
| D2 | `include/lutez.h` C ABI v1 | C99 sample compiles and runs; no leaks under Valgrind/ASan |
| D3 | WASM module `lutez.wasm` (wasm32-freestanding) | **zero imports**, ≤ 500 KB raw, runs in Node 24 and a browser smoke page |
| D4 | CommonMark conformance | **652/652** `test/commonmark-spec.json` examples: AST parity **and** HTML parity |
| D5 | GFM conformance | 100 % of generated GFM fixture set (tables, strikethrough, task lists, extended autolinks) |
| D6 | Robustness | 24 CPU-hours differential + coverage-guided fuzzing: 0 panics, 0 OOB, 0 leaks, 0 hangs (> 1 s/input) |
| D7 | Performance | ≤ 0.85 × upstream Go parse time on the spec corpus (≥ 1.2× faster), ≤ 0.5 × allocations/bytes |
| D8 | Reproducibility | `zig build check` + `node test/wasm/smoke.mjs` green from a clean checkout with only Zig 0.17.0 installed (no Go, no submodule); Go/submodule only for parity runs and regeneration |
| D9 | Provenance/compliance | Mulan PSL v2 headers preserved on ported files, `NOTICE` lists derived files, `tools/port-manifest.tsv` maps every Zig file → upstream file → upstream SHA |

---

## 3. Architecture

### 3.1 Layers and data flow

```
bytes + Options
      │
      ▼
┌─────────────────┐   copy + normalize (CRLF→LF, append "\n", NUL→U+FFFD)
│  lex.Lexer      │───────────────► document arena: normalized input []u8
└─────────────────┘                        │
      │ line slices (mutable, into input)  │
      ▼                                    │
┌─────────────────┐                        │
│  parse.Tree     │  block pass            │
│  (arena nodes)  │  inline pass           │
└─────────────────┘                        │
      │ node tree (u32 handles)            │
      ▼                                    ▼
┌────────────────────────────────────────────────┐
│ ast.wire.encode  → single contiguous buffer    │
│   header | nodes | extras | input | token pool │
└────────────────────────────────────────────────┘
      │
      ├── C:  lute_doc* (opaque, owns buffer)   → lute_doc_ast() returns ptr+len
      └── WASM: doc handle (u32) in a slot table → lutez_doc_ast(handle) → packed ptr/len
```

No AST node is ever exposed across the FFI boundary. The only cross-boundary artifacts
are `(ptr,len)` into a buffer the document owns.

### 3.2 Arena + index-based tree (ADR-1)

- One `std.heap.ArenaAllocator` per document (backed by `c_allocator` natively,
  `wasm_allocator` in WASM). Destruction is O(1) — matches AST lifetime.
- Nodes live in an `std.ArrayListUnmanaged(Node)`; all links are `Index = u32`
  (`null_node = 0xFFFF_FFFF`). No pointers inside the tree, therefore:
  - no dangling pointers on growth,
  - trivial serialization,
  - no pointer-size assumptions in WASM32.
- `Node` is a fixed-size struct with a type-specific `ext` union (max variant ≤ 32 B).
  Target `@sizeOf(Node) ≤ 96 B`, verified by a comptime assert.
- Tree ops (`appendChild`, `insertAfter`, `unlink`, `childByType`, `parentIs`,
  `isBlock`, `content`, `text`, `walk`) mirror upstream semantics exactly, including
  sibling/parent/child pointer maintenance order.

### 3.3 Token ownership and mutability (ADR-2)

Upstream's lexer *mutates* its input (CRLF→LF in place) and the parser occasionally
mutates token bytes in place (trailing-space trimming, label case folding). Therefore:

- `Tokens` are `[]u8` (mutable), never `[]const u8`.
- Every token slice points into the document arena: either the **normalized input**
  (the common case) or a **scratch/pool buffer** for fabricated bytes (entity-decoded
  text, synthesized markers, lowercased labels).
- The arena input is copied from caller memory at `parse` entry; the caller's buffer may
  be freed immediately after the call. This removes the dangling-slice hazard called out
  in the feasibility report §5.
- Encoder tags each token ref with a 1-bit source selector (input vs pool), so
  serialization is a copy with no pointer chasing. Slices larger than 2 GiB and inputs
  larger than 2 GiB are rejected with `LUTEZ_ERR_INPUT_TOO_LARGE` (WASM32 safety).

### 3.4 Options (ADR-3)

Zig-side `Options` is a plain struct with defaults matching upstream defaults:

```
gfm_table, gfm_task_list_item, gfm_strikethrough, gfm_auto_link,
inline_asterisk, inline_underscore, setext, indent_code_block,
link_ref, data_image, soft_break2_hard_break (internal), // 11 semantic flags
```

C ABI carries the same fields in a versioned struct with `struct_size` as the first
member; unknown/absent tail fields take defaults from a zero-initialized struct.
Options are validated (reject `struct_size` smaller than the v1 prefix).

### 3.5 Binary wire format (ADR-4)

`doc/WIRE_FORMAT.md` holds the normative spec. Summary:

```
Header 32 B: magic "LUTEAST1", u32 version, u32 flags, u32 node_count,
             u32 node_stride, u32 input_len, u32 pool_len, u32 ext_len
Sections (8-byte aligned, fixed order): nodes | extras | input | pool
Node 48 B: u16 type, u16 flags, u32 parent/first_child/last_child/prev/next,
           u32 tok_ref/tok_len, u32 data_ref/data_len, u32 ext_ref/ext_len
```

- Little-endian only, offsets are `u32`, absent = `0xFFFFFFFF`.
- `ext` blobs are type-specific, self-describing (length-prefixed), and documented per
  node type in `AST_SCHEMA.md`. Adding a field in a future version does not change the
  node stride.
- **No JSON writer in the core library.** JSON is produced only by the Go harness,
  which decodes the wire format. This avoids re-implementing `encoding/json` semantics
  (key ordering, `omitempty`, `[]byte` base64) in Zig, a stated landmine.
- Decoder lives in Zig too (`wire.decode`) because the corpus runner and round-trip
  tests need it; it is not part of the public ABI.

### 3.6 C ABI v1 (ADR-5)

Draft in `include/lutez.h`:

```c
typedef struct lutez_doc lutez_doc;

lutez_doc *lutez_parse(const uint8_t *md, size_t len, const lutez_opts *opts);
const uint8_t *lutez_doc_ast(const lutez_doc *doc, size_t *out_len);
uint32_t lutez_doc_abi_version(const lutez_doc *doc);
void lutez_doc_free(lutez_doc *doc);

/* ergonomic accessors (validated on a per-document offset table) */
uint32_t lutez_node_count(const lutez_doc *doc);
int32_t  lutez_node_type(const lutez_doc *doc, uint32_t node);
uint32_t lutez_node_first_child(const lutez_doc *doc, uint32_t node);
uint32_t lutez_node_next(const lutez_doc *doc, uint32_t node);
const uint8_t *lutez_node_data(const lutez_doc *doc, uint32_t node, size_t *len);

const char *lutez_last_error(void);   /* thread-local, never NULL */
int32_t     lutez_last_error_code(void);
const char *lutez_version_string(void);
```

Rules: `NULL` + thread-local error on failure; no panic may cross the boundary
(every exported function is a `catch`/validation boundary); no mutable globals;
`lutez_last_error()` returns a static string, never the document's memory.

### 3.7 WASM ABI (ADR-6)

`wasm32-freestanding`, no libc, no imports, built through the 0.17 Build API with
`rdynamic = true` + `export_memory = true` at `ReleaseSmall`. Zig 0.17's Build API cannot
pass `-fno-entry` (CLI-only flag) and the WASM linker requires an entry symbol, so
`src/wasm.zig` defines an empty `pub fn main` to supply `_start`; JS never calls it. The
import-free property is asserted by `zig build wasm` + the Node smoke test, and by
`build.zig.wasm.check` (M5).

Exports: `lutez_alloc(u32) -> u32`, `lutez_free(u32)`, `lutez_parse(ptr,len,opts_ptr) -> u32 handle`
(`0xFFFFFFFF` = error), `lutez_doc_ast(handle) -> u64` packed `(ptr << 32) | len`,
`lutez_doc_free(handle)`, `lutez_last_error_ptr() -> u64`, `lutez_version()`.
Document handles index a fixed-capacity slot table (no pointers in JS). JS glue
re-creates typed-array views after any call that can grow memory.

### 3.8 Errors, panics, thread safety (ADR-7)

- `lutez.Error` enum mirrors `lutez_err_*` codes; messages are static.
- Parser internals use Zig error unions only for allocation failure, invalid options,
  oversized input, and internal invariants; ordinary recoverable "malformed markdown"
  never errors (it produces text nodes, exactly like upstream).
- No `unreachable` reachable from document bytes. `@intCast` is banned on input-derived
  values; use `std.math.cast` + explicit error. `std.debug.assert` only for invariants
  that fuzzing is expected to prove.
- `-Doptimize=ReleaseSafe` is the default for release artifacts (trap = bug, and we
  want traps in CI); `ReleaseFast` is opt-in and benchmarked.
- Truly reentrant: all tables are `const`, no globals except the thread-local error
  string and the WASM slot table (single-threaded by construction).

---

## 4. Repository layout

```
lutez/
├── build.zig                  # native static+shared, wasm, tests, smoke-c
├── build.zig.zon
├── include/lutez.h            # C ABI v1 (versioned)
├── src/
│   ├── lutez.zig              # public Zig API: parse(), Doc, Options, Error
│   ├── c_api.zig              # exported C symbols (thin, validated)
│   ├── wasm.zig               # exported WASM symbols + slot table
│   ├── arena.zig              # document arena + scratch/pool buffer
│   ├── types.zig              # NodeType, Options, Error, version (done)
│   ├── lex/{token.zig,lexer.zig}
│   ├── ast/{node.zig,tree.zig,walk.zig,wire.zig}
│   ├── parse/{parse,blocks,block_start,blockquote,paragraph,heading,thematic_break,
│   │           list,html_block,code_block,code_span,link,inline_link,inlines,inline,
│   │           delimiter,text,image,linkrefdef_index,auto_link,table,inline_html}.zig
│   ├── html/{entity_tables.zig,escape.zig}
│   └── unicode/{tables.zig,fold.zig}
├── test/                      # ALL test material: roots, fixtures, corpora, bench
│   ├── root.zig               # `zig build test` root
│   ├── conformance.zig        # Go-free binary-corpus runner (M0.6)
│   ├── roundtrip.zig          # wire encode/decode + corruption tests (M0.4)
│   ├── spec/commonmark-spec.json
│   ├── corpus/                # committed *.lzc fixtures (Go-free CI)
│   ├── gfm/                   # generated GFM fixtures
│   ├── cases/                 # upstream-derived regression fixtures (M4.6)
│   ├── wasm/smoke.mjs         # Node smoke test: 0 imports, exports, ABI
│   └── bench/                 # parse benchmarks + Go baseline harness
├── parity/                    # EVERYTHING that proves parity against upstream
│   ├── README.md
│   └── go/                    # one Go module; replace lute => ../../upstream/lute
│       ├── astmodel/          # neutral AST structs (wire decoder target)
│       ├── mask.go            # out-of-scope fields zeroed before comparison
│       ├── lute/              # oracle: upstream parse
│       ├── lutez/             # cgo bridge to zig-out/lib/liblutez.a
│       └── cmd/{lute-ast,lutez-ast,diff,html-oracle,gencorpus,check-schema}
├── tools/
│   ├── upstream.sh            # submodule status / verify / diff / bump
│   ├── gen-unicode/           # Go generator: unicode + cases.Fold tables → Zig
│   ├── gen-entity/            # Go generator: upstream html/entity.go → Zig table
│   └── port-manifest.tsv      # Zig file ↔ upstream file ↔ status
├── js/                        # WASM glue + Node smoke test
├── samples/c/                 # C ABI sample
├── doc/{PLAN.md,AST_SCHEMA.md,WIRE_FORMAT.md,UPSTREAM.md,ZIG_PORT_FEASIBILITY.md}
└── upstream/lute/             # git submodule at the pinned commit (never edited)
```

Three rules keep this honest:

- **`upstream/` is a git submodule**, not a fetched copy: the gitlink recorded in the
  superproject commit *is* the pin. It is never edited and never imported by `src/`.
- **`test/` contains all test material** — Zig test roots, fixtures, corpora, and
  benchmarks. Nothing test-related lives at the repo root.
- **`parity/` contains everything that compares us to upstream** — the Go oracle, the
  cgo bridge, the differential runner, the HTML oracle, the corpus generator, and the
  schema-drift checker. If it needs the upstream tree, it lives in `parity/`.

---

## 5. Porting methodology

### 5.1 Two-phase translation

1. **Faithful port** — keep upstream file/function/variable names, control flow, and
   comments (translated to English where helpful), with `src/util/go_compat.zig`
   helpers that mirror `bytes.*` semantics (`IndexByte`, `TrimSpace`, `ReplaceAll`,
   `EqualFold`, `HasPrefix`, …). Goal: reviewable side-by-side diffs.
2. **Idiomatize** — only after the module's differential tests are green. Any cleanup
   must keep the parity tests green; no cleanup and porting in the same commit.

Every ported file starts with a provenance header:

```zig
// Ported from lute/parse/delimiter.go @ 61eb27b (Mulan PSL v2, (c) 2019-present b3log.org)
// Scope: CommonMark/GFM only; Kramdown IAL, math, emoji branches removed (see doc/PLAN.md §1.2).
```

### 5.2 Translation rules (Go → Zig)

| Go | Zig |
|---|---|
| `[]byte` token, mutated in place | `[]u8` slice into arena input/pool |
| `*ast.Node` | `Index` (`u32`), `null_node` sentinel |
| `node.Parent/Next/FirstChild` | same-name fields as indices + `node()` accessor |
| `map[*ast.Node]…` | `std.AutoHashMapUnmanaged(u32, …)` keyed by node index |
| `map[string]…` (ref defs) | `std.StringHashMapUnmanaged(Index)` over arena strings |
| `[]*ast.Node` | `std.ArrayListUnmanaged(Index)` |
| closures / `ast.Walk(node, func…)` | visitor with `ctx: anytype` comptime parameter |
| `for i, b := range bs` | `for (bs, 0..) \|b, i\|` |
| `utf8.DecodeRune` | `std.unicode.utf8Decode` (+ custom `RuneError` semantics wrapper) |
| `unicode.IsPunct` etc. | `unicode/categories.zig` (generated binary-search tables) |
| `bytes.EqualFold` | `unicode.fold.eqlFold` (full fold, generated) |
| `sort.Strings` | `std.sort.pdq` with byte-wise `<` (verified order-parity on attribute keys) |
| Go `nil` slice vs empty | irrelevant (binary format has no JSON `null`/`[]` distinction) |
| `panic(...)` on impossible state | `std.debug.assert` (internal) or `error.Internal` (input-reachable) |

### 5.3 Branch-stripping protocol

Out-of-scope branches are removed **while porting** (never ported then deleted), using
the feasibility report §2.3 checklist. Each port PR states which upstream branches were
dropped and why, and `tools/port-manifest.tsv` records the upstream file SHA. A weekly
`git diff` review against upstream (`tools/upstream.sh --diff`) lists new upstream
commits touching scoped files so drift is visible.

### 5.4 Definition of "ported"

A source file is *ported* only when: (a) it compiles with no `TODO(port)` markers,
(b) its unit tests exist, (c) its corpus slice parses with zero AST diffs, and
(d) it is listed in `port-manifest.tsv`.

---

## 6. Generated data

| Table | Generator | Size target | Test |
|---|---|---|---|
| `src/unicode/tables.zig` — `IsSpace`, `Zs`, `IsControl`, `IsPunct`, `IsSymbol`, `Quotation_Mark`, `SimpleFold` | `tools/gen-unicode` (Go, same Go version as upstream's `go.mod`) | ≤ 40 KB | exhaustive: every code point compared against Go |
| `src/unicode/fold.zig` — full case folding (`cases.Fold`) | `tools/gen-unicode` | ≤ 60 KB | exhaustive: every code point + `bytes.EqualFold` pairs |
| `src/html/entity_tables.zig` — entity names → bytes, two-stage trie (Go `html.UnescapeString` semantics incl. missing semicolons, attribute mode irrelevant here) | `tools/gen-entity` (parses upstream `html/entity.go`) | ≤ 120 KB | exhaustive: every entity, plus malformed/prefix cases vs Go |
| `test/corpus/*.lzc` — 652 CM examples + GFM fixtures + upstream regression cases, with expected wire AST | `parity/go/cmd/gencorpus` | ≤ 6 MB committed | re-run generator, must be byte-identical |

Generated files are committed (Zig CI needs no Go) and carry a `// GENERATED — do not
edit` header plus generator command and input SHA. Regeneration is a separate,
reviewed commit.

---

## 7. Test strategy

Layered so that failures localize quickly:

1. **L0 unit tests** (`zig build test`) — per-module, upstream-derived expectations
   (e.g. `TestIsWhitespace` ported from `lex/token_test.go`).
2. **L1 lexer golden tests** — line splitting/CRLF/NUL cases, byte-identical vs Go.
3. **L2 AST differential** (`parity/go/cmd/diff`) — parse with upstream Go and with
   `lutez` (via cgo static lib), decode both to Go structs, compare with
   `reflect.DeepEqual` after masking out-of-scope fields. Reports per-example diffs with
   the first divergent path. **Built in M0, before the parser exists.**
4. **L3 HTML oracle** — deserialize `lutez`'s AST into upstream `ast.Node` and render
   with upstream `render.HTMLRenderer`; compare to the spec's expected HTML
   byte-for-byte. Catches AST fields that L2 masks.
5. **L4 conformance runner** (`zig build conformance`) — Go-free: runs committed binary
   corpus, compares wire ASTs structurally, prints CommonMark section summary.
6. **L5 robustness** — `zig build fuzz` (libFuzzer on the C ABI through
   `zig build-lib -fsanitize-c`), Go dual-implementation random fuzzing, ASan/Valgrind
   on the C library, 8-thread stress under TSan.
7. **L6 performance** — `zig build bench` (hyperfine-style repeated runs, internal
   timer), Go baseline (`BenchmarkParseSpec` ≈ 17 ms, 12.7 MB, 25.8k allocs on reference
   hardware), results recorded in `doc/BENCHMARKS.md`.

### 7.1 Parity dashboard

`parity/go/cmd/diff --dashboard` prints:

```
CM examples:   652/652 AST-parity   (0 diffs)
GFM fixtures:  213/213 AST-parity   (0 diffs)
HTML oracle:   652/652 byte-identical
Leaks:         0 (testing allocator)    OOB: 0    Panics: 0
Perf:          7.1 ms (0.42x Go)    RSS: 4.2 MB (0.33x)
WASM:          312 KB, 0 imports
```

CI publishes this per commit; any regression above 0 diffs blocks merge from M2 onward.

### 7.2 Masked fields (L2 only)

`ID`, `Spec`, `Box`, `Path`, `DocumentTitle`, `Properties`, `KramdownIAL`,
`TextMark*`, `AttributeView*`, `Callout*`, `TabItemTitle`, `CustomBlock*`,
`TableCellRich`, `TableCellContent*`, `CodeMarkerLen`, `*Footnotes*`, `MathBlock*`,
`HeadingNormalizedID`, `TaskListItemChecked` (superseded by marker semantics — masked
only if upstream keeps setting both).

The mask list is data, not code: `parity/go/mask.go`, reviewed whenever the schema
changes.

---

## 8. Milestones

Effort in engineer-weeks (one experienced engineer). Parallelizable as noted.

### M0 — Freeze contracts + differential harness (2 wks)

| ID | Task | Exit |
|---|---|---|
| M0.1 | Repo skeleton, `build.zig` (static/shared/wasm/test/smoke-c steps), CI matrix, license headers | `zig build check` green |
| M0.2 | `upstream/lute` git submodule + `tools/upstream.sh` + `UPSTREAM.md` (pin, provenance, bump procedure) | `tools/upstream.sh --verify` green on a clean recursive checkout |
| M0.3 | `doc/AST_SCHEMA.md`: scoped node types (upstream numbering), per-type fields, `ext` blob layouts, mask list | reviewed + frozen |
| M0.4 | `doc/WIRE_FORMAT.md` v1 + Zig encoder/decoder + round-trip + fuzz-proof decoder tests | round-trip on synthetic trees |
| M0.5 | `parity/go` cgo bridge + `diff` runner using the 652 CM examples | harness reports 652 "not implemented" cleanly |
| M0.6 | `parity/go/cmd/gencorpus` producing binary corpus + expected wire ASTs | corpus committed, checksummed |
| M0.7 | `tools/port-manifest.tsv` + `parity/go/cmd/check-schema` drift check in CI | CI fails on upstream SHA/schema drift |

**Gate G0:** harness can parse the full corpus with upstream Go, and a *stub* `lutez`
returns an empty document for all 652 inputs, diffing cleanly (plumbing proven).

### M1 — Lexer, AST, Unicode, entities, wire (2.5 wks)

| ID | Task | Exit |
|---|---|---|
| M1.1 | `lex/token.zig` (byte class + whitespace/digit/hex/upper helpers) | unit tests green |
| M1.2 | `lex/lexer.zig` (input copy, CRLF→LF, trailing `\n`, NUL→U+FFFD) | byte-identical vs Go on corpus |
| M1.3 | `arena.zig`, `ast/node.zig`, `ast/tree.zig` (all tree ops), `ast/walk.zig` | unit tests + synthetic tree round-trip |
| M1.4 | `unicode` generators + `tables.zig` + `fold.zig` | exhaustive code-point parity |
| M1.5 | `html/entity_tables.zig` + `unescapeString` port | exhaustive entity parity |
| M1.6 | `html/escape.zig` — `EncodeDestination`/`DecodeDestination`/`EscapeHTMLStr` | upstream test cases + round-trip |
| M1.7 | `ast/wire.zig` encoder/decoder production implementation | round-trip, truncation/mutation fuzz |

**Gate G1:** lexer output and all lookup tables are byte-exact vs Go; no memory growth.

### M2 — Block parser (4 wks)

| ID | Task | Exit |
|---|---|---|
| M2.1 | Parse entry/context, block loop, block start dispatch, finalization, ref-def map | paragraphs + document structure |
| M2.2 | Paragraph, ATX heading, setext heading, thematic break | block AST parity for these sections |
| M2.3 | Blockquote + markers | parity |
| M2.4 | List/item: bullet/ordered, tight/loose, padding, marker offset, nested lists, interruption rules | parity (largest block risk) |
| M2.5 | Indented code, fenced code (info string, fence len/char/offset) | parity |
| M2.6 | HTML blocks 1–7 (termination rules) | parity |
| M2.7 | GFM table (aligns, rows, cells, escaped pipes) | parity incl. 2300 upstream table cases |
| M2.8 | Link reference definition block parsing + index + case fold | parity |
| M2.9 | Reference-def resolution + `linkRef` finalization | parity |

**Gate G2:** block-level structure parity on all 652 CM examples (inline content
compared as raw text), 100 % of GFM table fixtures.

### M3 — Inline parser (6 wks; parallelizable with M2 after M1)

| ID | Task | Exit |
|---|---|---|
| M3.1 | Inline container loop, text collection, soft/hard breaks, escapes (`NodeBackslash`) | parity |
| M3.2 | Code spans (backtick runs, content trimming, escapes) | parity |
| M3.3 | Delimiter stack: emphasis/strong, `*`/`_` rules, `InlineAsterisk/Underscore` options, rule-of-3 | parity (highest risk) |
| M3.4 | Links/images: inline, reference, collapsed, shortcut; dest/title scanning; percent encoding | parity |
| M3.5 | Autolinks: CM URI/email + GFM extended (trailing punctuation, parens, `www.`, mail) | parity |
| M3.6 | Inline HTML (`<tag …>`, comments, PI, CDATA, declarations) — lexical only | parity |
| M3.7 | Entities (`&…;` incl. legacy no-semicolon forms) | parity |
| M3.8 | GFM strikethrough (1 and 2 tilde) + task list markers | parity |
| M3.9 | Table cell inline parsing + alignment/width fields required by renderer | parity |

**Gate G3 (go/no-go):** 652/652 CM AST parity + 100 % GFM AST parity + 652/652 HTML
parity. If G3 is not met by week 14, invoke the stop rule (§10, R1).

### M4 — Hardening (3 wks)

- M4.1 Differential fuzzing (Go dual-run) + libFuzzer on C ABI; triage to zero.
- M4.2 Zig `std.testing.allocator` leak/ownership pass; ASan + Valgrind on C lib.
- M4.3 Decoder hardening: malformed wire ASTs rejected (corpus is trusted, ABI is not).
- M4.4 Performance: arena reuse audit, hot-path profiling, allocation count, input copy
  elimination for the C path (single-copy guarantee), benchmark doc.
- M4.5 Thread-safety stress (8 threads × corpus) + TSan.
- M4.6 Upstream regression corpus: port the ~313 upstream test functions that fall in
  scope (SiYuan-specific ones filtered) as corpus fixtures.

**Gate G4:** D6 and D7 met and recorded in `doc/BENCHMARKS.md`.

### M5 — C ABI, WASM, glue, packaging (2.5 wks)

- M5.1 Finalize `include/lutez.h` v1 (versioned opts, accessors, error API).
- M5.2 `src/c_api.zig` with full validation boundary; no panic escape; error messages.
- M5.3 `src/wasm.zig` slot table, `u64` packed ptr/len, growth-safe glue.
- M5.4 JS glue (`js/lutez.mjs` + `.d.ts`) and C sample (`samples/c/`), Node + browser
  smoke tests in CI.
- M5.5 Cross-compile matrix: linux-gnu/musl, macos aarch64/x86_64, windows-gnu
  (dll+lib), wasm32-freestanding; artifact naming + checksums.
- M5.6 Packaging: `zig build dist` tarball (header, static/shared libs, wasm, LICENSE,
  NOTICE, README snippet).

**Gate G5:** D1, D2, D3 met; Node/browser/C smoke tests green.

### M6 — Docs and release (1.5 wks)

- M6.1 Public docs: README (quick start C/WASM/Zig), `doc/ABI.md`, wire format
  compatibility policy (semver rules), `doc/PORTING_NOTES.md` (deviations from upstream).
- M6.2 Release checklist + `doc/RELEASE.md`; tag `v0.1.0`; reproducible-build check.
- M6.3 License compliance audit (headers on every derived file, NOTICE complete).
- M6.4 Publish benchmark and conformance dashboard for the release.

**Gate G6:** D8, D9 met; release artifacts reproducible.

### Timeline (single engineer, sequential)

```
M0  ██ 2w
M1  ███ 2.5w
M2  █████ 4w
M3  ████████ 6w
M4  ████ 3w
M5  ███ 2.5w
M6  ██ 1.5w
total ≈ 21.5 eng-weeks ≈ 5 eng-months (feasibility est. 4.5–6.5)
```

Two engineers: M2 and M3 run in parallel after M1 → ≈ 3.5–4 calendar months.
Vertical slice (M0 + M1 + M2 core + M3 core) is scheduled at 6–8 weeks per the
feasibility report and is the decisive go/no-go.

---

## 9. Vertical slice (first 8 weeks)

Deliberately the riskiest 80 % of the value:

1. M0 complete (harness + schema + wire format).
2. M1 complete (lexer, arena/AST, Unicode, entities, escape).
3. M2.1–M2.5 (paragraph, heading, thematic break, blockquote, list, code blocks).
4. M3.1–M3.4 (text, escapes, code spans, emphasis, links/images).

**Slice exit:** ≥ 95 % of the 652 CM examples with zero AST diffs, zero leaks, and the
HTML oracle at ≥ 95 %. If the slice is not at ≥ 90 % by week 8, escalate to §10 R1.

---

## 10. Risks and mitigations

| ID | Risk | Likelihood | Impact | Mitigation / trigger |
|---|---|---|---|---|
| R1 | Emphasis/link edge-case parity stalls | Medium | High | Build the differential harness first; port `delimiter.go` 1:1 before idiomatizing; per-example diff tooling. **Stop rule:** if G3 not met by week 14, re-evaluate against `cmark-gfm`/`md4c` (feasibility §9). |
| R2 | Unicode/fold table mismatch | Medium | Medium | Generate from the same Go/`x/text` versions; exhaustive tests over all code points; CI drift check on generator inputs. |
| R3 | Entity/URL encoding mismatch | Low–Medium | Medium | Port upstream algorithm verbatim + exhaustive entity test; HTML oracle catches residual diffs. |
| R4 | Zig 0.17 API churn (std.io, build) | High | Low–Medium | Pin 0.17.0; hand-rolled LE codec (no `std.io`); wasm built via CLI flags; small std surface; upgrade is its own milestone gate. |
| R5 | Panic/trap across FFI | Low | High | `ReleaseSafe`, no input-derived `unreachable`/`@intCast`, libFuzzer + dual fuzz, validation boundary in `c_api.zig`. Traps = CI failures. |
| R6 | AST contract drift vs upstream | High over time | Medium | Pinned submodule, `port-manifest.tsv`, `check-schema` CI job, `upstream.sh --verify` CI job, `UPSTREAM.md` bump procedure. |
| R7 | WASM32 addressing (> 2 GiB / u32 overflow) | Low | Medium | Explicit size limits + errors; `u32` wire format; JS glue re-views; conformance under wasm. |
| R8 | Upstream license/provenance | Low | Medium | Preserve Mulan PSL v2 headers, NOTICE with file list, no relicensing. |
| R9 | Scope creep (footnotes/math/SiYuan) | Medium | High | §1.2 is a hard gate; PR checklist rejects out-of-scope node types; CI asserts node type whitelist. |
| R10 | Perf gate not met with arena+copy | Low | Low | Input copy is one memcpy; pool dedup; if needed, optional zero-copy in-place mode (`lutez_parse_owned`) deferred to v1.1. |

---

## 11. Engineering conventions

- **Commits:** one upstream file (or tightly coupled pair) per commit; message
  `port(parse): delimiter.go` or `feat(wire): ext blobs`; each port commit green on L2/L4
  for its slice when possible.
- **Branches:** `main` always buildable; porting on `port/<area>`; parity/tooling on
  `tool/<name>`.
- **Provenance:** every ported file header names upstream path + SHA; `port-manifest.tsv`
  is the machine-readable copy.
- **No vendored upstream code** in `src/`: translation only, with attribution.
- **Formatting:** `zig fmt` enforced in CI; `-Doptimize=Debug` for tests,
  `ReleaseSafe` for release artifacts, `ReleaseSmall` for WASM.
- **No new Zig dependencies** without an ADR in `doc/PLAN.md`.

---

## 12. Open decisions (need sign-off before M0.3/M0.4 freeze)

1. **AST compatibility level** — recommend: keep upstream `NodeType` numeric values and
   type strings (`"Paragraph"`, `"Emphasis"`, …), so JSON/goldens and consumer
   expectations transfer. Alternative: new clean schema (cheaper, breaks compatibility).
2. **Wire format** — recommend: binary LE v1 only in the core; JSON only in the Go
   harness. Alternative: add a Zig JSON writer (adds ~1–2 weeks + `encoding/json`
   parity risk).
3. **Upstream pin** — recommend `61eb27b` (master, 2026-11-13), not tag `v1.7.8`: ~830
   lines of scoped-file changes landed after the tag. Confirm, or choose tag for a
   quieter baseline.
4. **C accessors in v1** — recommend yes (cheap, useful), accessor reads are validated
   against the wire format.
5. **Input ownership** — recommend always-copy (safe) with an optional v1.1
   `lutez_parse_owned` zero-copy mode. Alternative: owned-from-start.
6. **Release optimization mode** — recommend `ReleaseSafe` default; `ReleaseFast`
   measured but opt-in.
7. **Zig pin** — 0.17.0 (matches feasibility validation). Upgrading Zig is a separate,
   benchmarked PR.
8. **Repo location/name** — `lutez`, module `lutez`, C prefix `lutez_`, header
   `include/lutez.h`. Confirm (affects ABI naming forever).
9. **Scope fence** — confirm §1.2 remains a hard exclusion for v0.1, including footnotes/
   math/YAML/emoji/SiYuan extensions.

---

## 13. Immediate next actions (first commits)

1. `chore: skeleton build` — this commit: `build.zig`, `build.zig.zon`, `src/lutez.zig`,
   `src/types.zig`, `src/c_api.zig`, `src/wasm.zig` (stubs), `include/lutez.h` draft,
   docs, CI stub.
2. `chore: upstream submodule` — `upstream/lute`, `tools/upstream.sh`, `doc/UPSTREAM.md`,
   verify SHA (`tools/upstream.sh --verify`).
3. `doc: freeze AST schema` (M0.3) — with `parity/go/cmd/check-schema` scaffold.
4. `feat(wire): v1 encoder/decoder` (M0.4) — round-trip + corruption tests.
5. `parity: lute-ast + diff` (M0.5) — first 652-example run against the stub.
6. `tool(gen): unicode + entity tables` (M0/M1.4–M1.5) — start codegen early; it is
   independent of parser work and de-risks parity.

After (5) the project has a working parity scoreboard, which is the precondition for
starting the M1 port.
