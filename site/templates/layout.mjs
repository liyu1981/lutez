import { site } from "../config.mjs";

let siteVersion = "0.2";
export function setVersion(v) {
  siteVersion = String(v || "0.2");
}

export const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const logo = `<svg class="logo-mark" viewBox="0 0 32 32" aria-hidden="true">
  <rect x="1.25" y="1.25" width="29.5" height="29.5" rx="8" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".55"/>
  <path d="M10 8.5v15M10 12h6.5a4 4 0 0 1 4 4v1M10 20h6.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" opacity=".65"/>
  <circle cx="10" cy="8.5" r="2.6" fill="currentColor"/>
  <circle cx="10" cy="20" r="2.2" fill="currentColor" opacity=".85"/>
  <circle cx="21" cy="17.5" r="2.2" fill="currentColor" opacity=".85"/>
</svg>`;

function navLink(href, label, active) {
  const isActive = active === label.toLowerCase();
  return `<a class="nav-link${isActive ? " is-active" : ""}" href="${href}"${isActive ? ' aria-current="page"' : ""}>${label}</a>`;
}

export function topnav({ depth = 0, active = "" } = {}) {
  const rel = depth ? "../" : "./";
  const links = [
    navLink(`${rel}docs/`, "Docs", active),
    navLink(`${rel}demo/`, "Demo", active),
    navLink(`${rel}docs/benchmarks.html`, "Benchmarks", active),
  ].join("");
  const repo = site.repoUrl
    ? `<a class="nav-link nav-github" href="${site.repoUrl}" rel="noopener">GitHub<span aria-hidden="true">↗</span></a>`
    : "";
  return `<header class="topbar">
  <div class="topbar-inner">
    <a class="brand" href="${rel}index.html" aria-label="lutez home">${logo}<span>lutez</span><span class="brand-tag">v${siteVersion}</span></a>
    <nav class="nav" aria-label="Main">${links}${repo}</nav>
    <div class="topbar-actions">
      <button class="icon-btn theme-toggle" type="button" aria-label="Toggle color theme" title="Toggle theme">
        <span class="theme-icon" aria-hidden="true"></span>
      </button>
      <button class="icon-btn nav-toggle" type="button" aria-label="Toggle navigation" aria-expanded="false">
        <span aria-hidden="true">☰</span>
      </button>
    </div>
  </div>
</header>`;
}

export function footer(depth = 0) {
  const rel = depth ? "../" : "./";
  return `<footer class="footer">
  <div class="footer-inner">
    <div class="footer-brand">${logo}<div><strong>lutez</strong><span>CommonMark 0.31.2 + GFM · Zig</span></div></div>
    <nav class="footer-links" aria-label="Footer">
      <a href="${rel}docs/">Docs</a>
      <a href="${rel}demo/">Demo</a>
      <a href="${rel}docs/benchmarks.html">Benchmarks</a>
      <a href="${site.upstream}" rel="noopener">Upstream Lute ↗</a>
    </nav>
    <p class="footer-note">${site.license} · ported from Lute v1.7.8 · built with Zig 0.17</p>
  </div>
</footer>`;
}

export function themeScript() {
  return `<script>
  (function () {
    try {
      var stored = localStorage.getItem("lutez-theme");
      var sys = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
      document.documentElement.dataset.theme = stored || sys;
    } catch (e) {}
  })();
  </script>`;
}

export function page({ title, description, body, depth = 0, active = "", bodyClass = "", scripts = "", toc = "" }) {
  const rel = depth ? "../" : "./";
  const fullTitle = title === "lutez" ? title : `${title} · lutez`;
  return `<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(fullTitle)}</title>
<meta name="description" content="${esc(description || site.description)}">
<meta name="color-scheme" content="dark light">
<meta property="og:title" content="${esc(fullTitle)}">
<meta property="og:description" content="${esc(description || site.description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="lutez">
<meta name="twitter:card" content="summary">
<meta name="generator" content="lutez static site">
<link rel="icon" href="${rel}assets/favicon.svg" type="image/svg+xml">
<link rel="alternate" type="text/markdown" href="${rel}llms.txt" title="llms.txt">
<link rel="stylesheet" href="${rel}assets/site.css">
${themeScript()}
</head>
<body class="${bodyClass}">
<a class="skip-link" href="#main">Skip to content</a>
${topnav({ depth, active })}
${body}
${footer(depth)}
${toc}
<script type="module" src="${rel}assets/site.js"></script>
${scripts}
</body>
</html>`;
}

export function docsLayout({ doc, docsList, groups, content, tocHtml, depth = 1 }) {
  const groupsHtml = groups
    .map((group) => {
      const items = docsList
        .filter((d) => d.group === group)
        .map(
          (d) =>
            `<li><a class="side-link${d.slug === doc.slug ? " is-active" : ""}" href="${d.slug}.html"${d.slug === doc.slug ? ' aria-current="page"' : ""}>${esc(d.title)}</a></li>`,
        )
        .join("");
      return `<div class="side-group"><h2>${esc(group)}</h2><ul>${items}</ul></div>`;
    })
    .join("");

  return `<div class="docs-shell">
  <aside class="docs-sidebar" aria-label="Documentation">
    <a class="side-index${doc.slug === "index" ? " is-active" : ""}" href="./">All documentation</a>
    ${groupsHtml}
  </aside>
  <main id="main" class="docs-main">
    <article class="prose">
      ${content}
    </article>
    <nav class="doc-pager" aria-label="Previous and next">
      ${pager(doc, docsList)}
    </nav>
  </main>
  <aside class="docs-toc" aria-label="On this page">
    <div class="toc-inner"><h2>On this page</h2>${tocHtml || '<p class="muted">—</p>'}</div>
  </aside>
</div>`;
}

function pager(doc, list) {
  const i = list.findIndex((d) => d.slug === doc.slug);
  if (i < 0) return "";
  const prev = list[i - 1];
  const next = list[i + 1];
  return `${prev ? `<a class="pager-link prev" href="${prev.slug}.html"><span>Previous</span>${esc(prev.title)}</a>` : "<span></span>"}
  ${next ? `<a class="pager-link next" href="${next.slug}.html"><span>Next</span>${esc(next.title)}</a>` : "<span></span>"}`;
}
