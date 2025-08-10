# Phase 2: Context Server & RepoPrompt Implementation

## Executive Summary

Phase 2 establishes the intelligent context management system that powers AI-assisted development. This phase implements tree-sitter based AST parsing, RepoPrompt-style selection rules, and a sophisticated caching layer that enables sub-second context generation for repositories with 100K+ files. The system provides token-aware context building with real-time cost estimation and automatic optimization for different AI model limits.

## Core Objectives

1. **AST-Based Code Analysis**: Tree-sitter integration for accurate symbol extraction
2. **Intelligent Selection**: RepoPrompt-style rules for optimal context building
3. **Performance at Scale**: Incremental parsing and caching for instant context updates
4. **Token Economy**: Accurate counting with model-specific limits
5. **Developer Experience**: Terminal UI for interactive context management

## Technical Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Control Plane (Bun)                    │
├─────────────────────────────────────────────────────────┤
│  Session Manager  │  API Gateway    │  WebSocket Hub    │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Context Server (Phase 2)                   │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ Tree-sitter │  │  Code Maps   │  │ Token Counter │ │
│  │   Parsers   │  │  Generator   │  │   & Limiter   │ │
│  └─────────────┘  └──────────────┘  └───────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │  RepoPrompt │  │  Incremental │  │    Context    │ │
│  │    Rules    │  │   Parser     │  │     Cache     │ │
│  └─────────────┘  └──────────────┘  └───────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │File Watcher │  │Selection AI  │  │   Templates   │ │
│  └─────────────┘  └──────────────┘  └───────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 2.1: Tree-sitter Foundation (Days 1-3)

#### 2.1.1 Parser Infrastructure

**File: `control-plane/src/services/parsers/parser-manager.ts`**
```typescript
import Parser from 'tree-sitter';
import TypeScript from 'tree-sitter-typescript';
import JavaScript from 'tree-sitter-javascript';
import Python from 'tree-sitter-python';
import Rust from 'tree-sitter-rust';
import Go from 'tree-sitter-go';
import { Database } from "bun:sqlite";

export interface Language {
  name: string;
  parser: Parser;
  queries: QuerySet;
  extensions: string[];
  scopeDelimiters: string[];
}

export interface QuerySet {
  symbols: Parser.Query;
  imports: Parser.Query;
  calls: Parser.Query;
  definitions: Parser.Query;
  references: Parser.Query;
  comments: Parser.Query;
  tests: Parser.Query;
}

export class ParserManager {
  private parsers: Map<string, Language>;
  private cache: Database;
  
  constructor() {
    this.parsers = new Map();
    this.cache = new Database("parser-cache.db");
    this.initializeParsers();
    this.initializeCache();
  }
  
  private initializeParsers() {
    // TypeScript/TSX
    const tsParser = new Parser();
    tsParser.setLanguage(TypeScript.tsx);
    this.registerLanguage('typescript', {
      name: 'typescript',
      parser: tsParser,
      queries: this.loadQueries('typescript'),
      extensions: ['.ts', '.tsx', '.mts', '.cts'],
      scopeDelimiters: ['{', '}']
    });
    
    // JavaScript/JSX
    const jsParser = new Parser();
    jsParser.setLanguage(JavaScript);
    this.registerLanguage('javascript', {
      name: 'javascript',
      parser: jsParser,
      queries: this.loadQueries('javascript'),
      extensions: ['.js', '.jsx', '.mjs', '.cjs'],
      scopeDelimiters: ['{', '}']
    });
    
    // Python
    const pyParser = new Parser();
    pyParser.setLanguage(Python);
    this.registerLanguage('python', {
      name: 'python',
      parser: pyParser,
      queries: this.loadQueries('python'),
      extensions: ['.py', '.pyi'],
      scopeDelimiters: [':', 'indent']
    });
    
    // Rust
    const rsParser = new Parser();
    rsParser.setLanguage(Rust);
    this.registerLanguage('rust', {
      name: 'rust',
      parser: rsParser,
      queries: this.loadQueries('rust'),
      extensions: ['.rs'],
      scopeDelimiters: ['{', '}']
    });
    
    // Go
    const goParser = new Parser();
    goParser.setLanguage(Go);
    this.registerLanguage('go', {
      name: 'go',
      parser: goParser,
      queries: this.loadQueries('go'),
      extensions: ['.go'],
      scopeDelimiters: ['{', '}']
    });
  }
  
  private loadQueries(language: string): QuerySet {
    const queryDir = `./queries/${language}`;
    return {
      symbols: this.loadQuery(`${queryDir}/symbols.scm`),
      imports: this.loadQuery(`${queryDir}/imports.scm`),
      calls: this.loadQuery(`${queryDir}/calls.scm`),
      definitions: this.loadQuery(`${queryDir}/definitions.scm`),
      references: this.loadQuery(`${queryDir}/references.scm`),
      comments: this.loadQuery(`${queryDir}/comments.scm`),
      tests: this.loadQuery(`${queryDir}/tests.scm`)
    };
  }
  
  private loadQuery(path: string): Parser.Query {
    const content = Bun.file(path).text();
    const lang = this.detectLanguageFromPath(path);
    return this.parsers.get(lang)!.parser.query(content);
  }
  
  detectLanguage(filePath: string): string | null {
    const ext = path.extname(filePath);
    for (const [name, lang] of this.parsers) {
      if (lang.extensions.includes(ext)) {
        return name;
      }
    }
    return null;
  }
  
  async parseFile(filePath: string): Promise<ParseResult> {
    // Check cache first
    const cached = this.getCachedParse(filePath);
    if (cached && !this.isStale(filePath, cached)) {
      return cached;
    }
    
    const content = await Bun.file(filePath).text();
    const language = this.detectLanguage(filePath);
    
    if (!language) {
      throw new Error(`Unsupported file type: ${filePath}`);
    }
    
    const lang = this.parsers.get(language)!;
    const tree = lang.parser.parse(content);
    
    const result: ParseResult = {
      filePath,
      language,
      tree,
      content,
      timestamp: Date.now()
    };
    
    // Cache the result
    this.cacheParse(filePath, result);
    
    return result;
  }
  
  private initializeCache() {
    this.cache.exec(`
      CREATE TABLE IF NOT EXISTS parse_cache (
        file_path TEXT PRIMARY KEY,
        language TEXT NOT NULL,
        tree_data BLOB NOT NULL,
        content_hash TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      );
      
      CREATE INDEX idx_cache_timestamp ON parse_cache(timestamp);
    `);
  }
}
```

#### 2.1.2 Query Definitions

