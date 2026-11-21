// Interactive WASM playground: parse Markdown and render the wire AST as a tree.
import { Lutez } from "./lutez.mjs";
import { decodeAst, toJSON } from "./wire.mjs";
import { examples } from "./examples.mjs";

const $ = (id) => document.getElementById(id);
const editor = $("editor");
const treeEl = $("tree");
const jsonEl = $("json");
const inspector = $("inspector");
const statusEl = $("status");
const cursorEl = $("cursor");
const examplesEl = $("examples");
const statNodes = $("stat-nodes");
const statBytes = $("stat-bytes");
const statMs = $("stat-ms");
const statWire = $("stat-wire");
const toastEl = $("toast");

const state = {
  lutez: null,
  decoded: null,
  selected: null,
  active: examples[0].id,
  extensions: false,
  expanded: new Set(),
  timer: 0,
  json: "",
};

const encoder = new TextEncoder();
const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function toast(message) {
  toastEl.textContent = message;
  toastEl.classList.add("is-visible");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => toastEl.classList.remove("is-visible"), 1600);
}

function setStatus(text, isError = false) {
  statusEl.textContent = text;
  statusEl.classList.toggle("is-error", isError);
}

function updateCursor() {
  const pos = editor.selectionStart || 0;
  const before = editor.value.slice(0, pos);
  const line = before.split("\n").length;
  const col = pos - before.lastIndexOf("\n");
  cursorEl.textContent = `${line}:${col}`;
}

function fieldChips(fields) {
  return Object.entries(fields)
    .filter(([, v]) => v !== "" && v !== undefined && v !== null && v !== false)
    .map(([k, v]) => `<span class="field-chip">${escapeHtml(k)}=${escapeHtml(Array.isArray(v) ? v.join(",") : v === true ? "1" : v)}</span>`)
    .join("");
}

function nodeRow(node) {
  const hasChildren = node.children.length > 0;
  const expanded = state.expanded.has(node.index);
  const row = document.createElement("div");
  row.className = "node-row";
  row.dataset.index = String(node.index);
  row.style.setProperty("--depth", String(node.depth));
  row.tabIndex = 0;
  row.setAttribute("role", "treeitem");
  row.setAttribute("aria-level", String(node.depth + 1));
  if (hasChildren) row.setAttribute("aria-expanded", String(expanded));
  if (state.selected === node.index) row.classList.add("is-selected");
  const token = node.tokens ? node.tokens.replace(/\n/g, "⏎").slice(0, 120) : "";
  const span = node.derived ? `@${node.raw[0]}~` : `@${node.raw[0]}-${node.raw[1]}`;
  row.innerHTML = `<span class="twisty${hasChildren ? "" : " spacer"}">${hasChildren ? (expanded ? "▾" : "▸") : "·"}</span>
    <span class="badge b-${node.kind}">${escapeHtml(node.name)}</span>
    <span class="field-chip span-chip" title="raw bytes [${node.raw[0]}, ${node.raw[1]})">${span}</span>
    ${token ? `<span class="token" title="${escapeHtml(node.tokens.slice(0, 2000))}">${escapeHtml(token)}</span>` : `<span class="token empty">—</span>`}
    ${fieldChips(node.fields)}`;
  return row;
}

function renderNode(node, parent) {
  const wrap = document.createElement("div");
  wrap.className = "node";
  wrap.dataset.index = String(node.index);
  wrap.appendChild(nodeRow(node));
  if (node.children.length) {
    const kids = document.createElement("div");
    kids.className = "node-children";
    kids.setAttribute("role", "group");
    if (!state.expanded.has(node.index)) kids.classList.add("is-collapsed");
    node.children.forEach((idx) => renderNode(state.decoded.nodes[idx], kids));
    wrap.appendChild(kids);
  }
  parent.appendChild(wrap);
}

function renderTree() {
  treeEl.textContent = "";
  if (!state.decoded?.root) {
    treeEl.innerHTML = `<p class="muted" style="padding:16px">Nothing parsed yet.</p>`;
    return;
  }
  renderNode(state.decoded.root, treeEl);
}

