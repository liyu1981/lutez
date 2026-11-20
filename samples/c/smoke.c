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

  printf("ast: %zu bytes, %u nodes, first child type=%d\n", len, lutez_node_count(doc),
         (int)lutez_node_type(doc, 1));
  lutez_doc_free(doc);

  /* Invalid options must fail cleanly. */
  opts.struct_size = 2;
  assert(lutez_parse((const uint8_t *)md, strlen(md), &opts) == NULL);
  assert(lutez_last_error_code() == LUTEZ_ERR_INVALID_OPTIONS);

  printf("ok\n");
  return 0;
}