**File: `control-plane/queries/typescript/symbols.scm`**
```scheme
; Functions
(function_declaration
  name: (identifier) @function.name
  parameters: (formal_parameters) @function.params
  body: (statement_block) @function.body) @function

; Methods
(method_definition
  name: (property_identifier) @method.name
  parameters: (formal_parameters) @method.params
  body: (statement_block) @method.body) @method

; Classes
(class_declaration
  name: (type_identifier) @class.name
  body: (class_body) @class.body) @class

; Interfaces
(interface_declaration
  name: (type_identifier) @interface.name
  body: (interface_body) @interface.body) @interface

; Type aliases
(type_alias_declaration
  name: (type_identifier) @type.name
  value: (_) @type.value) @type

; Enums
(enum_declaration
  name: (identifier) @enum.name
  body: (enum_body) @enum.body) @enum

; Variables
(variable_declarator
  name: (identifier) @variable.name
  value: (_)? @variable.value) @variable

; Exports
(export_statement
  declaration: (_) @export.declaration) @export
```

### Phase 2.2: Symbol Extraction & Code Maps (Days 4-6)

#### 2.2.1 Symbol Extractor

**File: `control-plane/src/services/context/symbol-extractor.ts`**
```typescript
export interface Symbol {
  id: string;
  name: string;
  kind: SymbolKind;
  filePath: string;
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  signature?: string;
  docComment?: string;
  complexity: number;
  references: number;
  lastModified: number;
  importance: number;
  context?: string;
}

export enum SymbolKind {
  Function = 'function',
  Method = 'method',
  Class = 'class',
  Interface = 'interface',
  Type = 'type',
  Enum = 'enum',
  Variable = 'variable',
  Constant = 'constant',
  Module = 'module',
  Namespace = 'namespace'
}

export class SymbolExtractor {
  constructor(private parserManager: ParserManager) {}
  
  async extractSymbols(filePath: string): Promise<Symbol[]> {
    const parseResult = await this.parserManager.parseFile(filePath);
    const language = this.parserManager.parsers.get(parseResult.language)!;
    
    const symbols: Symbol[] = [];
    
    // Query for all symbol types
    const symbolCaptures = language.queries.symbols.captures(
      parseResult.tree.rootNode
    );
    
    for (const capture of symbolCaptures) {
      const symbol = this.createSymbol(capture, filePath, parseResult.content);
      if (symbol) {
        symbols.push(symbol);
      }
    }
    
    // Calculate complexity and importance
    for (const symbol of symbols) {
      symbol.complexity = this.calculateComplexity(symbol, parseResult.tree);
      symbol.references = await this.countReferences(symbol);
      symbol.importance = this.calculateImportance(symbol);
    }
    
    return symbols;
  }
  
  private createSymbol(
    capture: Parser.QueryCapture,
    filePath: string,
    content: string
  ): Symbol | null {
    const node = capture.node;
    const name = capture.name;
    
    // Extract symbol based on capture name
    const kind = this.getSymbolKind(name);
    if (!kind) return null;
    
    const startPos = node.startPosition;
    const endPos = node.endPosition;
    
    return {
      id: crypto.randomUUID(),
      name: this.extractName(node, name),
      kind,
      filePath,
      line: startPos.row + 1,
      column: startPos.column + 1,
      endLine: endPos.row + 1,
      endColumn: endPos.column + 1,
      signature: this.extractSignature(node, content),
      docComment: this.extractDocComment(node, content),
      complexity: 0,
      references: 0,
      lastModified: Date.now(),
      importance: 0,
      context: this.extractContext(node, content)
    };
  }
  
  private calculateComplexity(symbol: Symbol, tree: Parser.Tree): number {
    // Cyclomatic complexity calculation
    let complexity = 1;
    
    const node = this.findNodeForSymbol(symbol, tree);
    if (!node) return complexity;
    
    // Count decision points
    const cursor = tree.walk();
    cursor.gotoDescendant(node.startIndex);
    
    while (cursor.gotoNextSibling() && cursor.currentNode.endIndex <= node.endIndex) {
      const nodeType = cursor.currentNode.type;
      if (this.isDecisionPoint(nodeType)) {
        complexity++;
      }
    }
    
    return complexity;
  }
  
  private isDecisionPoint(nodeType: string): boolean {
    const decisionPoints = [
      'if_statement',
      'switch_statement',
      'while_statement',
      'for_statement',
      'do_statement',
      'catch_clause',
      'conditional_expression',
      'logical_and_expression',
      'logical_or_expression'
    ];
    return decisionPoints.includes(nodeType);
  }
  
  private async countReferences(symbol: Symbol): Promise<number> {
    // This would search across the codebase for references
    // For now, return a placeholder
    return 0;
  }
  
  private calculateImportance(symbol: Symbol): number {
    let score = 0;
    
    // Exported symbols are more important
    if (symbol.context?.includes('export')) score += 10;
    
    // Public methods/properties
    if (!symbol.name.startsWith('_') && !symbol.name.startsWith('#')) score += 5;
    
    // Complexity factor
    score += Math.min(symbol.complexity * 2, 20);
    
    // Reference factor
    score += Math.min(symbol.references * 3, 30);
    
    // Type-specific scoring
    switch (symbol.kind) {
      case SymbolKind.Class:
      case SymbolKind.Interface:
        score += 15;
        break;
      case SymbolKind.Function:
      case SymbolKind.Method:
        score += 10;
        break;
      case SymbolKind.Type:
        score += 8;
        break;
    }
    
    // Documentation bonus
    if (symbol.docComment) score += 5;
    
    return score;
  }
}
```

#### 2.2.2 Code Map Generator

