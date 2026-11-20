# Porting notes and deviations from upstream / plan

This records intentional differences so reviewers and consumers know what to expect.

## Structure

- **Arena pointers instead of index handles inside the parser.** ADR-1 in `PLAN.md`
  originally proposed `u32` indices for the in-memory tree. During the port, pointer-linked
  arena nodes were chosen instead: they match upstream control flow (`*Node`), eliminate
  index bookkeeping noise in 9k lines of parser code, and remain safe because nodes live in
  a per-document arena. The **wire format is still index-based**, so the ABI/ownership
  guarantees are unchanged.
- One `std.heap.ArenaAllocator` per document (backed by `smp_allocator` natively,
  `wasm_allocator` in freestanding builds). `deinit` is O(1).
- `Node` keeps the upstream field names but only the scoped subset (~45 fields). Marker
  nodes, code-block fence data, `ListData`, `TableAligns`, link type/label and task marker
  are retained because they are observable in the AST.

## Wire format vs `WIRE_FORMAT.md`

- Header is **40 bytes** (the draft said 32); fields are the same plus an explicit
  `reserved` word.
- v1 puts **all tokens in the pool** (`flags` bit 0 = 1); the input section exists but is
  empty. This avoids tracking which slices alias the normalized input.
- `data` is not stored; `data_ref = 0xFFFFFFFF`. `lutez_node_data` returns the token bytes
  (Lute has no in-scope node where `Data` differs from `Tokens` after our passes).
- `CodeBlock.fence_len` is `u8` in the extras blob (fences longer than 255 are a spec
  impossibility in practice; the parser still tracks `u32` in memory).
- Extras layouts for `code_block`/`list`/`link`/`table`/`code_span` are as implemented in
  `src/ast/wire.zig`; `AST_SCHEMA.md` §5 documents them.

## Scope stripping

- Removed at port time (never ported): Protyle/Vditor caret handling, text marks, callouts,
  tabs/super blocks, custom blocks, math, footnotes, emoji, YAML, heading IDs, kramdown IAL,
  tags/marks/sup/sub, ToC, block refs, audio/video/iframe/widgets, renderers, HTML5 parser.
- Options are the scoped 11 GFM/CM flags; all others are compile-time absent.
- Upstream's IAL/editor-only branches inside `paragraph`, `list`, `table` and `inline_html`
  are gone; behavior for plain CommonMark/GFM is preserved.

## Known simplifications (parity is corpus-verified)

- GFM extended autolinks use the upstream public-suffix table (`src/parse/tlds.zig`,
  generated from `parse/auto_link.go`'s `allTLDs`, plus `baz` to mirror
  `test/gfm_spec_test.go`). Domain validation and trailing punctuation/paren/entity rules
  follow upstream; the 672-case GFM corpus and 3000-case dual fuzz pass. Custom non-http
  schemes (upstream accepts any `scheme://` with letter/digit scheme) are not produced by
  our scanner yet — out of the corpus, tracked here.
- `LinkRefLabel` comparison uses generated full case folding (`cases.Fold` equivalent),
  matching upstream's `linkrefdef_case_fold.go`.
- Entity decoding uses the generated 2125-entry table from upstream `html.Entities`
  (semicolon required, matching Lute's `HtmlUnescapeString`).
- The parser is reentrant and allocation-failure-safe; malformed Markdown never errors.
- AST parity is defined for valid UTF-8 Markdown. Arbitrary invalid byte sequences are
  covered for crash/leak safety (Zig crash fuzzer), not for byte-level AST parity: upstream
  Lute itself has undefined-ish behavior there and the dual fuzz intentionally restricts
  itself to UTF-8 (3000/3000 match with CommonMark options).
- No node IDs, timestamps, `DocumentTitle`, or `Properties` exist in the scoped AST.

## Performance

- Arena backing allocator choice was the dominant factor (page allocator → 4.5× slower
  than Go; `smp_allocator` → 3.9× faster). See `BENCHMARKS.md`.

## Provenance

Every ported file carries a `Ported from lute/<file> @ v1.7.8` header; the machine-readable
map is `tools/port-manifest.tsv`. Upstream pin policy and bump procedure: `UPSTREAM.md`.
