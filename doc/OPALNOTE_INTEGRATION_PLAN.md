# opal_note integration: source positions and generic extensions

**Status:** **P1–P3 implemented in lutez 0.2.0** (source spans in the AST, wire v2 and
ABI v2). P4–P6 (generic extension engine + opal_note dialect) remain planned. Inputs:
opal_note integration review and the current `lutez` implementation. This document
evaluates the two blockers and proposes a path; §2 is now historical design context.

---

## 0. Summary

Both blockers are feasible. They should ship together as **lutez 0.2** because both need a
wire-format revision and an ABI revision; doing them separately would break consumers twice.

1. **Source positions — feasible, ~3–4 engineer-weeks.** The AST can carry exact spans, but
   they must be *recorded during parsing*, not reconstructed after the fact. Current tokens
   are not reliable input aliases and the wire format drops offsets. The fix is a wire v2
   with per-node spans plus a compact raw↔normalized source map.
2. **Generic extensions — feasible, ~4–6 engineer-weeks.** Do **not** expose arbitrary
   parser callbacks across C/WASM: they are unsafe, hard to version, and impossible to run
   inside freestanding WASM without host imports. Instead add a **data-driven extension
   specification** (block rules, inline delimiter rules, inline prefix rules) plus a generic
   extension node, and implement the five opal_note constructs on top of it (dogfooding).
   This is expressive enough for frontmatter, `#tags`, `$$math$$`, `[[wikilinks]]` and
   Logseq keywords, while keeping CommonMark/GFM parity unchanged when disabled.

Recommended sequence: **positions + wire v2 first**, then the extension engine on top of the
new span infrastructure. Vertical slice for opal_note: positions + frontmatter + tags +
math + wikilinks in ~6–7 weeks; Logseq keywords and polish in the next 2–3 weeks.

---

## 1. Current state (evidence from the codebase)

### 1.1 What exists

| Area | Current behaviour | Consequence |
|---|---|---|
| In-memory `Node` | `tokens: []u8`, links, scoped fields; **no span/offset fields** (`src/ast/node.zig`) | No source ranges anywhere in the tree |
| Block token assembly | `Tree.addLine` → `appendTokens` allocates a **new buffer per append** (`src/parse/tree.zig`) | Block tokens are usually *not* slices into the input, so pointer arithmetic cannot recover offsets |
| Inline parser | `InlineContext` has `tokens`, `pos` only (`src/parse/delimiter.zig`) | Positions are relative to the block token buffer, which itself has no source mapping |
| Text merging | `mergeText` allocates a new buffer and unlinks nodes (`src/parse/inline.zig`) | Adjacent text spans must be unioned before/while merging |
| Token rewrites | entities decode, destinations percent-encode, labels fold, code-span newlines become spaces | Token bytes differ from source bytes; spans must come from the scanner, not from token content |
| Lexer | CRLF→LF in place; NUL→U+FFFD via a replacement buffer; trailing `\n` appended (`src/lex/lexer.zig`) | Normalized offsets ≠ raw offsets; a map is required |
| BOM | not stripped (BOM bytes are content today) | Keep this behaviour for parity unless opal_note requires stripping |
| Wire v1 | 40-byte header, 48-byte node records, no offsets; `input_len = 0`; every token copied to the pool (`src/ast/wire.zig`, `doc/WIRE_FORMAT.md`) | Offsets are unrecoverable after serialization |
| AST schema | closed 62-type whitelist; `NodeType` is a non-exhaustive enum but decoders reject unknown types | No room for adopter nodes |
| Options / ABI | 16-byte versioned `lutez_opts`, 11 boolean flags (`src/abi.zig`) | No way to pass an extension spec |

### 1.2 Why a “position post-pass” is not enough

Matching tokens against the source in document order can appear to work for simple
paragraphs, but it fails on the constructs opal_note needs:

- blockquote/list content is a **concatenation of line remainders** (markers and indentation
  removed), so it is not a contiguous source slice;
- entity, link-destination and label tokens are **rewritten copies**;
- `mergeText` merges adjacent nodes, losing individual boundaries;
- code-span content may have newlines replaced in place;
- container/marker nodes (blockquotes, fences, list items, task markers) have no tokens at
  all.

