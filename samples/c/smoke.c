/* lutez C ABI smoke test: parse, inspect the wire AST, free. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "lutez.h"

int main(void) {
  printf("lutez %s (abi %u, wire %u)\n", lutez_version_string(), lutez_abi_version(),
         (unsigned)LUTEZ_WIRE_FORMAT_VERSION);
  assert(lutez_abi_version() == LUTEZ_ABI_VERSION);

  lutez_opts opts;
  memset(&opts, 0, sizeof opts);
  opts.struct_size = (uint32_t)sizeof opts;
  opts.gfm_table = 1;
  opts.setext = 1;
  opts.strip_bom = 1;

  const char *md = "# hello *world*\n\n- a\n- b\n";
  lutez_doc *doc = lutez_parse((const uint8_t *)md, strlen(md), &opts);
  if (doc == NULL) {
    fprintf(stderr, "parse failed: %s (code %d)\n", lutez_last_error(),
            (int)lutez_last_error_code());
    return 1;
  }

  size_t len = 0;
  const uint8_t *ast = lutez_doc_ast(doc, &len);
  assert(ast != NULL && len > 40);
  assert(memcmp(ast, "LUTEAST1", 8) == 0);
  assert(lutez_node_count(doc) >= 5);
  assert(lutez_node_type(doc, 0) == 0); /* document */
  assert(lutez_node_type(doc, 1) == 2); /* heading */
  assert(lutez_node_parent(doc, 0) == (uint32_t)LUTEZ_NULL_NODE);
  uint32_t span_start = 1, span_end = 0;
  assert(lutez_node_span(doc, 1, &span_start, &span_end));
  assert(span_start == 0 && span_end >= 7); /* "# hello" */
  assert(lutez_wire_format_version() == LUTEZ_WIRE_FORMAT_VERSION);

  printf("ast: %zu bytes, %u nodes, first child type=%d\n", len, lutez_node_count(doc),
         (int)lutez_node_type(doc, 1));
  lutez_doc_free(doc);

  /* Invalid options must fail cleanly. */
  opts.struct_size = 2;
  assert(lutez_parse((const uint8_t *)md, strlen(md), &opts) == NULL);
  assert(lutez_last_error_code() == LUTEZ_ERR_INVALID_OPTIONS);

  /* Optional dialect presets: frontmatter + tag. */
  const char *ext_md = "---\ntitle: demo\n...\n#tag\n";
  lutez_doc *ext = lutez_parse_presets((const uint8_t *)ext_md, strlen(ext_md), NULL,
                                      LUTEZ_EXT_FRONTMATTER | LUTEZ_EXT_TAGS);
  assert(ext != NULL);
  assert(lutez_node_type(ext, 1) == 500);
  assert(lutez_node_ext_kind(ext, 1) == 4);
  uint32_t tag_found = 0;
  for (uint32_t i = 0; i < lutez_node_count(ext); i++) {
    if (lutez_node_ext_kind(ext, i) == 3) tag_found = 1;
  }
  assert(tag_found);
  lutez_doc_free(ext);

  printf("ok\n");
  return 0;
}
