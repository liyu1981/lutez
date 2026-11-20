// Node smoke test for the freestanding WASM module and js/lutez.mjs glue.
import { readFileSync } from "node:fs";
import { Lutez } from "../../js/lutez.mjs";

const path = process.argv[2] ?? new URL("../../zig-out/lib/lutez.wasm", import.meta.url);
const bytes = readFileSync(path);
const module = new WebAssembly.Module(bytes);
const imports = WebAssembly.Module.imports(module);
if (imports.length !== 0) throw new Error(`expected zero imports, got ${JSON.stringify(imports)}`);

const lutez = await Lutez.load(bytes);
if (lutez.abiVersion !== 1) throw new Error(`unexpected ABI ${lutez.abiVersion}`);

const doc = lutez.parse("# hi *em*\n\n- a\n- b\n");
const count = doc.nodeCount();
const ast = doc.ast();
const magic = new TextDecoder().decode(ast.slice(0, 8));
if (magic !== "LUTEAST1") throw new Error(`bad AST magic: ${magic}`);
if (count < 5) throw new Error(`unexpected node count ${count}`);
if (doc.nodeType(0) !== 0) throw new Error(`root is not document: ${doc.nodeType(0)}`);
if (doc.nodeType(1) !== 2) throw new Error(`first child is not heading: ${doc.nodeType(1)}`);
doc.free();

let threw = false;
try {
  lutez.parse("\u0000"); // still valid markdown (NUL is replaced), must not throw
} catch (e) {
  threw = true;
}
if (threw) throw new Error("parse of NUL input should not fail");

console.log(
  `wasm ok: ${bytes.length} bytes, 0 imports, abi ${lutez.abiVersion}, v${lutez.version}, nodes ${count}`,
);
