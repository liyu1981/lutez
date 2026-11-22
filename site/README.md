# lutez website

Static site for lutez: landing page, generated docs, and a WASM-powered AST playground.
Output is plain HTML/CSS/JS, suitable for GitHub Pages (relative paths only, `.nojekyll`
included).

## Structure

```
site/
├── build.mjs              # static generator (docs + pages + assets)
├── docmap.mjs             # doc slug <-> source path resolution for links
├── llms.mjs               # llms.txt / llms-full.txt generation
├── serve.mjs              # tiny local server with application/wasm
├── config.mjs             # site metadata + docs manifest
├── templates/layout.mjs   # head/nav/footer/docs shell
├── pages/                 # landing, demo, 404 (each its own module)
├── content/docs/          # authored docs (others are pulled from ../doc)
├── assets/
│   ├── site.css           # design system
│   ├── site.js            # theme, nav, tabs, copy, TOC
│   ├── wire.mjs           # wire-format decoder used by the demo
│   ├── examples.mjs       # demo examples (simple → complex)
│   └── demo.mjs           # playground: parse + tree renderer
└── dist/                  # build output (gitignored)
```

Docs pages are generated from Markdown in `content/docs/` and `../doc/`; the manifest lives
in `config.mjs`. Links between docs are rewritten to `.html`, and repository paths become
GitHub links when `LUTEZ_REPO_URL` is set (otherwise they render as inert path chips).

Each build also writes `dist/llms.txt` and `dist/llms-full.txt` per
[llmstxt.org](https://llmstxt.org/): a Markdown index of every doc page with one-line
summaries, plus every page concatenated as one file for single-request context. Links are
absolute when `LUTEZ_SITE_URL` is set (for example `https://you.github.io/lutez`) and
relative to the site root otherwise. Every page `<head>` advertises the index via
`<link rel="alternate" type="text/markdown" href=".../llms.txt">`.

## Develop

The package manager is **pnpm 12.4.2**, pinned via `packageManager` in `package.json`
(`corepack enable` will provision it).

```sh
cd site
pnpm install
pnpm dev           # builds, then serves http://localhost:8080
pnpm build         # builds wasm (zig) + site into dist/
pnpm build:fast    # reuse ../zig-out/lib/lutez.wasm
```

`pnpm build` runs `zig build wasm` from the repository root. The demo fetches
`../wasm/lutez.wasm`; the JS glue is copied from `../js/lutez.mjs`.

## Demo

The playground decodes the wire AST in the browser (`assets/wire.mjs`) and renders a
collapsible tree with node types, tokens and type-specific fields. Examples cover headings
and emphasis up to tables, task lists, HTML blocks, entities and Unicode. Editing the
textarea re-parses after a short debounce; the AST JSON tab is copyable.

## Deploy to GitHub Pages

`.github/workflows/deploy-pages.yml` builds Zig + the site and deploys `site/dist` on pushes to
`main`. It sets `LUTEZ_REPO_URL` from the repository so docs source links work. Enable
**Settings → Pages → Source: GitHub Actions** once in the repository. For a manual deploy,
run the two commands above and publish `site/dist/`.

## Checks

```sh
pnpm check        # syntax-check the generator and browser JS
pnpm check:links  # verify every internal link (HTML, llms.txt) resolves in dist/
```
