// Node smoke test for the freestanding WASM module and js/lutez.mjs glue.
import { readFileSync } from "node:fs";
import { Lutez } from "../../js/lutez.mjs";

const path = process.argv[2] ?? new URL("../../zig-out/lib/lutez.wasm", import.meta.url);
const bytes = readFileSync(path);
const module = new WebAssembly.Module(bytes);
const imports = WebAssembly.Module.imports(module);
if (imports.length !== 0) throw new Error(`expected zero imports, got ${JSON.stringify(imports)}`);

const lutez = await Lutez.load(bytes);
if (lutez.abiVersion !== 2) throw new Error(`unexpected ABI ${lutez.abiVersion}`);

const doc = lutez.parse("# hi *em*\n\n- a\n- b\n");
const count = doc.nodeCount();
const ast = doc.ast();
const magic = new TextDecoder().decode(ast.slice(0, 8));
if (magic !== "LUTEAST1") throw new Error(`bad AST magic: ${magic}`);
if (count < 5) throw new Error(`unexpected node count ${count}`);
if (doc.nodeType(0) !== 0) throw new Error(`root is not document: ${doc.nodeType(0)}`);
if (doc.nodeType(1) !== 2) throw new Error(`first child is not heading: ${doc.nodeType(1)}`);
const span = doc.span(1);
if (!span || span[0] !== 0 || span[1] < 4) throw new Error(`bad heading span ${span}`);
doc.free();

let threw = false;
try {
  lutez.parse("\u0000"); // still valid markdown (NUL is replaced), must not throw
} catch (e) {
  threw = true;
}
if (threw) throw new Error("parse of NUL input should not fail");

const empty = lutez.parse("");
if (empty.nodeCount() !== 1) throw new Error("empty document should have one node");
empty.free();

const bom = lutez.parse("\uFEFF- a\n- b\n");
if (bom.nodeType(1) !== 7) throw new Error(`BOM should be stripped, first child ${bom.nodeType(1)}`);
if (bom.span(1)?.[0] !== 3) throw new Error(`BOM list span should start at raw 3, got ${bom.span(1)}`);
bom.free();

console.log(
  `wasm ok: ${bytes.length} bytes, 0 imports, abi ${lutez.abiVersion}, v${lutez.version}, nodes ${count}`,
);
