# Lute core parser → Zig (C ABI + WASM): feasibility report

**Scope decision (frozen for this report):** port only the **CommonMark / GFM Markdown
parser** to Zig, exposed as a C library and as a WASM library.

Explicitly **out of scope**:

- All SiYuan / Protyle / Vditor extensions (BlockRef, FileAnnotationRef, TextMark,
  Callout, Tabs, SuperBlock, CustomBlock, TableRich, DocumentTitle, GitConflict,
  Kramdown IAL, Spin, Tag, Mark, Sup/Sub, TOC, Emoji aliases, Footnotes, math blocks,
  YAML front matter, heading IDs, paragraph-beginning-space, Chinese-specific options).
- All rendering (HTML, Markdown formatting, JSON, Protyle/Vditor DOM renderers).
- All HTML parsing: no HTML5 tokenizer, no DOM tree construction, no `h2m`, no
  `html.Parse` / `html.ParseFragment` / `html/atom`.
- UI, editor integration, JavaScript renderer bridge, Lute `Lute` wrapper API.

**In scope and worth calling out:** CommonMark's *HTML block* and *inline HTML* rules
are part of the Markdown grammar and remain in scope, but only as **lexical scanning
that emits raw HTML text nodes**. No HTML document is parsed or interpreted. CommonMark
entity references (`&copy;`, `&#35;`) and link-destination percent-encoding are also in
scope because they are part of the Markdown grammar; they use entity/URL tables, not an
HTML parser.

The delivered library is therefore: **UTF-8 Markdown bytes + options → a serialized AST**.
Rendering is the caller's responsibility.

---

## 1. Verdict

**Feasible, and the narrowed scope makes it substantially more attractive.**

- The dependency graph for the scoped parser is very clean: no interfaces, no reflection,
  no goroutines, no regex, no JSON, no base64, no `time`/`rand`, no `net/url`, no cgo.
- **No HTML parser is needed** once the Protyle/Vditor branches are stripped from the
  in-scope files. This removes the single largest hidden dependency in the original code.
- The C ABI and the freestanding WASM build were validated end-to-end on this machine
  (see §4). The toolchain is not the risk.
- The main risk is **behavioral parity** on CommonMark/GFM edge cases.
- Strategic caveat: if the goal is merely “a CM/GFM parser in C/WASM”, mature options
  (`cmark-gfm`, `md4c`) already exist. Porting Lute is justified only if you need
  **Lute's AST shape/behavior** for existing consumers. See §9.

| Scope | Effort (one experienced engineer) |
|---|---:|
| Parser core (CM 0.31.2 + GFM tables/strikethrough/task lists/autolinks) | **3.5–5 engineer-months** |
| C ABI + WASM + JS/C glue + packaging/CI | **+0.75–1.5 months** |
| **Total** | **~4.5–6.5 engineer-months** |
| Two engineers (block/inline split, shared harness) | **~3–4 calendar months** |
| Vertical slice (see §8) | **6–8 weeks** |

---

## 2. What the scoped core actually is

The natural seam is `parse.Parse(name, markdown, options) *Tree`. For this scope,
`parse` depends only on `ast`, `lex`, and small parts of `util` and `html`.

### 2.1 In-scope files

| Area | Files | Non-test LOC |
|---|---|---:|
| `lex` | `lexer.go`, `token.go` | 536 |
| `parse` (CM/GFM) | `parse.go`, `blocks.go`, `block_start.go`, `blockquote.go`, `paragraph.go`, `heading.go`, `thematic_break.go`, `list.go`, `html_block.go`, `code_block.go`, `code_span.go`, `link.go`, `inline_link.go`, `inlines.go`, `inline.go`, `delimiter.go`, `text.go`, `image.go`, `linkrefdef_index.go`, `linkrefdef_case_fold.go`, `auto_link.go`, `table.go`, `inline_html.go` | **7,221** |
| `ast` (subset) | `Node` struct subset, `NodeType` subset, `walk.go`, tree ops (`AppendChild`, `InsertAfter`, `Unlink`, `ChildByType`, `ParentIs`, `IsBlock`, `Content`, `Text`, …) | ~600–700 |
| `util` (subset) | `byte_str`, `rune` helpers, panic guard | ~120 |
| `editor` | not needed once Protyle branches are removed | ~0 |
| `html` (subset) | entity decode table, escape/unescape, `EncodeDestination` / `DecodeDestination` | ~2,500 (mostly generated) |
| Unicode data | simple/full case folding, punctuation/symbol categories, whitespace | generated |

Hand-written Zig is therefore roughly **7–8k LOC**, plus generated tables. That is less
than half of the full-parity estimate.

### 2.2 Out-of-scope files (do not port)

