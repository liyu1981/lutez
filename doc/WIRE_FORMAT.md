# lutez wire format v2

**Status: v2 (wire layout unchanged in lutez 0.3.0; extension types added).** Governs `lutez_doc_ast()` bytes, the WASM memory view, and
the committed conformance corpus (`*.lzc`). v1 readers reject v2; see §8 for versioning.

Design constraints (from the feasibility report §5 and §6):

- little-endian, offset-based, no pointers, no `usize` (WASM32-safe);
- one contiguous, self-contained buffer; document owns it; O(1) free;
- node stride is independent of per-type payloads, so fields can be added without
  breaking consumers (`ext` blobs are length-delimited);
- no JSON in the core library;
- decoder must be safe against hostile bytes.

---

## 1. Buffer layout

```
offset 0                Header (40 bytes)
offset 40               Nodes      node_count × node_stride
                       padding to 8-byte alignment
                       Extras     ext_len bytes
                       padding to 8-byte alignment
                       Input      input_len bytes
                       padding to 8-byte alignment
                       Pool       pool_len bytes
                       padding to 8-byte alignment
                       SourceMap  map_len bytes
```

All offsets in the header are derived, not stored: a reader computes
`nodes_off = 40`, `extras_off = align8(40 + node_count*node_stride)`, and so on. This
keeps the header small and eliminates a class of inconsistent-offset bugs. If a future
version needs sections in a different order, `format_version` changes.

## 2. Header (40 bytes)

| Off | Size | Field | Value / meaning |
|---:|---:|---|---|
| 0 | 8 | `magic` | ASCII `LUTEAST1` (no NUL) |
| 8 | 4 | `format_version` | `2` |
| 12 | 4 | `flags` | bit 0 = little-endian; bit 1 = `has_extensions` (an extension node is present); bits 2–31 reserved, zero |
| 16 | 4 | `node_count` | number of nodes, including the document root (≥ 1) |
| 20 | 4 | `node_stride` | `56` for v2; readers must require ≥ 56 |
| 24 | 4 | `input_len` | normalized input bytes |
| 28 | 4 | `pool_len` | token pool bytes |
| 32 | 4 | `ext_len` | extras section bytes |
| 36 | 4 | `map_len` | source-map section bytes |

Readers must reject `node_stride < 56`, `node_count == 0`, unknown `format_version`, or
any section that would exceed the buffer length.

`map_off = align8(pool_off + pool_len)`; the source-map section is `4 + count × 20` bytes.

## 3. Node record (56 bytes, `node_stride` for v2)

| Off | Size | Field | Meaning |
|---:|---:|---|---|
| 0 | 2 | `type` | upstream `NodeType` value (see `AST_SCHEMA.md` §2) |
| 2 | 2 | `flags` | `AST_SCHEMA.md` §3 |
| 4 | 4 | `parent` | node index or `0xFFFFFFFF` |
| 8 | 4 | `first_child` | node index or `0xFFFFFFFF` |
| 12 | 4 | `last_child` | node index or `0xFFFFFFFF` |
| 16 | 4 | `prev` | node index or `0xFFFFFFFF` |
| 20 | 4 | `next` | node index or `0xFFFFFFFF` |
| 24 | 4 | `tok_ref` | offset into input (flags bit 0 = 0) or pool (bit 0 = 1); `0xFFFFFFFF` = empty |
| 28 | 4 | `tok_len` | length; must be `0` when `tok_ref` is absent |
| 32 | 4 | `src_norm_start` | normalized-input byte offset, inclusive |
| 36 | 4 | `src_norm_end` | normalized-input byte offset, exclusive |
| 40 | 4 | `src_raw_start` | caller's original-bytes offset, inclusive |
| 44 | 4 | `src_raw_end` | original-bytes offset, exclusive |
| 48 | 4 | `ext_ref` | offset into extras section; `0xFFFFFFFF` = no blob |
| 52 | 4 | `ext_len` | blob length; `0` when absent |

In v2 **all** tokens still live in the pool (`flags` bit 0 = 1); the input section is
reserved for a future zero-copy mode and is currently empty. `lutez_node_data` returns
the node's token bytes.

Spans are half-open and cover the source construct. Raw offsets are the primary consumer
contract (editors, deep links, line numbers); normalized offsets match the token buffer
and the source map. `flags` bit 8 marks **derived** nodes (zero-width span with no source
bytes, e.g. a synthesized reference-link paren). Node `0` is the `NodeDocument` root and
spans `[0, raw_len)`.

### 3.1 Extension nodes (types 500/501)

`NodeBlockExtension` (500) and `NodeInlineExtension` (501) carry their raw payload in the
normal token fields. Their `ext` blob is:

```
u32 kind
u16 flags
u8  payload_version (= 1)
u8  reserved (= 0)
```

Kind registry: 1 math, 2 wikilink, 3 tag, 4 frontmatter, 5 Logseq property, 6 Obsidian
block ID. Extension nodes are leaves. The header `has_extensions` flag lets older readers
reject an extension AST early. See `AST_SCHEMA.md` §2.4.

Node `0` is always the `NodeDocument` root (`parent == prev == next == 0xFFFFFFFF`).
Empty tokens and absent ext are both legal.

`previous` is stored explicitly: upstream preserves it and several parse steps rely on
sibling back-links (`InsertAfter`, delimiter retraction).

## 4. Extras section encoding

Primitives (used by `AST_SCHEMA.md` §5):

```
u8  1 byte
u16 2 bytes LE
u32 4 bytes LE
i32 4 bytes LE two's complement
bytes := u32 len, then len bytes (len ≤ remaining extras section)
```