Therefore spans must be produced by the parser at the moment each construct is recognized.

---

## 2. Source positions

### 2.1 Contract proposal

Introduce a `Span` on every node:

```
src_norm_start, src_norm_end : u32   // offsets into the normalized input
src_raw_start,  src_raw_end  : u32   // offsets into the caller's original bytes
src_flags                    : u8    // 0 = real span, 1 = derived/synthetic
```

- All spans are **byte offsets**, half-open `[start, end)`.
- **Raw offsets are the primary consumer contract** (editors, deep links, task line
  numbers). Normalized offsets are retained for parser diagnostics and token alignment.
- `derived` nodes (e.g. a list’s corrected `Num`, internal markers without source bytes)
  use a zero-width span at the enclosing position and a flag; they never invent text.
- Document root spans `[0, raw_len)`; the synthetic trailing newline is excluded.
- Container spans follow a per-type table (child of this plan) rather than “first child to
  last child”, because markers, trailing blank lines and fences differ by block type. Draft
  rules:
  - paragraph/heading/list item: first source byte of the construct through the last
    non-newline content byte;
  - blockquote: `>` or indentation included; excludes the final newline;
  - fenced code: includes opening and closing fences;
  - HTML block: full raw block including terminating blank line? **decision needed**;
  - link/image/emphasis/strong/strikethrough: includes delimiters;
  - code span: includes backticks; content node excludes markers;
  - entity/escape: raw entity/escape bytes;
  - table cells: trimmed cell content; table includes pipes/rows.
- Line/column and UTF-16 columns are **derived helpers**, not stored per node (LSP/editor
  columns are UTF-16; a C helper and a JS helper are cheaper than 4 more words/node).

### 2.2 Recording spans during parsing

1. **Document source map (lexer + `parseWith`).**
   Build a compact list of change segments while copying/normalizing:
   `{norm_start, raw_start, norm_len, raw_len, kind}` for CRLF→LF, NUL→U+FFFD, and the
   synthetic trailing newline. Unchanged regions are identity. BOM remains untouched in
   0.2 (documented), so no BOM segment is emitted unless we later add stripping.
2. **Absolute line offsets in `Context`.**
   Add `line_norm_start`, `line_raw_start`, `line_no`, and a `block_start_norm/raw` for the
   current construct. The lexer already advances line by line; pass both offsets.
3. **Block spans.**
   Each block start records its span start before consuming markers; each finalize records
   its end (and fixes trim/trailing-newline rules). Marker nodes (heading hashes, blockquote
   `>`, list markers, task markers, fence open/info/close) receive the consumed ranges.
4. **Token provenance for inline parsing.**
   Replace `appendTokens` with `appendTokensAt(node, bytes, norm_src_off)` and keep a
   per-block list of token segments `{tok_off, norm_src_off, len}` (arena only, not on the
   wire). Tab-expanded synthetic spaces map to the tab’s source byte; prefix-stripped line
   remainders map to their own offsets.
5. **Inline spans.**
   `InlineContext` gains a reference to the block’s token-segment map. Every scanner records
   the token-buffer range it consumed; convert with the segment map. For nodes assembled
   from multiple pieces (link text, merged text, autolinks), take the union of constituents.
   Text merging must union spans; do the union before `mergeText` unlinks nodes.
6. **Extension spans.**
   Extension rules receive the same mapping and must set a span; nodes produced without a
   span are rejected in debug builds and marked `derived` in release.

This is instrumentation, not a rewrite: the parser algorithms stay the same, but ~20 files
gain span assignments and the block/inline contexts gain offset bookkeeping.

### 2.3 Wire format v2

Bump `format_version` to **2** and `LUTEZ_ABI_VERSION` to **2** (release as 0.2.0).

- Header stays 40 bytes; `format_version = 2`; the reserved header word becomes `map_len`.
- Node record becomes **56 bytes**:
  ```
  u16 type, u16 flags,
  u32 parent, first_child, last_child, prev, next,
  u32 tok_ref, tok_len,
  u32 src_norm_start, src_norm_end,
  u32 src_raw_start, src_raw_end,
  u32 ext_ref, ext_len
  ```
  The unused `data_ref/data_len` pair from v1 is replaced by the two spans; no data field is
  needed in v2.
