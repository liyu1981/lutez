// Package lutez is a cgo bridge to the Zig library: markdown in, upstream ast.Node out.
package lutez

/*
#cgo CFLAGS: -I${SRCDIR}/../../../include
#cgo LDFLAGS: ${SRCDIR}/../../../zig-out/lib/liblutez.a -lc -lm
#include <stdint.h>
#include <stdlib.h>
#include "lutez.h"
*/
import "C"

import (
	"errors"
	"unsafe"

	"github.com/88250/lute/ast"
	"github.com/88250/lute/parse"
	"lutez/parity/wire"
)

// Parse parses markdown with lutez and returns the decoded upstream AST.
func Parse(md []byte, options *parse.Options) (*ast.Node, error) {
	var opts C.lutez_opts
	opts.struct_size = C.uint32_t(unsafe.Sizeof(opts))
	set := func(dst *C.uint8_t, v bool) {
		if v {
			*dst = 1
		} else {
			*dst = 0
		}
	}
	set(&opts.gfm_table, options.GFMTable)
	set(&opts.gfm_task_list_item, options.GFMTaskListItem)
	set(&opts.gfm_strikethrough, options.GFMStrikethrough)
	set(&opts.gfm_strikethrough1, options.GFMStrikethrough1)
	set(&opts.gfm_auto_link, options.GFMAutoLink)
	set(&opts.inline_asterisk, options.InlineAsterisk)
	set(&opts.inline_underscore, options.InlineUnderscore)
	set(&opts.setext, options.Setext)
	set(&opts.indent_code_block, options.IndentCodeBlock)
	set(&opts.link_ref, options.LinkRef)
	set(&opts.data_image, options.DataImage)

	var ptr *C.uint8_t
	if len(md) > 0 {
		ptr = (*C.uint8_t)(unsafe.Pointer(&md[0]))
	}
	doc := C.lutez_parse(ptr, C.size_t(len(md)), &opts)
	if doc == nil {
		msg := C.GoString(C.lutez_last_error())
		return nil, errors.New("lutez: " + msg)
	}
	defer C.lutez_doc_free(doc)
	var n C.size_t
	astPtr := C.lutez_doc_ast(doc, &n)
	if astPtr == nil || n == 0 {
		return nil, errors.New("lutez: empty AST")
	}
	buf := C.GoBytes(unsafe.Pointer(astPtr), C.int(n))
	return wire.Decode(buf)
}
