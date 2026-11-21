// Decoder for the lutez wire AST (format v1). Mirrors src/ast/wire.zig.
// Produces a plain JS tree for the demo (not part of the public ABI).

const NODE_TYPES = {
  0: "Document", 1: "Paragraph", 2: "Heading", 3: "HeadingC8hMarker", 4: "ThematicBreak",
  5: "Blockquote", 6: "BlockquoteMarker", 7: "List", 8: "ListItem", 9: "HTMLBlock",
  10: "InlineHTML", 11: "CodeBlock", 12: "CodeBlockFenceOpenMarker", 13: "CodeBlockFenceCloseMarker",
  14: "CodeBlockFenceInfoMarker", 15: "CodeBlockCode", 16: "Text", 17: "Emphasis",
  18: "EmA6kOpenMarker", 19: "EmA6kCloseMarker", 20: "EmU8eOpenMarker", 21: "EmU8eCloseMarker",
  22: "Strong", 23: "StrongA6kOpenMarker", 24: "StrongA6kCloseMarker",
  25: "StrongU8eOpenMarker", 26: "StrongU8eCloseMarker", 27: "CodeSpan",
  28: "CodeSpanOpenMarker", 29: "CodeSpanContent", 30: "CodeSpanCloseMarker",
  31: "HardBreak", 32: "SoftBreak", 33: "Link", 34: "Image", 35: "Bang", 36: "OpenBracket",
  37: "CloseBracket", 38: "OpenParen", 39: "CloseParen", 40: "LinkText", 41: "LinkDest",
  42: "LinkTitle", 43: "LinkSpace", 44: "HTMLEntity", 45: "LinkRefDefBlock", 46: "LinkRefDef",
  47: "Less", 48: "Greater",
  100: "TaskListItemMarker", 101: "Strikethrough", 102: "Strikethrough1OpenMarker",
  103: "Strikethrough1CloseMarker", 104: "Strikethrough2OpenMarker", 105: "Strikethrough2CloseMarker",
  106: "Table", 107: "TableHead", 108: "TableRow", 109: "TableCell",
  400: "Backslash", 401: "BackslashContent",
};

const KIND_BY_TYPE = new Map();
for (const t of [0]) KIND_BY_TYPE.set(t, "doc");
for (const t of [1, 2, 4, 5, 7, 8]) KIND_BY_TYPE.set(t, "block");
for (const t of [9, 10]) KIND_BY_TYPE.set(t, "html");
for (const t of [11, 12, 13, 14, 15, 27, 28, 29, 30]) KIND_BY_TYPE.set(t, "code");
for (const t of [3, 6, 18, 19, 20, 21, 23, 24, 25, 26, 28, 30, 35, 36, 37, 38, 39, 43, 47, 48, 102, 103, 104, 105]) KIND_BY_TYPE.set(t, "marker");
for (const t of [33, 34, 40, 41, 42, 45, 46]) KIND_BY_TYPE.set(t, "link");
for (const t of [106, 107, 108, 109]) KIND_BY_TYPE.set(t, "table");
for (const t of [31, 32]) KIND_BY_TYPE.set(t, "break");
for (const t of [400, 401]) KIND_BY_TYPE.set(t, "marker");
for (const t of [44]) KIND_BY_TYPE.set(t, "entity");
for (const t of [16, 17, 22, 101]) KIND_BY_TYPE.set(t, "inline");

const decoder = new TextDecoder("utf-8", { fatal: false });
const ALIGN = ["default", "left", "center", "right"];
const LIST_TYPES = { 0: "unordered", 1: "ordered", 3: "task" };
const LINK_TYPES = { 0: "inline", 1: "ref-def", 2: "autolink", 3: "reference" };

const clean = (s) => s.replace(/\u0000/g, "\uFFFD");

function reader(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let off = 0;
  return {
    get off() { return off; },
    u8() { const v = view.getUint8(off); off += 1; return v; },
    u16() { const v = view.getUint16(off, true); off += 2; return v; },
    u32() { const v = view.getUint32(off, true); off += 4; return v; },
    bytes() { const n = view.getUint32(off, true); off += 4; const v = bytes.subarray(off, off + n); off += n; return v; },
    done() { return off >= bytes.length; },
  };
}

function decodeExt(node, bytes) {
  const r = reader(bytes);
  const f = node.fields;
  const str = (b) => clean(decoder.decode(b));
  switch (node.type) {
    case 2:
      f.level = r.u8();
      if (r.u8()) f.setext = true;
      break;
    case 11: {
      const char = r.u8(); const len = r.u8(); const fenced = r.u8(); r.u8();
      const offset = r.u32();
      const open = str(r.bytes()); const info = str(r.bytes()); const close = str(r.bytes());
      if (char) f.fenceChar = String.fromCharCode(char);
      if (len) f.fenceLen = len;
      if (fenced) f.fenced = true;
      if (offset) f.fenceOffset = offset;
      if (open) f.openFence = open;
      if (info) f.info = info;
      if (close) f.closeFence = close;
      break;
    }
    case 9: f.htmlType = r.u8(); break;
    case 7: case 8: {
      const typ = r.u8(); const tight = r.u8(); const bullet = r.u8(); const delim = r.u8(); const checked = r.u8();
      r.u8(); r.u8(); r.u8();
      const start = r.u32() | 0; const num = r.u32() | 0; const padding = r.u32(); const markerOffset = r.u32();
      const marker = str(r.bytes());
      f.listType = LIST_TYPES[typ] || String(typ);
      if (tight) f.tight = true;
      if (bullet) f.bullet = String.fromCharCode(bullet);
      if (delim) f.delimiter = String.fromCharCode(delim);
      if (start) f.start = start;
      if (num && num !== -1) f.num = num;
      if (padding) f.padding = padding;
      if (markerOffset) f.markerOffset = markerOffset;
      if (checked) f.checked = true;
      if (marker) f.marker = marker;
      break;
    }
    case 33: case 34: {
      const linkType = r.u8();
      const label = str(r.bytes());
      f.linkType = LINK_TYPES[linkType] || String(linkType);
      if (label) f.label = label;
      break;
    }
    case 106: {
      const n = r.u32();
      const aligns = [];
      for (let i = 0; i < n; i++) aligns.push(ALIGN[r.u8()] || "default");
      f.aligns = aligns;
      break;
    }
    case 109: {
      const a = r.u8();
      if (a) f.align = ALIGN[a] || String(a);
      break;
    }
    case 100: {
      const m = r.u8();
      if (m) f.marker = String.fromCharCode(m);
      break;
    }
    case 27: f.codeMarkers = r.u32(); break;
    case 14: { const info = str(r.bytes()); if (info) f.info = info; break; }
    case 12: case 13: f.fenceLen = r.u32(); break;
    default: break;
  }
}

