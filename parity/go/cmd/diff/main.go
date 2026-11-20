// diff is the live L2 differential harness: parse the same markdown with upstream lute
// and lutez (C ABI), mask out-of-scope fields and compare canonical dumps.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/88250/lute/parse"
	parity "lutez/parity"
	"lutez/parity/corpus"
	"lutez/parity/lutez"
)

type specCase struct {
	Markdown string `json:"markdown"`
	Example  int    `json:"example"`
	Section  string `json:"section"`
}

func opts(gfm bool) *parse.Options {
	o := parse.NewOptions()
	o.GFMTable = gfm
	o.GFMTaskListItem = gfm
	o.GFMStrikethrough = gfm
	o.GFMStrikethrough1 = gfm
	o.GFMAutoLink = gfm
	o.Emoji = false
	o.Footnotes = false
	o.InlineMath = false
	o.YamlFrontMatter = false
	o.HeadingID = false
	o.KramdownBlockIAL = false
	return o
}

func firstDiff(a, b string) string {
	al := strings.Split(a, "\n")
	bl := strings.Split(b, "\n")
	for i := 0; i < len(al) || i < len(bl); i++ {
		var x, y string
		if i < len(al) {
			x = al[i]
		}
		if i < len(bl) {
			y = bl[i]
		}
		if x != y {
			return fmt.Sprintf("line %d\n  lute: [%s]\n  lutez:[%s]", i, x, y)
		}
	}
	return ""
}

func main() {
	corpusPath := flag.String("corpus", "../../test/spec/commonmark-spec.json", "spec json")
	filter := flag.String("filter", "", "only cases whose section contains this")
	dashboard := flag.Bool("dashboard", false, "print only the summary")

	raw, err := os.ReadFile(*corpusPath)
	if err != nil {
		panic(err)
	}
	var cases []specCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		panic(err)
	}
	gfm := flag.Bool("gfm", false, "enable GFM extensions")
	flag.Parse()
	o := opts(*gfm)
	fails, shown, ran := 0, 0, 0
	for _, c := range cases {
		if *filter != "" && !strings.Contains(strings.ToLower(c.Section), strings.ToLower(*filter)) {
			continue
		}
		ran++
		luteRoot := parse.Parse("", []byte(c.Markdown), o).Root
		parity.Mask(luteRoot)
		want := corpus.Dump(luteRoot)

		lutezRoot, err := lutez.Parse([]byte(c.Markdown), o)
		if err != nil {
			fails++
			fmt.Printf("FAIL cm-%d: %v\n", c.Example, err)
			continue
		}
		parity.Mask(lutezRoot)
		got := corpus.Dump(lutezRoot)
		if got != want {
			fails++
			if !*dashboard && shown < 20 {
				shown++
				fmt.Printf("FAIL cm-%d\n%s\n", c.Example, firstDiff(want, got))
			}
		}
	}
	if fails == 0 {
		fmt.Printf("differential: %d/%d cases match\n", ran, ran)
	} else {
		fmt.Printf("differential: %d/%d failed\n", fails, ran)
		os.Exit(1)
	}
}
