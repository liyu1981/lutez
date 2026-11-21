#!/usr/bin/env node
// Verify internal links in the built site resolve to files in dist/.
import { readdir, readFile, stat } from "node:fs/promises";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const dist = fileURLToPath(new URL("./dist/", import.meta.url));
const walk = async (dir) => {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(p)));
    else if (entry.name.endsWith(".html")) out.push(p);
  }
  return out;
};
const exists = async (p) => !!(await stat(p).catch(() => null));

const files = await walk(dist);
let broken = 0;
for (const file of files) {
  const html = await readFile(file, "utf8");
  for (const m of html.matchAll(/href="([^"]+)"/g)) {
    const href = m[1];
    if (/^(https?:|mailto:|#|\/\/)/i.test(href)) continue;
    const [pathPart] = href.split("#");
    if (!pathPart) continue;
    const base = dirname(file);
    let target = resolve(base, pathPart);
    if (target.endsWith("/")) target = join(target, "index.html");
    if (await exists(target)) continue;
    // directory targets resolve to index.html
    if (await exists(join(target, "index.html"))) continue;
    broken++;
    console.log(`broken: ${posix.relative(dist, file)} -> ${href}`);
  }
}
if (broken) {
  console.error(`${broken} broken internal link(s)`);
  process.exit(1);
}
console.log(`links ok: ${files.length} pages`);