`parse/block_ref.go`, `block_query_embed.go`, `callout.go`, `custom_block.go`,
`document_title.go`, `emoji.go`, `emoji_map.go`, `file_annotation_ref.go`,
`footnotes.go`, `gitconflict.go`, `heading_id.go`, `html_text_style*.go`,
`inline_attribute_list.go`, `inline_math.go`, `latex_math.go`, `math_block.go`,
`super_block.go`, `table_rich*.go`, `tabs.go`, `text_mark_delimiters.go`, `toc.go`,
`transform.go`, `yaml_front_matter.go`.

Also excluded: `render/*`, `h2m.go`, `protyle*.go`, `vditor*.go`, `lute.go`,
`html/parse.go`, `html/token.go`, `html/foreign.go`, `html/atom`.

### 2.3 What remains to strip from in-scope files

The in-scope files contain option-gated branches for the excluded features. They must be
removed or compiled out; this is mechanical but touches ~15–25% of their LOC:

- Protyle/Vditor caret handling and TextMark conversion in `inline_html.go` (the
  `html.ParseFragment`, `html.NewTokenizer`, and `atom` calls live here).
- Kramdown IAL handling in `parse.go`, `blocks.go`, `inline.go`, `list.go`, `table.go`.
- Emoji, math, footnotes, YAML, heading-ID branches in `parse.go`, `blocks.go`,
  `inline.go`, `inlines.go`, `code_span.go`, `link.go`, `auto_link.go`.
- `finalParseBlockIAL`, `finalParseTabs`, `finalParseTableCellRich` calls in `parse.go`.

After stripping, the scoped parser has **no dependency on the full `html` package, no
JSON decoder, no regex, no `sync`, no `sort`, no `time`/`rand`, no `net/url`.**

### 2.4 In-scope option surface

Only ~10–12 of the 52 `parse.Options` fields matter:

`GFMTable`, `GFMTaskListItem`, `GFMStrikethrough`, `GFMAutoLink`, `InlineAsterisk`,
`InlineUnderscore`, `Setext`, `IndentCodeBlock`, `LinkRef`, `DataImage` (minor), plus
internal flags needed by the parser. This keeps the C options ABI small and stable.

### 2.5 Relevant test oracle

- 652 CommonMark 0.31.2 examples in `test/commonmark-spec.json`
- GFM cases in `test/gfm_spec_test.go` (~40 table entries) plus the 10,218-line
  `test/gfm-spec.md` for generating a fuller GFM fixture set
- ~2,300 table cases and 313 test functions in `test/`, many SiYuan-specific but still
  useful as regression input
- `test/json_renderer_test.go` golden AST JSON (use as a *format* reference; its
  SiYuan extension cases are out of scope)

---

## 3. Why Zig fits the scoped parser

1. **The parser is byte-slice oriented.** It already indexes `[]byte`, uses
   `bytes.*`, and calls `utf8.DecodeRune`. Zig slices and `std.mem` map almost 1:1.
2. **Arena allocation matches AST lifetime.** A per-document arena removes per-node
   allocation and gives O(1) document destruction. Go currently allocates ~25k objects
   and 12.7 MB for the CommonMark spec (17 ms/op); an arena should cut allocation
   overhead substantially.
3. **No runtime or third-party dependencies.** The only external Go dependency in the
   scoped core is `golang.org/x/text/cases`; replace it with generated Unicode tables.
4. **One toolchain cross-compiles everything** — Linux/macOS/Windows shared and static
   libraries, plus `wasm32-freestanding`, from one machine.
5. **WASM size and startup.** No Go runtime, no GC, no `wasm_exec.js`, no imports.
6. **Mechanical portability.** No interfaces, reflection, goroutines, `goto`, or
   `fallthrough`. There are ~40 closures/`ast.Walk` callbacks and a handful of
   pointer-keyed maps; both translate cleanly with Zig context structs and handle keys.

---

## 4. Toolchain validation performed

Environment: Zig **0.17.0**, Go 1.27.1, Linux x86-64. Prototypes were built in `/tmp`;
the repository was not modified.

| Check | Result |
|---|---|
| Zig native shared library (C ABI) | ✅ `liblute.so`, 72 KB (toy) |
| Zig native static library + C consumer | ✅ `liblute.a`, linked and ran |
| Zig static library + Go cgo adapter | ✅ ran from Go |
| Zig freestanding WASM (`wasm32-freestanding`) | ✅ 3.9 KB, **zero imports**, ran in Node |
| Go `-buildmode=c-shared`, parse-only | 4.8 MB |
| Go `wasip1/wasm`, parse-only, `-s -w` | 7.2 MB raw / 1.98 MB gzip |
| Existing GopherJS full bundle | 4.5 MB raw / 727 KB gzip |

The Zig WASM row is a toy module, not the parser; a full scoped parser should be
measured after Unicode/entity tables are added. Even so, the expected result is a few
hundred KB, one to two orders of magnitude below the Go alternatives.