Blobs are packed back-to-back without per-blob padding. A blob's byte layout is defined
entirely by the node type; empty payload = `ext_ref = 0xFFFFFFFF`, `ext_len = 0`.
Decoders must reject blobs with trailing bytes (indicates schema/version mismatch).

`align8(extras_off + ext_len)` is the input section offset, so blobs need no internal
alignment; consumers that want raw `u32` views must copy (documented in the header).

## 4.1 Source-map section

Built while normalizing the input (CRLF/CR→LF, NUL→U+FFFD, synthetic trailing LF):

```
u32 count
count × {
  u32 norm_start, u32 norm_len,
  u32 raw_start,  u32 raw_len,
  u8  kind, u8 reserved[3]      // 0 identity, 1 CR/CRLF, 2 NUL, 3 synthetic LF, 4 BOM
}
```

Segments cover the normalized buffer in order. Consumers convert with:

- start: identity → `raw_start + (off - norm_start)`; changed/synthetic → `raw_start`;
- end: identity → `raw_start + (off - norm_start)`; changed/synthetic → `raw_start + raw_len`.

For unchanged regions (kind 0) lengths are equal; for NUL one raw byte maps to the three
bytes of U+FFFD. Synthetic trailing LF has `raw_len = 0`. A stripped BOM is a zero-width
segment at `norm_start = 0` with `raw_len = 3`: normalized offset 0 maps to raw 3, while
the `NodeDocument` root always spans `[0, raw_len)` so the BOM stays inside the document
range.

## 5. Input and pool sections

- **Input**: the normalized document text exactly as the lexer saw it — CRLF already
  converted to LF, trailing `\n` appended if missing, NUL bytes replaced with U+FFFD.
  Token refs with selector 0 index into this section. This is why AST slices never
  dangle after the caller frees its buffer.
- **Pool**: every non-input byte sequence referenced by any node (synthesized markers,
  entity-decoded text, folded labels, destination-encoded bytes). Duplicates are allowed
  in v2; a future version may dedupe (consumers must not assume uniqueness).

Pool bytes are opaque and have no alignment guarantees.

## 6. Invariants (checked by the encoder, trusted-but-validated by the decoder)

1. `type` is in the `AST_SCHEMA.md` whitelist.
2. Flags bits 9–15 and header reserved bits are zero.
3. `parent`/`first_child`/`last_child`/`prev`/`next` are either `null_node` or
   `< node_count`.
4. `prev.next == self` and `next.prev == self` for every linked node.
5. `first_child.prev == null_node`, `last_child.next == null_node`.
6. `first_child` and `last_child` are either both `null_node` or both present.
7. Every child has `parent == self`.
8. `tok_ref + tok_len` stays inside the pool section; `src_norm_*`/`src_raw_*` stay within
   the normalized/raw bounds; `src_norm_start <= src_norm_end`.
9. `ext_ref + ext_len` stays inside the extras section.
10. Every `ext` blob is fully consumed by its type's decoder.

The **decoder** must not assume 1–10; corpus bytes are trusted for conformance runs, but
the accessor API and any future consumer-facing decode path must validate lazily and
return errors instead of trapping. Failure mode: `error.BadWire`.

## 7. Document handle and ownership

Native (`c_api.zig`):

```c
typedef struct lutez_doc {
  void *buf;        /* single allocation (or arena block) */
  size_t len;
  uint32_t abi_version;
  /* internal: validated section offsets */
} lutez_doc;
```

- `lutez_parse` copies input into the document arena, parses, encodes into one buffer,
  returns the handle. The caller's input may be freed immediately.
- `lutez_doc_ast(doc, &len)` returns a pointer valid until `lutez_doc_free`.
- `lutez_doc_free(NULL)` is a no-op; double free is UB (documented).

WASM (`wasm.zig`):

- Documents live in a fixed-capacity slot table (`MAX_DOCS = 1024`, growable only by
  rebuild); handle 0 = "no document", `0xFFFFFFFF` = error.
- `lutez_doc_ast(handle) -> u64` returns `(ptr << 32) | len`; the glue must split with
  `BigInt`/`Number` carefully (`Number(ptr >>> 0)`), then create a `Uint8Array`.
- Any call may grow memory; JS must re-create views afterwards. Documented in `js/lutez.mjs`.
- `lutez_doc_free(handle)` releases arena; slot is reclaimed.

## 8. Versioning policy

- `format_version` increments on any change that a v2 reader cannot ignore:
  node stride change, new required flag semantics, section reordering.
- Adding a new core node type is a breaking change for consumers that whitelist types;
  adopter constructs use the extension types 500/501 and their payload instead.
- `ext` blob changes that only append fields are handled by bumping `format_version`
  (readers reject trailing bytes today). Removing/renaming fields is also a version bump.
- The C ABI has its own `lutez_opts`/`lutez_doc` version (`LUTEZ_ABI_VERSION`), which
  moves independently of `format_version`; both are reported by
  `lutez_version_string()`/`lutez_doc_abi_version()`.

## 9. Corpus file format (`*.lzc`)

Used by the Go-free conformance runner. Not part of the public ABI; frozen so committed
fixtures stay valid:

```
u32 magic 0x4C5A4332 ("LZC2")
u32 case_count
repeat case_count:
  u32 name_len, name bytes (UTF-8)
  u32 md_len,   markdown bytes
  u32 ast_len,  expected canonical AST dump (UTF-8 text, not the wire format)
```

All lengths are little-endian. Sections are concatenated, no alignment padding.