- New **source-map section** after the pool (8-byte aligned):
  `u32 count`, then `count × {u32 norm_start, u32 raw_start, u32 norm_len, u32 raw_len, u8 kind}`.
  Consumers binary-search and fall back to identity for gaps.
- Sections: `nodes | extras | input | pool | source_map`. `input_len` stays 0 in v2 (tokens
  are pooled), but is reserved for a future zero-copy mode.
- v1 readers already reject unknown versions; no dual emit. Provide a clear migration note
  and keep the old decoder in the parity harness for one release (test-only).
- New accessors:
  - C: `lutez_node_span(doc, node, uint32_t *raw_start, uint32_t *raw_end)`,
    `lutez_node_span_norm(...)`, `lutez_doc_source_map(...)`,
    `lutez_doc_raw_to_line_col(...)` (optional helper).
  - WASM/JS: `doc.span(i) -> [rawStart, rawEnd]`, `doc.normSpan(i)`,
    `doc.sourceMap()`, plus `doc.utf16Span(i, text)` in glue if needed.
- `lutez_opts` v2 appends `extensions_ptr/size` (see §3.5); `struct_size` keeps v1 callers
  source-compatible.

### 2.4 Tests and gates

- **Invariants (property tests):** spans within `[0, raw_len)`; children within parents;
  siblings non-overlapping in document order; marker nodes within their parent construct;
  derived flag only on zero-width spans.
- **Golden spans:** a checked-in fixture set for representative Markdown (headings, lists,
  quotes, tables, code, links, HTML, entities, escapes, CRLF, NUL, multibyte UTF-8) with
  exact raw/normalized spans; regenerate from the parser with review.
- **Token-origin check:** for nodes whose tokens are unmodified source text, slicing raw
  input by the span and comparing (modulo documented trim rules) must match; transformed
  nodes are checked by type-specific rules.
- **Editor scenarios:** block ranges, task marker line numbers, deep links, selection →
  node lookup, CRLF documents, LF documents, non-ASCII preceding bytes.
- **Parity:** spans are excluded from the existing canonical AST dump; CM 652/652 and GFM
  672/672 remain green. Add a span-aware dump for extension/position tests.
- **Performance:** parse benchmark gate ≤ 10% regression; wire size ≤ +20% on the spec
  corpus; WASM size check.
- **Fuzz:** random bytes; span invariants must hold even for malformed Markdown.

### 2.5 Effort

| Work | Estimate |
|---|---:|
| Source map + lexer/context offsets | 4–5 d |
| Block spans + marker/container rules | 5–7 d |
| Token-segment map + inline spans + merge union | 5–7 d |
| Wire v2 + decoder/tests + source map | 3–4 d |
| C/WASM/JS accessors + docs + migration | 2–3 d |
| Golden/editor/fuzz/perf hardening | 4–5 d |
| **Total** | **~3.5–4.5 eng-weeks** |

---

## 3. Generic extension mechanism

### 3.1 What opal_note needs

| Construct | Where | Why a post-pass is insufficient |
|---|---|---|
| Frontmatter (`--- … ---`) | block, document start | Changes document structure; must be removed from the body and exposed as a node before parsing |
| Logseq keywords (`key:: value`) | block, line start | Same: line becomes a structured node, not paragraph text |
| `$$math$$` / `$math$` | inline + block | Must respect code spans, escapes, HTML and link destinations; `$` is not currently a text marker |
| `[[wikilinks]]` | inline | Conflicts with CommonMark `[` bracket stack; requires precedence before link parsing |
| `#tag` | inline prefix | Cannot be done safely as a text post-pass: text is merged/split, `#` occurs in headings/URLs, and code spans/links/HTML must be excluded. Boundary rules need the parser’s before/after rune context |

Recommendation: **parser-level, data-driven rules** for all five; no arbitrary callbacks.

### 3.2 Extension node

