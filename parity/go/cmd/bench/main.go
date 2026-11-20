// Go baseline: parse the committed CommonMark corpus with upstream lute.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/88250/lute/parse"
)

type specCase struct {
	Markdown string `json:"markdown"`
}

func main() {
	raw, err := os.ReadFile("../../test/spec/commonmark-spec.json")
	if err != nil {
		panic(err)
	}
	var cases []specCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		panic(err)
	}
	o := parse.NewOptions()
	o.Emoji = false
	o.Footnotes = false
	o.InlineMath = false
	o.YamlFrontMatter = false
	o.HeadingID = false
	o.KramdownBlockIAL = false
	rounds := 20
	best := time.Hour
	var sink int
	var bytes int
	for r := 0; r < rounds; r++ {
		start := time.Now()
		for _, c := range cases {
			t := parse.Parse("", []byte(c.Markdown), o)
			sink += len(t.Root.Tokens) + 1
			bytes += len(c.Markdown)
		}
		if d := time.Since(start); d < best {
			best = d
		}
	}
	fmt.Printf("go baseline: docs=%d best=%.2fms (%.1fus/doc) sink=%d\n", len(cases), float64(best.Microseconds())/1000, float64(best.Microseconds())/float64(len(cases)), sink)
}
