# Extension engine — research and recommended design

**Status:** implemented in **lutez 0.3.0** (types 500/501, five presets, preset ABI).
The public binary-spec builder (adopter-defined rules) remains planned for 0.4. This
document records the design and the agreed decisions; the original gap (type ≥ 500
rejected, no preset ABI) is closed for presets.

**Goal:** let an embedder (opal_note first) opt into dialect constructs — frontmatter,
`#tags`, `$…$`/`$$…$$` math, `[[wikilinks]]`, Logseq `key:: value` — as first-class AST
nodes with source spans, without putting arbitrary callbacks into the C/WASM parser and
without changing CommonMark/GFM output when extensions are off.

---

## 1. Requirements

| # | Requirement | Notes |
|---:|---|---|
| R1 | Extensions are **opt-in per parse** | Empty/default = byte-identical scoped CM/GFM AST (652 + 672 corpora) |
| R2 | Extension results are **AST nodes** | Stable type, kind, payload, source spans; editors need ranges |
| R3 | Configuration works from **C, WASM and JS** | No callbacks required inside the parser; WASM stays import-free |
| R4 | Deterministic, bounded, safe | No recursion through host code; payload/rule/span limits; fuzzable |
| R5 | Generic enough for future constructs | Not five hard-coded switches buried in the parser |
| R6 | Stable ABI/version story | Existing 0.2 consumers keep working; new functions are additive |
| R7 | No CommonMark regressions | Extension triggers cannot fire inside code spans/blocks, HTML, autolinks, destinations, or escapes |
| R8 | Span correctness | Every extension node carries raw + normalized spans like core nodes |

Non-goals: arbitrary host code inside the parser, rendering of extension nodes, parsing
YAML/markdown inside payloads, nested inline parsing inside extension payloads (phase 1),
and changing the scope of `lutez_parse` (the default entry point).

---

## 2. Why the current gaps exist

- `NodeType` is non-exhaustive, but `types.nodeTypeFromInt` returns `null` for anything
  outside the 62-type whitelist; `wire.decode`, the C view, the Go decoder and the JS
  decoder all reject it (`src/types.zig`, `src/ast/wire.zig`, `doc/View`).
- `doc/AST_SCHEMA.md` is a closed whitelist; `check-schema` enforces it.
- `lutez_opts` is exactly 16 bytes and fully used (`strip_bom` took the last byte), so
  there is no room for a spec pointer. Pointers are also 32-bit in WASM and 64-bit in
  native C, so a shared options struct cannot carry one.
- The parser has no hook points: block starts are a fixed function array; inline dispatch
  is a `switch` on bytes; `parseText` stops only at `lex.isMarker`. `$` and `#` are not
  inline markers today, and `[[` falls into the core bracket/link path.
- The fast path in `incorporateLine` skips block starts unless the first non-space byte is
  in a hard-coded set — a Logseq keyword (`key::`) starts with a letter and would never
  reach a new block rule.
- GFM extended autolinks run as a post-pass over text nodes; extension nodes are leaves,
  so they must not “hide” text that GFM should link, and tag rules must reject URL
  fragments (`https://x/#tag`).

---

## 3. Design space

| Option | Expressiveness | C/WASM safety | Effort | Verdict |
|---|---|---|---|---|
| A. Five hard-coded flags, direct parser branches | Exactly the dialect | High | ~3 w | Gets opal_note unblocked, but not a mechanism; future adopts need core changes. Reject as the only solution |
| B. Native Zig vtable / host callbacks | Unlimited | **Low**: WASM imports, panic/lifetime/ABI hazards | 4–6 w | Reject for public C/WASM; possible internal-only future |
| C. Pre/post-processing outside the parser | Limited | High | 1–2 w | Frontmatter/keywords okay; inline unsafe for tags/math across emphasis, links, code. Reject as the mechanism |
| D. Data-driven rule spec + generic extension node | Four rule families cover the dialect and most future lexical constructs | High: no host code, deterministic | 5–7 w | **Recommended** |
| E. Full pluggable parser (token stream + external AST builder) | Unlimited | Medium | 3–4 months | Overkill; breaks Lute AST shape and parity investment |

Recommendation: **D**, with the opal_note dialect (six kinds under five presets)
implemented on the same rule engine (dogfooding). Keep callbacks out of the public parser.

