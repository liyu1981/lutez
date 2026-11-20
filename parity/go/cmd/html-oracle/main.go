// html-oracle is the L3 differential harness: decode lutez's AST into upstream ast.Node,
// render it with upstream's HTML renderer, and compare against the spec's expected HTML.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/88250/lute/parse"
	"github.com/88250/lute/render"
	"lutez/parity/lutez"
)

type specCase struct {
	Markdown string `json:"markdown"`
	HTML     string `json:"html"`
	Example  int    `json:"example"`
}

func main() {
	specPath := flag.String("corpus", "../../test/spec/commonmark-spec.json", "spec json")
	flag.Parse()
	raw, err := os.ReadFile(*specPath)
	if err != nil {
		panic(err)
	}
	var cases []specCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		panic(err)
	}
	opts := parse.NewOptions()
	opts.GFMTable = false
	opts.GFMTaskListItem = false
	opts.GFMStrikethrough = false
	opts.GFMStrikethrough1 = false
	opts.GFMAutoLink = false
	opts.Emoji = false
	opts.Footnotes = false
	opts.InlineMath = false
	opts.YamlFrontMatter = false
	opts.HeadingID = false
	opts.KramdownBlockIAL = false

	ro := render.NewOptions()
	ro.SoftBreak2HardBreak = false
	ro.AutoSpace = false
	ro.CodeSyntaxHighlight = false
	ro.CodeSyntaxHighlightDetectLang = false

	fails, shown := 0, 0
	for _, c := range cases {
		root, err := lutez.Parse([]byte(c.Markdown), opts)
		if err != nil {
			fails++
			continue
		}
		tree := &parse.Tree{Root: root, Context: &parse.Context{ParseOption: opts}}
		tree.Context.Tree = tree
		got := string(render.NewHtmlRenderer(tree, ro, opts).Render())
		want := strings.TrimSuffix(c.HTML, "\n")
		got = strings.TrimSuffix(got, "\n")
		if got != want {
			fails++
			if shown < 10 {
				shown++
				fmt.Printf("FAIL cm-%d\n  got:  %q\n  want: %q\n", c.Example, got, want)
			}
		}
	}
	if fails == 0 {
		fmt.Printf("html oracle: %d/%d byte-identical\n", len(cases), len(cases))
	} else {
		fmt.Printf("html oracle: %d/%d failed\n", fails, len(cases))
		os.Exit(1)
	}
}
