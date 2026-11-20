// Package wire decodes the lutez binary AST (format v1) into upstream ast.Node values.
package wire

import (
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/88250/lute/ast"
)

const (
	headerLen  = 40
	nodeStride = 48
	absent     = 0xFFFFFFFF
)

// Decode parses a wire buffer and returns the document root.
func Decode(buf []byte) (*ast.Node, error) {
	if len(buf) < headerLen || string(buf[0:8]) != "LUTEAST1" {
		return nil, errors.New("wire: bad magic")
	}
	version := binary.LittleEndian.Uint32(buf[8:12])
	if version != 1 {
		return nil, fmt.Errorf("wire: unsupported version %d", version)
	}
	count := binary.LittleEndian.Uint32(buf[16:20])
	stride := binary.LittleEndian.Uint32(buf[20:24])
	if stride != nodeStride || count == 0 {
		return nil, errors.New("wire: bad node table")
	}
	inputLen := binary.LittleEndian.Uint32(buf[24:28])
	poolLen := binary.LittleEndian.Uint32(buf[28:32])
	extLen := binary.LittleEndian.Uint32(buf[32:36])
	align := func(n int) int { return (n + 7) &^ 7 }
	nodesOff := headerLen
	extrasOff := align(nodesOff + int(count)*nodeStride)
	inputOff := align(extrasOff + int(extLen))
	poolOff := align(inputOff + int(inputLen))
	if poolOff+int(poolLen) > len(buf) {
		return nil, errors.New("wire: truncated sections")
	}
	nodes := make([]*ast.Node, count)
	for i := 0; i < int(count); i++ {
		off := nodesOff + i*nodeStride
		if off+nodeStride > len(buf) {
			return nil, errors.New("wire: truncated node")
		}
		rec := buf[off : off+nodeStride]
		t := binary.LittleEndian.Uint16(rec[0:2])
		n := &ast.Node{Type: ast.NodeType(t)}
		flags := binary.LittleEndian.Uint16(rec[2:4])
		n.Close = flags&(1<<2) != 0
		n.LastLineBlank = flags&(1<<3) != 0
		n.LastLineChecked = flags&(1<<4) != 0
		n.HeadingSetext = flags&(1<<5) != 0
		n.IsFencedCodeBlock = flags&(1<<6) != 0
		n.TaskListItemChecked = flags&(1<<7) != 0
		tokRef := binary.LittleEndian.Uint32(rec[24:28])
		tokLen := binary.LittleEndian.Uint32(rec[28:32])
		if tokRef != absent {
			if tokRef+tokLen > poolLen {
				return nil, errors.New("wire: token out of range")
			}
			n.Tokens = append([]byte(nil), buf[poolOff+int(tokRef):poolOff+int(tokRef)+int(tokLen)]...)
		}
		extRef := binary.LittleEndian.Uint32(rec[40:44])
		extLen2 := binary.LittleEndian.Uint32(rec[44:48])
		if extRef != absent {
			if extRef+extLen2 > extLen {
				return nil, errors.New("wire: ext out of range")
			}
			if err := decodeExt(n, buf[extrasOff+int(extRef):extrasOff+int(extRef)+int(extLen2)]); err != nil {
				return nil, err
			}
		}
		nodes[i] = n
	}
	link := func(i uint32) *ast.Node {
		if i == absent {
			return nil
		}
		return nodes[i]
	}
	for i := 0; i < int(count); i++ {
		rec := buf[nodesOff+i*nodeStride : nodesOff+i*nodeStride+nodeStride]
		n := nodes[i]
		n.Parent = link(binary.LittleEndian.Uint32(rec[4:8]))
		n.FirstChild = link(binary.LittleEndian.Uint32(rec[8:12]))
		n.LastChild = link(binary.LittleEndian.Uint32(rec[12:16]))
		n.Previous = link(binary.LittleEndian.Uint32(rec[16:20]))
		n.Next = link(binary.LittleEndian.Uint32(rec[20:24]))
	}
	return nodes[0], nil
}

type reader struct {
	b   []byte
	off int
}

func (r *reader) u8() (byte, error) {
	if r.off+1 > len(r.b) {
		return 0, errors.New("wire: ext truncated")
	}
	v := r.b[r.off]
	r.off++
	return v, nil
}

func (r *reader) u32() (uint32, error) {
	if r.off+4 > len(r.b) {
		return 0, errors.New("wire: ext truncated")
	}
	v := binary.LittleEndian.Uint32(r.b[r.off:])
	r.off += 4
	return v, nil
}

