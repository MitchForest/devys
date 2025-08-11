// AI Context Builder for Phase 4
// Intelligent file selection with learning capabilities and token optimization

import { Database } from 'bun:sqlite';
import { MerkleTreeService } from '../services/merkle';
import { SymbolExtractor } from '../services/parser/symbol-extractor';
import { TokenCounter } from '../services/tokens/token-counter';
import { PHASE_4_ROUTER_CONFIG } from '../routing/claude-code-router-config';
import { GitManager } from '../services/git/git-manager';

export interface ContextBuildRequest {
  task: string;
  files?: string[];
  includeCodeMaps?: boolean;
  includeRecentChanges?: boolean;
  maxTokens?: number;
  modelTarget?: string;
  priority?: 'accuracy' | 'speed' | 'cost';
}

export interface ContextResult {
  files: string[];
  totalTokens: number;
  scores: Record<string, number>;
  rationale: string;
  modelRecommendation: string;
  estimatedCost: number;
  cacheHit: boolean;
}

export interface Symbol {
  name: string;
  type: 'function' | 'class' | 'interface' | 'variable' | 'type';
  file: string;
  line: number;
  dependencies: string[];
  exports: boolean;
}

export interface DependencyGraph {
  nodes: Map<string, Symbol[]>;
  edges: Map<string, string[]>;
  weights: Map<string, number>;
}

export interface AccessPattern {
  files: string[];
  frequency: number;
  lastAccessed: number;
  context: string;
}

const STOP_WORDS = new Set([
  'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by',
  'from', 'up', 'about', 'into', 'through', 'during', 'before', 'after', 'above',
  'below', 'between', 'among', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should'
]);

/**
 * AI Context Builder - Intelligent file selection for optimal context
 */
export class AIContextBuilder {
  private merkleTree: MerkleTreeService;
  private symbolExtractor: SymbolExtractor;
  private tokenCounter: TokenCounter;
  private gitManager: GitManager;
  private db: Database;
  
  // Caching for performance
  private contextCache: Map<string, ContextResult>;
  private symbolCache: Map<string, Symbol[]>;
  private dependencyCache: Map<string, DependencyGraph>;
  
  // Learning system
  private accessPatterns: AccessPattern[];
  private cooccurrenceMatrix: Map<string, Map<string, number>>;
  private fileScores: Map<string, number>;
  
  constructor(workspace: string, db: Database) {
    this.db = db;
    this.merkleTree = new MerkleTreeService(workspace, db);
    this.symbolExtractor = new SymbolExtractor(db);
    this.tokenCounter = new TokenCounter();
    this.gitManager = new GitManager(workspace);
    
    // Initialize caches
    this.contextCache = new Map();
    this.symbolCache = new Map();
    this.dependencyCache = new Map();
    
    // Initialize learning data
    this.accessPatterns = [];
    this.cooccurrenceMatrix = new Map();
    this.fileScores = new Map();
    
    this.initializeDatabase();
    this.loadLearningData();
  }
  
  private initializeDatabase(): void {
    // Context cache table
    this.db.run(`
      CREATE TABLE IF NOT EXISTS context_cache (
        id TEXT PRIMARY KEY,
        task_hash TEXT NOT NULL,
        files TEXT NOT NULL, -- JSON array
        total_tokens INTEGER NOT NULL,
        scores TEXT NOT NULL, -- JSON object
        model_recommendation TEXT,
        estimated_cost REAL,
        created_at INTEGER NOT NULL,
        accessed_count INTEGER DEFAULT 1,
        last_accessed INTEGER NOT NULL
      )
    `);
    
    // Access patterns for learning
    this.db.run(`
      CREATE TABLE IF NOT EXISTS access_patterns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        files TEXT NOT NULL, -- JSON array
        context TEXT NOT NULL,
        frequency INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_accessed INTEGER NOT NULL
      )
    `);
    
    // File co-occurrence matrix
    this.db.run(`
      CREATE TABLE IF NOT EXISTS file_cooccurrence (
        file1 TEXT NOT NULL,
        file2 TEXT NOT NULL,
        count INTEGER NOT NULL,
        last_updated INTEGER NOT NULL,
        PRIMARY KEY (file1, file2)
      )
    `);
    
    // Context quality feedback
    this.db.run(`
      CREATE TABLE IF NOT EXISTS context_feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        context_id TEXT NOT NULL,
        rating INTEGER NOT NULL, -- 1-5 stars
        feedback_type TEXT, -- 'accuracy', 'completeness', 'relevance'
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    `);
  }
  
