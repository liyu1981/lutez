// Canonical AST dump, byte-identical to src/ast/dump.zig.
package corpus

import (
	"encoding/hex"
	"fmt"
	"strings"

	"github.com/88250/lute/ast"
)

// Dump renders the scoped AST fields of root, one line per node.
func Dump(root *ast.Node) string {
	var b strings.Builder
	dumpNode(&b, root, 0)
	return b.String()
}

func hexOf(bs []byte) string {
	if len(bs) == 0 {
		return "-"
	}
	return hex.EncodeToString(bs)
}

func dumpNode(b *strings.Builder, n *ast.Node, depth int) {
	fmt.Fprintf(b, "%d|%s|%s", depth, n.Type.String(), hexOf(n.Tokens))

	switch n.Type {
	case ast.NodeHeading:
		if n.HeadingLevel != 0 {
			fmt.Fprintf(b, "|level=%d", n.HeadingLevel)
		}
		if n.HeadingSetext {
			b.WriteString("|setext=1")
		}
	case ast.NodeCodeBlock:
		if n.IsFencedCodeBlock {
			b.WriteString("|fenced=1")
		}
		if n.CodeBlockFenceChar != 0 {
			fmt.Fprintf(b, "|fence_char=%d", n.CodeBlockFenceChar)
		}
		if n.CodeBlockFenceLen != 0 {
			fmt.Fprintf(b, "|fence_len=%d", n.CodeBlockFenceLen)
		}
		if n.CodeBlockFenceOffset != 0 {
			fmt.Fprintf(b, "|fence_offset=%d", n.CodeBlockFenceOffset)
		}
		if len(n.CodeBlockOpenFence) != 0 {
			fmt.Fprintf(b, "|open_fence=%s", hexOf(n.CodeBlockOpenFence))
		}
		if len(n.CodeBlockInfo) != 0 {
			fmt.Fprintf(b, "|info=%s", hexOf(n.CodeBlockInfo))
		}
		if len(n.CodeBlockCloseFence) != 0 {
			fmt.Fprintf(b, "|close_fence=%s", hexOf(n.CodeBlockCloseFence))
		}
	case ast.NodeHTMLBlock:
		if n.HtmlBlockType != 0 {
			fmt.Fprintf(b, "|html_type=%d", n.HtmlBlockType)
		}
	case ast.NodeList, ast.NodeListItem:
		d := n.ListData
		if d == nil {
			d = &ast.ListData{}
		}
		fmt.Fprintf(b, "|list_typ=%d", d.Typ)
		if d.Tight {
			b.WriteString("|tight=1")
		}
		if d.BulletChar != 0 {
			fmt.Fprintf(b, "|bullet=%d", d.BulletChar)
		}
		if d.Start != 0 {
			fmt.Fprintf(b, "|start=%d", d.Start)
		}
		if d.Delimiter != 0 {
			fmt.Fprintf(b, "|delim=%d", d.Delimiter)
		}
		if d.Padding != 0 {
			fmt.Fprintf(b, "|padding=%d", d.Padding)
		}
		if d.MarkerOffset != 0 {
			fmt.Fprintf(b, "|marker_offset=%d", d.MarkerOffset)
		}
		if d.Checked {
			b.WriteString("|checked=1")
		}
		if len(d.Marker) != 0 {
			fmt.Fprintf(b, "|marker=%s", hexOf(d.Marker))
		}
		if d.Num != 0 {
			fmt.Fprintf(b, "|num=%d", d.Num)
		}
	case ast.NodeTable:
		if len(n.TableAligns) != 0 {
			b.WriteString("|aligns=")
			for i, a := range n.TableAligns {
				if i != 0 {
					b.WriteByte(',')
				}
				fmt.Fprintf(b, "%d", a)
			}
		}
	case ast.NodeTableCell:
		if n.TableCellAlign != 0 {
			fmt.Fprintf(b, "|align=%d", n.TableCellAlign)
		}
	case ast.NodeLink, ast.NodeImage:
		fmt.Fprintf(b, "|link_type=%d", n.LinkType)
		if len(n.LinkRefLabel) != 0 {
			fmt.Fprintf(b, "|label=%s", hexOf(n.LinkRefLabel))
		}
	case ast.NodeTaskListItemMarker:
		if n.TaskListItemMarker != 0 {
			fmt.Fprintf(b, "|marker=%d", n.TaskListItemMarker)
		}
	case ast.NodeCodeSpan:
		if n.CodeMarkerLen != 0 {
			fmt.Fprintf(b, "|code_marker_len=%d", n.CodeMarkerLen)
		}
	}
	b.WriteByte('\n')
	for c := n.FirstChild; c != nil; c = c.Next {
		dumpNode(b, c, depth+1)
	}
}