export function decodeAst(bytes) {
  if (!(bytes instanceof Uint8Array)) throw new Error("decodeAst: expected Uint8Array");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = decoder.decode(bytes.subarray(0, 8));
  if (magic !== "LUTEAST1") throw new Error(`bad AST magic: ${magic}`);
  const version = view.getUint32(8, true);
  if (version !== 2) throw new Error(`unsupported wire version ${version}`);
  const count = view.getUint32(16, true);
  const stride = view.getUint32(20, true);
  if (stride !== 56) throw new Error(`unsupported node stride ${stride}`);
  const inputLen = view.getUint32(24, true);
  const poolLen = view.getUint32(28, true);
  const extLen = view.getUint32(32, true);
  const mapLen = view.getUint32(36, true);
  const align8 = (n) => (n + 7) & ~7;
  const nodesOff = 40;
  const extrasOff = align8(nodesOff + count * stride);
  const inputOff = align8(extrasOff + extLen);
  const poolOff = align8(inputOff + inputLen);
  const mapOff = align8(poolOff + poolLen);
  if (mapOff + mapLen > bytes.length) throw new Error("truncated wire AST");
  const pool = bytes.subarray(poolOff, poolOff + poolLen);
  const ABSENT = 0xffffffff;

  const nodes = [];
  for (let i = 0; i < count; i++) {
    const off = nodesOff + i * stride;
    const rec = new DataView(bytes.buffer, bytes.byteOffset + off, stride);
    const type = rec.getUint16(0, true);
    const flags = rec.getUint16(2, true);
    const parent = rec.getUint32(4, true);
    const first = rec.getUint32(8, true);
    const prev = rec.getUint32(16, true);
    const next = rec.getUint32(20, true);
    const tokRef = rec.getUint32(24, true);
    const tokLen = rec.getUint32(28, true);
    const normStart = rec.getUint32(32, true);
    const normEnd = rec.getUint32(36, true);
    const rawStart = rec.getUint32(40, true);
    const rawEnd = rec.getUint32(44, true);
    const extRef = rec.getUint32(48, true);
    const extSize = rec.getUint32(52, true);
    let tokens = "";
    if (tokRef !== ABSENT && tokLen > 0 && tokRef + tokLen <= pool.length) {
      tokens = clean(decoder.decode(pool.subarray(tokRef, tokRef + tokLen)));
    }
    const node = {
      index: i,
      type,
      name: NODE_TYPES[type] || `Unknown(${type})`,
      kind: KIND_BY_TYPE.get(type) || "inline",
      flags,
      tokens,
      fields: {},
      parent: parent === ABSENT ? null : parent,
      prev: prev === ABSENT ? null : prev,
      next: next === ABSENT ? null : next,
      firstChild: first === ABSENT ? null : first,
      children: [],
      depth: 0,
      raw: [rawStart, rawEnd],
      norm: [normStart, normEnd],
      derived: (flags & (1 << 8)) !== 0,
    };
    if (extRef !== ABSENT && extSize > 0 && extRef + extSize <= extLen) {
      try { decodeExt(node, bytes.subarray(extrasOff + extRef, extrasOff + extRef + extSize)); } catch {}
    }
    nodes.push(node);
  }
  for (let i = 0; i < count; i++) {
    const n = nodes[i];
    let child = n.firstChild;
    let guard = 0;
    while (child != null && child < count && guard++ < count) {
      const c = nodes[child];
      c.depth = n.depth + 1;
      n.children.push(child);
      child = c.next;
    }
  }
  // The source map is kept for consumers that need token↔raw conversion.
  const sourceMap = [];
  if (mapLen >= 4) {
    const n = view.getUint32(mapOff, true);
    for (let i = 0; i < n; i++) {
      const off = mapOff + 4 + i * 20;
      sourceMap.push({
        normStart: view.getUint32(off, true),
        normLen: view.getUint32(off + 4, true),
        rawStart: view.getUint32(off + 8, true),
        rawLen: view.getUint32(off + 12, true),
        kind: view.getUint8(off + 16),
      });
    }
  }
  return { count, nodes, root: nodes[0] || null, poolBytes: poolLen, sourceMap };
}

export function toJSON(decoded) {
  const walk = (i) => {
    const n = decoded.nodes[i];
    const out = { type: n.name };
    if (n.tokens) out.tokens = n.tokens;
    if (Object.keys(n.fields).length) out.fields = n.fields;
    if (n.children.length) out.children = n.children.map(walk);
    return out;
  };
  return decoded.root ? walk(0) : null;
}