Zig 0.17 specifics discovered:

- `std.heap.GeneralPurposeAllocator` is gone. Use `std.heap.c_allocator` for native
  builds and `std.heap.wasm_allocator` for freestanding WASM.
- A shared WASM *library* (`build-lib -dynamic`) imports memory/table/globals. Build a
  self-contained module with `zig build-exe -fno-entry -rdynamic` instead.
- Native shared libraries need `-fPIC`.
- Pin the Zig version; std/build APIs are still moving quickly.

---

## 5. Proposed ABI and ownership model

Do not expose `ast.Node` as a C struct. It has ~67 fields and will change. Use an opaque
document handle plus a serialized AST, with optional accessors.

```c
typedef struct lute_doc lute_doc;

lute_doc *lute_parse(const uint8_t *md, size_t len, const lute_opts *opts);
const uint8_t *lute_doc_ast(lute_doc *doc, size_t *out_len);
void lute_doc_free(lute_doc *doc);

/* optional ergonomic accessors for C hosts */
uint32_t lute_node_count(const lute_doc *doc);
int32_t  lute_node_type(const lute_doc *doc, uint32_t node);
uint32_t lute_node_first_child(const lute_doc *doc, uint32_t node);
uint32_t lute_node_next(const lute_doc *doc, uint32_t node);
const uint8_t *lute_node_data(const lute_doc *doc, uint32_t node, size_t *len);
```

Key design rules:

- **Input ownership.** The Go lexer mutates its input: it appends a trailing newline
  and normalizes CRLF in place. The C/WASM API must copy the input into the document
  arena (or explicitly take ownership). Otherwise AST token slices can dangle.
- **Options ABI.** Only ~10–12 fields are in scope. Use a versioned struct with a
  `size` field plus explicit fields, or setter functions. Do not raw-paste a 52-field
  Go struct across the boundary.
- **Errors.** Return `NULL` and expose `lute_last_error()` (thread-local). A Zig panic
  crossing FFI aborts the host process; all parser paths must return errors instead.
- **Thread safety.** No mutable globals. Parsing should be reentrant. The scoped parser
  does not need the global emoji map or node-ID generator, so this is simpler than the
  full engine.
- **AST format.** Prefer a compact little-endian binary format for production (node
  records, token pool, child indices). Offer JSON as a debug/differential format only.
  If JSON is used, match Go's `encoding/json` semantics exactly: declaration-order
  fields, `omitempty`, `[]byte` as base64, sorted map keys.
- **WASM.** Export `alloc`, `free`, `parse`, `doc_ast`, `doc_free`. Keep the module
  import-free. Use `u32` offsets/lengths; WASM is 32-bit little-endian. JS glue must
  re-create typed-array views after any call that can grow memory.

---

## 6. Porting landmines (scoped)

| Risk | Detail | Mitigation |
|---|---|---|
| **Behavioral parity** | 652 CommonMark examples plus GFM rules and Lute's existing quirks | Differential harness from day 1 |
| **Unicode semantics** | `unicode.IsPunct`, `IsSymbol`, `Quotation_Mark`, `SimpleFold`, `cases.Fold`, `bytes.EqualFold` | Generate tables from Go/Unicode data; test all code points |
| **HTML entity decoding** | Go's `html.UnescapeString` rules (missing semicolons, attribute mode) | Port exact algorithm + generated entity table; differential-test every entity |
| **Link destination encoding** | `html.EncodeDestination` / `DecodeDestination` behavior | Port the existing implementation; test against spec cases |
| **CommonMark HTML blocks / inline HTML** | Lexical tag scanning is required; full HTML parsing is not | Reuse the existing hand-written scanners in `html_block.go` / `inline_html.go` minus Protyle branches |
| **Input mutation** | Lexer rewrites CRLF and appends `\n` | Copy input into the arena; document ownership |
| **UTF-8 edge cases** | Invalid bytes, NUL replacement, rune boundaries | Match Go's `utf8.RuneError` semantics; fuzz |
| **Zig panics** | Safe modes trap on overflow/`unreachable` | Return errors; fuzz; avoid `unreachable` on input |
| **WASM 32-bit `usize`** | Offsets and lengths must fit 32 bits | Use `u32` in the serialized format; check casts |
| **Zig version churn** | 0.17 removed the GPA and changed build APIs | Pin Zig in CI; small std surface |
| **AST contract drift** | Go struct/field changes can desync Zig | Single source of truth + codegen or CI schema check |
| **License** | Mulan PSL v2 is permissive | Retain attribution/license headers |

Notably absent from this scope: JSON document-title decoding, base64, `time`/`rand`
node IDs, regex CSS validation, `net/url`, Kramdown IAL, emoji tables, and the HTML5
parser. Those were the hardest parts of a full-parity port and are now gone.

