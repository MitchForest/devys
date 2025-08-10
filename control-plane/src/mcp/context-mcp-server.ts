import { MCPServer } from './mcp-server';
import {
  MCPCapability,
  MCPRequest,
  MCPResponse,
  MCPConnection,
  MCPErrorCodes
} from '../types/mcp';
import { ContextGenerator } from '../services/context/context-generator';
import { MerkleTreeManager } from '../services/context/merkle-tree';
import { CodeParser } from '../services/context/code-parser';
import { Database } from 'bun:sqlite';
import { EventEmitter } from 'events';

/**
 * Context MCP Server - Provides context intelligence via MCP protocol
 * Implements methods for file mapping, code analysis, and context generation
 */
export class ContextMCPServer extends MCPServer {
  private contextGenerator: ContextGenerator;
  private merkleManager: MerkleTreeManager;
  private codeParser: CodeParser;
  private contextCache: Map<string, { data: any; timestamp: number }>;
  private readonly CACHE_TTL = 60000; // 1 minute cache
  
  constructor(
    private workspace: string,
    port: number,
    db: Database
  ) {
    super(
      {
        name: 'context-mcp',
        port,
        host: 'localhost',
        maxConnections: 50,
        heartbeatInterval: 30000
      },
      db
    );
    
    this.contextGenerator = new ContextGenerator(workspace, db);
    this.merkleManager = new MerkleTreeManager(workspace, db);
    this.codeParser = new CodeParser(workspace);
    this.contextCache = new Map();
    
    // Clean cache periodically
    setInterval(() => this.cleanCache(), 60000);
  }
  
  /**
   * Define server capabilities
   */
  defineCapabilities(): MCPCapability[] {
    return [
      {
        name: 'context',
        version: '1.0.0',
        methods: [
          'getFileMap',
          'getCodeMap',
          'getFullContext',
          'searchSymbols',
          'getWorkingSet',
          'getChangedFiles',
          'analyzeImpact',
          'getSimilarCode',
          'getDocumentation',
          'refreshContext'
        ],
        schema: {
          type: 'object',
          properties: {
            method: {
              type: 'string',
              enum: [
                'getFileMap',
                'getCodeMap',
                'getFullContext',
                'searchSymbols',
                'getWorkingSet',
                'getChangedFiles',
                'analyzeImpact',
                'getSimilarCode',
                'getDocumentation',
                'refreshContext'
              ]
            },
            params: {
              type: 'object'
            }
          }
        }
      },
      {
        name: 'cache',
        version: '1.0.0',
        methods: ['clearCache', 'getCacheStats'],
        schema: {
          type: 'object',
          properties: {
            method: {
              type: 'string',
              enum: ['clearCache', 'getCacheStats']
            }
          }
        }
      }
    ];
  }
  
