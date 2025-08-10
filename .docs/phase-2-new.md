# Phase 2: Context Intelligence Infrastructure

## Executive Summary

Phase 2 implements the core context intelligence infrastructure - a high-performance code analysis and caching system using Merkle trees for change detection and tree-sitter for AST parsing. This phase delivers sub-100ms incremental context generation for repositories with 100K+ files through git-aware caching and intelligent file selection. The system provides both **file maps** (directory structure) and **code maps** (symbol summaries without implementations) following RepoPrompt-style selection rules. This infrastructure is AI-agnostic and integrated directly into the control plane (not as an MCP server), providing REST APIs that any language model or tool can leverage.

## Core Objectives

1. **Merkle Tree Change Detection**: O(log n) diff detection with git commit caching
2. **Tree-sitter AST Parsing**: Multi-language symbol extraction and code analysis
3. **Code Maps Generation**: Symbol summaries with signatures, no implementation details
4. **RepoPrompt-Style Selection**: Intelligent symbol prioritization based on importance
5. **Git-Aware Caching**: Immutable cache keyed by commit SHA
6. **Incremental Updates**: Parse only changed files for instant updates
7. **Token Counting**: Accurate text measurement for context limits
8. **File Selection Engine**: Manual and rule-based file/folder selection

## System Architecture

```
File System Layer
┌─────────────────────────────────────────────────────────┐
│  Working Directory → Git Repository → File Changes      │
└────────────────────┬────────────────────────────────────┘
                     │
Change Detection Layer
┌────────────────────▼────────────────────────────────────┐
│  ┌─────────────────────────────────────────────────┐   │
│  │           Merkle Tree Change Detector           │   │
│  │  • Build hash tree of entire workspace          │   │
│  │  • Compare trees in O(log n) time               │   │
│  │  • Output list of changed files only            │   │
│  └────────────────┬────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────┘
                     │
Parsing Layer
┌────────────────────▼────────────────────────────────────┐
│  ┌─────────────────────────────────────────────────┐   │
│  │           Tree-sitter Parser Engine             │   │
│  │  • Language detection and parser selection      │   │
│  │  • AST generation for changed files only        │   │
│  │  • Symbol extraction (functions, classes, etc)  │   │
│  └────────────────┬────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────┘
                     │
Cache Layer
┌────────────────────▼────────────────────────────────────┐
│  ┌─────────────────────────────────────────────────┐   │
│  │           Git-Aware Cache System                │   │
│  │  • Cache by commit SHA (immutable)              │   │
│  │  • Memory cache for hot data                    │   │
│  │  • SQLite for persistent storage                │   │
│  └────────────────┬────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────┘
                     │
Context Assembly Layer
┌────────────────────▼────────────────────────────────────┐
│  ┌─────────────────────────────────────────────────┐   │
│  │           Context Generation Engine             │   │
│  │  • File selection (manual/rules)                │   │
│  │  • Token counting and optimization              │   │
│  │  • Output: File maps, code maps, content        │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Implementation Components

### Component 1: Merkle Tree System

#### 1.1 Core Data Structures

```typescript
interface MerkleNode {
  hash: string;
  path: string;
  type: 'file' | 'directory';
  children?: Map<string, MerkleNode>;
  size?: number;
  modified?: number;
}

interface MerkleTree {
  root: MerkleNode;
  workspace: string;
  commitSha?: string;
  timestamp: number;
  fileCount: number;
}

interface TreeDiff {
  added: string[];
  modified: string[];
  deleted: string[];
  unchanged: number;
}
```

#### 1.2 Hash Computation

```typescript
class MerkleTreeBuilder {
  async buildTree(workspace: string): Promise<MerkleTree> {
    const root = await this.buildNode(workspace);
    return {
      root,
      workspace,
      commitSha: await this.getGitCommit(workspace),
      timestamp: Date.now(),
      fileCount: this.countFiles(root)
    };
  }
  
  private async buildNode(path: string): Promise<MerkleNode> {
    const stat = await Bun.file(path).stat();
    
    if (stat.isDirectory()) {
      const children = new Map<string, MerkleNode>();
      const entries = await Bun.readdir(path);
      
      // Build child nodes in parallel
      const childPromises = entries
        .filter(e => !this.shouldIgnore(e.name))
        .map(async e => {
          const childPath = path.join(path, e.name);
          const childNode = await this.buildNode(childPath);
          children.set(e.name, childNode);
          return childNode.hash;
        });
      
      const childHashes = await Promise.all(childPromises);
      
      // Directory hash = hash of sorted child hashes
      const dirHash = this.computeHash(childHashes.sort().join(''));
      
      return {
        hash: dirHash,
        path,
        type: 'directory',
        children
      };
    } else {
      // File hash = hash of content
      const content = await Bun.file(path).arrayBuffer();
      const fileHash = this.computeHash(content);
      
      return {
        hash: fileHash,
        path,
        type: 'file',
        size: stat.size,
        modified: stat.mtime
      };
    }
  }
  