  private loadLearningData(): void {
    // Load access patterns
    const patterns = this.db.query('SELECT * FROM access_patterns ORDER BY last_accessed DESC LIMIT 1000').all() as any[];
    this.accessPatterns = patterns.map(p => ({
      files: JSON.parse(p.files),
      frequency: p.frequency,
      lastAccessed: p.last_accessed,
      context: p.context
    }));
    
    // Load co-occurrence matrix
    const cooccurrences = this.db.query('SELECT * FROM file_cooccurrence').all() as any[];
    for (const co of cooccurrences) {
      if (!this.cooccurrenceMatrix.has(co.file1)) {
        this.cooccurrenceMatrix.set(co.file1, new Map());
      }
      this.cooccurrenceMatrix.get(co.file1)!.set(co.file2, co.count);
    }
    
    console.log(`Loaded ${this.accessPatterns.length} access patterns and ${cooccurrences.length} co-occurrences`);
  }
  
  /**
   * Build context with intelligent file selection
   */
  async buildContext(request: ContextBuildRequest): Promise<ContextResult> {
    const startTime = Date.now();
    
    // Generate cache key
    const cacheKey = this.generateCacheKey(request);
    
    // Check cache first
    const cached = this.contextCache.get(cacheKey) || this.loadFromCache(cacheKey);
    if (cached && this.isCacheValid(cached, request)) {
      this.updateCacheAccess(cacheKey);
      return { ...cached, cacheHit: true };
    }
    
    try {
      // Step 1: Extract keywords and analyze task
      const keywords = await this.extractKeywords(request.task);
      const taskComplexity = this.analyzeTaskComplexity(request.task, keywords);
      
      // Step 2: Search for relevant symbols and files
      const symbols = await this.searchSymbols(keywords);
      const candidateFiles = await this.getCandidateFiles(request, symbols);
      
      // Step 3: Build dependency graph
      const dependencyGraph = await this.analyzeDependencies(candidateFiles);
      
      // Step 4: Score files by relevance
      const scores = await this.scoreFiles(candidateFiles, request, keywords, dependencyGraph);
      
      // Step 5: Apply learning from access patterns
      const learnedScores = this.applyLearning(scores, request.task);
      
      // Step 6: Select optimal files within token budget
      const selection = await this.selectOptimalFiles(learnedScores, request);
      
      // Step 7: Generate rationale and recommendations
      const rationale = this.generateRationale(selection, request, taskComplexity);
      const modelRecommendation = this.recommendModel(selection.totalTokens, taskComplexity);
      const estimatedCost = this.estimateCost(selection.totalTokens, modelRecommendation);
      
      const result: ContextResult = {
        files: selection.files,
        totalTokens: selection.totalTokens,
        scores: learnedScores,
        rationale,
        modelRecommendation,
        estimatedCost,
        cacheHit: false
      };
      
      // Cache the result
      this.cacheResult(cacheKey, result);
      
      // Record access pattern for learning
      await this.recordAccessPattern(result.files, request.task);
      
      console.log(`Context built in ${Date.now() - startTime}ms: ${result.files.length} files, ${result.totalTokens} tokens`);
      
      return result;
      
    } catch (error) {
      console.error('Context building failed:', error);
      throw error;
    }
  }
  