function renderInspector() {
  const node = state.selected == null ? null : state.decoded?.nodes[state.selected];
  if (!node) {
    inspector.innerHTML = `<p class="muted">Select a node to inspect its fields and tokens.</p>`;
    return;
  }
  const rows = [
    ["type", `${node.name} (${node.type})`],
    ["index", node.index],
    ["depth", node.depth],
    ["children", node.children.length],
    ["span", `${node.raw[0]}..${node.raw[1]}${node.derived ? " (derived)" : ""}`],
    ["norm span", `${node.norm[0]}..${node.norm[1]}`],
    ["tokens", node.tokens || "—"],
    ...(node.extension ? [["ext kind", node.extension.kind], ["ext flags", node.extension.flags]] : []),
    ...Object.entries(node.fields).map(([k, v]) => [k, Array.isArray(v) ? v.join(", ") : String(v)]),
  ];
  inspector.innerHTML = `<h3>Node ${node.index}</h3><dl>${rows
    .map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`)
    .join("")}</dl>`;
}

function expandAll() {
  if (!state.decoded) return;
  state.decoded.nodes.forEach((n) => n.children.length && state.expanded.add(n.index));
  renderTree();
  renderInspector();
}

function collapseAll() {
  state.expanded.clear();
  renderTree();
  renderInspector();
}

function defaultExpanded(decoded) {
  const set = new Set();
  const walk = (i) => {
    const n = decoded.nodes[i];
    if (n.children.length && n.depth < 2) {
      set.add(i);
      n.children.forEach(walk);
    }
  };
  walk(0);
  return set;
}

function parseNow() {
  if (!state.lutez) return;
  const md = editor.value;
  const bytes = encoder.encode(md);
  const t0 = performance.now();
  let doc;
  try {
    doc = state.lutez.parse(md, null, state.extensions ? { presets: ["opal-note"] } : null);
    const ast = doc.ast();
    const decoded = decodeAst(ast);
    state.decoded = decoded;
    state.json = JSON.stringify(toJSON(decoded), null, 2);
    statNodes.textContent = String(decoded.count);
    statWire.textContent = `${ast.length} B`;
    statBytes.textContent = `${bytes.length} B`;
    doc.free();
    const ms = performance.now() - t0;
    statMs.textContent = ms < 0.1 ? `${Math.max(1, Math.round(ms * 1000))} µs` : `${ms.toFixed(2)} ms`;
    if (!state.expanded.size) state.expanded = defaultExpanded(decoded);
    if (state.selected == null || state.selected >= decoded.count) state.selected = 0;
    renderTree();
    renderInspector();
    jsonEl.textContent = state.json;
    setStatus(`parsed ${decoded.count} nodes in ${statMs.textContent}`);
  } catch (e) {
    doc?.free?.();
    state.decoded = null;
    state.selected = null;
    state.json = "";
    statNodes.textContent = statBytes.textContent = statMs.textContent = statWire.textContent = "—";
    treeEl.innerHTML = `<div class="tree-error">${escapeHtml(e.message)}</div>`;
    inspector.innerHTML = `<p class="muted">Parse failed.</p>`;
    jsonEl.textContent = "";
    setStatus(e.message, true);
  }
}

function scheduleParse() {
  clearTimeout(state.timer);
  state.timer = setTimeout(parseNow, 160);
}

function setExample(id, updateHash = true) {
  const example = examples.find((e) => e.id === id) || examples[0];
  state.active = example.id;
  state.extensions = example.extensions === true;
  const extButton = $("toggle-extensions");
  extButton.textContent = state.extensions ? "Ext on" : "Ext off";
  extButton.setAttribute("aria-pressed", String(state.extensions));
  state.selected = null;
  state.expanded = new Set();
  editor.value = example.markdown;
  document.querySelectorAll(".example-chip").forEach((b) => b.classList.toggle("is-active", b.dataset.id === example.id));
  if (updateHash) history.replaceState(null, "", `#${example.id}`);
  setStatus(`loaded “${example.label}” example`);
  updateCursor();
  parseNow();
}

