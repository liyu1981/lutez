# lutez wire format v1 (draft)

**Status: DRAFT v0** — normative after M0.4. Governs `lutez_doc_ast()` bytes, the WASM
memory view, and the committed conformance corpus (`*.lzc`).

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
offset 0                Header (32 bytes)
offset 32               Nodes      node_count × node_stride
                       padding to 8-byte alignment
                       Extras     ext_len bytes
                       padding to 8-byte alignment
                       Input      input_len bytes
                       padding to 8-byte alignment
                       Pool       pool_len bytes
```

All offsets in the header are derived, not stored: a reader computes
`nodes_off = 32`, `extras_off = align8(32 + node_count*node_stride)`, and so on. This
keeps the header small and eliminates a class of inconsistent-offset bugs. If a future
version needs sections in a different order, `format_version` changes.

## 2. Header (32 bytes)

| Off | Size | Field | Value / meaning |
|---:|---:|---|---|
| 0 | 8 | `magic` | ASCII `LUTEAST1` (no NUL) |
| 8 | 4 | `format_version` | `1` |
| 12 | 4 | `flags` | bit 0 must be 1 = little-endian; bits 1–31 reserved, zero |
| 16 | 4 | `node_count` | number of nodes, including the document root (≥ 1) |
| 20 | 4 | `node_stride` | `48` for v1; readers must honor the value and require ≥ 48 |
| 24 | 4 | `input_len` | normalized input bytes |
| 28 | 12 | `ext_len`, `pool_len`, `reserved` | totals of the extras / pool sections; `reserved` = 0 |

Readers must reject `node_stride < 48`, `node_count == 0`, unknown `format_version`, or
any section that would exceed the buffer length.

## 3. Node record (48 bytes, `node_stride` for v1)

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
| 32 | 4 | `data_ref` | same encoding, selector = flags bit 1; `0xFFFFFFFF` = empty |
| 36 | 4 | `data_len` | length; `0` when absent |
| 40 | 4 | `ext_ref` | offset into extras section; `0xFFFFFFFF` = no blob |
| 44 | 4 | `ext_len` | blob length; `0` when absent |

Node `0` is always the `NodeDocument` root (`parent == prev == next == 0xFFFFFFFF`).
Empty tokens and absent ext are both legal; an empty `Data` with `data_ref = 0` and
`data_len = 0` means "empty", not "points at input[0]".

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

## 5. Input and pool sections

- **Input**: the normalized document text exactly as the lexer saw it — CRLF already
  converted to LF, trailing `\n` appended if missing, NUL bytes replaced with U+FFFD.
  Token refs with selector 0 index into this section. This is why AST slices never
  dangle after the caller frees its buffer.
- **Pool**: every non-input byte sequence referenced by any node (synthesized markers,
  entity-decoded text, folded labels, destination-encoded bytes). Duplicates are allowed
  in v1; a future version may dedupe (consumers must not assume uniqueness).

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
8. `tok_ref + tok_len` and `data_ref + data_len` stay inside their selected section.
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

- `format_version` increments on any change that a v1 reader cannot ignore:
  node stride change, new required flag semantics, section reordering.
- Adding a new node type for a *currently out-of-scope feature* is a breaking change for
  v1 consumers that whitelist types; it ships in v2 of the format and of the C ABI.
- `ext` blob changes that only append fields are handled by bumping `format_version`
  (readers reject trailing bytes today). Removing/renaming fields is also a version bump.
- The C ABI has its own `lutez_opts`/`lutez_doc` version (`LUTEZ_ABI_VERSION`), which
  moves independently of `format_version`; both are reported by
  `lutez_version_string()`/`lutez_doc_abi_version()`.

## 9. Corpus file format (`*.lzc`)

Used by the Go-free conformance runner. Not part of the public ABI, but frozen with
`format_version` 1 so committed fixtures stay valid:

```
u32 magic 0x4C5A4331 ("LZC1")
u32 case_count
repeat case_count:
  u32 name_len,  name bytes (UTF-8)
  u32 opts_len,  options blob (same field order as lutez_opts v1, LE)
  u32 md_len,    markdown bytes
  u32 ast_len,   expected wire AST bytes (§1–§6)
  u32 html_len,  expected HTML bytes (oracle output, for L3 debug; may be 0)
```

All lengths are little-endian. Sections are concatenated, no alignment padding.