  private computeHash(data: string | ArrayBuffer): string {
    const hasher = new Bun.CryptoHasher('sha256');
    hasher.update(data);
    return hasher.digest('hex');
  }
}
```

#### 1.3 Diff Algorithm

```typescript
class MerkleTreeDiffer {
  diff(oldTree: MerkleTree, newTree: MerkleTree): TreeDiff {
    const result: TreeDiff = {
      added: [],
      modified: [],
      deleted: [],
      unchanged: 0
    };
    
    this.compareNodes(oldTree.root, newTree.root, result);
    return result;
  }
  
  private compareNodes(
    oldNode: MerkleNode | undefined,
    newNode: MerkleNode | undefined,
    result: TreeDiff,
    parentPath: string = ''
  ) {
    // Node added
    if (!oldNode && newNode) {
      this.collectAllPaths(newNode, result.added);
      return;
    }
    
    // Node deleted
    if (oldNode && !newNode) {
      this.collectAllPaths(oldNode, result.deleted);
      return;
    }
    
    // Both exist - compare hashes
    if (oldNode && newNode) {
      if (oldNode.hash === newNode.hash) {
        // Unchanged - skip entire subtree (optimization)
        result.unchanged += this.countFiles(oldNode);
        return;
      }
      
      // Hash different
      if (newNode.type === 'file') {
        result.modified.push(newNode.path);
      } else {
        // Directory changed - compare children
        const oldChildren = oldNode.children || new Map();
        const newChildren = newNode.children || new Map();
        
        const allKeys = new Set([...oldChildren.keys(), ...newChildren.keys()]);
        
        for (const key of allKeys) {
          this.compareNodes(
            oldChildren.get(key),
            newChildren.get(key),
            result,
            path.join(parentPath, key)
          );
        }
      }
    }
  }
}
```

### Component 2: Tree-sitter Integration

#### 2.1 Parser Manager

```typescript
interface ParserConfig {
  language: string;
  parser: Parser;
  extensions: string[];
  queries: {
    symbols: Parser.Query;
    imports: Parser.Query;
    tests: Parser.Query;
  };
}

class ParserManager {
  private parsers: Map<string, ParserConfig>;
  
  constructor() {
    this.parsers = new Map();
    this.initializeParsers();
  }
  
  private initializeParsers() {
    // TypeScript/JavaScript
    this.registerParser('typescript', {
      language: 'typescript',
      parser: this.createParser(TypeScript.tsx),
      extensions: ['.ts', '.tsx', '.js', '.jsx'],
      queries: this.loadQueries('typescript')
    });
    
    // Python
    this.registerParser('python', {
      language: 'python',
      parser: this.createParser(Python),
      extensions: ['.py', '.pyi'],
      queries: this.loadQueries('python')
    });
    
    // Rust
    this.registerParser('rust', {
      language: 'rust',
      parser: this.createParser(Rust),
      extensions: ['.rs'],
      queries: this.loadQueries('rust')
    });
    
    // Go
    this.registerParser('go', {
      language: 'go',
      parser: this.createParser(Go),
      extensions: ['.go'],
      queries: this.loadQueries('go')
    });
    
    // Java
    this.registerParser('java', {
      language: 'java',
      parser: this.createParser(Java),
      extensions: ['.java'],
      queries: this.loadQueries('java')
    });
  }
  
  async parseFile(filePath: string): Promise<ParsedFile> {
    const language = this.detectLanguage(filePath);
    if (!language) {
      return { filePath, language: 'unknown', symbols: [] };
    }
    
    const config = this.parsers.get(language)!;
    const content = await Bun.file(filePath).text();
    const tree = config.parser.parse(content);
    
    return {
      filePath,
      language,
      tree,
      content,
      symbols: this.extractSymbols(tree, config.queries.symbols)
    };
  }
}
```

#### 2.2 Symbol Extraction

```typescript
interface ExtractedSymbol {
  name: string;
  kind: 'function' | 'class' | 'interface' | 'type' | 'variable' | 'method';
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  signature?: string;
  complexity?: number;
}

class SymbolExtractor {
  extractSymbols(tree: Parser.Tree, query: Parser.Query): ExtractedSymbol[] {
    const symbols: ExtractedSymbol[] = [];
    const captures = query.captures(tree.rootNode);
    
    for (const capture of captures) {
      const node = capture.node;
      const kind = this.getSymbolKind(capture.name);
      
      if (kind) {
        symbols.push({
          name: this.extractName(node),
          kind,
          line: node.startPosition.row + 1,
          column: node.startPosition.column + 1,
          endLine: node.endPosition.row + 1,
          endColumn: node.endPosition.column + 1,
          signature: this.extractSignature(node),
          complexity: this.calculateComplexity(node)
        });
      }
    }
    
    return symbols;
  }
  