---

## 7. Test strategy

1. **Differential harness first.** Build the Zig parser as a static library and call it
   from the existing Go test suite via cgo. Emit the AST from both implementations and
   compare semantically (unmarshal both, `reflect.DeepEqual`), not byte-for-byte.
2. **CommonMark/GFM conformance.** Run all 652 `commonmark-spec.json` examples and a
   generated GFM fixture set. Compare **ASTs** first, then HTML as a second check.
3. **Use the existing Go renderer as an oracle.** Rendering is not being ported, but the
   current Go renderer can consume a deserialized Zig AST. Byte-identical HTML on the
   scoped corpus is a strong end-to-end signal.
4. **Fuzzing.** libFuzzer/AFL on the C ABI, and a Go fuzz harness that parses random
   input with both implementations and compares. No panics, no out-of-bounds reads.
5. **Memory checks.** Zig `std.testing.allocator` leak detection, `ReleaseSafe`,
   ASan/Valgrind on the C library, and a multi-threaded stress test.
6. **Performance gates.** Baseline: `BenchmarkParseSpec` ≈ 17 ms, 12.7 MB, 25.8k allocs.
   Suggested gate: ≥1.2× faster parse, and scoped WASM ≤500 KB raw, before proceeding
   past the vertical slice.

---

## 8. Suggested plan

| Phase | Work | Exit criterion |
|---|---|---|
| 0 | Freeze the AST schema; build the Go↔Zig differential harness | Harness runs the 652 spec examples |
| 1 | Port `lex`, `ast` subset, `util` subset, serialization | Lexer/AST match Go on corpus |
| 2 | Port block parser (paragraph, heading, list, blockquote, code, HTML block, table) | Block-level AST/HTML parity |
| 3 | Port inline parser (emphasis, links, code span, autolinks, entities) | 652 CM + GFM cases pass |
| 4 | Differential hardening, fuzzing, performance tuning | Gates in §7 met |
| 5 | C ABI + WASM + JS/C glue + packaging/CI | C sample and Node/browser smoke tests |
| 6 | Docs, versioned header, release artifacts | Publishable library |

**Vertical slice (weeks 1–8):** block paragraphs/headings/lists/fenced code + inline
text/emphasis/strong/code spans/links/autolinks + AST serialization. If that slice
reaches 100% of the 652 CommonMark examples in 6–8 weeks, green-light the rest. If it
stalls on parity, stop and use an existing C parser (see §9).

---

## 9. Alternatives and strategic recommendation

| Option | Cost | WASM size | Notes |
|---|---:|---:|---|
| **Zig scoped port** | 4.5–6.5 engineer-months | expected few hundred KB | Best control, small runtime, Lute-compatible AST |
| **Use `cmark-gfm` / `md4c`** | days–weeks | small | Already implements CM/GFM; different AST; no Lute compatibility |
| **Go `-buildmode=c-shared`** | days | n/a | 4.8 MB measured; Go runtime/GC; cgo deployment pain |
| **Go `wasip1/wasm` + `//go:wasmexport`** | days–weeks | 7.2 MB / 2 MB gz | Already compiles; no rewrite; large |
| **TinyGo → WASM** | weeks | ~1–2 MB | Compatibility risk with `x/text`, `regexp`, `unsafe` |
| **Rust + wasm-bindgen** | 4–6 months | ~0.5–1.5 MB | Mature ecosystem, larger tooling surface |

**Recommendation.**

- If the requirement is “**a** CommonMark/GFM parser callable from C and WASM”, do not
  port Lute. Use `cmark-gfm` or `md4c`; it is dramatically cheaper and already
  spec-compliant. Add Lute-specific behavior only where needed.
- If the requirement is “**Lute’s** CM/GFM parser, with Lute’s AST/quirks, callable from
  C and WASM”, the Zig port is technically sound and the narrowed scope makes it
  practical. Budget ~5–6 engineer-months for production quality.
- If the immediate need is to ship *something* in WASM this quarter, use Go/TinyGo first
  and keep the Zig port as a follow-up. The C ABI and differential harness are reusable
  either way.

---

## 10. Bottom line

- **C library:** feasible and clean. Keep the AST opaque, copy the input, version the
  options, and return errors rather than panicking.
- **WASM library:** strongly feasible and the main technical win. No imports, no Go
  runtime, no GopherJS version constraints, and a much smaller artifact.
- **Cost:** ~7–8k LOC of hand-written Zig plus generated tables; ~4.5–6.5
  engineer-months for production quality, ~6–8 weeks for a decisive vertical slice.
- **Biggest risk:** CommonMark/GFM edge-case parity, not Zig.
- **Biggest strategic question:** whether Lute-specific AST compatibility is actually
  required. If not, an existing C parser is the better buy.