---

## 4. Recommended architecture

```
spec bytes (binary v1)
   │ validate + compile (bounded)
   ▼
ExtensionSet ──────────────┐
   │                       │
   ▼                       ▼
block phase              inline phase
 - document-start        - trigger bitset in parseText
   delimited rules        - try rules before core switch
   (frontmatter)          - delimited rules: math / wikilinks
 - line-start prefix       - prefix rules: tags
   rules (Logseq)
   │                       │
   └──────────┬────────────┘
              ▼
       NodeExtension (type 500)
       kind + raw payload + source span
```

### 4.1 Extension node

- Add **two** whitelisted types sharing one payload/kind registry:
  - **`NodeBlockExtension` = 500** — frontmatter, Logseq keyword lines (block leaves),
  - **`NodeInlineExtension` = 501** — math, wikilinks, tags (inline leaves).

  Two types keep `isBlock`/`CanContain`/`acceptLines` unambiguous. Using a single type 500
  with a “block” flag was considered; it would force core predicates to consult extension
  metadata, which is more error-prone for a one-time schema cost. Both types use the same
  extras layout and `ext_kind` registry, so consumers handle them with one code path.
- Payload convention: the node's **tokens are the raw payload**; the source span covers the
  full construct, including delimiters/prefix. This reuses the existing token pool,
  `lutez_node_data`, JS `wire.mjs` decoding, and span machinery.
- Extras blob for both extension types:
  ```
  u32 kind
  u8  payload_version (= 1)
  u8  flags            // e.g. delimiter-excluded, display math
  u16 reserved
  ```
  Payload bytes are not duplicated: `tokens` carries them.
- Kind registry (public ABI, freeze in schema):
  | kind | construct | payload |
  |---:|---|---|
  | 1 | inline math | content without `$`/`$$` delimiters |
  | 2 | wikilink | content without `[[` `]]` (e.g. `target|alias`) |
  | 3 | tag | name without `#` |
  | 4 | frontmatter | YAML body without the `---` fences |
  | 5 | Logseq property | `key:: value` line content (consumers split at `::`) |
  | 6 | Obsidian block ID | trailing `^key` marker content (key only) |
  | 1000+ | adopter-defined (0.4+) | raw payload |
- Built-in payloads stay **raw text**: no YAML parser, no wikilink target/alias split in
  core, no tag normalization. JS/C helpers can offer convenience parsers later. This keeps
  the engine generic and the wire stable.
- Extension nodes are **leaves** in phase 1; their payload is not inline-parsed. This is
  correct for math/wikilinks/tags and avoids recursion limits. A future flag can opt into
  inline children with an offset base.
- Every extension node gets a full source span (raw + normalized). Delimiters are included
  in the span; payload excludes them by rule flag.

### 4.2 Wire and ABI impact

- **Wire layout stays v2**: no header/record change. A buffer with `has_extensions = 0`
  remains readable by 0.2 decoders; `has_extensions = 1` requires a 0.3-capable decoder. `NodeBlockExtension` (500) and
  `NodeInlineExtension` (501) are added to the schema; an optional header flag bit
  (`has_extensions`) lets readers fail fast when they encounter an extension AST. Old 0.2
  decoders still reject types ≥ 500 — that is expected:
  parsing with extensions is a new capability, and decoders must be updated to use it.
- **C ABI 3** (0.3.0). `lutez_opts` stays 16 bytes. A separate entry point carries the spec:

  ```c
  /* 0.3: presets only */
  lutez_doc *lutez_parse_presets(const uint8_t *md, size_t len,
                                 const lutez_opts *opts, uint32_t preset_mask);

  enum {
    LUTEZ_EXT_FRONTMATTER      = 1u << 0,
    LUTEZ_EXT_MATH             = 1u << 1,  // inline + fenced block math
    LUTEZ_EXT_WIKILINKS        = 1u << 2,
    LUTEZ_EXT_TAGS             = 1u << 3,
    LUTEZ_EXT_OUTLINER_BLOCKS  = 1u << 4   // Logseq key:: + Obsidian ^block-id
  };

  /* 0.4: editable rules (same internal engine) */
  lutez_doc *lutez_parse_ext(const uint8_t *md, size_t len,
                             const lutez_opts *opts,
                             const uint8_t *spec, size_t spec_len);
  ```
  `lutez_parse` and `lutez_parse_presets` with an empty mask are equivalent and
  byte-identical to 0.2 output.