  private calculateComplexity(node: Parser.Node): number {
    let complexity = 1;
    const cursor = node.walk();
    
    // Count decision points
    const decisionTypes = [
      'if_statement',
      'switch_statement',
      'for_statement',
      'while_statement',
      'catch_clause',
      'conditional_expression'
    ];
    
    const visit = () => {
      if (decisionTypes.includes(cursor.nodeType)) {
        complexity++;
      }
      
      if (cursor.gotoFirstChild()) {
        do {
          visit();
        } while (cursor.gotoNextSibling());
        cursor.gotoParent();
      }
    };
    
    visit();
    return complexity;
  }
}
```

### Component 3: Git-Aware Cache

#### 3.1 Cache Schema

```sql
-- Merkle trees by commit
CREATE TABLE merkle_cache (
  workspace TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  tree_data BLOB NOT NULL,
  root_hash TEXT NOT NULL,
  file_count INTEGER,
  created_at INTEGER,
  PRIMARY KEY (workspace, commit_sha)
);

-- Parsed files by content hash
CREATE TABLE file_cache (
  file_path TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  parsed_ast BLOB,
  symbols TEXT, -- JSON array
  language TEXT,
  parse_time_ms REAL,
  created_at INTEGER,
  PRIMARY KEY (file_path, content_hash)
);

-- Code maps by workspace state
CREATE TABLE codemap_cache (
  workspace TEXT NOT NULL,
  state_hash TEXT NOT NULL, -- Hash of all file hashes
  code_map BLOB NOT NULL,
  file_count INTEGER,
  symbol_count INTEGER,
  created_at INTEGER,
  PRIMARY KEY (workspace, state_hash)
);

-- Performance metrics
CREATE TABLE cache_metrics (
  operation TEXT,
  hit_count INTEGER DEFAULT 0,
  miss_count INTEGER DEFAULT 0,
  avg_time_ms REAL,
  last_updated INTEGER
);
```

#### 3.2 Cache Manager

```typescript
class CacheManager {
  private memory: Map<string, CacheEntry>;
  private db: Database;
  private maxMemorySize: number = 100 * 1024 * 1024; // 100MB
  private currentSize: number = 0;
  
  constructor() {
    this.memory = new Map();
    this.db = new Database("context-cache.db");
    this.initializeDatabase();
  }
  
  async getMerkleTree(workspace: string, commitSha: string): Promise<MerkleTree | null> {
    // Check memory cache
    const memKey = `merkle:${workspace}:${commitSha}`;
    const memEntry = this.memory.get(memKey);
    if (memEntry) {
      this.recordHit('merkle_memory');
      return memEntry.data;
    }
    
    // Check disk cache
    const row = this.db.query(
      "SELECT tree_data FROM merkle_cache WHERE workspace = ? AND commit_sha = ?"
    ).get(workspace, commitSha);
    
    if (row) {
      this.recordHit('merkle_disk');
      const tree = JSON.parse(row.tree_data);
      
      // Promote to memory cache
      this.addToMemory(memKey, tree);
      
      return tree;
    }
    
    this.recordMiss('merkle');
    return null;
  }
  
