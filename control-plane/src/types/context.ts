// Core types for context intelligence infrastructure

export interface MerkleNode {
  hash: string;
  path: string;
  type: 'file' | 'directory';
  children?: Map<string, MerkleNode>;
  size?: number;
  modified?: number;
}

export interface MerkleTree {
  root: MerkleNode;
  workspace: string;
  commitSha?: string;
  timestamp: number;
  fileCount: number;
}

export interface TreeDiff {
  added: string[];
  modified: string[];
  deleted: string[];
  unchanged: number;
}

export interface ParsedFile {
  filePath: string;
  language: string;
  tree?: any; // Tree-sitter AST
  content?: string;
  symbols: ExtractedSymbol[];
  parseTimeMs?: number;
}

export interface ExtractedSymbol {
  name: string;
  kind: 'function' | 'class' | 'interface' | 'type' | 'variable' | 'method' | 'enum' | 'constant';
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  signature?: string;
  complexity?: number;
  exported: boolean;
  async?: boolean;
  references?: number;
  file?: string;
}

export interface FileMap {
  structure: FileNode[];
  totalFiles: number;
  selectedFiles: number;
  languages: Map<string, number>;
  sizeBytes: number;
}

export interface FileNode {
  name: string;
  path: string;
  type: 'file' | 'directory';
  language?: string;
  size?: number;
  selected: boolean;
  children?: FileNode[];
}

export interface CodeMap {
  functions: FunctionSummary[];
  classes: ClassSummary[];
  interfaces: InterfaceSummary[];
  types: TypeSummary[];
  imports: ImportSummary[];
  exports: ExportSummary[];
  byFile: Map<string, SymbolSummary[]>;
  byKind: Map<string, SymbolSummary[]>;
  totalSymbols: number;
  languages: Map<string, number>;
}

export interface FunctionSummary {
  name: string;
  signature: string;
  file: string;
  line: number;
  complexity: number;
  exported: boolean;
  async: boolean;
  generator?: boolean;
  importanceScore?: number;
}

export interface ClassSummary {
  name: string;
  extends?: string;
  implements?: string[];
  methods: string[];
  properties: string[];
  file: string;
  line: number;
  exported: boolean;
  abstract?: boolean;
  importanceScore?: number;
}

export interface InterfaceSummary {
  name: string;
  extends?: string[];
  properties: PropertySummary[];
  methods: MethodSignature[];
  file: string;
  line: number;
  exported: boolean;
  importanceScore?: number;
}

export interface TypeSummary {
  name: string;
  definition: string;
  file: string;
  line: number;
  exported: boolean;
  importanceScore?: number;
}

export interface PropertySummary {
  name: string;
  type: string;
  optional: boolean;
  readonly?: boolean;
}

export interface MethodSignature {
  name: string;
  signature: string;
  optional?: boolean;
}

export interface ImportSummary {
  source: string;
  specifiers: string[];
  file: string;
  line: number;
}

export interface ExportSummary {
  name: string;
  kind: string;
  file: string;
  line: number;
}

export type SymbolSummary = FunctionSummary | ClassSummary | InterfaceSummary | TypeSummary;

export interface FileContent {
  path: string;
  content: string;
  language: string;
  tokens: number;
}

export interface GeneratedContext {
  fileMap: FileMap;
  codeMap?: CodeMap;
  selectedFiles?: FileContent[];
  metadata: ContextMetadata;
}

export interface ContextMetadata {
  workspace: string;
  timestamp: number;
  commitSha?: string;
  totalTokens: number;
  fileCount: number;
  symbolCount: number;
  parseTimeMs: number;
  cacheHits: number;
  cacheMisses: number;
}

export interface SelectionOptions {
  files?: string[];
  folders?: string[];
  patterns?: string[];
  excludePatterns?: string[];
  useGitignore?: boolean;
  useAiIgnore?: boolean;
  maxFiles?: number;
  maxTokens?: number;
}

export interface SelectionRules {
  maxTokens: number;
  maxFiles: number;
  priorityWeights: {
    exported: number;
    recent: number;
    complex: number;
    referenced: number;
    hasTests: number;
    documented: number;
    entryPoint: number;
  };
  includePatterns: string[];
  excludePatterns: string[];
  workingSetBoost: number;
  recencyDecay: number;
}

export interface WorkingSet {
  openFiles: string[];
  recentlyModified: string[];
  gitChanges: string[];
  currentBranch: string;
}

export interface CacheEntry {
  data: any;
  size: number;
  lastUsed: number;
  hits: number;
}

export interface CacheMetrics {
  hits: number;
  misses: number;
  hitRate: number;
  avgResponseTimeMs: number;
  memoryUsageBytes: number;
}