  /**
   * Extract keywords using NLP techniques
   */
  private async extractKeywords(task: string): Promise<string[]> {
    const tokens = task.toLowerCase()
      .replace(/[^\w\s]/g, ' ')
      .split(/\s+/)
      .filter(token => token.length > 2 && !STOP_WORDS.has(token));
    
    // Extract technical terms, file names, function names
    const technicalTerms = tokens.filter(token => 
      token.includes('_') || 
      token.includes('-') ||
      /[A-Z]/.test(token) || // CamelCase
      token.endsWith('.ts') ||
      token.endsWith('.js') ||
      token.endsWith('.py')
    );
    
    // Combine and deduplicate
    const keywords = [...new Set([...tokens, ...technicalTerms])];
    
    // Weight keywords by importance
    return keywords.sort((a, b) => {
      const aWeight = this.getKeywordWeight(a);
      const bWeight = this.getKeywordWeight(b);
      return bWeight - aWeight;
    }).slice(0, 20); // Top 20 keywords
  }
  
  private getKeywordWeight(keyword: string): number {
    let weight = 1;
    
    // Technical indicators get higher weight
    if (keyword.includes('function') || keyword.includes('class')) weight += 3;
    if (keyword.includes('error') || keyword.includes('bug') || keyword.includes('fix')) weight += 2;
    if (keyword.includes('api') || keyword.includes('endpoint')) weight += 2;
    if (keyword.includes('test') || keyword.includes('spec')) weight += 1.5;
    if (keyword.includes('.ts') || keyword.includes('.js')) weight += 2;
    
    // Camel case suggests code terms
    if (/[A-Z]/.test(keyword)) weight += 1.5;
    
    return weight;
  }
  
  /**
   * Analyze task complexity
   */
  private analyzeTaskComplexity(task: string, keywords: string[]): 'simple' | 'moderate' | 'complex' {
    const complexityIndicators = {
      simple: ['format', 'style', 'comment', 'rename', 'delete'],
      moderate: ['add', 'update', 'modify', 'change', 'implement'],
      complex: ['refactor', 'optimize', 'debug', 'architecture', 'design', 'migrate', 'integrate']
    };
    
    const taskLower = task.toLowerCase();
    
    // Check for complexity indicators
    for (const [level, indicators] of Object.entries(complexityIndicators)) {
      if (indicators.some(indicator => taskLower.includes(indicator))) {
        return level as 'simple' | 'moderate' | 'complex';
      }
    }
    
    // Consider keyword complexity
    const technicalKeywords = keywords.filter(k => 
      k.includes('_') || /[A-Z]/.test(k) || k.includes('.')
    );
    
    if (technicalKeywords.length > 10) return 'complex';
    if (technicalKeywords.length > 5) return 'moderate';
    return 'simple';
  }
  
  /**
   * Search for symbols based on keywords
   */
  private async searchSymbols(keywords: string[]): Promise<Symbol[]> {
    const symbols: Symbol[] = [];
    
    for (const keyword of keywords) {
      // Check symbol cache first
      const cacheKey = `symbols:${keyword}`;
      let keywordSymbols = this.symbolCache.get(cacheKey);
      
      if (!keywordSymbols) {
        // Extract symbols from code
        keywordSymbols = await this.symbolExtractor.search(keyword);
        this.symbolCache.set(cacheKey, keywordSymbols);
      }
      
      symbols.push(...keywordSymbols);
    }
    
    // Deduplicate by file and name
    const uniqueSymbols = symbols.filter((symbol, index, arr) => 
      arr.findIndex(s => s.file === symbol.file && s.name === symbol.name) === index
    );
    
    return uniqueSymbols;
  }
  
  /**
   * Get candidate files from multiple sources
   */
  private async getCandidateFiles(request: ContextBuildRequest, symbols: Symbol[]): Promise<string[]> {
    const candidates = new Set<string>();
    
    // Files from symbols
    symbols.forEach(symbol => candidates.add(symbol.file));
    
    // Explicitly requested files
    if (request.files) {
      request.files.forEach(file => candidates.add(file));
    }
    
    // Recently modified files (if requested)
    if (request.includeRecentChanges) {
      const recentFiles = await this.gitManager.getRecentlyChangedFiles(7); // Last 7 days
      recentFiles.forEach(file => candidates.add(file));
    }
    
    // Files from access patterns
    const relatedFiles = this.getRelatedFilesFromPatterns(request.task);
    relatedFiles.forEach(file => candidates.add(file));
    
    return Array.from(candidates).filter(file => this.isValidFile(file));
  }
  
