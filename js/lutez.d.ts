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
  /** Strip a leading UTF-8 BOM (default true). */
  stripBom?: boolean;
}

export declare class Doc {
  readonly handle: number;
  /** Serialized AST (wire format v2). */
  ast(): Uint8Array;
  nodeCount(): number;
  nodeType(node: number): number;
  /** Raw [start, end) byte offsets in the original Markdown, or null. */
  span(node: number): [number, number] | null;
  extension(node: number): Extension | null;
  free(): void;
}

export type PresetName =
  | "frontmatter"
  | "math"
  | "wikilinks"
  | "tags"
  | "outlinerBlocks"
  | "outlinerKeywords"
  | "opal-note";

export type Extensions =
  | PresetName
  | PresetName[]
  | { presets: PresetName[] }
  | Partial<Record<PresetName, boolean>>
  | number;

export interface Extension {
  kind: number;
  flags: number;
}

export declare class Lutez {
  static load(source: string | URL | Uint8Array): Promise<Lutez>;
  readonly abiVersion: number;
  readonly version: string;
  parse(markdown: string, opts?: LutezOptions | null, extensions?: Extensions | null): Doc;
}

export declare const PRESETS: Record<PresetName, number>;
export declare const NULL_NODE: number;