- New accessors (C/WASM):
  ```c
  int32_t  lutez_node_ext_kind(const lutez_doc *doc, uint32_t node); // -1 if not an extension
  uint32_t lutez_node_ext_flags(const lutez_doc *doc, uint32_t node);
  /* payload is lutez_node_data() */
  ```
- Spec as a **target-independent binary blob** (little-endian TLV), built by:
  - a small C builder (`lutez_ext_builder_*`) shipped in `include/lutez.h` or a companion
    header, and
  - the JS glue (`Lutez.parse(md, opts, { extensions: [...] })` / preset object),
  - or embedded byte arrays generated once.
  Rationale: a struct with native pointers cannot be shared between 64-bit C and
  wasm32; a binary blob can. The core copies and validates the spec into the document
  arena.
- Zig API: `parseWithExtensions(allocator, input, options, ExtensionSet)`, with
  `ExtensionSet.compile(spec)` and preset constructors.

### 4.3 Spec format (v1, binary)

```
magic "LUTEXT1" | u16 version=1 | u16 rule_count | reserved u32
repeat rule_count:
  u16 rule_type   // 1 block_delimited, 2 block_prefix, 3 inline_delimited, 4 inline_prefix
  u16 flags
  i16 priority
  u32 kind
  u32 open_len   + open bytes
  u32 close_len  + close bytes
  u32 pattern_len + pattern bytes   // for prefix rules: allowed char classes / key shape
  u32 limits      // max payload, boundary classes, flags
```

Rules are small and bounded: max 32 rules, 64 KiB spec, 1 MiB payload per node.
Strings/bytes are length-prefixed; no NUL terminators; no JSON/parser dependency.

Rule families (phase 1):

1. **`block_delimited`** (frontmatter; optional block math):
   `start_line` marker, `end_line` marker, `at_document_start`, `consume_unclosed`,
   `include_delimiters`, `payload_excludes_delimiters`, kind, priority.
2. **`block_prefix`** (Logseq):
   line starts with a key matching `[A-Za-z][A-Za-z0-9_-]*` followed by `::`,
   optional key whitelist, payload = rest of line, kind.