  private isValidFile(file: string): boolean {
    // Filter out non-source files
    const validExtensions = ['.ts', '.js', '.tsx', '.jsx', '.py', '.java', '.cpp', '.c', '.h', '.rs', '.go'];
    const hasValidExt = validExtensions.some(ext => file.endsWith(ext));
    
    // Exclude node_modules, build directories, etc.
    const excludePatterns = ['node_modules', 'dist/', 'build/', '.git/', 'target/'];
    const isExcluded = excludePatterns.some(pattern => file.includes(pattern));
    
    return hasValidExt && !isExcluded;
  }
  
  /**
   * Analyze dependencies between files
   */
  private async analyzeDependencies(files: string[]): Promise<DependencyGraph> {
    const cacheKey = `deps:${files.sort().join(':')}`;
    let graph = this.dependencyCache.get(cacheKey);
    
    if (!graph) {
      graph = {
        nodes: new Map(),
        edges: new Map(),
        weights: new Map()
      };
      
      // Build dependency graph
      for (const file of files) {
        const fileSymbols = await this.symbolExtractor.getFileSymbols(file);
        graph.nodes.set(file, fileSymbols);
        
        // Analyze imports/dependencies
        const dependencies = await this.symbolExtractor.getFileDependencies(file);
        graph.edges.set(file, dependencies);
        
        // Calculate weights based on dependency count and symbol count
        const weight = dependencies.length + fileSymbols.length * 0.5;
        graph.weights.set(file, weight);
      }
      
      this.dependencyCache.set(cacheKey, graph);
    }
    
    return graph;
  }
  
  /**
   * Score files by relevance
   */
  private async scoreFiles(
    files: string[],
    request: ContextBuildRequest,
    keywords: string[],
    dependencies: DependencyGraph
  ): Promise<Record<string, number>> {
    const scores: Record<string, number> = {};
    
    for (const file of files) {
      let score = 0;
      
      // Base score from keywords matching file content
      score += await this.calculateKeywordMatch(file, keywords);
      
      // Recent modification boost
      const lastModified = await this.getLastModified(file);
      const hoursSince = (Date.now() - lastModified) / 3600000;
      if (hoursSince < 1) score += 20;
      else if (hoursSince < 24) score += 10;
      else if (hoursSince < 168) score += 5; // 1 week
      
      // Dependency importance
      const deps = dependencies.edges.get(file) || [];
      score += deps.length * 2;
      
      // File type importance
      if (file.includes('index') || file.includes('main')) score += 15;
      if (file.includes('.test.') || file.includes('.spec.')) score += 5;
      if (file.includes('config') || file.includes('setup')) score += 8;
      
      // Working set boost (files modified in current git branch)
      if (await this.isInWorkingSet(file)) score += 25;
      
      // Symbol density (more symbols = more important)
      const symbols = dependencies.nodes.get(file) || [];
      score += symbols.length * 0.5;
      
      // File size penalty (very large files might be less relevant)
      const fileSize = await this.getFileSize(file);
      if (fileSize > 10000) score -= 5; // Penalty for large files
      if (fileSize > 50000) score -= 15;
      
      scores[file] = Math.max(0, score);
    }
    
    return scores;
  }
  
  private async calculateKeywordMatch(file: string, keywords: string[]): Promise<number> {
    try {
      const content = await Bun.file(file).text();
      const contentLower = content.toLowerCase();
      
      let matches = 0;
      for (const keyword of keywords) {
        // Count occurrences with weight
        const occurrences = (contentLower.match(new RegExp(keyword.toLowerCase(), 'g')) || []).length;
        matches += occurrences * this.getKeywordWeight(keyword);
      }
      
      return Math.min(matches, 50); // Cap at 50 points
    } catch {
      return 0;
    }
  }
  