- New whitelisted type `NodeExtension` (**500**), with an extras payload:
  ```
  u32 kind          // stable registry id
  u32 flags
  bytes payload     // raw source bytes (or rule-defined key/value encoding)
  ```
- Built-in kind ids: `1 math`, `2 wikilink`, `3 tag`, `4 frontmatter`, `5 logseq-keyword`
  (reserved 1–999); adopters use `1000+`.
- Unknown kinds are preserved by the wire decoder and JSON/JS; the core never interprets
  them.
- Extension nodes are **leaves by default**. They receive spans like any other node. An
  optional `inline_children` mode (future) can run the core inline parser inside a payload
  with an offset base; not needed for math/wikilinks/tags.
- AST schema, `check-schema`, JSON dump, C/WASM accessors (`lutez_node_ext_kind`,
  `lutez_node_ext_payload`) and the JS decoder are extended in the same change.

### 3.3 Rule language (data, not code)

A versioned binary spec (TLV/struct array; no JSON parser in the core):

- **`block_delimited`** — for frontmatter and block math:
  `start` marker (line-anchored), `end` marker, `allow_indent`, `at_document_start`,
  `payload_includes_delimiters`, `kind`, priority.
- **`block_prefix`** — for Logseq keywords:
  line-start regex-free matcher (ASCII key charset + `::`), value = rest of line,
  optional key whitelist, `kind`.
