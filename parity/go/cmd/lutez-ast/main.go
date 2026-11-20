// lutez-ast prints the canonical AST dump of stdin markdown using the lutez C ABI.
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/88250/lute/parse"
	"lutez/parity/corpus"
	"lutez/parity/lutez"
)

func main() {
	md, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	opts := parse.NewOptions()
	opts.Emoji = false
	opts.Footnotes = false
	opts.InlineMath = false
	opts.YamlFrontMatter = false
	opts.HeadingID = false
	opts.KramdownBlockIAL = false
	root, err := lutez.Parse(md, opts)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Print(corpus.Dump(root))
}
