const snippetC = `#include "lutez.h"

lutez_doc *doc = lutez_parse((const uint8_t *)md, len, NULL);
size_t n;
const uint8_t *ast = lutez_doc_ast(doc, &n);   /* wire format v1 */
printf("%u nodes\\n", lutez_node_count(doc));
lutez_doc_free(doc);`;

const snippetJs = `import { Lutez } from "./lutez.mjs";

const lutez = await Lutez.load("lutez.wasm");
const doc = lutez.parse("# hi *em*\\n");
const ast = doc.ast();          // Uint8Array
console.log(doc.nodeCount());
doc.free();`;

const snippetZig = `const lutez = @import("lutez");

var doc = try lutez.parse("# hi\\n", .{});
defer doc.deinit();

// doc.root: *ast_node.Node (arena-owned)`;

const snippetCli = `zig build                 # static + shared lib, header
zig build check           # tests + 652/652 CM + 672/672 GFM
zig build bench           # 0.91 ms for the spec corpus
tools/build-release.sh    # 15 packages + wasm + SHA256SUMS`;

function codeTabs() {
  const tabs = [
    ["C", "c", snippetC],
    ["JS / WASM", "js", snippetJs],
    ["Zig", "zig", snippetZig],
    ["CLI", "sh", snippetCli],
  ];
  return `<div class="code-card" data-tabs>
    <div class="code-tabs" role="tablist">${tabs
      .map(
        ([label, id], i) =>
          `<button class="code-tab${i === 0 ? " is-active" : ""}" role="tab" aria-selected="${i === 0}" data-tab="${id}">${label}</button>`,
      )
      .join("")}</div>
    ${tabs
      .map(
        ([label, id, code], i) =>
          `<pre class="code-panel${i === 0 ? " is-active" : ""}" data-panel="${id}" role="tabpanel"><code class="language-${id}">${code
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")}</code></pre>`,
      )
      .join("")}
  </div>`;
}

const features = [
  ["Lute-compatible AST", "Upstream node types, marker nodes, list data and table aligns — the shape existing Lute consumers already understand.", "◈"],
  ["No runtime, no imports", "A freestanding WASM module with zero imports. No Go runtime, no GC, no wasm_exec.js, no loader shims.", "⬡"],
  ["Arena allocation", "One arena per document. Nodes are pointer-linked during parsing and serialized to an index-based wire tree.", "◎"],
  ["Parity, not vibes", "652/652 CommonMark and 672/672 GFM AST parity, an HTML oracle, a live differential harness and dual fuzzing.", "✓"],
  ["Reentrant C ABI", "Opaque documents, versioned options, thread-local errors and ergonomic node accessors. No panics across FFI.", "⌘"],
  ["Fast by construction", "Small docs average 1.4 µs; the 652-example corpus parses in 0.91 ms — 3.9× faster than the Go upstream.", "↯"],
];

const stats = [
  ["652/652", "CommonMark AST parity"],
  ["672/672", "GFM AST parity"],
  ["652/652", "HTML oracle identical"],
  ["0", "WASM imports"],
];

export function renderLanding({ version, upstreamSha }) {
  return `<main id="main">
  <section class="hero">
    <div class="hero-glow" aria-hidden="true"></div>
    <div class="hero-inner">
      <div class="hero-copy">
        <p class="eyebrow"><span class="dot"></span> CommonMark 0.31.2 + GFM · Zig ${version}</p>
        <h1>Markdown, parsed at<br><span class="grad">native speed.</span></h1>
        <p class="lede">lutez is a C-callable, WASM-ready parser ported from Lute. It produces a versioned binary AST — no renderer, no runtime, no compromises on parity.</p>
        <div class="hero-cta">
          <a class="btn btn-primary" href="./demo/">Try the live demo <span aria-hidden="true">→</span></a>
          <a class="btn btn-ghost" href="./docs/getting-started.html">Get started</a>
        </div>
        <div class="hero-meta">
          <span>v${version}</span><span>upstream ${upstreamSha.slice(0, 7)}</span><span>${"Mulan PSL v2"}</span>
        </div>
      </div>
      <div class="hero-visual" aria-hidden="true">
        <div class="window">
          <div class="window-bar"><span></span><span></span><span></span><em>parse</em></div>
          <div class="window-body">
            <pre class="mini-src"># Built for <em>speed</em>

- [x] arena AST
- [x] zero imports