**File: `control-plane/src/services/context/code-map-generator.ts`**
```typescript
export interface CodeMap {
  workspace: string;
  timestamp: number;
  fileCount: number;
  symbolCount: number;
  languages: Map<string, number>;
  symbols: {
    functions: Symbol[];
    classes: Symbol[];
    interfaces: Symbol[];
    types: Symbol[];
    enums: Symbol[];
    modules: Symbol[];
  };
  dependencies: Dependency[];
  workingSet: WorkingFile[];
  testFiles: TestFile[];
  entryPoints: string[];
  structure: DirectoryStructure;
}

export interface Dependency {
  name: string;
  version?: string;
  type: 'npm' | 'cargo' | 'go' | 'pip' | 'gem';
  path: string;
  directDependents: string[];
}

export interface WorkingFile {
  path: string;
  lastModified: number;
  symbols: Symbol[];
  imports: string[];
  exports: string[];
}

export interface DirectoryStructure {
  name: string;
  path: string;
  type: 'directory' | 'file';
  children?: DirectoryStructure[];
  language?: string;
  symbolCount?: number;
}

export class CodeMapGenerator {
  private symbolExtractor: SymbolExtractor;
  private cache: Database;
  private fileWatcher: FSWatcher;
  
  constructor(
    private parserManager: ParserManager,
    private workspace: string
  ) {
    this.symbolExtractor = new SymbolExtractor(parserManager);
    this.cache = new Database("codemap-cache.db");
    this.initializeCache();
    this.setupFileWatcher();
  }
  
  async generateCodeMap(): Promise<CodeMap> {
    const startTime = performance.now();
    
    // Check cache
    const cached = await this.getCachedCodeMap();
    if (cached && !this.isStale(cached)) {
      console.log(`Loaded code map from cache in ${performance.now() - startTime}ms`);
      return cached;
    }
    
    console.log(`Generating fresh code map for ${this.workspace}`);
    
    // Find all source files
    const files = await this.findSourceFiles();
    console.log(`Found ${files.length} source files`);
    
    // Parse files in parallel batches
    const BATCH_SIZE = 50;
    const allSymbols: Symbol[] = [];
    
    for (let i = 0; i < files.length; i += BATCH_SIZE) {
      const batch = files.slice(i, i + BATCH_SIZE);
      const batchSymbols = await Promise.all(
        batch.map(file => this.symbolExtractor.extractSymbols(file))
      );
      allSymbols.push(...batchSymbols.flat());
      
      // Report progress
      const progress = Math.min(100, ((i + BATCH_SIZE) / files.length) * 100);
      console.log(`Progress: ${progress.toFixed(1)}%`);
    }
    
    // Build code map
    const codeMap: CodeMap = {
      workspace: this.workspace,
      timestamp: Date.now(),
      fileCount: files.length,
      symbolCount: allSymbols.length,
      languages: this.detectLanguages(files),
      symbols: this.categorizeSymbols(allSymbols),
      dependencies: await this.extractDependencies(),
      workingSet: await this.buildWorkingSet(files),
      testFiles: this.findTestFiles(files),
      entryPoints: this.findEntryPoints(files),
      structure: await this.buildDirectoryStructure()
    };
    
    // Cache the result
    await this.cacheCodeMap(codeMap);
    
    const elapsed = performance.now() - startTime;
    console.log(`Generated code map in ${elapsed.toFixed(2)}ms`);
    
    return codeMap;
  }
  
  private async findSourceFiles(): Promise<string[]> {
    const gitignore = await this.loadGitignore();
    const files: string[] = [];
    
    const walk = async (dir: string) => {
      const entries = await Bun.readdir(dir);
      
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        
        // Skip ignored paths
        if (this.shouldIgnore(fullPath, gitignore)) continue;
        
        if (entry.isDirectory()) {
          await walk(fullPath);
        } else if (this.isSourceFile(fullPath)) {
          files.push(fullPath);
        }
      }
    };
    
    await walk(this.workspace);
    return files;
  }
  
  private isSourceFile(filePath: string): boolean {
    const supportedExtensions = [
      '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
      '.py', '.pyi',
      '.rs',
      '.go',
      '.java',
      '.c', '.cpp', '.cc', '.h', '.hpp',
      '.rb',
      '.php',
      '.swift',
      '.kt',
      '.scala',
      '.ml', '.mli'
    ];
    
    return supportedExtensions.some(ext => filePath.endsWith(ext));
  }
  
  private categorizeSymbols(symbols: Symbol[]): CodeMap['symbols'] {
    return {
      functions: symbols.filter(s => s.kind === SymbolKind.Function),
      classes: symbols.filter(s => s.kind === SymbolKind.Class),
      interfaces: symbols.filter(s => s.kind === SymbolKind.Interface),
      types: symbols.filter(s => s.kind === SymbolKind.Type),
      enums: symbols.filter(s => s.kind === SymbolKind.Enum),
      modules: symbols.filter(s => s.kind === SymbolKind.Module)
    };
  }
  
  private setupFileWatcher() {
    // Watch for file changes
    this.fileWatcher = Bun.file(this.workspace).watch((event, filename) => {
      this.handleFileChange(event, filename);
    });
  }
  
  private handleFileChange = debounce(async (event: string, filename: string) => {
    console.log(`File changed: ${filename} (${event})`);
    
    // Invalidate cache for this file
    await this.invalidateFileCache(filename);
    
    // Schedule incremental update
    this.scheduleIncrementalUpdate();
  }, 100);
  
  private scheduleIncrementalUpdate = debounce(async () => {
    // Perform incremental code map update
    const codeMap = await this.getCachedCodeMap();
    if (!codeMap) return;
    
    // Update only changed files
    const changedFiles = await this.getChangedFiles(codeMap.timestamp);
    
    for (const file of changedFiles) {
      const symbols = await this.symbolExtractor.extractSymbols(file);
      this.updateCodeMapSymbols(codeMap, file, symbols);
    }
    
    await this.cacheCodeMap(codeMap);
  }, 500);
}
```

### Phase 2.3: RepoPrompt Selection Rules (Days 7-9)

#### 2.3.1 Selection Engine

