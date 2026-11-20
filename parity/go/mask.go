// Package parity holds shared helpers for the differential harness.
package parity

import "github.com/88250/lute/ast"

// Mask zeroes fields that are out of scope for lutez. The wire decoder already leaves
// them zero; this function documents and enforces the mask (doc/AST_SCHEMA.md §6).
func Mask(n *ast.Node) {
	for {
		n.ID = ""
		n.Spec = ""
		n.Box = ""
		n.Path = ""
		n.Properties = nil
		n.KramdownIAL = nil
		n.TextMarkType = ""
		n.TextMarkAHref = ""
		n.TextMarkATitle = ""
		n.TextMarkInlineMathContent = ""
		n.TextMarkInlineMemoContent = ""
		n.TextMarkBlockRefID = ""
		n.TextMarkBlockRefSubtype = ""
		n.TextMarkFileAnnotationRefID = ""
		n.TextMarkFlashcardOcclusionID = ""
		n.TextMarkTextContent = ""
		n.AttributeViewID = ""
		n.AttributeViewType = ""
		n.CalloutType = ""
		n.CalloutTitle = ""
		n.CalloutTitleExplicit = false
		n.TabItemTitle = ""
		n.CalloutIcon = ""
		n.CalloutIconType = 0
		n.CustomBlockFenceOffset = 0
		n.CustomBlockInfo = ""
		n.TableCellRich = nil
		n.TableCellContentWidth = 0
		n.TableCellContentMaxWidth = 0
		n.HeadingNormalizedID = ""
		n.FootnotesRefLabel = nil
		n.FootnotesRefId = ""
		n.FootnotesRefs = nil
		n.HtmlEntityTokens = nil
		for c := n.FirstChild; c != nil; c = c.Next {
			Mask(c)
		}
		return
	}
}