  private async getLastModified(file: string): Promise<number> {
    try {
      const stat = await Bun.file(file).stat();
      return stat?.mtime?.getTime() || 0;
    } catch {
      return 0;
    }
  }
  
  private async getFileSize(file: string): Promise<number> {
    try {
      return await Bun.file(file).size;
    } catch {
      return 0;
    }
  }
  
  private async isInWorkingSet(file: string): Promise<boolean> {
    try {
      const modifiedFiles = await this.gitManager.getModifiedFiles();
      return modifiedFiles.includes(file);
    } catch {
      return false;
    }
  }
  
  /**
   * Apply learning from access patterns
   */
  private applyLearning(scores: Record<string, number>, task: string): Record<string, number> {
    const learnedScores = { ...scores };
    
    // Find similar tasks from access patterns
    const similarPatterns = this.findSimilarPatterns(task);
    
    for (const pattern of similarPatterns) {
      const similarity = this.calculateTaskSimilarity(task, pattern.context);
      const boost = similarity * pattern.frequency * 0.1; // Scale boost
      
      for (const file of pattern.files) {
        if (learnedScores[file] !== undefined) {
          learnedScores[file] += boost;
        }
      }
    }
    
    // Apply co-occurrence boosting
    const highScoreFiles = Object.entries(learnedScores)
      .filter(([, score]) => score > 30)
      .map(([file]) => file);
    
    for (const file of highScoreFiles) {
      const cooccurrences = this.cooccurrenceMatrix.get(file);
      if (cooccurrences) {
        for (const [coFile, count] of cooccurrences) {
          if (learnedScores[coFile] !== undefined) {
            learnedScores[coFile] += Math.min(count * 0.5, 10); // Cap boost at 10
          }
        }
      }
    }
    
    return learnedScores;
  }
  
