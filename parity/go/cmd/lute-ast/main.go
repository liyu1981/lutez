// lute-ast prints the canonical AST dump of stdin markdown using upstream lute.
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/88250/lute/parse"
	"lutez/parity/corpus"
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
	tree := parse.Parse("", md, opts)
	fmt.Print(corpus.Dump(tree.Root))
}
