#!/usr/bin/env node
// Static site builder for lutez. Outputs a GitHub-Pages-ready site in site/dist.
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { marked } from "marked";
import { site, docs, docGroups } from "./config.mjs";
import { page, docsLayout, esc } from "./templates/layout.mjs";
import { renderLanding } from "./pages/index.mjs";
import { renderDemo } from "./pages/demo.mjs";
import { renderNotFound } from "./pages/notfound.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const dist = join(here, "dist");
const skipZig = process.argv.includes("--skip-zig");
const wasmSrc = join(repo, "zig-out/lib/lutez.wasm");

const read = (p) => readFileSync(join(here, p), "utf8");
const version = (readFileSync(join(repo, "build.zig.zon"), "utf8").match(/\.version\s*=\s*"([^"]+)"/) || [])[1] || "0.1.0";
const upstreamSha = (readFileSync(join(repo, "src/types.zig"), "utf8").match(/upstream_sha\s*=\s*"([0-9a-f]{40})"/) || [])[1] || "";

if (!skipZig) {
  console.log("building wasm (zig build wasm)…");
  const r = spawnSync("zig", ["build", "wasm"], { cwd: repo, stdio: "inherit" });
  if (r.status !== 0) {
    console.error("zig build wasm failed; re-run with --skip-zig to use an existing artifact");
    process.exit(r.status || 1);
  }
}
if (!existsSync(wasmSrc)) {
  console.error(`missing ${wasmSrc}; run: zig build wasm`);
  process.exit(1);
}

rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, "assets"), { recursive: true });
mkdirSync(join(dist, "wasm"), { recursive: true });
mkdirSync(join(dist, "docs"), { recursive: true });
mkdirSync(join(dist, "demo"), { recursive: true });

// ---- static assets -------------------------------------------------------
for (const f of ["site.css", "site.js", "wire.mjs", "demo.mjs", "examples.mjs", "favicon.svg"]) {
  cpSync(join(here, "assets", f), join(dist, "assets", f));
}
cpSync(join(repo, "js/lutez.mjs"), join(dist, "assets/lutez.mjs"));
cpSync(wasmSrc, join(dist, "wasm/lutez.wasm"));
writeFileSync(join(dist, ".nojekyll"), "");
writeFileSync(join(dist, "robots.txt"), "User-agent: *\nAllow: /\n");

// ---- markdown -> docs ----------------------------------------------------
const byBasename = new Map(docs.map((d) => [posix.basename(d.source).toLowerCase(), d.slug]));

function slugify(text, used) {
  let base = text
    .replace(/<[^>]+>/g, "")
    .replace(/&[a-z]+;/gi, " ")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "section";
  let slug = base;
  let n = 2;
  while (used.has(slug)) slug = `${base}-${n++}`;
  used.add(slug);
  return slug;
}

function rewriteLinks(html, doc) {
  const key = (href) => href.replace(/&amp;/g, "&");
  return html.replace(/<a\s+([^>]*?)href="([^"]+)"([^>]*)>/g, (m, pre, rawHref, post) => {
    const href = key(rawHref);
    if (/^(https?:|mailto:|#|\/\/)/i.test(href) || /^(\.\.?\/)?(demo|docs|assets|wasm)\b/i.test(href) || /\.html?($|#)/i.test(href)) {
      const ext = /^https?:/i.test(href);
      return `<a ${pre}href="${href}"${post}${ext ? ' rel="noopener"' : ""}>`;
    }
    const [pathPart, hash = ""] = href.split("#");
    const base = posix.basename(pathPart);
    if (pathPart.endsWith(".md") && byBasename.has(base.toLowerCase())) {
      return `<a ${pre}href="${byBasename.get(base.toLowerCase())}.html${hash ? "#" + hash : ""}"${post}>`;
    }
    // Resolve other relative paths against the source doc, then map to the repo.
    const fromRepo = posix.normalize(posix.join("doc", posix.relative("../doc", doc.source), pathPart));
    const repoPath = posix.normalize(posix.join("doc", pathPart));
    const resolved = fromRepo.startsWith("..") ? repoPath : fromRepo;
    if (site.repoUrl) {
      return `<a ${pre}href="${site.repoUrl}/blob/main/${resolved}${hash ? "#" + hash : ""}" rel="noopener"${post}>`;
    }
    const label = m.replace(/^<a\s+[^>]*?>/, "").replace(/<\/a>$/, "");
    return `<span class="path-ref" title="Repository path: ${esc(resolved)}">${label}</span>`;
  });
}