3. **`inline_delimited`** (math, wikilinks):
   `open`, `close`, `escape` (default `\`), `allow_newline` (false), `max_span`,
   `trim`, boundary classes before/after, kind, priority.
4. **`inline_prefix`** (tags):
   `prefix` (`#`), allowed-character classes (default Unicode letters/digits `_-/`),
   `min_len`, `exclude_all_digits`, boundary classes before/after, kind, priority.

Boundary classes encode a compact predicate: whitespace, punctuation, ASCII
letter/digit, Unicode letter/digit, or explicit sets. The matcher uses the same Unicode
tables as the parser.

### 4.4 Parser insertion points

**Block phase**

- `parseBlocks`: if a document-start rule exists, run a preamble scan before the normal
  line loop. It consumes raw lines from the lexer, produces one extension block at root,
  and records the end offset; the body parses normally. If the closing delimiter is absent
  by EOF: default **fallback to normal Markdown** (`consume_unclosed=false`) so a stray
  `---` cannot swallow a document.
- `incorporateLine`: when extensions are active, run `block_prefix` rules at the current
  line position **before** the hard-coded `maybeMarker` fast path and before core block
  starts. The rule sees the line after the matched container prefix, so Logseq keywords
  can appear in blockquotes/list items if the rule allows it. On match: consume the line,
  append a leaf `NodeExtension` to the current tip/container, set the span, return.
- Extension blocks never accept continuation lines (except document-start delimited
  blocks); this keeps the block state machine unchanged.

**Inline phase**

- Add a `trigger[256]` bitset to `InlineContext` when extensions are active. `parseText`
  stops at core markers **or** extension triggers.
- At the top of `parseInline`, for a trigger byte, try rules in priority order before the
  core `switch`. On match: create `NodeExtension`, set span from the existing token map,
  advance `ctx.pos`, continue.
- If no rule matches a trigger, consume **one byte as text** (or let `parseText` skip the
  trigger) so the loop always progresses; `mergeText` coalesces the one-byte nodes.
- `[[` is tried before the core `[` handler; `$`/`#` are triggers only when rules exist.
  On a failed match:
  - if the trigger is a core marker (`[`), fall through to the core `switch` (so
    `[[unclosed` still follows CommonMark bracket handling),
  - otherwise consume the trigger byte as text (so `#` followed by a space cannot loop).
  Escaped characters are already consumed by the backslash handler, so `\#tag` is safe.
- Extension rules do not run inside code spans/blocks (their payloads are consumed
  atomically by core scanners), HTML nodes, autolinks, or link destinations. Link **text**
  is parsed by the inline loop; rules can opt out of link-text/image-alt contexts.
- GFM extended autolinks remain a post-pass over text nodes. Extension nodes are opaque;
  tag boundary classes (e.g. reject `#` after `/` `.` `:`) prevent URL fragments from
  being split. Tests must cover `https://x/#tag`, `www.x/y#tag`, and markdown links.
- Inline math vs emphasis: the extension consumes `$…$` as a leaf before `*` can be
  interpreted inside it. Wikilinks consume `[[…]]` before the bracket stack. Tags consume
  `#…` before text. This is the reason post-pass rewriting is not sufficient.

### 4.5 Presets

The built-ins are **presets**, not special cases in the parser:

| Preset | Rule | Defaults |
|---|---|---|
| Frontmatter | `block_delimited` | only at document start; `---` … `---`; payload excludes fences; unclosed falls back; span includes fences |
| Logseq property | `block_prefix` | `^[A-Za-z][A-Za-z0-9_-]*::\s*`; applies at block start (document/blockquote/list item); payload = rest of line; span includes key/`::` |
| Obsidian block ID | `inline_prefix` + `end_of_block` | trailing ` ^key` (`[A-Za-z0-9-]+`) at the end of a paragraph/heading/list-item block; payload = key; span includes `^`; preceding space excluded |
| Math (inline) | `inline_delimited` | `$…$` and `$$…$$` on one line; no newline; opening `$` not followed by space; closing `$` not preceded by space; escape `\`; payload excludes delimiters |
| Math (block) | `block_delimited` | a line containing only `$$` opens, the next line containing only `$$` closes; applies inside containers; payload raw between fences; span includes fences |
| Wikilink | `inline_delimited` | `[[…]]`; no nested `[[`; no newline; payload excludes brackets; `target|alias` left raw |
| Tag | `inline_prefix` | `#` + Unicode letter/digit/`_-/`; min 1; not all digits; before not letter/digit/`_` or URL-ish `/.:`; payload excludes `#` |

Preset mapping:

| Preset bit | Kinds/rules |
|---|---|
| `LUTEZ_EXT_FRONTMATTER` | kind 4, document-start block |
| `LUTEZ_EXT_MATH` | kind 1, inline `$…$`/`$$…$$` + fenced `$$` block |
| `LUTEZ_EXT_WIKILINKS` | kind 2, inline `[[…]]` |
| `LUTEZ_EXT_TAGS` | kind 3, inline `#tag` |
| `LUTEZ_EXT_OUTLINER_BLOCKS` | kind 5 `key::` + kind 6 trailing `^block-id` |

`LUTEZ_EXT_*` preset mask / JS `{ presets: ["opal-note"] }` expands to these rules.
0.3 ships presets only; the public binary-spec builder is deferred to 0.4 (the internal
rule engine is shared, so the split is API-only).

### 4.6 Scope change note

This deliberately brings dialect constructs that were excluded in `PLAN.md` §1.2
(math, tags, wikilinks, frontmatter, Logseq keywords) into scope **as optional extension
nodes**, without renderers or YAML parsing. Update the scope fence when the feature is
accepted: core CM/GFM remains unchanged; extension nodes are opt-in.

---

## 5. Compatibility and versioning

| Artifact | Change |
|---|---|
| Zig library version | 0.3.0 |
| C ABI | **3** — additive functions/accessors; `lutez_opts` stays 16 bytes |
| Wire format | **stays v2** layout; adds `NodeBlockExtension`/`NodeInlineExtension` (500/501) and an optional `has_extensions` header flag; old decoders must be updated to read extension ASTs |
| `lutez_parse` | unchanged, no extensions |
| `lutez_parse_presets` | new entry point (0.3); `lutez_parse_ext` and spec builder in 0.4 |
| JS `Lutez.parse` | third optional `extensions` argument; `doc.extension(node)` accessor |
| Go parity decoder | accepts 500 and exposes kind/payload for tests |
| AST schema | v2: add block/inline extension types, kind registry, payload/flags, span rules |
| CM/GFM corpora | unchanged; no-extension gate must stay 652/652 + 672/672 |

Why not bump the wire layout: no byte layout changes are needed; the only change is a new
node type and a header capability bit. Consumers that never opt in see identical bytes.
Why bump the C ABI: new functions/accessors are additive but older headers cannot declare
or link them; ABI 3 makes the capability explicit. (Alternative considered: `format_version`
3 for every AST — rejected as unnecessary churn for non-extension users.)

---

## 6. Testing

1. **No-extension gate**: preset mask 0 produces byte-identical AST for the
   existing 652 + 672 corpora.
2. **Extension corpus** (~150 hand-written cases): each construct, boundaries, escapes,
   code spans/blocks, HTML, links/images, emphasis interactions, URL fragments, empty
   frontmatter, unclosed frontmatter, frontmatter-only documents, CRLF/BOM/NUL, multibyte
   tags, `$$` vs `$`, nested brackets, priority conflicts.
3. **Span invariants** for extension nodes and their surrounding core nodes (reuse the
   positions invariant suite).
4. **ABI/decoder roundtrips**: C, WASM, JS, Go; kind/payload preserved; derived/spans.
5. **Fuzz**: mutated specs (oversized, unknown rule types, truncated strings) and inputs;
   no panic/OOB/hang; limits enforced.
6. **Performance**: no-extension benchmark unchanged (≤2%); preset kitchen-sink benchmark
   recorded.
7. **Editor scenarios**: tag/math/wikilink ranges, frontmatter block range, Logseq line
   numbers, deep links; CRLF/BOM raw offsets.
8. **Cross-check with a reference scanner** (Go/Python) for the five presets (six kinds)
   against a hand-written dialect fixture set; no upstream oracle exists for these
   constructs.

---

## 7. Effort and sequencing

| Phase | Work | Estimate |
|---|---|---:|
| E0 | Freeze schema: block/inline extension types, kind registry (six kinds), five-preset mask, wire flags, scope note | 3–4 d |
| E1 | Wire/ABI/JS/Go plumbing: types 500/501, ext kind accessors, `lutez_parse_presets`, `has_extensions`, empty-mask no-op | 5–6 d |
| E2 | Internal rule engine + preset rule tables + validation/limits | 4–5 d |
| E3 | Block rules: frontmatter (`---`/`...`, EOF), Logseq `key::`, fenced `$$` math; container contexts + spans | 4–5 d |
| E4 | Inline rules: `$…$`/`$$…$$`, `[[…]]`, `#tag`, trailing `^block-id`; triggers, boundaries, contexts + spans | 7–9 d |
| E5 | Five presets (six kinds) + extension corpus + C/JS demos | 6–8 d |
| E6 | Docs, fuzz, perf, release 0.3 | 4–5 d |
| **Total** | | **~6–7 eng-weeks** |

Vertical slice for opal_note: E0–E4 + frontmatter, Logseq, tags, inline math in **3–4
weeks**; wikilinks, Obsidian block IDs and block math complete 0.3. 0.4 adds the public
binary-spec builder (no AST/ABI change).

Phase 0.4 (after 0.3): spec compiler + C/JS builders + adopter-defined kinds (est.
1.5–2 weeks), reusing E2–E4.

---

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Trigger bytes interact with GFM autolinks/emphasis/links | Wrong AST or lost links | Extension rules run only on declared triggers; boundary classes; dedicated URL/emphasis corpus; no post-pass rewriting |
| Parse doesn't progress on a failed trigger | Infinite loop | fall through to core markers, otherwise consume one text byte; fuzz |
| Frontmatter swallowing a document | Data loss | Unclosed consumes to EOF by decision; explicit frontmatter-only/unclosed tests; span/payload checks |
| Preset-only 0.3 is too narrow | Adopter needs custom rules | Internal engine is rule-driven; 0.4 exposes the spec builder without AST/ABI changes |
| Spec complexity / support burden | Maintenance | Only four rule families; presets are ordinary rules; limits; JSON not embedded |
| ABI/wire confusion | Consumer breakage | ABI 3, wire layout unchanged, `has_extensions` flag, migration guide, no-extension gate |
| Payload conventions diverge between consumers | Interop bugs | Freeze kind registry and payload (raw) conventions in `AST_SCHEMA.md` |
| Performance regression | Parse latency | Disabled path is a single null check/trigger bitset; bench gate |

---

## 9. Decisions (agreed) and remaining clarifications

Agreed:

1. **Frontmatter** — opening `---`; closing accepts **both `---` and `...`**; an unclosed
   frontmatter **consumes to EOF**; fences are excluded from the payload; the node span
   includes the fences. Opening must be the first line (after a stripped BOM), a closing
   line may have trailing spaces/tabs, and the payload is the raw text between the fence
   lines (including body newlines).
2. **Logseq + Obsidian block syntax** — support Logseq property lines `key:: value`
   (block extension kind 5) **and** Obsidian block IDs `^key` (inline extension kind 6,
   trailing marker at the end of a paragraph/heading/list-item block, key
   `[A-Za-z0-9-]+`).
3. **Extension contexts** — inline rules run in all inline contexts by default: paragraphs,
   headings, table cells, link text, image alt, emphasis/strong/strikethrough content.
   They never run in code spans/blocks, inline/block HTML, autolinks, link
   destinations/titles, or after a backslash escape. Per-rule flags can opt out of link
   text/image alt/heading contexts later.
4. **Math in phase 1** — yes. Inline `$…$` and display `$$…$$` on one line, plus a fenced
   `$$` block form (a line containing only `$$` opens; the next such line closes; works
   inside containers). Payload excludes delimiters.
5. **Wikilink payload** — raw content between `[[` and `]]`; `target|alias` split is left
   to the consumer.
6. **Payload** — raw bytes only, no TLV fields in 0.3. Kind-specific conventions are
   documented; consumers split `::`, `|`, YAML, etc.
7. **Scope of 0.3** — the five presets first: frontmatter, math, wikilink, tag, and
   outliner blocks (Logseq `key::` + Obsidian `^block-id`; two kinds under one preset
   bit). The public binary-spec builder and adopter-defined rules move to 0.4; the
   internal engine is already rule-driven.
8. **ABI** — may change: release 0.3.0 with C ABI **3**; `lutez_opts` remains 16 bytes;
   preset APIs are additive; updated decoders are acceptable.

Remaining clarifications (assumed above, flag if different):

- **Obsidian `^key` placement**: implemented as a *trailing* block marker, matching
  Obsidian (`text ^id`), not as a standalone `^id` line. A standalone line would be a
  paragraph whose only content is the extension node.
- **Math block scope**: the fenced `$$` block form is included in phase 1; if only inline
  math is needed, that rule can be disabled by a preset flag.
- **Logseq properties in containers**: allowed at block start inside document, blockquote
  and list items; adjust the preset context flags if Logseq only permits top-level
  properties in your data.
- **Tag alphabet/boundaries**: Unicode letters/digits plus `_-/`; not all digits; `#`
  must follow whitespace/start or a non-URL punctuation class (rejects `/`, `.`, `:`);
  tags are case-sensitive and allowed in link text.
- **Frontmatter payload trailing newline**: the body newline before the closing fence is
  included in the payload; consumers may `TrimSpace`.

## 10. Recommendation

- Build **D**: a data-driven rule engine, not callbacks. In 0.3 the engine is internal and
  driven by six **presets**; 0.4 exposes the same rules through a public binary spec and
  builder.
- Keep the wire layout v2; add `NodeBlockExtension`/`NodeInlineExtension` (500/501) and
  `has_extensions`; bump C ABI to 3 and add `lutez_parse_presets`.
- Make payloads raw bytes keyed by kind; consumers decode `target|alias`, `key:: value`,
  YAML, etc. This keeps the core free of dialect policy and the wire stable.
- Gate everything behind a preset mask; the no-extension path must remain byte-identical.

If schedule pressure dominates further, ship frontmatter + Logseq + tags + math first and
add wikilinks/Obsidian block IDs in a 0.3.x preset update; the AST/ABI surface does not
change.