func (r *reader) bytes() ([]byte, error) {
	l, err := r.u32()
	if err != nil {
		return nil, err
	}
	if r.off+int(l) > len(r.b) {
		return nil, errors.New("wire: ext bytes out of range")
	}
	v := append([]byte(nil), r.b[r.off:r.off+int(l)]...)
	r.off += int(l)
	return v, nil
}

func decodeExt(n *ast.Node, b []byte) error {
	r := &reader{b: b}
	switch n.Type {
	case ast.NodeHeading:
		lv, err := r.u8()
		if err != nil {
			return err
		}
		n.HeadingLevel = int(lv)
		se, err := r.u8()
		if err != nil {
			return err
		}
		n.HeadingSetext = se != 0
	case ast.NodeCodeBlock:
		ch, err := r.u8()
		if err != nil {
			return err
		}
		fl, err := r.u8()
		if err != nil {
			return err
		}
		fn, err := r.u8()
		if err != nil {
			return err
		}
		if _, err := r.u8(); err != nil {
			return err
		}
		fo, err := r.u32()
		if err != nil {
			return err
		}
		of, err := r.bytes()
		if err != nil {
			return err
		}
		inf, err := r.bytes()
		if err != nil {
			return err
		}
		cf, err := r.bytes()
		if err != nil {
			return err
		}
		n.CodeBlockFenceChar = ch
		n.CodeBlockFenceLen = int(fl)
		n.IsFencedCodeBlock = fn != 0
		n.CodeBlockFenceOffset = int(fo)
		n.CodeBlockOpenFence = of
		n.CodeBlockInfo = inf
		n.CodeBlockCloseFence = cf
	case ast.NodeCodeBlockFenceInfoMarker:
		inf, err := r.bytes()
		if err != nil {
			return err
		}
		n.CodeBlockInfo = inf
	case ast.NodeCodeBlockFenceOpenMarker, ast.NodeCodeBlockFenceCloseMarker:
		fl, err := r.u32()
		if err != nil {
			return err
		}
		n.CodeBlockFenceLen = int(fl)
	case ast.NodeHTMLBlock:
		t, err := r.u8()
		if err != nil {
			return err
		}
		n.HtmlBlockType = int(t)
	case ast.NodeList, ast.NodeListItem:
		d := &ast.ListData{}
		var err error
		if d.Typ, err = readU8Int(r); err != nil {
			return err
		}
		tight, err := r.u8()
		if err != nil {
			return err
		}
		d.Tight = tight != 0
		if d.BulletChar, err = r.u8(); err != nil {
			return err
		}
		if d.Delimiter, err = r.u8(); err != nil {
			return err
		}
		chk, err := r.u8()
		if err != nil {
			return err
		}
		d.Checked = chk != 0
		for i := 0; i < 3; i++ {
			if _, err := r.u8(); err != nil {
				return err
			}
		}
		st, err := r.u32()
		if err != nil {
			return err
		}
		num, err := r.u32()
		if err != nil {
			return err
		}
		pad, err := r.u32()
		if err != nil {
			return err
		}
		mo, err := r.u32()
		if err != nil {
			return err
		}
		marker, err := r.bytes()
		if err != nil {
			return err
		}
		d.Start = int(int32(st))
		d.Num = int(int32(num))
		d.Padding = int(pad)
		d.MarkerOffset = int(mo)
		d.Marker = marker
		n.ListData = d
	case ast.NodeLink, ast.NodeImage:
		lt, err := r.u8()
		if err != nil {
			return err
		}
		n.LinkType = int(lt)
		if n.LinkRefLabel, err = r.bytes(); err != nil {
			return err
		}
	case ast.NodeTable:
		cnt, err := r.u32()
		if err != nil {
			return err
		}
		if r.off+int(cnt) > len(r.b) {
			return errors.New("wire: table aligns out of range")
		}
		al := make([]int, cnt)
		for i := range al {
			al[i] = int(r.b[r.off+i])
		}
		r.off += int(cnt)
		n.TableAligns = al
	case ast.NodeTableCell:
		a, err := r.u8()
		if err != nil {
			return err
		}
		n.TableCellAlign = int(a)
	case ast.NodeTaskListItemMarker:
		m, err := r.u8()
		if err != nil {
			return err
		}
		n.TaskListItemMarker = m
	case ast.NodeCodeSpan:
		ml, err := r.u32()
		if err != nil {
			return err
		}
		n.CodeMarkerLen = int(ml)
	}
	if r.off != len(r.b) {
		return errors.New("wire: ext has trailing bytes")
	}
	return nil
}

func readU8Int(r *reader) (int, error) {
	v, err := r.u8()
	return int(v), err
}
