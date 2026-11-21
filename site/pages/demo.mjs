export function renderDemo() {
  return `<main id="main" class="demo-shell">
  <section class="demo-head">
    <div>
      <p class="eyebrow">Playground</p>
      <h1>Parse Markdown, inspect the tree.</h1>
      <p class="lede">Runs the real <code>lutez.wasm</code> build locally. Edit the source, pick an example, or copy the AST as JSON.</p>
    </div>
    <div class="demo-stats" aria-live="polite">
      <div><span>nodes</span><strong id="stat-nodes">—</strong></div>
      <div><span>bytes</span><strong id="stat-bytes">—</strong></div>
      <div><span>parse</span><strong id="stat-ms">—</strong></div>
      <div><span>wire</span><strong id="stat-wire">—</strong></div>
    </div>
  </section>

  <section class="demo-examples" aria-label="Examples">
    <div class="example-bar" id="examples"></div>
  </section>

  <section class="demo-grid">
    <div class="panel editor-panel">
      <div class="panel-head">
        <h2>Markdown</h2>
        <div class="panel-actions">
          <span class="hint">⌘/Ctrl + Enter to parse</span>
          <button class="btn btn-small" id="reset" type="button">Reset</button>
        </div>
      </div>
      <textarea id="editor" spellcheck="false" autocapitalize="off" aria-label="Markdown source"></textarea>
      <div class="status-bar"><span id="status">ready</span><span id="cursor">1:1</span></div>
    </div>

    <div class="panel output-panel">
      <div class="panel-head">
        <div class="tabs" role="tablist">
          <button class="tab is-active" role="tab" aria-selected="true" data-view="tree">Tree</button>
          <button class="tab" role="tab" aria-selected="false" data-view="json">AST JSON</button>
        </div>
        <div class="panel-actions">
          <button class="btn btn-small" id="toggle-extensions" type="button" aria-pressed="false">Ext off</button>
          <button class="btn btn-small" id="toggle-spans" type="button" aria-pressed="true">Spans on</button>
          <button class="btn btn-small" id="expand-all" type="button">Expand</button>
          <button class="btn btn-small" id="collapse-all" type="button">Collapse</button>
          <button class="btn btn-small" id="copy-json" type="button">Copy JSON</button>
        </div>
      </div>
      <div class="view view-tree is-active" id="view-tree">
        <div class="tree-scroll">
          <div class="tree" id="tree" role="tree" aria-label="Parsed AST"></div>
        </div>
        <div class="inspector" id="inspector">
          <p class="muted">Select a node to inspect its fields and tokens.</p>
        </div>
      </div>
      <div class="view view-json" id="view-json">
        <pre class="json-view" id="json"></pre>
      </div>
    </div>
  </section>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><p class="noscript">The demo needs JavaScript and WebAssembly enabled.</p></noscript>
</main>`;
}