  private findSimilarPatterns(task: string): AccessPattern[] {
    const taskTokens = new Set(task.toLowerCase().split(/\s+/));
    
    return this.accessPatterns
      .map(pattern => ({
        ...pattern,
        similarity: this.calculateTaskSimilarity(task, pattern.context)
      }))
      .filter(p => p.similarity > 0.3) // Minimum similarity threshold
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, 10); // Top 10 similar patterns
  }
  
  private calculateTaskSimilarity(task1: string, task2: string): number {
    const tokens1 = new Set(task1.toLowerCase().split(/\s+/));
    const tokens2 = new Set(task2.toLowerCase().split(/\s+/));
    
    const intersection = new Set([...tokens1].filter(token => tokens2.has(token)));
    const union = new Set([...tokens1, ...tokens2]);
    
    return intersection.size / union.size; // Jaccard similarity
  }
  
  private getRelatedFilesFromPatterns(task: string): string[] {
    const similarPatterns = this.findSimilarPatterns(task);
    const relatedFiles = new Set<string>();
    
    for (const pattern of similarPatterns.slice(0, 3)) { // Top 3 patterns
      pattern.files.forEach(file => relatedFiles.add(file));
    }
    
    return Array.from(relatedFiles);
  }
  
  /**
   * Select optimal files within token budget
   */
  private async selectOptimalFiles(
    scores: Record<string, number>,
    request: ContextBuildRequest
  ): Promise<{ files: string[]; totalTokens: number }> {
    // Sort files by score
    const sortedFiles = Object.entries(scores)
      .sort(([, a], [, b]) => b - a);
    
    const maxTokens = request.maxTokens || this.getDefaultMaxTokens(request.modelTarget);
    const selected: string[] = [];
    let totalTokens = 0;
    
    // Add files while staying within token budget (leave 20% buffer)
    const tokenBudget = Math.floor(maxTokens * 0.8);
    
    for (const [file, score] of sortedFiles) {
      if (score < 1) break; // Skip very low relevance files
      
      const fileTokens = await this.tokenCounter.countFile(file);
      if (totalTokens + fileTokens <= tokenBudget) {
        selected.push(file);
        totalTokens += fileTokens;
      }
    }
    
    // Ensure we have at least some files even if they exceed budget
    if (selected.length === 0 && sortedFiles.length > 0) {
      const [topFile] = sortedFiles[0];
      selected.push(topFile);
      totalTokens = await this.tokenCounter.countFile(topFile);
    }
    
    return { files: selected, totalTokens };
  }
  
  private getDefaultMaxTokens(modelTarget?: string): number {
    if (!modelTarget) return 100000; // Default
    
    // Look up model's context limit
    for (const provider of Object.values(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider.models[modelTarget]) {
        return provider.models[modelTarget].maxTokens;
      }
    }
    
    return 100000; // Fallback
  }
  
  /**
   * Generate explanation of context selection
   */
  private generateRationale(
    selection: { files: string[]; totalTokens: number },
    request: ContextBuildRequest,
    complexity: string
  ): string {
    const rationale = [
      `Selected ${selection.files.length} files (${selection.totalTokens} tokens) for ${complexity} task.`,
      `Context optimized for: ${request.priority || 'accuracy'}`
    ];
    
    // Add specific reasoning
    if (selection.files.length > 10) {
      rationale.push(`Large context selected due to task complexity and extensive dependencies.`);
    } else if (selection.files.length < 3) {
      rationale.push(`Focused context selected for targeted changes.`);
    }
    
    if (request.includeRecentChanges) {
      rationale.push(`Included recently modified files for context awareness.`);
    }
    
    return rationale.join(' ');
  }
  
  /**
   * Recommend model based on context size and complexity
   */
  private recommendModel(tokens: number, complexity: string): string {
    // Use routing config logic
    if (complexity === 'simple' && tokens < 32000) {
      return 'qwen2.5-coder:14b'; // Local model for simple tasks
    }
    
    if (tokens > 500000) {
      return 'gemini-2.0-flash-thinking'; // Large context model
    }
    
    if (complexity === 'complex') {
      return 'claude-3-5-sonnet'; // High quality model
    }
    
    if (tokens < 50000) {
      return 'claude-3-5-haiku'; // Fast model for small contexts
    }
    
    return 'claude-3-5-sonnet'; // Default to high quality
  }
  
  private estimateCost(tokens: number, model: string): number {
    // Look up model cost
    for (const provider of Object.values(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider.models[model]) {
        return tokens * provider.models[model].cost;
      }
    }
    
    return 0; // Free model or unknown
  }
  
  /**
   * Caching and persistence
   */
  private generateCacheKey(request: ContextBuildRequest): string {
    const key = {
      task: request.task,
      files: request.files?.sort(),
      includeCodeMaps: request.includeCodeMaps,
      includeRecentChanges: request.includeRecentChanges,
      maxTokens: request.maxTokens,
      modelTarget: request.modelTarget
    };
    
    return Buffer.from(JSON.stringify(key)).toString('base64').slice(0, 32);
  }
  
  private isCacheValid(cached: ContextResult, request: ContextBuildRequest): boolean {
    // Cache is valid for 1 hour for most requests
    const cacheAge = Date.now() - (cached as any).createdAt || 0;
    const maxAge = request.includeRecentChanges ? 300000 : 3600000; // 5 min vs 1 hour
    
    return cacheAge < maxAge;
  }
  
  private loadFromCache(cacheKey: string): ContextResult | null {
    const row = this.db.query('SELECT * FROM context_cache WHERE id = ?').get(cacheKey) as any;
    
    if (!row) return null;
    
    return {
      files: JSON.parse(row.files),
      totalTokens: row.total_tokens,
      scores: JSON.parse(row.scores),
      rationale: row.rationale || '',
      modelRecommendation: row.model_recommendation,
      estimatedCost: row.estimated_cost,
      cacheHit: true
    };
  }
  
  private cacheResult(cacheKey: string, result: ContextResult): void {
    this.contextCache.set(cacheKey, result);
    
    this.db.run(
      `INSERT OR REPLACE INTO context_cache 
       (id, task_hash, files, total_tokens, scores, model_recommendation, estimated_cost, created_at, last_accessed)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        cacheKey,
        cacheKey.slice(0, 16),
        JSON.stringify(result.files),
        result.totalTokens,
        JSON.stringify(result.scores),
        result.modelRecommendation,
        result.estimatedCost,
        Date.now(),
        Date.now()
      ]
    );
  }
  
  private updateCacheAccess(cacheKey: string): void {
    this.db.run(
      'UPDATE context_cache SET accessed_count = accessed_count + 1, last_accessed = ? WHERE id = ?',
      [Date.now(), cacheKey]
    );
  }
  
  /**
   * Record access pattern for learning
   */
  private async recordAccessPattern(files: string[], task: string): Promise<void> {
    // Update co-occurrence matrix
    for (let i = 0; i < files.length; i++) {
      for (let j = i + 1; j < files.length; j++) {
        const file1 = files[i];
        const file2 = files[j];
        
        // Ensure consistent ordering
        const [f1, f2] = file1 < file2 ? [file1, file2] : [file2, file1];
        
        if (!this.cooccurrenceMatrix.has(f1)) {
          this.cooccurrenceMatrix.set(f1, new Map());
        }
        
        const current = this.cooccurrenceMatrix.get(f1)!.get(f2) || 0;
        this.cooccurrenceMatrix.get(f1)!.set(f2, current + 1);
        
        // Update database
        this.db.run(
          `INSERT OR REPLACE INTO file_cooccurrence (file1, file2, count, last_updated)
           VALUES (?, ?, ?, ?)`,
          [f1, f2, current + 1, Date.now()]
        );
      }
    }
    
    // Record access pattern
    this.db.run(
      `INSERT INTO access_patterns (session_id, files, context, created_at, last_accessed)
       VALUES (?, ?, ?, ?, ?)`,
      [
        'default',
        JSON.stringify(files),
        task.slice(0, 500), // Truncate long tasks
        Date.now(),
        Date.now()
      ]
    );
  }
  
  /**
   * Learning and feedback methods
   */
  async recordFeedback(contextId: string, rating: number, type: string, notes?: string): Promise<void> {
    this.db.run(
      `INSERT INTO context_feedback (context_id, rating, feedback_type, notes, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      [contextId, rating, type, notes || null, Date.now()]
    );
  }
  
  async getContextStats(): Promise<any> {
    const cacheStats = this.db.query('SELECT COUNT(*) as total, AVG(accessed_count) as avg_access FROM context_cache').get() as any;
    const patternStats = this.db.query('SELECT COUNT(*) as total FROM access_patterns').get() as any;
    const feedbackStats = this.db.query('SELECT AVG(rating) as avg_rating, COUNT(*) as total FROM context_feedback').get() as any;
    
    return {
      cache: cacheStats,
      patterns: patternStats,
      feedback: feedbackStats,
      cooccurrenceSize: this.cooccurrenceMatrix.size
    };
  }
  
  /**
   * Suggest related files based on learning
   */
  async suggestRelatedFiles(currentFiles: string[], limit: number = 5): Promise<string[]> {
    const suggestions = new Set<string>();
    
    for (const file of currentFiles) {
      const related = this.cooccurrenceMatrix.get(file);
      if (related) {
        const sorted = Array.from(related.entries())
          .sort(([, a], [, b]) => b - a)
          .slice(0, limit);
        
        for (const [relatedFile] of sorted) {
          if (!currentFiles.includes(relatedFile)) {
            suggestions.add(relatedFile);
          }
        }
      }
    }
    
    return Array.from(suggestions).slice(0, limit);
  }
  
  /**
   * Clean up old cache entries
   */
  async cleanupCache(maxAge: number = 7 * 24 * 3600 * 1000): Promise<void> {
    const cutoff = Date.now() - maxAge;
    
    this.db.run('DELETE FROM context_cache WHERE last_accessed < ?', [cutoff]);
    this.db.run('DELETE FROM access_patterns WHERE last_accessed < ?', [cutoff]);
    
    // Clean up in-memory caches
    this.contextCache.clear();
    this.symbolCache.clear();
    this.dependencyCache.clear();
  }
}