  /**
   * Handle incoming requests
   */
  async handleRequest(
    request: MCPRequest,
    connection: MCPConnection
  ): Promise<MCPResponse> {
    const startTime = Date.now();
    
    try {
      // Check cache first
      const cacheKey = `${request.method}:${JSON.stringify(request.params)}`;
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        console.log(`Cache hit for ${request.method}`);
        return {
          id: request.id,
          result: cached
        };
      }
      
      let result: any;
      
      switch (request.method) {
        case 'getFileMap':
          result = await this.handleGetFileMap(request.params);
          break;
          
        case 'getCodeMap':
          result = await this.handleGetCodeMap(request.params);
          break;
          
        case 'getFullContext':
          result = await this.handleGetFullContext(request.params);
          break;
          
        case 'searchSymbols':
          result = await this.handleSearchSymbols(request.params);
          break;
          
        case 'getWorkingSet':
          result = await this.handleGetWorkingSet(request.params);
          break;
          
        case 'getChangedFiles':
          result = await this.handleGetChangedFiles(request.params);
          break;
          
        case 'analyzeImpact':
          result = await this.handleAnalyzeImpact(request.params);
          break;
          
        case 'getSimilarCode':
          result = await this.handleGetSimilarCode(request.params);
          break;
          
        case 'getDocumentation':
          result = await this.handleGetDocumentation(request.params);
          break;
          
        case 'refreshContext':
          result = await this.handleRefreshContext(request.params);
          break;
          
        case 'clearCache':
          result = await this.handleClearCache();
          break;
          
        case 'getCacheStats':
          result = await this.handleGetCacheStats();
          break;
          
        default:
          throw this.createError(
            MCPErrorCodes.METHOD_NOT_FOUND,
            `Unknown method: ${request.method}`
          );
      }
      
      // Cache successful results
      if (result && this.shouldCache(request.method)) {
        this.putInCache(cacheKey, result);
      }
      
      // Track performance
      const duration = Date.now() - startTime;
      console.log(`${request.method} completed in ${duration}ms`);
      
      // Broadcast updates if context changed
      if (this.isContextModifyingMethod(request.method)) {
        this.broadcast({
          type: 'context-updated',
          method: request.method,
          timestamp: Date.now()
        });
      }
      
      return {
        id: request.id,
        result
      };
      
    } catch (error) {
      console.error(`Error handling ${request.method}:`, error);
      
      return {
        id: request.id,
        error: {
          code: error.code || MCPErrorCodes.INTERNAL_ERROR,
          message: error.message || 'Internal server error',
          data: error.data
        }
      };
    }
  }
  
  /**
   * Get file structure map
   */
  private async handleGetFileMap(params: any): Promise<any> {
    const options = {
      patterns: params.patterns || ['**/*.ts', '**/*.tsx', '**/*.js', '**/*.jsx'],
      excludePatterns: params.excludePatterns || ['node_modules/**', 'dist/**'],
      maxDepth: params.maxDepth || 10
    };
    
    const fileMap = await this.contextGenerator.getFileMap(options);
    
    return {
      files: fileMap.files,
      directories: fileMap.directories,
      totalSize: fileMap.totalSize,
      fileCount: fileMap.fileCount
    };
  }
  
  /**
   * Get code structure map with symbols
   */
  private async handleGetCodeMap(params: any): Promise<any> {
    const options = {
      files: params.files,
      patterns: params.patterns || ['**/*.ts', '**/*.tsx'],
      includeImports: params.includeImports !== false,
      includeExports: params.includeExports !== false,
      maxDepth: params.maxDepth || 3
    };
    
    const codeMap = await this.contextGenerator.getCodeMap(options);
    
    return {
      symbols: codeMap.symbols,
      dependencies: codeMap.dependencies,
      exports: codeMap.exports,
      imports: codeMap.imports,
      symbolCount: codeMap.symbolCount
    };
  }
  
  /**
   * Get full context for AI processing
   */
  private async handleGetFullContext(params: any): Promise<any> {
    const options = {
      files: params.files,
      patterns: params.patterns,
      maxTokens: params.maxTokens || 10000,
      includeTests: params.includeTests || false,
      includeComments: params.includeComments !== false,
      format: params.format || 'xml'
    };
    
    const context = await this.contextGenerator.generateContext(options);
    
    return {
      content: context.content,
      metadata: context.metadata,
      selectedFiles: context.selectedFiles,
      truncated: context.truncated
    };
  }
  
  /**
   * Search for symbols across codebase
   */
  private async handleSearchSymbols(params: any): Promise<any> {
    if (!params.query) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Query parameter is required'
      );
    }
    
    const options = {
      query: params.query,
      type: params.type, // 'function', 'class', 'interface', etc.
      caseSensitive: params.caseSensitive || false,
      maxResults: params.maxResults || 100
    };
    
    const results = await this.codeParser.searchSymbols(options);
    
    return {
      results: results.map(r => ({
        name: r.name,
        type: r.type,
        file: r.file,
        line: r.line,
        column: r.column,
        context: r.context
      })),
      totalMatches: results.length
    };
  }
  
  /**
   * Get current working set of files
   */
  private async handleGetWorkingSet(params: any): Promise<any> {
    const recentMinutes = params.recentMinutes || 30;
    const cutoffTime = Date.now() - (recentMinutes * 60 * 1000);
    
    // Get recently modified files from Merkle tree
    const changedFiles = await this.merkleManager.getChangedFiles(cutoffTime);
    
    // Get open files (would need IDE integration)
    const openFiles = params.openFiles || [];
    
    // Combine and deduplicate
    const workingSet = new Set([...changedFiles, ...openFiles]);
    
    // Get file details
    const files = await Promise.all(
      Array.from(workingSet).map(async (file) => {
        const stats = await Bun.file(`${this.workspace}/${file}`).stat();
        const symbols = await this.codeParser.parseFile(file);
        
        return {
          path: file,
          size: stats.size,
          modified: stats.mtime,
          symbolCount: symbols.length,
          symbols: symbols.slice(0, 10) // First 10 symbols
        };
      })
    );
    
    return {
      files,
      totalFiles: files.length,
      totalSize: files.reduce((sum, f) => sum + f.size, 0)
    };
  }
  
  /**
   * Get files changed since a timestamp
   */
  private async handleGetChangedFiles(params: any): Promise<any> {
    const since = params.since || Date.now() - 3600000; // Default: last hour
    const includeDeleted = params.includeDeleted || false;
    
    const changes = await this.merkleManager.getChangesSince(since);
    
    return {
      added: changes.added,
      modified: changes.modified,
      deleted: includeDeleted ? changes.deleted : [],
      timestamp: Date.now(),
      changeCount: changes.added.length + changes.modified.length + 
                  (includeDeleted ? changes.deleted.length : 0)
    };
  }
  
  /**
   * Analyze impact of changes
   */
  private async handleAnalyzeImpact(params: any): Promise<any> {
    if (!params.files || params.files.length === 0) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Files parameter is required'
      );
    }
    
    const impactAnalysis = await this.contextGenerator.analyzeImpact(params.files);
    
    return {
      directDependents: impactAnalysis.directDependents,
      transitiveDependents: impactAnalysis.transitiveDependents,
      affectedTests: impactAnalysis.affectedTests,
      riskLevel: impactAnalysis.riskLevel,
      suggestions: impactAnalysis.suggestions
    };
  }
  
  /**
   * Find similar code patterns
   */
  private async handleGetSimilarCode(params: any): Promise<any> {
    if (!params.code && !params.file) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Either code or file parameter is required'
      );
    }
    
    let targetCode = params.code;
    
    if (params.file) {
      const file = Bun.file(`${this.workspace}/${params.file}`);
      targetCode = await file.text();
    }
    
    const similarCode = await this.codeParser.findSimilar(targetCode, {
      minSimilarity: params.minSimilarity || 0.7,
      maxResults: params.maxResults || 10,
      excludeFile: params.file
    });
    
    return {
      results: similarCode.map(r => ({
        file: r.file,
        similarity: r.similarity,
        startLine: r.startLine,
        endLine: r.endLine,
        preview: r.preview
      })),
      totalMatches: similarCode.length
    };
  }
  
  /**
   * Get documentation for symbols
   */
  private async handleGetDocumentation(params: any): Promise<any> {
    if (!params.symbol && !params.file) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Either symbol or file parameter is required'
      );
    }
    
    const docs = await this.codeParser.extractDocumentation({
      symbol: params.symbol,
      file: params.file,
      includeExamples: params.includeExamples !== false,
      includeReferences: params.includeReferences !== false
    });
    
    return {
      documentation: docs.documentation,
      examples: docs.examples,
      references: docs.references,
      signature: docs.signature,
      deprecated: docs.deprecated
    };
  }
  
  /**
   * Refresh context and clear caches
   */
  private async handleRefreshContext(params: any): Promise<any> {
    // Clear all caches
    this.contextCache.clear();
    this.contextGenerator.clearCache();
    
    // Rebuild Merkle tree
    await this.merkleManager.rebuild();
    
    // Re-parse critical files
    if (params.files) {
      await Promise.all(
        params.files.map((file: string) => this.codeParser.parseFile(file))
      );
    }
    
    return {
      success: true,
      message: 'Context refreshed',
      timestamp: Date.now()
    };
  }
  
  /**
   * Clear cache
   */
  private async handleClearCache(): Promise<any> {
    const previousSize = this.contextCache.size;
    this.contextCache.clear();
    
    return {
      success: true,
      cleared: previousSize,
      message: `Cleared ${previousSize} cached entries`
    };
  }
  
  /**
   * Get cache statistics
   */
  private async handleGetCacheStats(): Promise<any> {
    const stats = {
      entries: this.contextCache.size,
      hitRate: this.calculateHitRate(),
      memoryUsage: this.estimateCacheMemory(),
      oldestEntry: this.getOldestCacheEntry(),
      newestEntry: this.getNewestCacheEntry()
    };
    
    return stats;
  }
  
  /**
   * Cache management utilities
   */
  private getFromCache(key: string): any | null {
    const entry = this.contextCache.get(key);
    
    if (!entry) return null;
    
    if (Date.now() - entry.timestamp > this.CACHE_TTL) {
      this.contextCache.delete(key);
      return null;
    }
    
    return entry.data;
  }
  
  private putInCache(key: string, data: any): void {
    this.contextCache.set(key, {
      data,
      timestamp: Date.now()
    });
  }
  
  private cleanCache(): void {
    const now = Date.now();
    const expired: string[] = [];
    
    for (const [key, entry] of this.contextCache) {
      if (now - entry.timestamp > this.CACHE_TTL) {
        expired.push(key);
      }
    }
    
    for (const key of expired) {
      this.contextCache.delete(key);
    }
    
    if (expired.length > 0) {
      console.log(`Cleaned ${expired.length} expired cache entries`);
    }
  }
  
  private shouldCache(method: string): boolean {
    // Don't cache methods that modify state
    const noCacheMethods = ['refreshContext', 'clearCache'];
    return !noCacheMethods.includes(method);
  }
  
  private isContextModifyingMethod(method: string): boolean {
    const modifyingMethods = ['refreshContext'];
    return modifyingMethods.includes(method);
  }
  
  private calculateHitRate(): number {
    // Would need to track hits/misses for accurate calculation
    return 0.0;
  }
  
  private estimateCacheMemory(): number {
    // Rough estimate of memory usage
    let totalSize = 0;
    
    for (const [key, entry] of this.contextCache) {
      totalSize += key.length;
      totalSize += JSON.stringify(entry.data).length;
    }
    
    return totalSize;
  }
  
  private getOldestCacheEntry(): number | null {
    let oldest: number | null = null;
    
    for (const entry of this.contextCache.values()) {
      if (!oldest || entry.timestamp < oldest) {
        oldest = entry.timestamp;
      }
    }
    
    return oldest;
  }
  
  private getNewestCacheEntry(): number | null {
    let newest: number | null = null;
    
    for (const entry of this.contextCache.values()) {
      if (!newest || entry.timestamp > newest) {
        newest = entry.timestamp;
      }
    }
    
    return newest;
  }
  
  /**
   * Start the server with additional context-specific initialization
   */
  async start(): Promise<void> {
    // Initialize context systems
    await this.merkleManager.initialize();
    await this.codeParser.initialize();
    
    // Start base server
    await super.start();
    
    console.log(`Context MCP Server ready on port ${this.config.port}`);
    
    // Emit ready event
    this.emit('context-ready', {
      workspace: this.workspace,
      capabilities: this.capabilities
    });
  }
  
  /**
   * Stop the server and cleanup
   */
  async stop(): Promise<void> {
    // Clear caches
    this.contextCache.clear();
    
    // Stop base server
    await super.stop();
    
    console.log('Context MCP Server stopped');
  }
}