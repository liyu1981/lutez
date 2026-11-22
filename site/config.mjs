// Site configuration. `LUTEZ_REPO_URL` enables source links and the GitHub nav item.
// Example: LUTEZ_REPO_URL=https://github.com/you/lutez npm run build
export const site = {
  name: "lutez",
  tagline: "CommonMark + GFM parser in Zig",
  description:
    "lutez is a CommonMark 0.31.2 + GFM parser written in Zig, ported from Lute. Callable from C and WASM, with a Lute-compatible AST.",
  repoUrl: (process.env.LUTEZ_REPO_URL || "").replace(/\/+$/, ""),
  // Public origin (for example https://you.github.io/lutez). Used for absolute links in
  // llms.txt; without it those links stay relative to the site root.
  siteUrl: (process.env.LUTEZ_SITE_URL || "").replace(/\/+$/, ""),
  upstream: "https://github.com/88250/lute",
  license: "Mulan PSL v2",
};

// Docs are generated from Markdown. Paths are relative to site/.
export const docs = [
  { slug: "overview", summary: "What lutez is, why it exists, and how the pieces fit together.", title: "Overview", group: "Introduction", source: "content/docs/overview.md" },
  { slug: "getting-started", summary: "Build the C library, call it from C/WASM/Zig, and run the test suites.", title: "Getting started", group: "Introduction", source: "content/docs/getting-started.md" },
  { slug: "abi", summary: "The C, WASM, JS and Zig APIs: ownership, errors, threading and versioning.", title: "ABI guide", group: "Reference", source: "../doc/ABI.md" },
  { slug: "wire-format", summary: "Binary AST v1: header, node records, extras and the token pool.", title: "Wire format", group: "Reference", source: "../doc/WIRE_FORMAT.md" },
  { slug: "ast-schema", summary: "The 62 in-scope node types, flags, and per-type payload layouts.", title: "AST schema", group: "Reference", source: "../doc/AST_SCHEMA.md" },
  { slug: "plan", summary: "Scope fence, architecture decisions, milestones and parity gates.", title: "Implementation plan", group: "Project", source: "../doc/PLAN.md" },
  { slug: "benchmarks", summary: "Measured parity, fuzz, sanitizer and performance results.", title: "Benchmarks", group: "Project", source: "../doc/BENCHMARKS.md" },
  { slug: "porting-notes", summary: "Intentional deviations from upstream and known limitations.", title: "Porting notes", group: "Project", source: "../doc/PORTING_NOTES.md" },
  { slug: "release", summary: "Release checklist, artifact matrix and reproducibility checks.", title: "Release process", group: "Project", source: "../doc/RELEASE.md" },
  { slug: "upstream", summary: "Pinned upstream revision and the release-tag bump procedure.", title: "Upstream pin", group: "Project", source: "../doc/UPSTREAM.md" },
  { slug: "extensions", summary: "Optional opal_note dialect presets, extension nodes and payloads.", title: "Extensions", group: "Reference", source: "../doc/EXTENSIONS_DESIGN.md" },
];

export const docGroups = ["Introduction", "Reference", "Project"];