**File: `control-plane/src/services/context/selection-engine.ts`**
```typescript
export interface SelectionRules {
  maxTokens: number;
  maxFiles: number;
  priorityRules: PriorityRule[];
  excludePatterns: string[];
  includeTests: boolean;
  includeDocumentation: boolean;
  semanticSearch?: string;
  workingSetWeight: number;
  recencyWeight: number;
  complexityWeight: number;
  referenceWeight: number;
}

export interface PriorityRule {
  name: string;
  weight: number;
  condition: (symbol: Symbol) => boolean;
}

export interface SelectedContext {
  symbols: Symbol[];
  files: FileContext[];
  totalTokens: number;
  tokensByModel: Map<string, number>;
  estimatedCost: Map<string, number>;
  summary: string;
  warnings: string[];
}

export interface FileContext {
  path: string;
  content: string;
  symbols: Symbol[];
  tokens: number;
  reason: string;
}

export class SelectionEngine {
  private tokenCounter: TokenCounter;
  private codeMap: CodeMap;
  
  constructor() {
    this.tokenCounter = new TokenCounter();
  }
  
  async selectContext(
    codeMap: CodeMap,
    rules: SelectionRules,
    anchor?: string
  ): Promise<SelectedContext> {
    this.codeMap = codeMap;
    
    // Phase 1: Score all symbols
    const scoredSymbols = this.scoreSymbols(codeMap, rules);
    
    // Phase 2: Apply anchor-based filtering if provided
    let relevantSymbols = scoredSymbols;
    if (anchor) {
      relevantSymbols = this.filterByAnchor(scoredSymbols, anchor);
    }
    
    // Phase 3: Apply priority rules
    relevantSymbols = this.applyPriorityRules(relevantSymbols, rules);
    
    // Phase 4: Token-aware selection
    const selected = await this.selectWithinTokenLimit(relevantSymbols, rules);
    
    // Phase 5: Build file contexts
    const fileContexts = await this.buildFileContexts(selected, rules);
    
    // Phase 6: Calculate costs
    const costs = this.calculateCosts(fileContexts);
    
    return {
      symbols: selected,
      files: fileContexts,
      totalTokens: costs.totalTokens,
      tokensByModel: costs.tokensByModel,
      estimatedCost: costs.estimatedCost,
      summary: this.generateSummary(selected, fileContexts),
      warnings: this.generateWarnings(costs, rules)
    };
  }
  
  private scoreSymbols(codeMap: CodeMap, rules: SelectionRules): ScoredSymbol[] {
    const allSymbols = [
      ...codeMap.symbols.functions,
      ...codeMap.symbols.classes,
      ...codeMap.symbols.interfaces,
      ...codeMap.symbols.types,
      ...codeMap.symbols.enums,
      ...codeMap.symbols.modules
    ];
    
    return allSymbols.map(symbol => {
      let score = symbol.importance;
      
      // Working set bonus
      if (this.isInWorkingSet(symbol)) {
        score += rules.workingSetWeight;
      }
      
      // Recency bonus
      const recencyScore = this.calculateRecencyScore(symbol);
      score += recencyScore * rules.recencyWeight;
      
      // Complexity factor
      score += symbol.complexity * rules.complexityWeight;
      
      // Reference factor
      score += symbol.references * rules.referenceWeight;
      
      return { symbol, score };
    }).sort((a, b) => b.score - a.score);
  }
  
  private filterByAnchor(symbols: ScoredSymbol[], anchor: string): ScoredSymbol[] {
    // Parse anchor to determine filter type
    if (anchor.startsWith('file:')) {
      const filePath = anchor.substring(5);
      return symbols.filter(s => s.symbol.filePath === filePath);
    }
    
    if (anchor.startsWith('function:')) {
      const funcName = anchor.substring(9);
      return this.findRelatedSymbols(symbols, funcName);
    }
    
    if (anchor.startsWith('test:')) {
      const testName = anchor.substring(5);
      return this.findTestRelatedSymbols(symbols, testName);
    }
    
    // Default: semantic search
    return this.semanticFilter(symbols, anchor);
  }
  
  private applyPriorityRules(
    symbols: ScoredSymbol[],
    rules: SelectionRules
  ): ScoredSymbol[] {
    for (const rule of rules.priorityRules) {
      symbols = symbols.map(s => {
        if (rule.condition(s.symbol)) {
          s.score += rule.weight;
        }
        return s;
      });
    }
    
    return symbols.sort((a, b) => b.score - a.score);
  }
  
  private async selectWithinTokenLimit(
    symbols: ScoredSymbol[],
    rules: SelectionRules
  ): Promise<Symbol[]> {
    const selected: Symbol[] = [];
    let totalTokens = 0;
    
    for (const { symbol } of symbols) {
      const tokens = await this.tokenCounter.countSymbol(symbol);
      
      if (totalTokens + tokens > rules.maxTokens) {
        // Try to fit summary instead
        const summary = this.createSymbolSummary(symbol);
        const summaryTokens = await this.tokenCounter.count(summary);
        
        if (totalTokens + summaryTokens <= rules.maxTokens) {
          symbol.context = summary;
          selected.push(symbol);
          totalTokens += summaryTokens;
        }
        continue;
      }
      
      selected.push(symbol);
      totalTokens += tokens;
      
      if (selected.length >= rules.maxFiles) {
        break;
      }
    }
    
    return selected;
  }
  
  private createSymbolSummary(symbol: Symbol): string {
    return `${symbol.kind} ${symbol.name} in ${symbol.filePath}:${symbol.line}`;
  }
  
  private isInWorkingSet(symbol: Symbol): boolean {
    return this.codeMap.workingSet.some(
      file => file.path === symbol.filePath
    );
  }
  
  private calculateRecencyScore(symbol: Symbol): number {
    const now = Date.now();
    const age = now - symbol.lastModified;
    const hours = age / (1000 * 60 * 60);
    
    if (hours < 1) return 100;
    if (hours < 24) return 50;
    if (hours < 168) return 20; // 1 week
    if (hours < 720) return 10; // 1 month
    return 0;
  }
}
```

#### 2.3.2 RepoPrompt Rules Implementation

**File: `control-plane/src/services/context/repoprompt-rules.ts`**
```typescript
export class RepoPromptRules {
  static readonly DEFAULT_RULES: SelectionRules = {
    maxTokens: 100000,
    maxFiles: 50,
    priorityRules: [
      {
        name: 'exported',
        weight: 20,
        condition: (s) => s.context?.includes('export') ?? false
      },
      {
        name: 'hasTests',
        weight: 15,
        condition: (s) => s.references > 5
      },
      {
        name: 'documented',
        weight: 10,
        condition: (s) => !!s.docComment
      },
      {
        name: 'entryPoint',
        weight: 25,
        condition: (s) => s.filePath.includes('index') || s.filePath.includes('main')
      },
      {
        name: 'highComplexity',
        weight: 15,
        condition: (s) => s.complexity > 10
      }
    ],
    excludePatterns: [
      'node_modules',
      '.git',
      'dist',
      'build',
      'coverage',
      '.next',
      '__pycache__',
      'target',
      'vendor'
    ],
    includeTests: false,
    includeDocumentation: true,
    workingSetWeight: 30,
    recencyWeight: 2,
    complexityWeight: 1.5,
    referenceWeight: 3
  };
  
  static readonly TASK_SPECIFIC_RULES: Map<string, Partial<SelectionRules>> = new Map([
    ['debugging', {
      includeTests: true,
      priorityRules: [
        {
          name: 'errorHandling',
          weight: 30,
          condition: (s) => s.context?.includes('catch') || s.context?.includes('error')
        },
        {
          name: 'logging',
          weight: 20,
          condition: (s) => s.context?.includes('console') || s.context?.includes('log')
        }
      ],
      complexityWeight: 3,
      recencyWeight: 5
    }],
    
    ['refactoring', {
      priorityRules: [
        {
          name: 'highComplexity',
          weight: 40,
          condition: (s) => s.complexity > 15
        },
        {
          name: 'duplicated',
          weight: 30,
          condition: (s) => s.references > 10
        }
      ],
      complexityWeight: 5,
      referenceWeight: 4
    }],
    
    ['testing', {
      includeTests: true,
      priorityRules: [
        {
          name: 'untested',
          weight: 50,
          condition: (s) => !s.context?.includes('test')
        },
        {
          name: 'public',
          weight: 20,
          condition: (s) => !s.name.startsWith('_')
        }
      ]
    }],
    
    ['documentation', {
      includeDocumentation: true,
      priorityRules: [
        {
          name: 'undocumented',
          weight: 40,
          condition: (s) => !s.docComment
        },
        {
          name: 'public',
          weight: 30,
          condition: (s) => s.context?.includes('export')
        }
      ]
    }]
  ]);
  
  static combineRules(base: SelectionRules, overrides: Partial<SelectionRules>): SelectionRules {
    return {
      ...base,
      ...overrides,
      priorityRules: [
        ...(base.priorityRules || []),
        ...(overrides.priorityRules || [])
      ]
    };
  }
  
  static getRulesForTask(taskType: string): SelectionRules {
    const taskRules = this.TASK_SPECIFIC_RULES.get(taskType);
    if (!taskRules) {
      return this.DEFAULT_RULES;
    }
    return this.combineRules(this.DEFAULT_RULES, taskRules);
  }
}
```