- **`inline_delimited`** — for math and wikilinks:
  `open`, `close`, `escape` (default `\`), `allow_newline`, `max_span`, `boundary_before`,
  `boundary_after`, `nesting: none`, `kind`, priority.
- **`inline_prefix`** — for tags:
  `prefix` (`#`), `allowed_chars` (Unicode letters/digits/`_-/` configurable),
  `min_len`, `boundary_before` (not alnum/underscore), `boundary_after`
  (whitespace/punctuation), `kind`, priority.
- Rules can declare **trigger bytes** so the inline text scanner stops there; otherwise the
  core would swallow `#`, `$` or `[[` as text.
- **Precedence:** longest match wins; ties by priority; extension rules run before core
  inline handling for their trigger positions, but never inside code spans, raw HTML, link
  destinations/titles, or after a backslash escape.
- **Limits:** max payload bytes, max rules, max nesting = 0, no recursion, no allocation
  beyond the document arena. Reject malformed specs with `LUTEZ_ERR_INVALID_EXTENSIONS`.
- **Default: no rules.** With an empty spec, byte-for-byte AST parity is unchanged.

### 3.4 Pipeline insertion points

```
raw bytes
  → normalize + source map
  → pre-block scan (block_delimited at doc start: frontmatter; line prefixes: Logseq)
  → core block parser (unchanged; extension nodes are block leaves)
  → core inline parser
       ├─ at extension trigger bytes: try extension rules (longest match, priority)
       └─ otherwise existing CommonMark/GFM handling
  → merge text (union spans)
  → post-pass: none in core
  → wire v2
```

- Frontmatter is split before block parsing; its raw payload and span are retained.
- Logseq keyword lines are recognized by a block rule; they do not interrupt normal
  paragraphs unless configured.
- Inline rules are consulted from `parseInline` before the core switch when the current
  byte is a declared trigger.
- **No AST rewrite/post-pass in the core**: consumers can rewrite their decoded tree (JS
  and C-side) if they need target normalization; the wire stays immutable.

### 3.5 ABI

- `lutez_opts` v2 appends `extensions_ptr`/`extensions_len` and `wire_version_request`
  (0 = default v2), guarded by `struct_size`.
- The spec is a packed binary blob owned by the caller for the duration of `lutez_parse`;
  it is copied/validated into the document arena.
- JS glue accepts a plain object and serializes it (`Lutez.parse(md, { extensions: [...] })`).
- A tiny C builder (`lutez_ext_builder_*`) and a JS helper keep the binary format usable;
  both are versioned.
- Optional convenience flags (not a substitute for the spec): `frontmatter: true`,
  `math: true`, `wikilinks: true`, `tags: true`, `logseqKeywords: true`, which expand to the
  built-in rules.

### 3.6 Why not callbacks

- **WASM:** host callbacks require imports, violating the zero-import guarantee; code size
  and JS↔WASM call overhead explode.
- **C:** callbacks inside the parser would need longjmp/error handling, reentrancy and
  panic containment; ABI/versioning becomes far harder than a data spec.
- **Parity/security:** arbitrary code can mutate parser state, allocate without limits, or
  produce invalid spans. Data rules are testable, fuzzable and deterministic.
- **Escape hatch:** a future Zig-native (source-level) plugin API can expose the same rule
  engine plus custom scanners for C/Zig hosts that accept the ABI risk. Not in 0.2.

### 3.7 Built-in rules for opal_note

| Rule | Kind | Default | Details |
|---|---|---:|---|
| Frontmatter | 4 | off | only at document start; `---` … `---`; payload raw; delimiters in span, excluded from payload; max size limit |
| Math | 1 | off | `$$…$$`, `$…$`; no newline for inline; block `$$` accepted; escapes; not in code/HTML; payload raw |
| Wikilink | 2 | off | `[[…]]`; no nested `[[`; payload raw; optional `target|alias` split exposed as separate payload fields in a future payload revision; span includes brackets |
| Tag | 3 | off | `#` + Unicode alnum/`_-/`; boundary before not alnum/underscore; not after `\`; excludes code/HTML/link content; span includes `#` |
| Logseq keyword | 5 | off | `^[A-Za-z][\w-]*::\s*`; optional key whitelist; payload key + value; span includes key and `::` |

Each rule is defined *in the spec*, not hard-coded, so adopters can tweak chars/delimiters
without a fork. The five built-ins are compiled-in presets.

### 3.8 Tests and effort

- **Dialect corpus** (~100 curated cases): frontmatter at EOF/with CRLF/no closing; math
  inside code/links/emphasis; wikilinks vs `[[]]`; tags vs headings/URLs/code/escapes;
  Logseq keys; precedence between rules; unknown kinds preserved.
- **No-regression gate:** empty spec → CM 652/652, GFM 672/672 unchanged.
- **Span tests:** every extension node has a raw span; payload equals raw slice for raw
  payload rules (modulo chosen delimiters).
- **Fuzz:** mutated specs and inputs; reject oversized/looping specs; no panic.
- **ABI/JS:** C sample + Node demo + WASM size; spec round-trip.

| Work | Estimate |
|---|---:|
| Extension node + wire/AST/ABI plumbing | 4–5 d |
| Spec codec + validation + C/JS builders | 4–5 d |
| Block rule engine (delimited + prefix) | 4–5 d |
| Inline rule engine (trigger/precedence/boundaries) | 6–8 d |
| Five built-ins + dialect corpus | 6–8 d |
| ABI/JS/demo/docs/fuzz | 4–5 d |
| **Total** | **~5–6 eng-weeks** |

---

## 4. Combined plan (0.2.0)

### Phase P1 — position contract and wire v2 (week 1)

- Freeze span semantics per node type (decision with opal_note).
- Draft wire v2 + source-map format; update `AST_SCHEMA`/`WIRE_FORMAT`.
- Bump `format_version=2`, `LUTEZ_ABI_VERSION=2`, version `0.2.0`.
- Add golden span fixtures and span dump (test-only).

### Phase P2 — block spans and token provenance (weeks 2–3)

- Lexer source map; absolute line offsets; block start/end capture; marker spans.
- `appendTokensAt` + per-block token segment maps.
- Block-level span tests (quotes, nested lists, tables, code, HTML, CRLF/NUL).

### Phase P3 — inline spans and accessors (weeks 3–4)

- Inline context base mapping; spans for text, emphasis, links, images, code spans,
  entities, autolinks, HTML, breaks, table cells; merge union.
- Wire v2 encoder/decoder + C/WASM/JS accessors; migration notes.
- Editor/deep-link acceptance tests; perf/size gates.

**Milestone P (opal_note unblocked for positions):** exact spans for all scoped nodes,
C/WASM/JS accessors, 652+672 parity unchanged, ≤10% parse regression.

### Phase P4 — extension infrastructure (weeks 5–6)

- `NodeExtension` (500), kind registry, payload, whitelist/JSON/accessors.
- Binary spec codec + validators + C/JS builders; options v2 plumbing.
- Empty-spec regression gate.

### Phase P5 — rule engines (weeks 6–7)

- Block delimited/prefix rules; inline delimited/prefix rules; triggers/precedence/boundary
  checks; span assignment; safety limits.

### Phase P6 — built-ins and opal_note corpus (weeks 7–8)

- Frontmatter, math, wikilinks, tags, Logseq keywords as spec presets.
- ~100-case dialect corpus; C/JS demo; docs (`doc/EXTENSIONS.md`, `doc/POSITIONS.md`).
- Release 0.2.0 (wire v2 / ABI v2), update parity harness to decode both versions.

**Milestone E (opal_note unblocked for dialect):** all five constructs parsed into extension
nodes with spans, old corpora unchanged with empty spec.

---

## 5. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Token provenance is more fragmented than expected (tab expansion, prefix stripping, merged text) | Spans wrong/missing | Per-block token segment map; assert every node span in debug; golden + editor tests |
| Span semantics ambiguity (include markers/newlines/blank lines) | Editor jumps off by one | Freeze per-type rules before coding; fixtures per type; opal_note sign-off |
| Raw/normalized map bugs (CRLF, NUL, trailing LF) | Offsets drift | Dedicated fixtures; property test `map(map⁻¹(x)) == x` for unchanged bytes; fuzz |
| Wire v2/ABI break | Consumer migration | 0.2.0 release note + migration guide; keep v1 decoder in test harness for parity; single coordinated bump |
| Extension precedence conflicts with CommonMark | Regressions | Empty spec gate; extension rules only on declared triggers; corpus precedence tests; fuzz |
| Data rules are not expressive enough later | Need native plugins | Escape hatch: Zig-native plugin API in a later release; consumers can post-process decoded trees |
| Payload/rule DoS | Hangs/memory | Hard limits (rules, payload, span), linear scans, no recursion; fuzz malformed specs |
| Performance | Parse regression | Bench gate; spans are stored, not recomputed; source map is small; ReleaseFast measurements |
| Scope creep into full dialect support | Slippage | Keep built-ins to the five constructs; everything else via specs/post-processing |

---

## 6. Decisions needed from opal_note

1. **Offset units.** Raw UTF-8 byte offsets as the contract, with derived line/column and
   UTF-16 helpers? (Editors often index UTF-16; deep links usually bytes.)
2. **Span semantics.** Include construct markers (`#`, `**`, `[](`, fences)? Include/exclude
   trailing newlines and blank lines for blocks? (Proposed rules in §2.1.)
3. **Container spans.** Should a list item’s span include nested children (yes, proposal) and
   trailing blank lines (no)?
4. **Frontmatter shape.** Payload includes delimiters or not; expose the parsed YAML later or
   keep raw bytes?
5. **Tag alphabet.** Unicode letters/digits + `_-/`? Case handling? Allow at line start?
6. **Math syntax.** `$…$` and `$$…$$` both inline? Block `$$`? Escapes/newlines?
7. **Wikilink payload.** Raw `[[…]]` payload, or split `target`/`alias` in the node?
8. **Logseq keywords.** Specific key whitelist or any `key::`?
9. **Compatibility.** Can opal_note move to wire v2/ABI v2, or does it need a v1 compatibility
   mode for the transition?
10. **Extension ownership.** Per-document spec supplied by the host, or a global profile
    configured at process/library start?

---

## 7. Recommendation

- **Yes to source positions**, implemented in the parser and exposed in wire v2 with raw +
  normalized spans and a source map. Do not ship a heuristic post-pass.
- **Yes to generic extensions**, but as **data-driven rules**, not callbacks. Implement
  `NodeExtension` + a small rule language and ship the five opal_note constructs as presets.
- Ship both in **0.2.0** (one wire/ABI break), keep CommonMark/GFM parity locked behind the
  existing corpora, and treat opal_note’s dialect as a second, opt-in corpus.
- Start with P1–P3 (positions) because the extension engine depends on the span/mapping
  infrastructure; give opal_note an early access build once P3 lands.
