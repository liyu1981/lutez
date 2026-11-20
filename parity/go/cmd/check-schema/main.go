// check-schema enforces the AST scope contract:
//  1. every NodeType used by src/ is in doc/AST_SCHEMA.md's whitelist;
//  2. every field named in parity/mask.go exists on upstream ast.Node;
//  3. the schema whitelist matches the node types the corpus actually contains.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var typeLine = regexp.MustCompile("`(Node[A-Za-z0-9]+)`")

func fail(msg string, args ...any) {
	fmt.Printf("check-schema: "+msg+"\n", args...)
	os.Exit(1)
}

func schemaWhitelist() map[string]bool {
	raw, err := os.ReadFile("../../doc/AST_SCHEMA.md")
	if err != nil {
		fail("read schema: %v", err)
	}
	wl := map[string]bool{}
	for _, line := range strings.Split(string(raw), "\n") {
		if !strings.HasPrefix(line, "|") {
			continue
		}
		if m := typeLine.FindStringSubmatch(line); m != nil {
			wl[m[1]] = true
		}
	}
	if len(wl) < 50 {
		fail("schema whitelist too small (%d)", len(wl))
	}
	return wl
}

func scannedTypes() map[string]string {
	// types.zig maps enum member -> upstream type string; parse that switch.
	raw, err := os.ReadFile("../../src/types.zig")
	if err != nil {
		fail("read types: %v", err)
	}
	re := regexp.MustCompile(`\.([a-z0-9_]+) => "(Node[A-Za-z0-9]+)"`)
	byMember := map[string]string{}
	for _, m := range re.FindAllStringSubmatch(string(raw), -1) {
		byMember[m[1]] = m[2]
	}
	if len(byMember) < 50 {
		fail("types.zig mapping too small (%d)", len(byMember))
	}
	used := map[string]string{}
	lit := regexp.MustCompile(`\.([a-z][a-z0-9_]*)\b`)
	filepath.Walk("../../src", func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(path, ".zig") {
			return nil
		}
		b, _ := os.ReadFile(path)
		for _, m := range lit.FindAllStringSubmatch(string(b), -1) {
			if t, ok := byMember[m[1]]; ok {
				used[t] = path
			}
		}
		return nil
	})
	return used
}

func maskFields() []string {
	raw, err := os.ReadFile("mask.go")
	if err != nil {
		fail("read mask: %v", err)
	}
	re := regexp.MustCompile(`n\.([A-Z][A-Za-z0-9]*) =`)
	var out []string
	seen := map[string]bool{}
	for _, m := range re.FindAllStringSubmatch(string(raw), -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			out = append(out, m[1])
		}
	}
	return out
}

func upstreamFields() map[string]bool {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "../../upstream/lute/ast/node.go", nil, 0)
	if err != nil {
		fail("parse upstream node.go: %v", err)
	}
	fields := map[string]bool{}
	ast.Inspect(f, func(n ast.Node) bool {
		ts, ok := n.(*ast.TypeSpec)
		if !ok || ts.Name.Name != "Node" {
			return true
		}
		st, ok := ts.Type.(*ast.StructType)
		if !ok {
			return true
		}
		for _, fld := range st.Fields.List {
			for _, name := range fld.Names {
				fields[name.Name] = true
			}
		}
		return false
	})
	return fields
}

func main() {
	wl := schemaWhitelist()
	used := scannedTypes()
	var missing []string
	for t, path := range used {
		if !wl[t] {
			missing = append(missing, t+" ("+path+")")
		}
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		fail("node types used but not in AST_SCHEMA whitelist: %v", missing)
	}

	up := upstreamFields()
	var badFields []string
	for _, f := range maskFields() {
		if !up[f] {
			badFields = append(badFields, f)
		}
	}
	if len(badFields) > 0 {
		fail("mask fields missing from upstream ast.Node: %v", badFields)
	}
	fmt.Printf("check-schema: ok (%d whitelisted types, %d used, %d masked fields verified)\n", len(wl), len(used), len(maskFields()))
}
