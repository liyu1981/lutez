/* lutez C ABI smoke test.
 *
 * M0 expectations: the ABI/header link and run; parsing reports
 * LUTEZ_ERR_NOT_IMPLEMENTED until the parser lands (doc/PLAN.md §8). */
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

  const char *md = "# hello\n\n- a\n- b\n";
  lutez_doc *doc = lutez_parse((const uint8_t *)md, strlen(md), &opts);
  if (doc == NULL) {
    printf("parse: %s (code %d) [expected in M0]\n", lutez_last_error(),
           (int)lutez_last_error_code());
    assert(lutez_last_error_code() == LUTEZ_ERR_NOT_IMPLEMENTED);
  } else {
    size_t len = 0;
    const uint8_t *ast = lutez_doc_ast(doc, &len);
    printf("ast: %zu bytes, %u nodes\n", len, lutez_node_count(doc));
    assert(ast != NULL && len > 0);
    lutez_doc_free(doc);
  }

  printf("ok\n");
  return 0;
}
