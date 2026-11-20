# lutez AST schema (scoped CommonMark/GFM subset)

**Status: DRAFT v0** — normative only after M0.3 sign-off. Changes require a schema
version bump and a harness mask update.

Upstream reference: `lute/ast/node.go` @ `v1.7.8` (56b87cd, see `UPSTREAM.md`).
Wire encoding: `doc/WIRE_FORMAT.md`. This document defines *what* fields exist; the wire
document defines *how* they are encoded.

---

## 1. Conventions

| Concept | Representation |
|---|---|
| Node handle | `u32` index into the document node array; `0xFFFF_FFFF` (`null_node`) = absent |
| Type | `u16`, **upstream `NodeType` numeric values are preserved verbatim** |
| Type string | upstream stringer name (`"NodeParagraph"`, …) — used by harness JSON only, not stored in the wire format |
| Flags | 16 packed bits, §3 |
| Tokens | mutable `[]u8` slice into the document arena (normalized input or pool) |
| Data | `[]u8`; upstream `Node.Data` may differ from `Tokens` after entity decoding/text transforms, so it is stored separately |
| Ext | optional variable-length blob, type-specific (§5); empty for most nodes |
| Integers | little-endian in the wire format |
| Strings/bytes | `u32 len` + raw bytes inside `ext` blobs |

Rules:

- Node handles are only meaningful within one document. They are never pointers and
  never stable across `parse` calls.
- `Previous` is stored explicitly (upstream code and renders use it); it must always
  agree with the parent's child chain. The encoder asserts this; the decoder validates it
  only on accessor use (cheap check: `prev` of `first_child` is null, etc.).
- A node's children are reachable via `first_child` + `next`; `last_child` is cached for
  O(1) append, exactly like upstream.
- No node type outside §2 may be constructed by parser code. CI enforces the whitelist
  by grepping for the enum members used in `src/parse/`.

---

## 2. Node type whitelist (55 types)

Numbers are upstream values and must never be renumbered.

### 2.1 CommonMark blocks and inline structure (0–48)

| # | Go constant | Type string | Notes |
|---:|---|---|---|
| 0 | `NodeDocument` | `NodeDocument` | root; ext carries nothing |
| 1 | `NodeParagraph` | `NodeParagraph` | |
| 2 | `NodeHeading` | `NodeHeading` | ext: level, setext |
| 3 | `NodeHeadingC8hMarker` | `NodeHeadingC8hMarker` | ATX `#` run (tokens) |
| 4 | `NodeThematicBreak` | `NodeThematicBreak` | |
| 5 | `NodeBlockquote` | `NodeBlockquote` | |
| 6 | `NodeBlockquoteMarker` | `NodeBlockquoteMarker` | `>` |
| 7 | `NodeList` | `NodeList` | ext: `ListData` (without item-only fields) |
| 8 | `NodeListItem` | `NodeListItem` | ext: `ListData` |
| 9 | `NodeHTMLBlock` | `NodeHTMLBlock` | ext: `html_block_type` (1–7) |
| 10 | `NodeInlineHTML` | `NodeInlineHTML` | raw text in tokens |
| 11 | `NodeCodeBlock` | `NodeCodeBlock` | ext: fence char/len/offset, open/info/close fences |
| 12 | `NodeCodeBlockFenceOpenMarker` | `NodeCodeBlockFenceOpenMarker` | |
| 13 | `NodeCodeBlockFenceCloseMarker` | `NodeCodeBlockFenceCloseMarker` | |
| 14 | `NodeCodeBlockFenceInfoMarker` | `NodeCodeBlockFenceInfoMarker` | |
| 15 | `NodeCodeBlockCode` | `NodeCodeBlockCode` | |
| 16 | `NodeText` | `NodeText` | |
| 17 | `NodeEmphasis` | `NodeEmphasis` | |
| 18–21 | `NodeEmA6k{,Open,Close}Marker`, `NodeEmU8e{,Open,Close}Marker` | same | 18,19 = `*`; 20,21 = `_` |
| 22 | `NodeStrong` | `NodeStrong` | |
| 23–26 | `NodeStrongA6k/U8e{Open,Close}Marker` | same | |
| 27 | `NodeCodeSpan` | `NodeCodeSpan` | |
| 28 | `NodeCodeSpanOpenMarker` | `NodeCodeSpanOpenMarker` | |
| 29 | `NodeCodeSpanContent` | `NodeCodeSpanContent` | |
| 30 | `NodeCodeSpanCloseMarker` | `NodeCodeSpanCloseMarker` | |
| 31 | `NodeHardBreak` | `NodeHardBreak` | |
| 32 | `NodeSoftBreak` | `NodeSoftBreak` | |
| 33 | `NodeLink` | `NodeLink` | ext: link type, ref label |
| 34 | `NodeImage` | `NodeImage` | ext: link type, ref label |
| 35 | `NodeBang` | `NodeBang` | `!` |
| 36 | `NodeOpenBracket` | `NodeOpenBracket` | `[` |
| 37 | `NodeCloseBracket` | `NodeCloseBracket` | `]` |
| 38 | `NodeOpenParen` | `NodeOpenParen` | `(` |
| 39 | `NodeCloseParen` | `NodeCloseParen` | `)` |
| 40 | `NodeLinkText` | `NodeLinkText` | |
| 41 | `NodeLinkDest` | `NodeLinkDest` | |
| 42 | `NodeLinkTitle` | `NodeLinkTitle` | |
| 43 | `NodeLinkSpace` | `NodeLinkSpace` | |
| 44 | `NodeHTMLEntity` | `NodeHTMLEntity` | tokens = raw source; data = decoded |
| 45 | `NodeLinkRefDefBlock` | `NodeLinkRefDefBlock` | container |
| 46 | `NodeLinkRefDef` | `NodeLinkRefDef` | ext: ref label (raw, pre-fold) |
| 47 | `NodeLess` | `NodeLess` | `<` |
| 48 | `NodeGreater` | `NodeGreater` | `>` |

