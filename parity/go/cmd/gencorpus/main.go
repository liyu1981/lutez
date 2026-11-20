// gencorpus parses the CommonMark spec examples with the pinned upstream parser and
// writes test/corpus/spec.lzc: a compact corpus of (name, markdown, canonical AST dump).
package main

import (
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/88250/lute/parse"
	"lutez/parity/corpus"
)

type specCase struct {
	name      string
	Markdown  string `json:"markdown"`
	HTML      string `json:"html"`
	Example   int    `json:"example"`
	Section   string `json:"section"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
}

func scopedOptions(gfm bool) *parse.Options {
	o := parse.NewOptions()
	// Out-of-scope extensions must be off so the oracle emits the scoped AST.
	o.Emoji = false
	o.Footnotes = false
	o.InlineMath = false
	o.YamlFrontMatter = false
	o.HeadingID = false
	o.KramdownBlockIAL = false
	o.BlockRef = false
	o.FileAnnotationRef = false
	o.Mark = false
	o.Callout = false
	o.CustomBlock = false
	o.SuperBlock = false
	o.Tag = false
	o.GitConflict = false
	o.Tabs = false
	o.ToC = false
	o.IndentCodeBlock = true
	o.Setext = true
	o.LinkRef = true
	o.DataImage = true
	o.GFMTable = gfm
	o.GFMTaskListItem = gfm
	o.GFMStrikethrough = gfm
	o.GFMStrikethrough1 = gfm
	o.GFMAutoLink = gfm
	o.InlineAsterisk = true
	o.InlineUnderscore = true
	return o
}

func extractGFM(md string) []struct{ md, html string } {
	lines := strings.Split(md, "\n")
	var out []struct{ md, html string }
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		if !strings.HasPrefix(line, "``````") {
			continue
		}
		fenceEnd := strings.IndexFunc(line, func(r rune) bool { return r != '`' })
		if fenceEnd < 0 {
			continue
		}
		fence := line[:fenceEnd]
		info := strings.TrimSpace(line[fenceEnd:])
		if !strings.HasPrefix(info, "example") {
			continue
		}
		// "disabled" marks task-list examples whose reference HTML uses disabled
		// checkboxes; those are in scope. tagfilter is a separate GFM extension we do
		// not implement.
		if label := strings.TrimSpace(strings.TrimPrefix(info, "example")); label == "tagfilter" {
			continue
		}
		i++
		var block []string
		for ; i < len(lines) && strings.TrimSpace(lines[i]) != "."; i++ {
			block = append(block, lines[i])
		}
		i++ // skip "."
		var htmlLines []string
		for ; i < len(lines) && !strings.HasPrefix(strings.TrimSpace(lines[i]), fence); i++ {
			htmlLines = append(htmlLines, lines[i])
		}
		mdText := strings.ReplaceAll(strings.Join(block, "\n")+"\n", "\u2192", "\t")
		out = append(out, struct{ md, html string }{mdText, strings.Join(htmlLines, "\n")})
	}
	return out
}

func main() {
	specPath := flag.String("spec", "../../test/spec/commonmark-spec.json", "spec json")
	outPath := flag.String("out", "../../test/corpus/spec.lzc", "output corpus")
	gfmPath := flag.String("gfm-spec", "", "GFM spec markdown (optional)")
	gfmOut := flag.String("gfm-out", "../../test/corpus/gfm.lzc", "GFM output corpus")
	flag.Parse()

	opts := scopedOptions(false) // CommonMark corpus: GFM extensions off
	gfmOpts := scopedOptions(true)
	gfmOpts.GFMAutoLink = true
	parse.AddAutoLinkDomainSuffix("baz") // mirrors upstream test/gfm_spec_test.go
	type outCase struct{ name, md, ast string }

	writeCorpus := func(cases []specCase, outPath string, opts *parse.Options) {
		out := make([]outCase, 0, len(cases))
		for _, c := range cases {
			tree := parse.Parse("", []byte(c.Markdown), opts)
			out = append(out, outCase{c.name, c.Markdown, corpus.Dump(tree.Root)})
		}
		if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
			panic(err)
		}
		f, err := os.Create(outPath)
		if err != nil {
			panic(err)
		}
		defer f.Close()
		put := func(bs []byte) {
			var hdr [4]byte
			binary.LittleEndian.PutUint32(hdr[:], uint32(len(bs)))
			if _, err := f.Write(hdr[:]); err != nil {
				panic(err)
			}
			if _, err := f.Write(bs); err != nil {
				panic(err)
			}
		}
		if _, err := f.Write([]byte("LZC2")); err != nil {
			panic(err)
		}
		var cnt [4]byte
		binary.LittleEndian.PutUint32(cnt[:], uint32(len(out)))
		if _, err := f.Write(cnt[:]); err != nil {
			panic(err)
		}
		for _, c := range out {
			put([]byte(c.name))
			put([]byte(c.md))
			put([]byte(c.ast))
		}
		fmt.Printf("wrote %s: %d cases\n", outPath, len(out))
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		panic(err)
	}
	var cases []specCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		panic(err)
	}
	for i := range cases {
		cases[i].name = fmt.Sprintf("cm-%d", cases[i].Example)
	}
	writeCorpus(cases, *outPath, opts)

	if *gfmPath != "" {
		gfmRaw, err := os.ReadFile(*gfmPath)
		if err != nil {
			panic(err)
		}
		var gfm []specCase
		for i, e := range extractGFM(string(gfmRaw)) {
			gfm = append(gfm, specCase{name: fmt.Sprintf("gfm-%d", i+1), Markdown: e.md, HTML: e.html})
		}
		writeCorpus(gfm, *gfmOut, gfmOpts)
	}
}
