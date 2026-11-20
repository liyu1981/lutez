// Node smoke test for the freestanding WASM module (M0: version/error surface).
// Asserts: zero imports, expected exports, ABI version, stub parse error.
import { readFileSync } from "node:fs";

const path = new URL("../../zig-out/lib/lutez.wasm", import.meta.url);
const bytes = readFileSync(path);
const module = new WebAssembly.Module(bytes);

const imports = WebAssembly.Module.imports(module);
if (imports.length !== 0) {
  throw new Error(`expected zero imports, got ${JSON.stringify(imports)}`);
}

const instance = new WebAssembly.Instance(module, {});
const x = instance.exports;
const required = [
  "memory",
  "lutez_alloc",
  "lutez_free",
  "lutez_parse",
  "lutez_doc_ast",
  "lutez_doc_free",
  "lutez_last_error_ptr",
  "lutez_version",
  "lutez_abi_version",
];
for (const name of required) {
  if (!(name in x)) throw new Error(`missing export: ${name}`);
}

const abi = x.lutez_abi_version();
if (abi !== 1) throw new Error(`unexpected abi version: ${abi}`);

// WASM `u32` exports surface as signed JS numbers: coerce with `>>> 0`.
const handle = x.lutez_parse(0, 0, 0) >>> 0;
if (handle !== 0xffffffff) throw new Error(`expected error handle, got ${handle}`);

const packed = x.lutez_last_error_ptr();
const ptr = Number(packed >> 32n);
const len = Number(packed & 0xffffffffn);
const msg = Buffer.from(new Uint8Array(x.memory.buffer, ptr, len)).toString("utf8");
if (msg !== "not implemented") throw new Error(`unexpected error: ${msg}`);

console.log(`wasm ok: ${bytes.length} bytes, 0 imports, abi ${abi}, err "${msg}"`);