| backend | time |
|---------|-----:|
| lutez   | 0.91 |
| go      | 3.54 |</pre>
            <div class="mini-tree">
              <div class="mt-row"><span class="badge b-doc">doc</span></div>
              <div class="mt-row l1"><span class="badge b-block">heading</span><span class="mt-tok">level=1</span></div>
              <div class="mt-row l1"><span class="badge b-block">list</span><span class="mt-tok">tight</span></div>
              <div class="mt-row l2"><span class="badge b-inline">task</span><span class="mt-tok">[x]</span></div>
              <div class="mt-row l1"><span class="badge b-table">table</span><span class="mt-tok">aligns=1,3</span></div>
              <div class="mt-row l1"><span class="badge b-wire">wire</span><span class="mt-tok">688 B</span></div>
            </div>
          </div>
        </div>
        <div class="float-chip c1">0 imports</div>
        <div class="float-chip c2">217 KB wasm</div>
      </div>
    </div>
    <div class="stat-strip">
      ${stats.map(([n, label]) => `<div class="stat"><strong>${n}</strong><span>${label}</span></div>`).join("")}
    </div>
  </section>

  <section class="section">
    <header class="section-head">
      <p class="eyebrow">Why lutez</p>
      <h2>A parser you can embed anywhere.</h2>
      <p class="lede">The scope is deliberately narrow: Markdown bytes in, a self-contained AST out. Everything else is the caller’s choice.</p>
    </header>
    <div class="feature-grid">
      ${features
        .map(
          ([title, text, icon]) => `<article class="feature">
            <div class="feature-icon" aria-hidden="true">${icon}</div>
            <h3>${title}</h3>
            <p>${text}</p>
          </article>`,
        )
        .join("")}
    </div>
  </section>

  <section class="section section-split">
    <div class="split-copy">
      <p class="eyebrow">Drop-in</p>
      <h2>Four ways in, one AST.</h2>
      <p class="lede">Static or shared C libraries, a freestanding WASM module with JS and TypeScript glue, or the Zig module directly. The wire format is the same everywhere.</p>
      <ul class="check-list">
        <li>Versioned options struct with upstream defaults</li>
        <li>Opaque document handles; the input is copied for you</li>
        <li><code>lutez_node_*</code> accessors or decode the wire bytes</li>
        <li>Thread-safe parsing, no mutable globals</li>
      </ul>
      <a class="link-arrow" href="./docs/abi.html">Read the ABI guide <span aria-hidden="true">→</span></a>
    </div>
    <div class="split-code">${codeTabs()}</div>
  </section>

  <section class="section">
    <header class="section-head">
      <p class="eyebrow">Pipeline</p>
      <h2>From bytes to a portable tree.</h2>
    </header>
    <div class="pipeline" role="img" aria-label="Markdown bytes flow through a lexer, block parser, inline parser, arena AST, and wire encoder to the C and WASM ABIs.">
      <div class="pipe-step"><span>1</span><strong>Lexer</strong><small>CRLF, NUL, lines</small></div>
      <div class="pipe-arrow">→</div>
      <div class="pipe-step"><span>2</span><strong>Blocks</strong><small>lists, tables, HTML</small></div>
      <div class="pipe-arrow">→</div>
      <div class="pipe-step"><span>3</span><strong>Inlines</strong><small>emphasis, links</small></div>
      <div class="pipe-arrow">→</div>
      <div class="pipe-step"><span>4</span><strong>Arena AST</strong><small>pointer-linked</small></div>
      <div class="pipe-arrow">→</div>
      <div class="pipe-step"><span>5</span><strong>Wire v1</strong><small>index-based, LE</small></div>
      <div class="pipe-arrow">→</div>
      <div class="pipe-step accent"><span>6</span><strong>C / WASM</strong><small>u32 offsets</small></div>
    </div>
    <div class="parity-grid">
      <div class="parity-card"><span class="parity-num">652/652</span><h3>CommonMark</h3><p>AST parity with upstream Lute on the 0.31.2 spec corpus.</p></div>
      <div class="parity-card"><span class="parity-num">672/672</span><h3>GFM</h3><p>Tables, strikethrough, task lists and extended autolinks.</p></div>
      <div class="parity-card"><span class="parity-num">652/652</span><h3>HTML oracle</h3><p>Upstream’s renderer consumes our AST byte-identically.</p></div>
      <div class="parity-card"><span class="parity-num">3.9×</span><h3>Faster</h3><p>0.91 ms vs 3.54 ms for the spec corpus (best of 20).</p></div>
    </div>
  </section>

  <section class="section">
    <header class="section-head">
      <p class="eyebrow">Explore</p>
      <h2>Start with the parts you need.</h2>
    </header>
    <div class="doc-grid">
      <a class="doc-card" href="./docs/getting-started.html"><span class="doc-card-group">Introduction</span><h3>Getting started</h3><p>Build the library, parse from C, and wire up the WASM module.</p><span class="doc-card-cta">Read →</span></a>
      <a class="doc-card" href="./docs/ast-schema.html"><span class="doc-card-group">Reference</span><h3>AST schema</h3><p>The 62 in-scope node types, flags and per-type payloads.</p><span class="doc-card-cta">Read →</span></a>
      <a class="doc-card" href="./docs/wire-format.html"><span class="doc-card-group">Reference</span><h3>Wire format</h3><p>Header, node records, extras and the token pool, byte by byte.</p><span class="doc-card-cta">Read →</span></a>
      <a class="doc-card" href="./demo/"><span class="doc-card-group">Interactive</span><h3>Live demo</h3><p>Edit Markdown and inspect the parsed tree in your browser.</p><span class="doc-card-cta">Open →</span></a>
    </div>
  </section>

  <section class="cta-band">
    <div>
      <h2>Parse it in your browser.</h2>
      <p>The demo runs the same WASM build that ships in the release tarball — zero imports, no server round-trip.</p>
    </div>
    <a class="btn btn-primary" href="./demo/">Open the playground <span aria-hidden="true">→</span></a>
  </section>
</main>`;
}