  async saveMerkleTree(workspace: string, commitSha: string, tree: MerkleTree) {
    const memKey = `merkle:${workspace}:${commitSha}`;
    
    // Save to memory
    this.addToMemory(memKey, tree);
    
    // Save to disk
    this.db.run(
      `INSERT OR REPLACE INTO merkle_cache 
       (workspace, commit_sha, tree_data, root_hash, file_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [workspace, commitSha, JSON.stringify(tree), tree.root.hash, tree.fileCount, Date.now()]
    );
  }
  
  async getParsedFile(filePath: string, contentHash: string): Promise<ParsedFile | null> {
    const row = this.db.query(
      "SELECT * FROM file_cache WHERE file_path = ? AND content_hash = ?"
    ).get(filePath, contentHash);
    
    if (row) {
      this.recordHit('file_cache');
      return {
        filePath,
        language: row.language,
        symbols: JSON.parse(row.symbols),
        tree: row.parsed_ast // Could deserialize if needed
      };
    }
    
    this.recordMiss('file_cache');
    return null;
  }
  
  private addToMemory(key: string, data: any) {
    const size = this.estimateSize(data);
    
    // Evict if necessary
    while (this.currentSize + size > this.maxMemorySize && this.memory.size > 0) {
      this.evictLRU();
    }
    
    this.memory.set(key, {
      data,
      size,
      lastUsed: Date.now(),
      hits: 0
    });
    
    this.currentSize += size;
  }
  
  private evictLRU() {
    let oldest: [string, CacheEntry] | null = null;
    
    for (const entry of this.memory.entries()) {
      if (!oldest || entry[1].lastUsed < oldest[1].lastUsed) {
        oldest = entry;
      }
    }
    
    if (oldest) {
      this.memory.delete(oldest[0]);
      this.currentSize -= oldest[1].size;
    }
  }
}
```

### Component 4: RepoPrompt-Style Selection Rules

#### 4.1 Symbol Importance Scoring

```typescript
interface SelectionRules {
  maxTokens: number;
  maxFiles: number;
  priorityWeights: {
    exported: 20;        // Public API surface
    recent: 15;          // Recently modified  
    complex: 10;         // High cyclomatic complexity
    referenced: 10;      // Frequently imported/called
    hasTests: 5;         // Has associated tests
    documented: 5;       // Has documentation
    entryPoint: 25;      // Main/index files
  };
  
  includePatterns: string[];
  excludePatterns: string[];
  
  workingSetBoost: number;  // Boost for files in working set
  recencyDecay: number;      // How much recency matters
}

class SymbolScorer {
  scoreSymbol(symbol: SymbolSummary, rules: SelectionRules): number {
    let score = 0;
    
    // Public API surface is most important
    if (symbol.exported) {
      score += rules.priorityWeights.exported;
    }
    
    // Recently modified symbols likely relevant
    const hoursSinceModified = (Date.now() - symbol.lastModified) / 3600000;
    if (hoursSinceModified < 1) score += rules.priorityWeights.recent;
    else if (hoursSinceModified < 24) score += rules.priorityWeights.recent * 0.5;
    else if (hoursSinceModified < 168) score += rules.priorityWeights.recent * 0.2;
    
    // Complex code needs more attention
    if (symbol.complexity > 10) {
      score += rules.priorityWeights.complex;
    }
    
    // Frequently referenced = important
    score += Math.min(symbol.references * 2, rules.priorityWeights.referenced);
    
    // Entry points are critical
    if (symbol.file.includes('index') || symbol.file.includes('main')) {
      score += rules.priorityWeights.entryPoint;
    }
    
    // Has tests = important
    if (symbol.hasTests) {
      score += rules.priorityWeights.hasTests;
    }
    
    // Documentation bonus
    if (symbol.hasDocComment) {
      score += rules.priorityWeights.documented;
    }
    
    return score;
  }
}
```

#### 4.2 Working Set Tracking

```typescript
interface WorkingSet {
  openFiles: string[];        // Currently open in editor
  recentlyModified: string[]; // Modified in last hour
  gitChanges: string[];       // Files in git diff
  currentBranch: string;      // Active git branch
}

class WorkingSetTracker {
  async getWorkingSet(workspace: string): Promise<WorkingSet> {
    return {
      openFiles: await this.getOpenEditorFiles(),
      recentlyModified: await this.getRecentlyModified(workspace),
      gitChanges: await this.getGitChanges(workspace),
      currentBranch: await this.getCurrentBranch(workspace)
    };
  }
  
  isInWorkingSet(file: string, workingSet: WorkingSet): boolean {
    return workingSet.openFiles.includes(file) ||
           workingSet.recentlyModified.includes(file) ||
           workingSet.gitChanges.includes(file);
  }
}
```

### Component 5: Context Generation Engine

#### 5.1 File Selection

```typescript
interface SelectionOptions {
  files?: string[];
  folders?: string[];
  patterns?: string[];
  excludePatterns?: string[];
  useGitignore?: boolean;
  useAiIgnore?: boolean;
  maxFiles?: number;
  maxTokens?: number;
}

class FileSelector {
  async selectFiles(workspace: string, options: SelectionOptions): Promise<string[]> {
    let files: Set<string> = new Set();
    
    // Manual file selection
    if (options.files) {
      options.files.forEach(f => files.add(f));
    }
    
    // Folder selection
    if (options.folders) {
      for (const folder of options.folders) {
        const folderFiles = await this.getFilesInFolder(folder);
        folderFiles.forEach(f => files.add(f));
      }
    }
    
    // Pattern matching
    if (options.patterns) {
      for (const pattern of options.patterns) {
        const matched = await this.glob(workspace, pattern);
        matched.forEach(f => files.add(f));
      }
    }
    
    // Apply exclusions
    if (options.excludePatterns) {
      files = this.applyExclusions(files, options.excludePatterns);
    }
    
    // Apply .gitignore
    if (options.useGitignore) {
      const gitignore = await this.loadGitignore(workspace);
      files = this.applyGitignore(files, gitignore);
    }
    
    // Apply .aiignore
    if (options.useAiIgnore) {
      const aiignore = await this.loadAiIgnore(workspace);
      files = this.applyAiIgnore(files, aiignore);
    }
    
    // Limit file count
    if (options.maxFiles && files.size > options.maxFiles) {
      return Array.from(files).slice(0, options.maxFiles);
    }
    
    return Array.from(files);
  }
}
```

#### 5.2 Token Counter

```typescript
class TokenCounter {
  // Simple token estimation (not model-specific)
  // Real implementation would use proper tokenizers
  
  estimateTokens(text: string): number {
    // Rough estimate: ~4 characters per token
    return Math.ceil(text.length / 4);
  }
  
  async countFile(filePath: string): Promise<number> {
    const content = await Bun.file(filePath).text();
    return this.estimateTokens(content);
  }
  
  async countFiles(filePaths: string[]): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    
    await Promise.all(
      filePaths.map(async path => {
        const count = await this.countFile(path);
        counts.set(path, count);
      })
    );
    
    return counts;
  }
  
  optimizeForLimit(
    files: Map<string, number>,
    limit: number
  ): string[] {
    // Sort by token count (smallest first for maximum file count)
    const sorted = Array.from(files.entries())
      .sort((a, b) => a[1] - b[1]);
    
    const selected: string[] = [];
    let total = 0;
    
    for (const [file, tokens] of sorted) {
      if (total + tokens <= limit) {
        selected.push(file);
        total += tokens;
      }
    }
    
    return selected;
  }
}
```

#### 5.3 Context Assembly

**Key Distinction: File Maps vs Code Maps**

```typescript
// FILE MAP: Shows directory structure and organization
interface FileMap {
  structure: FileNode[];
  totalFiles: number;
  selectedFiles: number;
  languages: Map<string, number>;
  sizeBytes: number;
}

interface FileNode {
  name: string;
  path: string;
  type: 'file' | 'directory';
  language?: string;
  size?: number;
  selected: boolean;
  children?: FileNode[];
}

// CODE MAP: Shows symbols WITHOUT implementation
// This is what makes context efficient - summaries not full code
interface CodeMap {
  functions: FunctionSummary[];   // Signatures only
  classes: ClassSummary[];         // Structure only
  interfaces: InterfaceSummary[];  // Shape only
  types: TypeSummary[];            // Definitions only
  imports: ImportSummary[];        // Dependencies
  exports: ExportSummary[];        // Public API
}

// CONTEXT OUTPUT: Combines maps with selective file contents
interface GeneratedContext {
  fileMap: FileMap;              // Always included (lightweight)
  codeMap?: CodeMap;              // Optional symbol summaries
  selectedFiles?: FileContent[];  // Full contents when needed
  metadata: ContextMetadata;
}
```

**Context Assembly Strategy**

```typescript
class ContextAssembler {
  async assembleContext(
    workspace: string,
    options: ContextOptions
  ): Promise<GeneratedContext> {
    // Step 1: Generate file map (always included, lightweight)
    const fileMap = await this.generateFileMap(workspace, options);
    
    // Step 2: Generate code map (symbol summaries)
    const codeMap = await this.generateCodeMap(workspace, options);
    
    // Step 3: Decide what files need full content
    const importantFiles = this.selectFilesForFullContent(
      codeMap,
      options.maxTokens
    );
    
    // Step 4: Load only important file contents
    const selectedFiles = await this.loadFileContents(importantFiles);
    
    // Step 5: Optimize for token limit
    const optimized = this.optimizeForTokens(
      fileMap,
      codeMap,
      selectedFiles,
      options.maxTokens
    );
    
    return optimized;
  }
  
  private selectFilesForFullContent(
    codeMap: CodeMap,
    tokenLimit: number
  ): string[] {
    // Strategy: Include full content for:
    // 1. Files with high-importance symbols
    // 2. Entry points (main, index)
    // 3. Files in working set
    // 4. Recently modified files
    // 
    // Use code maps for everything else
    
    const important: string[] = [];
    let estimatedTokens = 0;
    
    // Sort all symbols by importance score
    const allSymbols = [
      ...codeMap.functions,
      ...codeMap.classes,
      ...codeMap.interfaces
    ].sort((a, b) => b.importanceScore - a.importanceScore);
    
    // Take files of top symbols until token limit
    for (const symbol of allSymbols) {
      if (!important.includes(symbol.file)) {
        const fileTokens = await this.estimateFileTokens(symbol.file);
        if (estimatedTokens + fileTokens < tokenLimit * 0.7) {
          important.push(symbol.file);
          estimatedTokens += fileTokens;
        }
      }
    }
    
    return important;
  }
}
```

```typescript
interface GeneratedContext {
  fileMap: FileMap;
  codeMap: CodeMap;
  selectedFiles: FileContent[];
  metadata: ContextMetadata;
}

interface FileMap {
  structure: FileNode[];
  totalFiles: number;
  selectedFiles: number;
  languages: Map<string, number>;
}

interface CodeMap {
  // Symbol summaries WITHOUT implementation details
  functions: FunctionSummary[];
  classes: ClassSummary[];
  interfaces: InterfaceSummary[];
  types: TypeSummary[];
  imports: ImportSummary[];
  exports: ExportSummary[];
  
  // Organization
  byFile: Map<string, SymbolSummary[]>;
  byKind: Map<string, SymbolSummary[]>;
  
  // Metadata
  totalSymbols: number;
  languages: Map<string, number>;
}

interface FunctionSummary {
  name: string;
  signature: string;  // Just the function signature, no body
  file: string;
  line: number;
  complexity: number;
  exported: boolean;
  async: boolean;
  generator: boolean;
}

interface ClassSummary {
  name: string;
  extends?: string;
  implements?: string[];
  methods: string[];  // Just method names/signatures
  properties: string[];  // Just property names/types
  file: string;
  line: number;
  exported: boolean;
}

interface InterfaceSummary {
  name: string;
  extends?: string[];
  properties: PropertySummary[];
  methods: MethodSignature[];
  file: string;
  line: number;
  exported: boolean;
}

interface TypeSummary {
  name: string;
  definition: string;  // Type alias definition
  file: string;
  line: number;
  exported: boolean;
}

interface FileContent {
  path: string;
  content: string;
  language: string;
  tokens: number;
}

interface ContextMetadata {
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

class ContextGenerator {
  private merkleBuilder: MerkleTreeBuilder;
  private merkleDigger: MerkleTreeDiffer;
  private parserManager: ParserManager;
  private cacheManager: CacheManager;
  private fileSelector: FileSelector;
  private tokenCounter: TokenCounter;
  
  async generateContext(
    workspace: string,
    options: SelectionOptions
  ): Promise<GeneratedContext> {
    const startTime = performance.now();
    
    // Step 1: Build/retrieve Merkle tree
    const currentTree = await this.getCurrentTree(workspace);
    
    // Step 2: Get changed files if we have a previous tree
    const changedFiles = await this.getChangedFiles(workspace, currentTree);
    
    // Step 3: Parse changed files only
    const parsedFiles = await this.parseFiles(changedFiles);
    
    // Step 4: Select files based on options
    const selectedPaths = await this.fileSelector.selectFiles(workspace, options);
    
    // Step 5: Build file map
    const fileMap = this.buildFileMap(currentTree, selectedPaths);
    
    // Step 6: Build code map from parsed files
    const codeMap = this.buildCodeMap(parsedFiles, selectedPaths);
    
    // Step 7: Load file contents
    const selectedFiles = await this.loadFileContents(selectedPaths);
    
    // Step 8: Generate metadata
    const metadata: ContextMetadata = {
      workspace,
      timestamp: Date.now(),
      commitSha: currentTree.commitSha,
      totalTokens: selectedFiles.reduce((sum, f) => sum + f.tokens, 0),
      fileCount: selectedFiles.length,
      symbolCount: codeMap.symbols.length,
      parseTimeMs: performance.now() - startTime,
      cacheHits: this.cacheManager.getMetrics().hits,
      cacheMisses: this.cacheManager.getMetrics().misses
    };
    
    return {
      fileMap,
      codeMap,
      selectedFiles,
      metadata
    };
  }
  
  private async getCurrentTree(workspace: string): Promise<MerkleTree> {
    const commitSha = await this.getGitCommit(workspace);
    
    if (commitSha) {
      // Try to load cached tree for this commit
      const cached = await this.cacheManager.getMerkleTree(workspace, commitSha);
      if (cached) {
        return cached;
      }
    }
    
    // Build new tree
    const tree = await this.merkleBuilder.buildTree(workspace);
    
    // Cache it if we have a commit
    if (commitSha) {
      await this.cacheManager.saveMerkleTree(workspace, commitSha, tree);
    }
    
    return tree;
  }
  
  private async getChangedFiles(
    workspace: string,
    currentTree: MerkleTree
  ): Promise<string[]> {
    // Get previous tree (from last known commit or cache)
    const previousTree = await this.getPreviousTree(workspace);
    
    if (!previousTree) {
      // No previous tree - all files are "changed"
      return this.getAllFiles(currentTree);
    }
    
    // Diff trees to find changed files
    const diff = this.merkleDigger.diff(previousTree, currentTree);
    
    return [...diff.added, ...diff.modified];
  }
}
```

### Component 6: Incremental Updates

```typescript
class IncrementalUpdater {
  private fileWatcher: FSWatcher;
  private updateQueue: Set<string>;
  private updateTimer: Timer | null = null;
  
  constructor(
    private workspace: string,
    private contextGenerator: ContextGenerator
  ) {
    this.updateQueue = new Set();
    this.setupWatcher();
  }
  
  private setupWatcher() {
    this.fileWatcher = watch(this.workspace, {
      recursive: true,
      persistent: true
    });
    
    this.fileWatcher.on('change', (eventType, filename) => {
      if (filename && this.shouldProcess(filename)) {
        this.queueUpdate(filename);
      }
    });
  }
  
  private queueUpdate(filename: string) {
    this.updateQueue.add(filename);
    
    // Debounce updates
    if (this.updateTimer) {
      clearTimeout(this.updateTimer);
    }
    
    this.updateTimer = setTimeout(() => {
      this.processUpdates();
    }, 100);
  }
  
  private async processUpdates() {
    const files = Array.from(this.updateQueue);
    this.updateQueue.clear();
    
    console.log(`Processing incremental updates for ${files.length} files`);
    
    // Invalidate cache for changed files
    for (const file of files) {
      await this.cacheManager.invalidateFile(file);
    }
    
    // Re-parse changed files
    const parsed = await this.parserManager.parseFiles(files);
    
    // Update code maps incrementally
    await this.updateCodeMaps(parsed);
    
    // Notify listeners
    this.emit('context-updated', {
      changedFiles: files,
      timestamp: Date.now()
    });
  }
}
```

## Performance Requirements

### Benchmarks

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Initial parse (10K files) | < 5s | Time to generate first context |
| Incremental update (1 file) | < 100ms | Time to update after file save |
| Merkle tree diff (100K files) | < 50ms | Time to find changed files |
| Cache retrieval | < 10ms | Time to load from cache |
| Context assembly (100 files) | < 500ms | Time to build final context |

### Memory Limits

- Maximum memory cache: 100MB
- Maximum AST cache: 50MB  
- Maximum SQLite cache: 1GB
- File size limit: 10MB per file

## Testing Strategy

### Unit Tests

```typescript
describe("MerkleTree", () => {
  test("builds tree correctly", async () => {
    const tree = await builder.buildTree("./test-workspace");
    expect(tree.root.type).toBe("directory");
    expect(tree.fileCount).toBeGreaterThan(0);
  });
  
  test("detects file changes", async () => {
    const tree1 = await builder.buildTree("./test-workspace");
    await Bun.write("./test-workspace/test.txt", "modified");
    const tree2 = await builder.buildTree("./test-workspace");
    
    const diff = differ.diff(tree1, tree2);
    expect(diff.modified).toContain("./test-workspace/test.txt");
  });
  
  test("hash stability", async () => {
    const tree1 = await builder.buildTree("./test-workspace");
    const tree2 = await builder.buildTree("./test-workspace");
    expect(tree1.root.hash).toBe(tree2.root.hash);
  });
});

describe("TreeSitter", () => {
  test("parses TypeScript", async () => {
    const result = await parser.parseFile("./test.ts");
    expect(result.language).toBe("typescript");
    expect(result.symbols.length).toBeGreaterThan(0);
  });
  
  test("extracts symbols correctly", async () => {
    const code = `
      function testFunc() {}
      class TestClass {}
      interface TestInterface {}
    `;
    const symbols = await extractor.extract(code, "typescript");
    expect(symbols).toHaveLength(3);
  });
});

describe("Cache", () => {
  test("caches by commit SHA", async () => {
    const tree = await builder.buildTree("./test");
    await cache.saveMerkleTree("./test", "abc123", tree);
    
    const retrieved = await cache.getMerkleTree("./test", "abc123");
    expect(retrieved?.root.hash).toBe(tree.root.hash);
  });
  
  test("LRU eviction", async () => {
    // Fill cache to limit
    for (let i = 0; i < 1000; i++) {
      await cache.add(`key${i}`, `data${i}`);
    }
    
    // Check oldest entries were evicted
    expect(await cache.get("key0")).toBeNull();
    expect(await cache.get("key999")).toBeDefined();
  });
});
```

### Integration Tests

```typescript
describe("Context Generation", () => {
  test("generates context for large repo", async () => {
    const start = performance.now();
    const context = await generator.generateContext("./large-repo", {
      patterns: ["src/**/*.ts"],
      maxTokens: 100000
    });
    const elapsed = performance.now() - start;
    
    expect(elapsed).toBeLessThan(5000);
    expect(context.metadata.fileCount).toBeGreaterThan(0);
    expect(context.metadata.totalTokens).toBeLessThanOrEqual(100000);
  });
  
  test("incremental updates", async () => {
    // Generate initial context
    await generator.generateContext("./test-repo", {});
    
    // Modify a file
    await Bun.write("./test-repo/test.ts", "// modified");
    
    // Generate again - should be fast
    const start = performance.now();
    await generator.generateContext("./test-repo", {});
    const elapsed = performance.now() - start;
    
    expect(elapsed).toBeLessThan(100);
  });
});
```

## Architecture Integration

### Not an MCP Server

Phase 2 is **NOT** implemented as a Model Context Protocol (MCP) server. Instead, it's integrated directly into the control plane as a service layer. MCP servers come later in the architecture (Phase 3+) for specific AI integrations.

### Integration with Control Plane

```typescript
// control-plane/src/services/context-service.ts
export class ContextService {
  private merkleTreeBuilder: MerkleTreeBuilder;
  private parserManager: ParserManager;
  private codeMapGenerator: CodeMapGenerator;
  private selectionEngine: SelectionEngine;
  private cacheManager: CacheManager;
  
  constructor() {
    // Initialize all components
    // This runs INSIDE the control plane, not as separate server
  }
  
  // REST API exposed by control plane
  async handleContextRequest(req: Request): Promise<Response> {
    // This is called by control plane's HTTP server
    // Not a separate service
  }
}
```

## Implementation Timeline

| Day | Component | Deliverables |
|-----|-----------|--------------|
| 1-2 | Merkle Trees | Hash computation, tree building, diff algorithm |
| 3-4 | Git Integration | Commit detection, git-aware caching |
| 5-7 | Tree-sitter | Parser setup, symbol extraction for 5 languages |
| 8-9 | Cache Layer | SQLite schema, memory cache, LRU eviction |
| 10-11 | File Selection | Pattern matching, .gitignore/.aiignore support |
| 12 | Token Counting | Generic token estimation, optimization |
| 13 | RepoPrompt Rules | Symbol scoring, working set tracking |
| 14-15 | Context Assembly | File maps vs code maps, smart content selection |
| 15 | Incremental Updates | File watching, debounced updates |
| 16-17 | Testing | Unit tests, integration tests, benchmarks |
| 18 | Documentation | API docs, usage examples |

## API Specification

### REST Endpoints

```typescript
// Generate context
POST /api/context/generate
Request: {
  workspace: string;
  files?: string[];
  folders?: string[];
  patterns?: string[];
  excludePatterns?: string[];
  maxTokens?: number;
}
Response: GeneratedContext

// Get file map
GET /api/context/file-map?workspace=/path/to/workspace
Response: FileMap

// Get code map  
GET /api/context/code-map?workspace=/path/to/workspace&files=file1,file2
Response: CodeMap

// Invalidate cache
POST /api/context/invalidate
Request: {
  workspace: string;
  files?: string[];
}

// Get metrics
GET /api/context/metrics
Response: {
  cacheHitRate: number;
  avgParseTime: number;
  totalContextsGenerated: number;
}
```

## Configuration

### .aiignore Format

```gitignore
# Exclude patterns
node_modules/
dist/
*.log
.env*

# Include specific files even if parent is excluded
!src/important.ts
```

### Context Configuration

```yaml
# .ai/context.yaml
selection:
  patterns:
    - "src/**/*.ts"
    - "src/**/*.tsx"
  exclude:
    - "**/*.test.ts"
    - "**/*.spec.ts"
  maxFiles: 100
  maxTokens: 100000

cache:
  maxMemoryMB: 100
  maxDiskGB: 1
  ttlSeconds: 3600

parsing:
  languages:
    - typescript
    - javascript
    - python
    - rust
    - go
```

## Success Criteria

### Required
- [ ] Merkle tree diff < 50ms for 100K files
- [ ] Incremental parse < 100ms per file
- [ ] 5+ languages supported
- [ ] Git-aware caching working
- [ ] File selection with patterns
- [ ] Code maps with symbol summaries (no implementations)
- [ ] RepoPrompt-style selection rules
- [ ] Clear file map vs code map distinction
- [ ] Token counting and optimization
- [ ] 80%+ test coverage

### Performance
- [ ] Initial context < 5s for 10K files
- [ ] Cache hit rate > 90%
- [ ] Memory usage < 100MB
- [ ] Zero memory leaks

---

## Key Concepts Summary

### File Maps vs Code Maps

**File Maps** answer: "What files exist and how are they organized?"
- Directory structure
- File names and paths
- Languages distribution
- File sizes
- Selection status

**Code Maps** answer: "What symbols exist without seeing the code?"
- Function signatures (no bodies)
- Class structures (no implementations)
- Interface shapes (no details)
- Type definitions
- Import/export relationships
- Complexity metrics

### Why Code Maps Matter

Instead of sending 100K tokens of full code, send 5K tokens of summaries:
```typescript
// Instead of this (full file content):
function calculateTotalPrice(items: CartItem[], taxRate: number): number {
  const subtotal = items.reduce((sum, item) => {
    return sum + (item.price * item.quantity);
  }, 0);
  
  const tax = subtotal * taxRate;
  const shipping = calculateShipping(items);
  
  return subtotal + tax + shipping;
}

// Send this (code map entry):
{
  name: "calculateTotalPrice",
  signature: "(items: CartItem[], taxRate: number) => number",
  file: "src/cart/pricing.ts",
  line: 42,
  complexity: 3,
  exported: true,
  references: 7
}
```

This allows AI models to understand code structure and relationships without token explosion.

### RepoPrompt-Style Selection

Prioritize symbols based on:
1. **Public API Surface** - Exported symbols are most important
2. **Recency** - Recently modified code is likely relevant
3. **Complexity** - Complex code needs more attention
4. **References** - Frequently used code is important
5. **Entry Points** - Main/index files are critical
6. **Working Set** - Open/modified files are contextually relevant

---

*Phase 2 provides the foundational context intelligence infrastructure. This system is completely AI-agnostic, integrated into the control plane (not an MCP server), and can be used by any tool or model that needs efficient code analysis and context generation.*