function buildExamples() {
  examplesEl.innerHTML = examples
    .map(
      (e) =>
        `<button class="example-chip${e.id === state.active ? " is-active" : ""}" data-id="${e.id}" type="button" title="${escapeHtml(e.difficulty)}">${escapeHtml(e.label)}</button>`,
    )
    .join("");
  examplesEl.addEventListener("click", (ev) => {
    const chip = ev.target.closest(".example-chip");
    if (chip) setExample(chip.dataset.id);
  });
}

function buildTabs() {
  document.querySelectorAll(".tab[data-view]").forEach((tab) => {
    tab.addEventListener("click", () => {
      const view = tab.dataset.view;
      document.querySelectorAll(".tab[data-view]").forEach((t) => {
        const on = t === tab;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", String(on));
      });
      document.querySelectorAll(".view").forEach((v) => v.classList.toggle("is-active", v.id === `view-${view}`));
      if (view === "json") jsonEl.textContent = state.json;
    });
  });
}

function bindTree() {
  treeEl.addEventListener("click", (ev) => {
    const row = ev.target.closest(".node-row");
    if (!row) return;
    const idx = Number(row.dataset.index);
    state.selected = idx;
    if (ev.target.closest(".twisty") && state.decoded.nodes[idx].children.length) {
      if (state.expanded.has(idx)) state.expanded.delete(idx);
      else state.expanded.add(idx);
      renderTree();
    } else {
      treeEl.querySelectorAll(".node-row.is-selected").forEach((r) => r.classList.remove("is-selected"));
      row.classList.add("is-selected");
    }
    renderInspector();
  });
  treeEl.addEventListener("keydown", (ev) => {
    const row = ev.target.closest(".node-row");
    if (!row) return;
    const idx = Number(row.dataset.index);
    if (ev.key === "ArrowRight" && state.decoded.nodes[idx].children.length) {
      state.expanded.add(idx); renderTree();
    } else if (ev.key === "ArrowLeft") {
      state.expanded.delete(idx); renderTree();
    } else if (ev.key === "Enter" || ev.key === " ") {
      ev.preventDefault(); state.selected = idx; renderTree(); renderInspector();
    }
  });
}

async function boot() {
  buildExamples();
  buildTabs();
  bindTree();
  $("expand-all").addEventListener("click", expandAll);
  $("collapse-all").addEventListener("click", collapseAll);
  $("reset").addEventListener("click", () => setExample(state.active, false));
  const extToggle = $("toggle-extensions");
  extToggle.addEventListener("click", () => {
    state.extensions = !state.extensions;
    extToggle.textContent = state.extensions ? "Ext on" : "Ext off";
    extToggle.setAttribute("aria-pressed", String(state.extensions));
    parseNow();
  });
  const spanToggle = $("toggle-spans");
  spanToggle.addEventListener("click", () => {
    const on = treeEl.classList.toggle("no-spans");
    spanToggle.setAttribute("aria-pressed", String(!on));
    spanToggle.textContent = on ? "Spans" : "Spans on";
  });
  $("copy-json").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(state.json || "");
      toast("AST JSON copied");
    } catch {
      toast("Clipboard unavailable");
    }
  });
  editor.addEventListener("input", () => { scheduleParse(); updateCursor(); });
  editor.addEventListener("keyup", updateCursor);
  editor.addEventListener("click", updateCursor);
  editor.addEventListener("keydown", (ev) => {
    if ((ev.metaKey || ev.ctrlKey) && ev.key === "Enter") {
      ev.preventDefault();
      parseNow();
    }
    if (ev.key === "Tab") {
      ev.preventDefault();
      const start = editor.selectionStart;
      editor.setRangeText("  ", start, editor.selectionEnd, "end");
      scheduleParse();
    }
  });

  setStatus("loading wasm…");
  try {
    const wasmUrl = new URL("../wasm/lutez.wasm", import.meta.url);
    state.lutez = await Lutez.load(wasmUrl);
    const fromHash = location.hash.slice(1);
    setExample(examples.some((e) => e.id === fromHash) ? fromHash : examples[0].id, false);
  } catch (e) {
    setStatus(`failed to load wasm: ${e.message}`, true);
    treeEl.innerHTML = `<div class="tree-error">${escapeHtml(e.message)}</div>`;
  }
}

boot();