### 2.2 GFM (100–109)

| # | Go constant | Type string | Notes |
|---:|---|---|---|
| 100 | `NodeTaskListItemMarker` | `NodeTaskListItemMarker` | ext: marker byte (`' '`, `'x'`, `'X'`, …) |
| 101 | `NodeStrikethrough` | `NodeStrikethrough` | |
| 102 | `NodeStrikethrough1OpenMarker` | `NodeStrikethrough1OpenMarker` | `~` |
| 103 | `NodeStrikethrough1CloseMarker` | `NodeStrikethrough1CloseMarker` | |
| 104 | `NodeStrikethrough2OpenMarker` | `NodeStrikethrough2OpenMarker` | `~~` |
| 105 | `NodeStrikethrough2CloseMarker` | `NodeStrikethrough2CloseMarker` | |
| 106 | `NodeTable` | `NodeTable` | ext: aligns |
| 107 | `NodeTableHead` | `NodeTableHead` | |
| 108 | `NodeTableRow` | `NodeTableRow` | |
| 109 | `NodeTableCell` | `NodeTableCell` | ext: align |

### 2.3 Backslash escapes (400–401)

| # | Go constant | Type string | Notes |
|---:|---|---|---|
| 400 | `NodeBackslash` | `NodeBackslash` | `\` marker + one child |
| 401 | `NodeBackslashContent` | `NodeBackslashContent` | escaped byte |

**Not whitelisted** (must never be constructed): emoji 200–203, math 300–307,
VditorCaret 405, footnotes 410–412, ToC 415, HeadingID 420, YAML 425–428,
BlockRef 430–434, Mark 450–454, Kramdown IAL 455–456, Tags 460–462, query embed,
braces, SuperBlock, Sup/Sub, GitConflict, IFrame/Audio/Video, Kbd, Underline, Br,
TextMark, Widget, FileAnnotationRef, AttributeView, CustomBlock, HTMLTag, Callout,
Tabs, TabItem, Mindmap, and any type ≥ 500.

---

## 3. Flags (u16, bit assignments are wire-frozen)

| Bit | Name | Meaning | Upstream field |
|---:|---|---|---|
| 0 | `tokens_in_pool` | token ref points into pool, not normalized input | — (wire only) |
| 1 | `data_in_pool` | data ref points into pool | — (wire only) |
| 2 | `close` | node closed during block parse | `Close` |
| 3 | `last_line_blank` | last line blank (list tightness) | `LastLineBlank` |
| 4 | `last_line_checked` | | `LastLineChecked` |
| 5 | `heading_setext` | setext heading | `HeadingSetext` |
| 6 | `code_fenced` | fenced (vs indented) code block | `IsFencedCodeBlock` |
| 7 | `task_checked` | task list item checked (legacy boolean view) | `TaskListItemChecked` |
| 8 | `gfm_auto_link` | autolink produced by GFM extension | internal |
| 9–15 | reserved | must be zero on write, ignored on read | — |

`HeadingLevel`, `HtmlBlockType`, `ListData`, `LinkType`, etc. live in `ext`, not in
flags (they are not booleans).

---

## 4. Structural rules (subset; mirrors upstream `CanContain`/parse code)

| Container | Allowed children |
|---|---|
| `Document` | blocks (paragraph, heading, thematic break, blockquote, list, HTML block, code block, table, link-ref-def block) |
| `Blockquote` | blocks |
| `ListItem` | blocks (plus `TaskListItemMarker` as first inline child of its paragraph) |
| `List` | `ListItem` only |
| `Paragraph` | inlines |
| `Heading` | inlines (after `HeadingC8hMarker`) |
| `Table` | `TableHead`, `TableRow` |
| `TableHead` / `TableRow` | `TableCell` only |
| `TableCell` | inlines |
| `Link` / `Image` | `Bang`(image), `OpenBracket`, `LinkText`, `CloseBracket`, `OpenParen`, `LinkDest`, `LinkSpace`, `LinkTitle`, `CloseParen` |
| `LinkRefDef` | `LinkRefDefBlock` members per upstream (`[label]:` inlines) |
| `Backslash` | exactly one `BackslashContent` |
| `CodeBlock` | marker/info/code nodes (§6.2) |
| `CodeSpan` | open marker, content, close marker |
| `Emphasis` / `Strong` / `Strikethrough` | marker nodes + inlines |

Whitespace/text normalizations are **not** schema-level: they follow upstream parser
behavior byte for byte (e.g. softbreak stripping in tight lists keeps the same node
types and tokens).

---

## 5. `ext` blob layouts

Encoding primitives (wire format §4):

- `u8`, `u16`, `u32`, `i32` — little-endian fixed width.
- `bytes` — `u32 len` followed by `len` raw bytes.
- `bool` — `u8` 0/1 (only used inside `ext`, never in flags).
- Absent blob (`ext_len == 0`) means "all fields at their zero default".
- Encoders must write fields in the listed order; decoders must reject `ext` blobs with
  trailing bytes or truncated fields (`error.BadExtBlob`).

### 5.1 `Heading` (type 2)

```
u8  level          // 1..6
u8  setext         // 0/1, mirrored in flags bit 5
```

### 5.2 `CodeBlock` (type 11)

```
u8   fence_char         // '`' or '~' (0 for indented code)
u8   fence_len          // 3..  (0 for indented code)
u8   fenced             // 0/1, mirrored in flags bit 6
u8   _pad
u32  fence_offset
bytes open_fence        // CodeBlockOpenFence
bytes info              // CodeBlockInfo
bytes close_fence       // CodeBlockCloseFence
```

Upstream stores these as `[]byte` fields in addition to child marker nodes; both are
retained because renderers and `Tools` code read them directly.

### 5.3 `HTMLBlock` (type 9)

```
u8  html_block_type     // 1..7
```

### 5.4 `List` (7) and `ListItem` (8) — `ListData`

```
u8   typ                // 0 unordered, 1 ordered, 3 task
u8   tight              // bool
u8   bullet_char        // '*', '-', '+' (0 if ordered/task)
u8   delimiter          // '.' or ')' (0 if unordered)
u8   checked            // bool (ListData.Checked, item-level)
u8   _pad[3]
i32  start              // ordered start number
i32  num                // corrected number (upstream ListData.Num)
u32  padding            // W+N in CommonMark terms
u32  marker_offset
bytes marker            // raw marker bytes
```

Whitelist for `typ`: `{0,1,3}` — upstream's task list `3` is kept because GFM task
lists are in scope.

### 5.5 `Link` (33) and `Image` (34)

```
u8   link_type          // 0 inline, 1 ref-def, 2 autolink, 3 ref
bytes link_ref_label    // raw label bytes; empty for inline/autolink
```

Upstream `LinkType` is an `int` but only 0–3 occur in scope; reject others on read.

### 5.6 `Table` (106)

```
u32   count
u8    aligns[count]     // 0 default, 1 left, 2 center, 3 right
```

### 5.7 `TableCell` (109)

```
u8  align               // 0..3
```

`TableCellContentWidth` / `TableCellContentMaxWidth` / `TableCellRich` are **out of
scope** (they exist only for SiYuan rich-table projection); they are not in the schema.

### 5.8 `LinkRefDef` (46)

```
bytes ref_label         // raw label as written, pre-fold; canonical fold lives in the
                        // ref-def index, not on the node