function addHeadingIds(html) {
  const used = new Set();
  const toc = [];
  const out = html.replace(/<h([23])>(.*?)<\/h\1>/g, (m, level, inner) => {
    const id = slugify(inner, used);
    toc.push({ level: Number(level), id, text: inner.replace(/<[^>]+>/g, "") });
    return `<h${level} id="${id}">${inner}<a class="heading-anchor" href="#${id}" aria-hidden="true">#</a></h${level}>`;
  });
  const tocHtml = toc.length
    ? `<ul class="toc-list">${toc
        .map((t) => `<li class="toc-l${t.level}"><a href="#${t.id}">${esc(t.text)}</a></li>`)
        .join("")}</ul>`
    : "";
  return { html: out, tocHtml };
}

function renderDoc(doc) {
  const md = read(doc.source);
  const rendered = marked.parse(md, { gfm: true, breaks: false });
  // The layout renders the page title itself; drop the source document's leading h1.
  const raw = rendered.replace(/^\s*<h1[^>]*>[\s\S]*?<\/h1>\s*/, "");
  const { html, tocHtml } = addHeadingIds(rewriteLinks(raw, doc));
  const content = `<p class="doc-eyebrow">${esc(doc.group)}</p><h1>${esc(doc.title)}</h1>\n${html}`;
  return {
    html,
    tocHtml,
    page: docsLayout({ doc, docsList: docs, groups: docGroups, content, tocHtml }),
  };
}

for (const doc of docs) {
  const out = renderDoc(doc);
  writeFileSync(
    join(dist, "docs", `${doc.slug}.html`),
    page({
      title: doc.title,
      description: doc.summary || site.description,
      body: out.page,
      depth: 1,
      active: "docs",
    }),
  );
}

// docs index
const cards = docGroups
  .map((group) => {
    const items = docs
      .filter((d) => d.group === group)
      .map(
        (d) => `<a class="doc-card" href="${d.slug}.html">
          <h3>${esc(d.title)}</h3>
          <p>${esc(d.summary || "")}</p>
          <span class="doc-card-cta">Read →</span>
        </a>`,
      )
      .join("");
    return `<section class="docs-index-group"><h2>${esc(group)}</h2><div class="doc-grid">${items}</div></section>`;
  })
  .join("");
const docsIndex = `<div class="docs-index">
  <header class="page-head">
    <p class="eyebrow">Documentation</p>
    <h1>Everything you need to embed lutez.</h1>
    <p class="lede">API contracts, the binary AST, parity measurements, porting notes and the release process — all in one place.</p>
  </header>
  ${cards}
</div>`;
writeFileSync(
  join(dist, "docs", "index.html"),
  page({ title: "Documentation", description: "lutez documentation", body: docsIndex, depth: 1, active: "docs", bodyClass: "docs-index-page" }),
);

// ---- landing / demo / 404 ------------------------------------------------
writeFileSync(
  join(dist, "index.html"),
  page({
    title: "lutez",
    description: site.description,
    body: renderLanding({ version, upstreamSha }),
    depth: 0,
    bodyClass: "landing",
    scripts: `<script type="module" src="./assets/site.js"></script>`,
  }),
);
writeFileSync(
  join(dist, "demo", "index.html"),
  page({
    title: "Demo",
    description: "Parse Markdown with the lutez WASM build and inspect the AST live.",
    body: renderDemo(),
    depth: 1,
    active: "demo",
    bodyClass: "demo-page",
    scripts: `<script type="module" src="../assets/demo.mjs"></script>`,
  }),
);
writeFileSync(
  join(dist, "404.html"),
  page({ title: "Not found", description: "Page not found", body: renderNotFound(), depth: 0 }),
);

console.log(`site built → ${dist} (${docs.length} docs, version ${version})`);
