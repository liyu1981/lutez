/*
 * lutez — CommonMark 0.31.2 + GFM parser (Zig port of upstream lute)
 *
 * C ABI v2. Parses CommonMark 0.31.2 + GFM into a versioned binary AST; the
 * document owns all memory until lutez_doc_free().
 *
 * Rules:
 *   - documents are opaque handles; no AST struct is exposed;
 *   - errors are reported via NULL/0 + lutez_last_error*(), never by panicking;
 *   - lutez_doc_ast() bytes are valid until lutez_doc_free();
 *   - the input buffer is copied: the caller may free it right after lutez_parse().
 *
 * Windows: link `lutez.lib` for the DLL (with `lutez.dll`) or `lutez_static.lib`
 * for the static library. Other platforms: `-llutez` / `liblutez.a`.
 *
 * License: Mulan PSL v2 (see LICENSE). Derived from github.com/88250/lute.
 */
#ifndef LUTEZ_H
#define LUTEZ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUTEZ_ABI_VERSION 2u
#define LUTEZ_WIRE_FORMAT_VERSION 2u

/* Error codes returned by lutez_last_error_code(). */
enum {
  LUTEZ_OK = 0,
  LUTEZ_ERR_OOM = 1,
  LUTEZ_ERR_INVALID_OPTIONS = 2,
  LUTEZ_ERR_INPUT_TOO_LARGE = 3,
  LUTEZ_ERR_NOT_IMPLEMENTED = 4,
  LUTEZ_ERR_INTERNAL = 5,
  LUTEZ_ERR_BAD_WIRE = 6
};

/* Versioned options struct (v1, 16 bytes).
 *
 * Zero-initialize, set struct_size = sizeof(lutez_opts), then set flags to 1 for
 * enabled. Passing NULL for opts means "use upstream defaults" (all scoped flags on);
 * an all-zero struct means "all flags off". Flags are uint8_t (0/1), not C bool, for
 * ABI stability across compilers. */
typedef struct lutez_opts {
  uint32_t struct_size;
  uint8_t gfm_table;
  uint8_t gfm_task_list_item;
  uint8_t gfm_strikethrough;
  uint8_t gfm_strikethrough1;
  uint8_t gfm_auto_link;
  uint8_t inline_asterisk;
  uint8_t inline_underscore;
  uint8_t setext;
  uint8_t indent_code_block;
  uint8_t link_ref;
  uint8_t data_image;
  uint8_t strip_bom; /* 1 = ignore a leading UTF-8 BOM (NULL opts: 1) */
} lutez_opts;

typedef struct lutez_doc lutez_doc;

/* ---- lifecycle ---------------------------------------------------------- */

const char *lutez_version_string(void);
uint32_t lutez_abi_version(void);
uint32_t lutez_wire_format_version(void);

/* Parse UTF-8 markdown. Returns NULL on failure. The input is copied. */
lutez_doc *lutez_parse(const uint8_t *md, size_t len, const lutez_opts *opts);

/* Serialized AST (doc/WIRE_FORMAT.md v1). Valid until lutez_doc_free().
 * Returns NULL and sets *out_len = 0 when doc is NULL. */
const uint8_t *lutez_doc_ast(const lutez_doc *doc, size_t *out_len);

uint32_t lutez_doc_abi_version(const lutez_doc *doc);

/* Releases the document. NULL is a no-op; double free is undefined. */
void lutez_doc_free(lutez_doc *doc);

/* ---- optional ergonomic accessors -------------------------------------- *
 * Node handles are uint32_t indices; LUTEZ_NULL_NODE means "absent".
 * lutez_node_data returns the node's token bytes (same as the wire token pool).
 * Invalid doc/node values return 0 / -1 / LUTEZ_NULL_NODE / NULL, never crash. */
#define LUTEZ_NULL_NODE 0xFFFFFFFFu

uint32_t lutez_node_count(const lutez_doc *doc);
int32_t lutez_node_type(const lutez_doc *doc, uint32_t node);
uint32_t lutez_node_parent(const lutez_doc *doc, uint32_t node);
uint32_t lutez_node_first_child(const lutez_doc *doc, uint32_t node);
uint32_t lutez_node_next(const lutez_doc *doc, uint32_t node);
const uint8_t *lutez_node_data(const lutez_doc *doc, uint32_t node, size_t *out_len);

/* Source spans: raw offsets into the caller's original bytes (primary contract),
 * normalized offsets into the CRLF/NUL-normalized buffer, and a derived flag. */
int lutez_node_span(const lutez_doc *doc, uint32_t node, uint32_t *out_start, uint32_t *out_end);
int lutez_node_span_norm(const lutez_doc *doc, uint32_t node, uint32_t *out_start, uint32_t *out_end);
int lutez_node_span_derived(const lutez_doc *doc, uint32_t node);

/* ---- errors (thread-local, never NULL) --------------------------------- */

const char *lutez_last_error(void);
int32_t lutez_last_error_code(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* LUTEZ_H */