```

### 5.9 `TaskListItemMarker` (100)

```
u8 marker               // raw byte between brackets: ' ', 'x', 'X', '-', '/', '>', '!'
```

### 5.10 All other types

`ext_len == 0`.

---

## 6. Fields intentionally **not** in the schema

Kept out because they are out-of-scope features, SiYuan integration, or debug-only:

`ID`, `Spec`, `Box`, `Path`, `DocumentTitle`, `Children` (derived from links),
`TypeStr` (derived), `Properties`, `KramdownIAL`, `TextMark*`, `AttributeView*`,
`Callout*`, `TabItemTitle`, `CustomBlock*`, `MathBlock*`, `Footnotes*`,
`TableCellRich`, `TableCellContent*`, `CodeMarkerLen`, `HeadingNormalizedID`,
`HtmlEntityTokens` (derived: raw token + decoded data is enough), `Br/Video/Audio/IFrame`
extension nodes.

If a future in-scope feature needs one of these, it is a schema version bump.

---

## 7. Validation duties

Encoder (`src/ast/wire.zig`):

- asserts parent/child/sibling reciprocity while writing (Debug/ReleaseSafe only);
- rejects tokens/data pointing outside the arena input and pool;
- writes flags bits 0–8 only; zeroes reserved bits.

Decoder (internal only, used by conformance runner and round-trip tests):

- rejects bad magic/version, misaligned sections, out-of-range node refs, cyclic child
  chains (bounded walk), `ext` overruns, unknown node types;
- never trusts lengths: every offset+len pair checked against section sizes;
- returns `error.BadWire` rather than trapping (fuzzed).

Accessors in `c_api.zig` validate the handle and node index before reading, and return
`null_node`/`NULL` for invalid input (documented, no UB).
