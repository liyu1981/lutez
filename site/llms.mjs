// llms.txt / llms-full.txt generator (https://llmstxt.org/).
//
// llms.txt is a short Markdown map of the docs for LLM crawlers and agents;
// llms-full.txt inlines the complete Markdown source of every page. Links are
// absolute when LUTEZ_SITE_URL is set and relative to the site root otherwise.
import { posix } from "node:path";
import { makeDocMap, slugifyBasename } from "./docmap.mjs";

const withHash = (href, hash) => (hash ? `${href}#${hash}` : href);

function linkBase(site) {
  return (p) => (site.siteUrl ? `${site.siteUrl}/${p.replace(/^\/+/, "")}` : p);
}

const dirTarget = { demo: "demo/index.html", docs: "docs/index.html" };

// Point relative Markdown links at their generated pages, the demo, or the repository.
function rewriteMdLinks(md, doc, { site, docs }) {
  const docMap = makeDocMap(docs);
  const url = linkBase(site);
  const baseDir = posix.dirname(docMap.repoPath(doc.source));
  return md.replace(/\[([^\]]*)\]\(([^)\s]+)\)/g, (m, label, href) => {
    if (/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i.test(href)) return m;
    const [pathPart, hash = ""] = href.split("#");
    const linked = docMap.get(pathPart);
    if (linked) return `[${label}](${withHash(url(`docs/${linked.slug}.html`), hash)})`;
    const target = dirTarget[slugifyBasename(pathPart)];
    if (target && (pathPart.endsWith("/") || !posix.extname(pathPart))) {
      return `[${label}](${withHash(url(target), hash)})`;
    }
    const resolved = posix.normalize(posix.join(baseDir, pathPart));
    if (site.repoUrl) return `[${label}](${withHash(`${site.repoUrl}/blob/main/${resolved}`, hash)})`;
    const plain = label.replace(/[`*]/g, "").trim();
    if (plain === resolved || posix.basename(plain) === posix.basename(resolved)) return label;
    return `${label} (\`${resolved}\`)`;
  });
}

const stripLeadingH1 = (md) => md.replace(/^\s*#\s+[^\n]*\n+/, "");

export function renderLlmsTxt({ site, docs, docGroups, version, upstreamSha = "" }) {
  const url = linkBase(site);
  const page = (d) => url(`docs/${d.slug}.html`);

  const out = [];

  out.push(`# ${site.name}`);
  out.push("");
  out.push(`> ${site.description}`);
  out.push("");
  out.push(
    [
      `${site.name} parses UTF-8 Markdown into a versioned binary AST (wire format v2) and is`,
      "exposed as a C ABI, a WASM module with JS/TypeScript glue, and a Zig module. Rendering",
      "is out of scope: the caller walks the tree. Dialect constructs (frontmatter, math,",
      "wikilinks, tags, Logseq/Obsidian blocks, TODO/DOING keywords) are opt-in extension",
      "presets that never change the default AST.",
    ].join(" "),
  );
  out.push("");
  out.push(
    `Version ${version}${upstreamSha ? `, ported from Lute v1.7.8 (upstream ${upstreamSha.slice(0, 12)})` : ""}.` +
      ` Licensed under the ${site.license}.` +
      (site.repoUrl ? ` Source: ${site.repoUrl}.` : ""),
  );
  out.push("");
  out.push("Entry points:");
  out.push("");
  out.push("- C: `lutez_parse(md, len, NULL)` → `lutez_doc_ast(doc, &n)` → `lutez_doc_free(doc)` in `include/lutez.h`.");
  out.push('- JS/WASM: `lutez.parse(md, null, presets)` returns a document with an AST accessor and `extension(node)`.');
  out.push("- Wire format: little-endian, index-based node records; see the wire-format page for the layout.");
  out.push("");

  for (const group of docGroups) {
    const items = docs.filter((d) => d.group === group);
    if (!items.length) continue;
    out.push(`## ${group}`);
    out.push("");
    for (const d of items) {
      out.push(`- [${d.title}](${page(d)})${d.summary ? `: ${d.summary}` : ""}`);
    }
    out.push("");
  }

  out.push("## Optional");
  out.push("");
  out.push(`- [Full documentation in one file](${url("llms-full.txt")}): every page below concatenated as Markdown, for single-request context.`);
  out.push(`- [Interactive AST demo](${url("demo/index.html")}): parse Markdown in the browser and inspect the decoded wire AST.`);
  out.push(`- [Upstream Lute](${site.upstream}): the Go implementation lutez is ported from.`);
  out.push("");

  return out.join("\n");
}

export function renderLlmsFullTxt({ site, docs, docGroups, version, read, upstreamSha = "" }) {
  const url = linkBase(site);
  const out = [];

  out.push(`# ${site.name} — full documentation`);
  out.push("");
  out.push(`> ${site.description}`);
  out.push("");
  out.push(
    `Version ${version}${upstreamSha ? `, upstream Lute ${upstreamSha.slice(0, 12)}` : ""}. ` +
      `Generated from the Markdown sources indexed by ${url("llms.txt")}.`,
  );
  out.push("");
  out.push("Contents:");
  out.push("");
  for (const group of docGroups) {
    const items = docs.filter((d) => d.group === group);
    if (!items.length) continue;
    out.push(`- ${group}`);
    for (const d of items) {
      out.push(`  - [${d.title}](#${d.slug})${d.summary ? `: ${d.summary}` : ""}`);
    }
  }
  out.push("");

  for (const d of docs) {
    const md = rewriteMdLinks(stripLeadingH1(read(d.source)), d, { site, docs }).trim();
    out.push(`<a id="${d.slug}"></a>`);
    out.push("");
    out.push(`# ${d.title}`);
    out.push("");
    out.push(md);
    out.push("");
    out.push(`Source: ${url(`docs/${d.slug}.html`)}`);
    out.push("");
    out.push("---");
    out.push("");
  }

  return out.join("\n");
}
