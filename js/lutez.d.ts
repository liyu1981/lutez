// Type definitions for js/lutez.mjs (WASM glue).
export interface LutezOptions {
  gfmTable?: boolean;
  gfmTaskListItem?: boolean;
  gfmStrikethrough?: boolean;
  gfmStrikethrough1?: boolean;
  gfmAutoLink?: boolean;
  inlineAsterisk?: boolean;
  inlineUnderscore?: boolean;
  setext?: boolean;
  indentCodeBlock?: boolean;
  linkRef?: boolean;
  dataImage?: boolean;
}

export declare class Doc {
  readonly handle: number;
  /** Serialized AST (wire format v1). */
  ast(): Uint8Array;
  nodeCount(): number;
  nodeType(node: number): number;
  free(): void;
}

export declare class Lutez {
  static load(source: string | URL | Uint8Array): Promise<Lutez>;
  readonly abiVersion: number;
  readonly version: string;
  parse(markdown: string, opts?: LutezOptions | null): Doc;
}

export declare const NULL_NODE: number;