### Phase 2.4: Token Counting & Optimization (Days 10-11)

#### 2.4.1 Token Counter

**File: `control-plane/src/services/context/token-counter.ts`**
```typescript
import { Tiktoken, encoding_for_model } from 'tiktoken';

export interface ModelLimits {
  model: string;
  contextWindow: number;
  outputLimit: number;
  costPer1kInput: number;
  costPer1kOutput: number;
}

export class TokenCounter {
  private encoders: Map<string, Tiktoken>;
  private modelLimits: Map<string, ModelLimits>;
  
  constructor() {
    this.encoders = new Map();
    this.modelLimits = new Map();
    this.initializeModels();
  }
  
  private initializeModels() {
    // Claude models
    this.registerModel('claude-3-opus', {
      model: 'claude-3-opus',
      contextWindow: 200000,
      outputLimit: 4096,
      costPer1kInput: 0.015,
      costPer1kOutput: 0.075
    });
    
    this.registerModel('claude-3-sonnet', {
      model: 'claude-3-sonnet',
      contextWindow: 200000,
      outputLimit: 4096,
      costPer1kInput: 0.003,
      costPer1kOutput: 0.015
    });
    
    this.registerModel('claude-3-haiku', {
      model: 'claude-3-haiku',
      contextWindow: 200000,
      outputLimit: 4096,
      costPer1kInput: 0.00025,
      costPer1kOutput: 0.00125
    });
    
    // GPT models
    this.registerModel('gpt-4-turbo', {
      model: 'gpt-4-turbo',
      contextWindow: 128000,
      outputLimit: 4096,
      costPer1kInput: 0.01,
      costPer1kOutput: 0.03
    });
    
    this.registerModel('gpt-4o', {
      model: 'gpt-4o',
      contextWindow: 128000,
      outputLimit: 4096,
      costPer1kInput: 0.005,
      costPer1kOutput: 0.015
    });
    
    // Gemini models
    this.registerModel('gemini-1.5-pro', {
      model: 'gemini-1.5-pro',
      contextWindow: 2000000,
      outputLimit: 8192,
      costPer1kInput: 0.00125,
      costPer1kOutput: 0.005
    });
    
    // DeepSeek
    this.registerModel('deepseek-v2', {
      model: 'deepseek-v2',
      contextWindow: 128000,
      outputLimit: 4096,
      costPer1kInput: 0.0001,
      costPer1kOutput: 0.0002
    });
  }
  
  async count(text: string, model: string = 'claude-3-opus'): Promise<number> {
    const encoder = this.getEncoder(model);
    const tokens = encoder.encode(text);
    return tokens.length;
  }
  
  async countSymbol(symbol: Symbol): Promise<number> {
    const content = symbol.signature || symbol.name;
    const doc = symbol.docComment || '';
    const context = symbol.context || '';
    
    const fullText = `${content}\n${doc}\n${context}`;
    return this.count(fullText);
  }
  
  async countFile(filePath: string): Promise<number> {
    const content = await Bun.file(filePath).text();
    return this.count(content);
  }
  
  async optimize(
    content: string,
    targetTokens: number,
    model: string = 'claude-3-opus'
  ): Promise<string> {
    const currentTokens = await this.count(content, model);
    
    if (currentTokens <= targetTokens) {
      return content;
    }
    
    // Strategy 1: Remove comments
    let optimized = this.removeComments(content);
    let tokens = await this.count(optimized, model);
    
    if (tokens <= targetTokens) {
      return optimized;
    }
    
    // Strategy 2: Remove empty lines
    optimized = this.removeEmptyLines(optimized);
    tokens = await this.count(optimized, model);
    
    if (tokens <= targetTokens) {
      return optimized;
    }
    
    // Strategy 3: Truncate
    return this.truncateToTokenLimit(optimized, targetTokens, model);
  }
  
  private removeComments(content: string): string {
    // Remove single-line comments
    content = content.replace(/\/\/.*$/gm, '');
    
    // Remove multi-line comments
    content = content.replace(/\/\*[\s\S]*?\*\//g, '');
    
    // Remove Python comments
    content = content.replace(/#.*$/gm, '');
    
    // Remove Python docstrings
    content = content.replace(/"""[\s\S]*?"""/g, '');
    content = content.replace(/'''[\s\S]*?'''/g, '');
    
    return content;
  }
  
  private removeEmptyLines(content: string): string {
    return content.replace(/^\s*[\r\n]/gm, '');
  }
  
  private async truncateToTokenLimit(
    content: string,
    targetTokens: number,
    model: string
  ): Promise<string> {
    const encoder = this.getEncoder(model);
    const tokens = encoder.encode(content);
    
    if (tokens.length <= targetTokens) {
      return content;
    }
    
    // Truncate and decode
    const truncated = tokens.slice(0, targetTokens);
    return encoder.decode(truncated);
  }
  
  calculateCost(
    inputTokens: number,
    outputTokens: number,
    model: string
  ): number {
    const limits = this.modelLimits.get(model);
    if (!limits) {
      throw new Error(`Unknown model: ${model}`);
    }
    
    const inputCost = (inputTokens / 1000) * limits.costPer1kInput;
    const outputCost = (outputTokens / 1000) * limits.costPer1kOutput;
    
    return inputCost + outputCost;
  }
  
  getModelLimits(model: string): ModelLimits | undefined {
    return this.modelLimits.get(model);
  }
  
  private getEncoder(model: string): Tiktoken {
    if (!this.encoders.has(model)) {
      // Use appropriate encoding for model family
      if (model.startsWith('claude')) {
        this.encoders.set(model, encoding_for_model('gpt-4')); // Claude uses similar
      } else if (model.startsWith('gpt')) {
        this.encoders.set(model, encoding_for_model(model));
      } else {
        // Default to GPT-4 encoding
        this.encoders.set(model, encoding_for_model('gpt-4'));
      }
    }
    
    return this.encoders.get(model)!;
  }
  
  private registerModel(name: string, limits: ModelLimits) {
    this.modelLimits.set(name, limits);
  }
}
```

