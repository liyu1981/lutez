// lutez WASM glue: load the module and wrap the C-style ABI with a small JS API.
//
//   const lutez = await Lutez.load("zig-out/lib/lutez.wasm");
//   const doc = lutez.parse("# hi\n");
//   const ast = doc.ast();            // Uint8Array (wire format v1)
//   doc.nodeType(0);                  // 0 = document
//   doc.free();
//
// Any call may grow WASM memory: `doc.ast()` and node data create fresh views.

const ABI = 1;
const OPTS_SIZE = 16;
const NULL_NODE = 0xffffffff;

export class Lutez {
  #x;
  #wasm;

  constructor(instance) {
    this.#x = instance.exports;
    this.#wasm = instance;
  }

  static async load(source) {
    let bytes;
    if (source instanceof Uint8Array) {
      bytes = source;
    } else if (typeof source === "string" || source instanceof URL) {
      const isNode = typeof process !== "undefined" && process.versions?.node;
      if (isNode) {
        const { readFile } = await import("node:fs/promises");
        bytes = await readFile(source);
      } else {
        const res = await fetch(source);
        if (!res.ok) throw new Error(`Lutez.load: fetch failed (${res.status})`);
        bytes = new Uint8Array(await res.arrayBuffer());
      }
    } else {
      throw new TypeError("Lutez.load: expected a path, URL, or Uint8Array");
    }
    const module = await WebAssembly.compile(bytes);
    const imports = WebAssembly.Module.imports(module);
    if (imports.length !== 0) {
      throw new Error(`lutez.wasm must be import-free, found ${JSON.stringify(imports)}`);
    }
    const instance = await WebAssembly.instantiate(module, {});
    const self = new Lutez(instance);
    if (self.#x.lutez_abi_version() !== ABI) {
      throw new Error(`unexpected lutez ABI ${self.#x.lutez_abi_version()}`);
    }
    return self;
  }

  get abiVersion() {
    return this.#x.lutez_abi_version();
  }

  get version() {
    const v = this.#x.lutez_version();
    return `${(v >> 16) & 0xff}.${(v >> 8) & 0xff}.${v & 0xff}`;
  }

  #memory() {
    return new Uint8Array(this.#x.memory.buffer);
  }

  #copyIn(bytes) {
    const ptr = this.#x.lutez_alloc(bytes.length);
    if (ptr === 0 && bytes.length !== 0) throw new Error("lutez: out of memory");
    this.#memory().set(bytes, ptr);
    return ptr;
  }

  #error() {
    const packed = this.#x.lutez_last_error_ptr();
    const ptr = Number(packed >> 32n);
    const len = Number(packed & 0xffffffffn);
    return new TextDecoder().decode(this.#memory().slice(ptr, ptr + len));
  }

  #opts(opts) {
    if (opts === undefined || opts === null) return 0;
    const ptr = this.#x.lutez_alloc(OPTS_SIZE);
    if (ptr === 0) throw new Error("lutez: out of memory");
    const view = new DataView(this.#x.memory.buffer, ptr, OPTS_SIZE);
    view.setUint32(0, OPTS_SIZE, true);
    const flags = [
      "gfmTable", "gfmTaskListItem", "gfmStrikethrough", "gfmStrikethrough1",
      "gfmAutoLink", "inlineAsterisk", "inlineUnderscore", "setext",
      "indentCodeBlock", "linkRef", "dataImage",
    ];
    flags.forEach((name, i) => {
      view.setUint8(4 + i, opts[name] === false ? 0 : 1, true);
    });
    return ptr;
  }

  /// Parse UTF-8 markdown; returns a Doc. Throws with the library error message.
  parse(markdown, opts) {
    const md = new TextEncoder().encode(markdown);
    const mdPtr = this.#copyIn(md);
    const optsPtr = this.#opts(opts);
    let handle;
    try {
      handle = this.#x.lutez_parse(mdPtr, md.length, optsPtr) >>> 0;
    } finally {
      if (mdPtr) this.#x.lutez_free(mdPtr, md.length);
      if (optsPtr) this.#x.lutez_free(optsPtr, OPTS_SIZE);
    }
    if (handle === 0xffffffff) throw new Error(`lutez parse failed: ${this.#error()}`);
    return new Doc(this.#x, handle);
  }
}

export class Doc {
  #x;
  #handle;
  #freed = false;

  constructor(x, handle) {
    this.#x = x;
    this.#handle = handle;
  }

  #check() {
    if (this.#freed) throw new Error("lutez: document already freed");
  }

  get handle() {
    return this.#handle;
  }

  /// Serialized AST (wire format v1).
  ast() {
    this.#check();
    const packed = this.#x.lutez_doc_ast(this.#handle);
    const ptr = Number(packed >> 32n);
    const len = Number(packed & 0xffffffffn);
    return new Uint8Array(this.#x.memory.buffer, ptr, len);
  }

  nodeCount() {
    this.#check();
    return this.#x.lutez_node_count(this.#handle) >>> 0;
  }

  nodeType(node) {
    this.#check();
    return this.#x.lutez_node_type(this.#handle, node);
  }

  free() {
    if (this.#freed) return;
    this.#x.lutez_doc_free(this.#handle);
    this.#freed = true;
  }
}

export { NULL_NODE };
