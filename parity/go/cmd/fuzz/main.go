// fuzz runs a deterministic dual-implementation fuzz loop: random and mutated inputs are
// parsed by upstream lute and by lutez (C ABI); canonical dumps must match, and neither
// side may panic. This complements the Zig-side crash fuzzer.
package main

import (
	"flag"
	"fmt"
	"math/rand"
	"os"
	"strings"
	"unicode/utf8"

	"github.com/88250/lute/parse"
	parity "lutez/parity"
	"lutez/parity/corpus"
	"lutez/parity/lutez"
)

func opts() *parse.Options {
	o := parse.NewOptions()
	o.GFMTable = false
	o.GFMTaskListItem = false
	o.GFMStrikethrough = false
	o.GFMStrikethrough1 = false
	o.GFMAutoLink = false
	o.Emoji = false
	o.Footnotes = false
	o.InlineMath = false
	o.YamlFrontMatter = false
	o.HeadingID = false
	o.KramdownBlockIAL = false
	return o
}

var seeds = []string{
	"# hi\n\npara *em* **strong** `code`\n",
	"- [ ] a\n- [x] b\n\n1. one\n2. two\n",
	"| a | b |\n|:-:|--:|\n| 1 | 2 |\n",
	"> quote\n> > nested\n\n```go\nfmt.Println()\n```\n",
	"[ref]: /u \"t\"\n\n[ref] and <https://x.y> ![i](/p)\n",
	"foo\\\nbar\\*baz &amp; &#35;\n",
	"a\n---\n\n    indented\n\n<div>\nx\n</div>\n",
	"~~del~~ ~one~ www.example.com https://e.x/y_(z))\n",
}

func main() {
	iterations := flag.Int("n", 3000, "iterations")
	seed := flag.Int64("seed", 1, "PRNG seed")
	flag.Parse()
	rng := rand.New(rand.NewSource(*seed))
	o := opts()
	buf := make([]byte, 0, 1024)

	fails := 0
	for i := 0; i < *iterations; i++ {
		// Valid UTF-8 only: arbitrary-byte crash-robustness is covered by the Zig fuzzer;
		// AST parity is defined on UTF-8 markdown.
		switch rng.Intn(3) {
		case 0:
			n := rng.Intn(120)
			buf = buf[:0]
			for j := 0; j < n; j++ {
				r := rune(rng.Intn(0x2FA1D))
				if r >= 0xD800 && r <= 0xDFFF {
					r = 'x'
				}
				buf = utf8.AppendRune(buf, r)
			}
		default:
			rs := []rune(string(seeds[rng.Intn(len(seeds))]))
			n := rng.Intn(8)
			for j := 0; j < n && len(rs) > 0; j++ {
				switch rng.Intn(3) {
				case 0:
					rs = rs[:rng.Intn(len(rs))]
				case 1:
					rs[rng.Intn(len(rs))] = rune(rng.Intn(0x2FA1D))
				default:
					pos := rng.Intn(len(rs))
					rs = append(rs[:pos], append([]rune{rune(rng.Intn(0x2FA1D))}, rs[pos:]...)...)
				}
			}
			buf = utf8.AppendRune(buf[:0], 0)
			buf = buf[:0]
			for _, r := range rs {
				buf = utf8.AppendRune(buf, r)
			}
		}
		if !utf8.Valid(buf) {
			continue
		}
		luteRoot := parse.Parse("", append([]byte(nil), buf...), o).Root
		parity.Mask(luteRoot)
		want := corpus.Dump(luteRoot)
		gotRoot, err := lutez.Parse(buf, o)
		if err != nil {
			fmt.Printf("iteration %d: lutez error: %v\ninput: %q\n", i, err, buf)
			fails++
			continue
		}
		parity.Mask(gotRoot)
		got := corpus.Dump(gotRoot)
		if got != want {
			fails++
			if fails <= 5 {
				fmt.Printf("iteration %d: AST mismatch\ninput: %q\n", i, buf)
				fmt.Printf("first diff: %s\n", firstDiff(want, got))
			}
		}
	}
	if fails > 0 {
		fmt.Printf("dual fuzz: %d/%d mismatches\n", fails, *iterations)
		os.Exit(1)
	}
	fmt.Printf("dual fuzz: %d/%d iterations match\n", *iterations, *iterations)
}

func firstDiff(a, b string) string {
	al, bl := strings.Split(a, "\n"), strings.Split(b, "\n")
	for i := 0; i < len(al) || i < len(bl); i++ {
		var x, y string
		if i < len(al) {
			x = al[i]
		}
		if i < len(bl) {
			y = bl[i]
		}
		if x != y {
			return fmt.Sprintf("line %d lute=[%s] lutez=[%s]", i, x, y)
		}
	}
	return ""
}
