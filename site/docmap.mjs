// Cross-document link resolution shared by the HTML and llms.txt generators.
//
// Doc sources have machine names (`doc/WIRE_FORMAT.md`) while their slugs are
// human-readable (`wire-format`), and authored docs link to each other with
// either form. Normalize a path's basename to a slug so both spellings match.
import { posix } from "node:path";

export const slugifyBasename = (p) =>
  posix
    .basename(p)
    .replace(/\.[a-z0-9]+$/i, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

// Repo-relative path of a doc's Markdown source (`site/content/docs/x.md` or `doc/X.md`).
export const repoPathOf = (source) =>
  source.startsWith("../") ? posix.normalize(source.replace(/^\.\.\//, "")) : posix.join("site", source);

export function makeDocMap(docs) {
  const byKey = new Map();
  for (const doc of docs) {
    for (const candidate of [doc.slug, slugifyBasename(doc.source), slugifyBasename(doc.title)]) {
      if (candidate && !byKey.has(candidate)) byKey.set(candidate, doc);
    }
  }
  return {
    docs,
    get: (href) => byKey.get(slugifyBasename(href)) || byKey.get(slugifyBasename(href.replace(/\.html$/i, ""))),
    repoPath: repoPathOf,
  };
}
