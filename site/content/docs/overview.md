# Overview

**lutez** is a [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) + GFM **parser**
written in Zig, ported from [Lute](https://github.com/88250/lute) at release tag `v1.7.8`.
It turns UTF-8 Markdown bytes into a versioned binary AST. Rendering is intentionally out
of scope: the caller decides what to do with the tree.

The parser is exposed through four surfaces that share one AST contract:

- a **C ABI** (static and shared libraries plus a versioned header),
- a **WASM** module (wasm32-freestanding, zero imports) with JS and TypeScript glue,
- a **Zig module** for native Zig consumers, and
- the **wire format** itself, for any language that can read little-endian bytes.

## What is in scope

| Area | Included |
|---|---|
| CommonMark blocks | paragraphs, ATX/setext headings, thematic breaks, blockquotes, lists, indented/fenced code, HTML blocks 1–7 |
| CommonMark inlines | text, escapes, code spans, emphasis/strong, links, images, autolinks, entities, inline HTML, soft/hard breaks |
| GFM | tables, strikethrough (`~`/`~~`), task list items, extended autolinks |
| Grammar tables | HTML entities, Unicode categories, simple + full case folding, public suffixes |

## What is not

Renderers, HTML parsing (HTML blocks are scanned lexically and kept as raw text), the
SiYuan/Protyle/Vditor extensions, Kramdown IAL, footnotes, upstream math/YAML/tag
extensions, emoji aliases, heading IDs, TOC, block refs, and document metadata. The
opal_note dialect is available as opt-in presets (raw payloads, no YAML parsing); the
scope fence is recorded in the [implementation plan](./plan.md).

## Design at a glance

1. **Copy and normalize** the input (CRLF → LF, trailing newline, NUL → U+FFFD).
2. **Lex** lines and **parse blocks** build a container tree using an arena.
3. **Parse inlines** with a delimiter stack, bracket stack and link reference index.
4. **Serialize** the tree to the index-based [wire format](./wire-format.md) in one buffer.

The in-memory tree uses pointer links into a per-document arena; the serialized tree uses
`u32` indices, so it is safe for WASM32 and trivially copyable. See
[porting notes](./porting-notes.md) for why.

## Parity and performance (v0.3.0)

| Check | Result |
|---|---|
| CommonMark corpus (GFM off) | **652/652** AST parity |
| GFM corpus | **672/672** AST parity |
| Live differential (Go oracle ↔ C ABI) | **652/652** |
| HTML oracle (upstream renderer over our AST) | **652/652** byte-identical |
| Spec-corpus parse time | **0.91 ms** vs 3.54 ms upstream Go |
| WASM artifact | **243,408 B**, zero imports |

Measurements and commands live in [benchmarks](./benchmarks.md).

## Repository map

| Path | Contents |
|---|---|
| `src/lex`, `src/parse`, `src/ast` | the ported parser and AST |
| `src/{lutez,c_api,wasm,doc,abi}.zig` | public Zig API and ABI surfaces |
| `test/corpus` | committed CommonMark + GFM corpora for Go-free conformance |
| `parity/` | Go oracle, wire decoder, differential/HTML/fuzz tooling |
| `site/` | this website and the WASM playground |
| `upstream/lute` | pinned git submodule (never edited) |

## Optional extensions

lutez can parse the opal_note dialect (frontmatter, `$…$`/`$$…$$` math, `[[wikilinks]]`,
`#tags`, Logseq `key::` properties and Obsidian `^block-id`) through **presets**. They are
off by default; enabling them never changes the core CM/GFM AST. Extension nodes are
`NodeBlockExtension`/`NodeInlineExtension` with raw payloads and source spans; see
[`Extensions`](./extensions.html) in the repository.

## Next

- [Getting started](./getting-started.md) — build and call the library.
- [ABI guide](./abi.md) — ownership, errors, options and accessors.
- [Live demo](../demo/) — edit Markdown, inspect the parsed tree, and see raw source spans
  (`@start-end`) on every node; toggle them in the playground toolbar.