### Phase 2.5: Context Cache & Performance (Days 12-13)

#### 2.5.1 Context Cache Manager

**File: `control-plane/src/services/context/cache-manager.ts`**
```typescript
export interface CacheEntry {
  key: string;
  value: any;
  timestamp: number;
  hits: number;
  size: number;
  ttl: number;
}

export class CacheManager {
  private db: Database;
  private memoryCache: Map<string, CacheEntry>;
  private maxMemorySize: number = 100 * 1024 * 1024; // 100MB
  private currentMemorySize: number = 0;
  
  constructor() {
    this.db = new Database("context-cache.db");
    this.memoryCache = new Map();
    this.initializeDatabase();
    this.startCleanupTimer();
  }
  
  private initializeDatabase() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS cache_entries (
        key TEXT PRIMARY KEY,
        value BLOB NOT NULL,
        timestamp INTEGER NOT NULL,
        hits INTEGER DEFAULT 0,
        size INTEGER NOT NULL,
        ttl INTEGER NOT NULL
      );
      
      CREATE INDEX idx_cache_timestamp ON cache_entries(timestamp);
      CREATE INDEX idx_cache_hits ON cache_entries(hits);
      
      CREATE TABLE IF NOT EXISTS cache_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hit_rate REAL,
        miss_rate REAL,
        avg_latency REAL,
        total_hits INTEGER,
        total_misses INTEGER,
        timestamp INTEGER NOT NULL
      );
    `);
  }
  
  async get<T>(key: string): Promise<T | null> {
    const startTime = performance.now();
    
    // Check memory cache first
    const memEntry = this.memoryCache.get(key);
    if (memEntry) {
      if (this.isExpired(memEntry)) {
        this.memoryCache.delete(key);
        this.currentMemorySize -= memEntry.size;
      } else {
        memEntry.hits++;
        this.recordHit(performance.now() - startTime);
        return memEntry.value as T;
      }
    }
    
    // Check disk cache
    const diskEntry = await this.getFromDisk(key);
    if (diskEntry) {
      if (this.isExpired(diskEntry)) {
        await this.deleteFromDisk(key);
      } else {
        // Promote to memory cache if hot
        if (diskEntry.hits > 5) {
          this.addToMemoryCache(key, diskEntry);
        }
        this.recordHit(performance.now() - startTime);
        return diskEntry.value as T;
      }
    }
    
    this.recordMiss(performance.now() - startTime);
    return null;
  }
  
  async set<T>(
    key: string,
    value: T,
    ttl: number = 3600000 // 1 hour default
  ): Promise<void> {
    const size = this.estimateSize(value);
    const entry: CacheEntry = {
      key,
      value,
      timestamp: Date.now(),
      hits: 0,
      size,
      ttl
    };
    
    // Add to memory cache if space available
    if (size < this.maxMemorySize * 0.1) { // Don't cache items > 10% of max
      this.addToMemoryCache(key, entry);
    }
    
    // Always persist to disk
    await this.saveToDisk(entry);
  }
  
  private addToMemoryCache(key: string, entry: CacheEntry) {
    // Evict if necessary
    while (this.currentMemorySize + entry.size > this.maxMemorySize) {
      this.evictLRU();
    }
    
    this.memoryCache.set(key, entry);
    this.currentMemorySize += entry.size;
  }
  
  private evictLRU() {
    let lruKey: string | null = null;
    let lruTime = Infinity;
    
    for (const [key, entry] of this.memoryCache) {
      const lastAccess = entry.timestamp + (entry.hits * 1000); // Boost for hits
      if (lastAccess < lruTime) {
        lruTime = lastAccess;
        lruKey = key;
      }
    }
    
    if (lruKey) {
      const entry = this.memoryCache.get(lruKey)!;
      this.memoryCache.delete(lruKey);
      this.currentMemorySize -= entry.size;
    }
  }
  
  private isExpired(entry: CacheEntry): boolean {
    return Date.now() - entry.timestamp > entry.ttl;
  }
  
  private estimateSize(obj: any): number {
    return JSON.stringify(obj).length * 2; // Rough estimate (2 bytes per char)
  }
  
  private async getFromDisk(key: string): Promise<CacheEntry | null> {
    const row = this.db.query(
      "SELECT * FROM cache_entries WHERE key = ?"
    ).get(key) as any;
    
    if (!row) return null;
    
    // Update hit count
    this.db.run(
      "UPDATE cache_entries SET hits = hits + 1 WHERE key = ?",
      [key]
    );
    
    return {
      key: row.key,
      value: JSON.parse(row.value),
      timestamp: row.timestamp,
      hits: row.hits + 1,
      size: row.size,
      ttl: row.ttl
    };
  }
  
  private async saveToDisk(entry: CacheEntry) {
    this.db.run(
      `INSERT OR REPLACE INTO cache_entries 
       (key, value, timestamp, hits, size, ttl)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        entry.key,
        JSON.stringify(entry.value),
        entry.timestamp,
        entry.hits,
        entry.size,
        entry.ttl
      ]
    );
  }
  
  private async deleteFromDisk(key: string) {
    this.db.run("DELETE FROM cache_entries WHERE key = ?", [key]);
  }
  
  private recordHit(latency: number) {
    // Update metrics
    this.updateMetrics(true, latency);
  }
  
  private recordMiss(latency: number) {
    // Update metrics
    this.updateMetrics(false, latency);
  }
  
  private updateMetrics(hit: boolean, latency: number) {
    // This would update running metrics
    // Implementation depends on monitoring requirements
  }
  
  private startCleanupTimer() {
    setInterval(() => {
      this.cleanup();
    }, 60000); // Every minute
  }
  
  private async cleanup() {
    // Remove expired entries from memory
    for (const [key, entry] of this.memoryCache) {
      if (this.isExpired(entry)) {
        this.memoryCache.delete(key);
        this.currentMemorySize -= entry.size;
      }
    }
    
    // Remove expired entries from disk
    const expired = Date.now() - 86400000; // 24 hours
    this.db.run(
      "DELETE FROM cache_entries WHERE timestamp + ttl < ?",
      [expired]
    );
  }
}
```

### Phase 2.6: Integration with Control Plane (Days 14-15)

#### 2.6.1 Context Service Integration

**File: `control-plane/src/services/context/context-service.ts`**
```typescript
import { ParserManager } from './parsers/parser-manager';
import { CodeMapGenerator } from './code-map-generator';
import { SelectionEngine } from './selection-engine';
import { TokenCounter } from './token-counter';
import { CacheManager } from './cache-manager';
import { RepoPromptRules } from './repoprompt-rules';

export class ContextService {
  private parserManager: ParserManager;
  private codeMapGenerators: Map<string, CodeMapGenerator>;
  private selectionEngine: SelectionEngine;
  private tokenCounter: TokenCounter;
  private cacheManager: CacheManager;
  
  constructor() {
    this.parserManager = new ParserManager();
    this.codeMapGenerators = new Map();
    this.selectionEngine = new SelectionEngine();
    this.tokenCounter = new TokenCounter();
    this.cacheManager = new CacheManager();
  }
  
  async generateContext(
    workspace: string,
    options?: ContextOptions
  ): Promise<RepoContext> {
    // Get or create code map generator for workspace
    if (!this.codeMapGenerators.has(workspace)) {
      this.codeMapGenerators.set(
        workspace,
        new CodeMapGenerator(this.parserManager, workspace)
      );
    }
    
    const generator = this.codeMapGenerators.get(workspace)!;
    
    // Generate or retrieve cached code map
    const cacheKey = `codemap:${workspace}`;
    let codeMap = await this.cacheManager.get<CodeMap>(cacheKey);
    
    if (!codeMap) {
      codeMap = await generator.generateCodeMap();
      await this.cacheManager.set(cacheKey, codeMap, 3600000); // 1 hour
    }
    
    // Apply selection rules
    const rules = options?.taskType 
      ? RepoPromptRules.getRulesForTask(options.taskType)
      : RepoPromptRules.DEFAULT_RULES;
    
    if (options?.rules) {
      Object.assign(rules, options.rules);
    }
    
    // Select context
    const selectedContext = await this.selectionEngine.selectContext(
      codeMap,
      rules,
      options?.anchor
    );
    
    // Build final context
    return {
      codeMap: {
        functions: selectedContext.symbols.filter(s => s.kind === SymbolKind.Function),
        classes: selectedContext.symbols.filter(s => s.kind === SymbolKind.Class),
        interfaces: selectedContext.symbols.filter(s => s.kind === SymbolKind.Interface),
        types: selectedContext.symbols.filter(s => s.kind === SymbolKind.Type),
        imports: codeMap.dependencies,
        workingSet: codeMap.workingSet
      },
      recentChanges: await this.getRecentChanges(workspace),
      activeFiles: selectedContext.files.map(f => f.path),
      failingTests: await this.getFailingTests(workspace),
      openPRs: await this.getOpenPRs(workspace),
      metadata: {
        totalTokens: selectedContext.totalTokens,
        tokensByModel: Object.fromEntries(selectedContext.tokensByModel),
        estimatedCost: Object.fromEntries(selectedContext.estimatedCost),
        fileCount: selectedContext.files.length,
        symbolCount: selectedContext.symbols.length,
        summary: selectedContext.summary,
        warnings: selectedContext.warnings
      }
    };
  }
  
  async updateContext(
    workspace: string,
    currentContext: RepoContext,
    trigger: string,
    data?: any
  ): Promise<RepoContext> {
    console.log(`Updating context for ${workspace} due to ${trigger}`);
    
    // Handle different triggers
    switch (trigger) {
      case 'file_save':
        return this.handleFileSave(workspace, currentContext, data);
      
      case 'file_open':
        return this.handleFileOpen(workspace, currentContext, data);
      
      case 'git_commit':
        return this.handleGitCommit(workspace, currentContext, data);
      
      case 'test_run':
        return this.handleTestRun(workspace, currentContext, data);
      
      default:
        // Full regeneration
        return this.generateContext(workspace);
    }
  }
  
  private async handleFileSave(
    workspace: string,
    context: RepoContext,
    data: { filePath: string }
  ): Promise<RepoContext> {
    // Invalidate cache for this file
    const cacheKey = `file:${data.filePath}`;
    await this.cacheManager.delete(cacheKey);
    
    // Re-parse the file
    const symbols = await this.parserManager.parseFile(data.filePath);
    
    // Update context with new symbols
    // ... implementation
    
    return context;
  }
  
  // Additional trigger handlers...
}
```

### Phase 2.7: Testing Strategy (Day 16)

#### 2.7.1 Unit Tests

**File: `control-plane/test/context/parser-manager.test.ts`**
```typescript
import { expect, test, describe, beforeAll } from "bun:test";
import { ParserManager } from "../../src/services/parsers/parser-manager";

describe("ParserManager", () => {
  let parserManager: ParserManager;
  
  beforeAll(() => {
    parserManager = new ParserManager();
  });
  
  test("detects language from file extension", () => {
    expect(parserManager.detectLanguage("test.ts")).toBe("typescript");
    expect(parserManager.detectLanguage("test.py")).toBe("python");
    expect(parserManager.detectLanguage("test.rs")).toBe("rust");
    expect(parserManager.detectLanguage("test.go")).toBe("go");
  });
  
  test("parses TypeScript file correctly", async () => {
    const testFile = "./test/fixtures/sample.ts";
    const result = await parserManager.parseFile(testFile);
    
    expect(result.language).toBe("typescript");
    expect(result.tree).toBeDefined();
    expect(result.tree.rootNode.type).toBe("program");
  });
  
  test("caches parse results", async () => {
    const testFile = "./test/fixtures/sample.ts";
    
    const start1 = performance.now();
    await parserManager.parseFile(testFile);
    const time1 = performance.now() - start1;
    
    const start2 = performance.now();
    await parserManager.parseFile(testFile);
    const time2 = performance.now() - start2;
    
    // Cached should be much faster
    expect(time2).toBeLessThan(time1 / 2);
  });
});
```

#### 2.7.2 Integration Tests

**File: `control-plane/test/context/integration.test.ts`**
```typescript
import { expect, test, describe } from "bun:test";
import { ContextService } from "../../src/services/context/context-service";

describe("Context Service Integration", () => {
  let contextService: ContextService;
  
  beforeAll(() => {
    contextService = new ContextService();
  });
  
  test("generates context for workspace", async () => {
    const context = await contextService.generateContext("./test/fixtures/sample-project");
    
    expect(context.codeMap).toBeDefined();
    expect(context.codeMap.functions.length).toBeGreaterThan(0);
    expect(context.metadata.totalTokens).toBeGreaterThan(0);
  });
  
  test("respects token limits", async () => {
    const context = await contextService.generateContext("./test/fixtures/sample-project", {
      rules: { maxTokens: 1000 }
    });
    
    expect(context.metadata.totalTokens).toBeLessThanOrEqual(1000);
  });
  
  test("applies task-specific rules", async () => {
    const debugContext = await contextService.generateContext("./test/fixtures/sample-project", {
      taskType: 'debugging'
    });
    
    const refactorContext = await contextService.generateContext("./test/fixtures/sample-project", {
      taskType: 'refactoring'
    });
    
    // Different tasks should produce different selections
    expect(debugContext.codeMap.functions).not.toEqual(refactorContext.codeMap.functions);
  });
});
```

### Phase 2.8: Performance Benchmarks (Day 17)

**File: `control-plane/benchmark/context-performance.ts`**
```typescript
async function benchmarkContextGeneration() {
  const workspaces = [
    { path: "./small-project", files: 100 },
    { path: "./medium-project", files: 1000 },
    { path: "./large-project", files: 10000 }
  ];
  
  for (const workspace of workspaces) {
    console.log(`\nBenchmarking ${workspace.path} (${workspace.files} files)`);
    
    // Cold start
    const coldStart = performance.now();
    await contextService.generateContext(workspace.path);
    const coldTime = performance.now() - coldStart;
    
    // Warm cache
    const warmStart = performance.now();
    await contextService.generateContext(workspace.path);
    const warmTime = performance.now() - warmStart;
    
    console.log(`  Cold start: ${coldTime.toFixed(2)}ms`);
    console.log(`  Warm cache: ${warmTime.toFixed(2)}ms`);
    console.log(`  Speedup: ${(coldTime / warmTime).toFixed(2)}x`);
  }
}
```

## Success Criteria

### Performance Metrics
- [ ] Code map generation < 5 seconds for 10K files
- [ ] Cached context retrieval < 100ms
- [ ] Incremental updates < 500ms
- [ ] Token counting accuracy > 99%
- [ ] Memory usage < 500MB for large repos

### Functionality
- [ ] Support for 5+ programming languages
- [ ] Accurate symbol extraction
- [ ] Working RepoPrompt rules
- [ ] Real-time file watching
- [ ] Incremental parsing

### Quality
- [ ] Test coverage > 80%
- [ ] Zero memory leaks
- [ ] Graceful error handling
- [ ] Comprehensive logging

## Implementation Timeline

| Day | Task | Deliverable |
|-----|------|------------|
| 1-3 | Tree-sitter Foundation | Parser infrastructure, language support |
| 4-6 | Symbol Extraction | Code map generator, symbol ranking |
| 7-9 | RepoPrompt Rules | Selection engine, priority rules |
| 10-11 | Token Counting | Model limits, optimization strategies |
| 12-13 | Caching Layer | Memory/disk cache, performance optimization |
| 14-15 | Integration | Control plane API updates, service wiring |
| 16 | Testing | Unit and integration test suites |
| 17 | Benchmarks | Performance validation and optimization |

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tree-sitter performance | High | Implement aggressive caching, incremental parsing |
| Memory usage for large repos | High | Streaming processing, pagination, LRU eviction |
| Token counting accuracy | Medium | Use official tokenizers, extensive testing |
| Cache invalidation bugs | Medium | Clear invalidation rules, comprehensive tests |

## Dependencies

```json
{
  "dependencies": {
    "tree-sitter": "^0.20.0",
    "tree-sitter-typescript": "^0.20.0",
    "tree-sitter-javascript": "^0.20.0",
    "tree-sitter-python": "^0.20.0",
    "tree-sitter-rust": "^0.20.0",
    "tree-sitter-go": "^0.20.0",
    "tiktoken": "^1.0.0",
    "zod": "^4.0.0"
  }
}
```

## API Changes

### New Endpoints

```typescript
// Get code map for workspace
GET /api/context/code-map?workspace=/path/to/workspace

// Generate context with options
POST /api/context/generate
Body: {
  workspace: string,
  taskType?: string,
  anchor?: string,
  rules?: Partial<SelectionRules>
}

// Get token count
POST /api/context/tokens
Body: {
  content: string,
  model: string
}

// Clear cache
DELETE /api/context/cache?workspace=/path/to/workspace
```

## Monitoring & Observability

### Metrics to Track
- Code map generation time
- Cache hit/miss rates
- Token counting accuracy
- Memory usage
- Parser performance by language
- Selection rule effectiveness

### Logging Strategy
```typescript
logger.info('context.generation.started', { workspace, options });
logger.debug('context.cache.hit', { key, size, ttl });
logger.warn('context.token.limit.exceeded', { limit, actual });
logger.error('context.parser.failed', { file, language, error });
```

## Documentation Requirements

1. **API Documentation**: OpenAPI spec for new endpoints
2. **Configuration Guide**: How to customize selection rules
3. **Performance Tuning**: Cache settings, parser optimization
4. **Language Support**: Adding new languages guide
5. **Integration Examples**: Using context in AI workflows

---

## Phase 2 Completion Checklist

### Core Implementation
- [ ] Parser infrastructure with 5+ languages
- [ ] Symbol extraction with ranking
- [ ] Code map generation
- [ ] RepoPrompt selection rules
- [ ] Token counting and optimization
- [ ] Cache layer with LRU eviction
- [ ] File watching and incremental updates
- [ ] Control plane integration

### Testing & Validation
- [ ] Unit tests (>80% coverage)
- [ ] Integration tests
- [ ] Performance benchmarks
- [ ] Memory leak testing
- [ ] Token accuracy validation

### Documentation
- [ ] API documentation
- [ ] Configuration guide
- [ ] Architecture diagrams
- [ ] Troubleshooting guide

### Deployment
- [ ] Database migrations
- [ ] Environment configuration
- [ ] Monitoring setup
- [ ] Performance baselines

---

*Phase 2 represents the intelligence layer of the AI-First Terminal IDE. Upon completion, the system will provide sophisticated, token-aware context management that enables efficient AI-assisted development at scale.*