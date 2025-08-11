// Context Service for Phase 4
// High-level interface to the AI Context Builder

import { Database } from 'bun:sqlite';
import { AIContextBuilder, ContextBuildRequest, ContextResult } from '../../context/ai-context-builder';

export interface ContextServiceOptions {
  query: string;
  files?: string[];
  includeFiles?: boolean;
  includeCodeMaps?: boolean;
  includeRecentChanges?: boolean;
  maxTokens?: number;
  modelTarget?: string;
  priority?: 'accuracy' | 'speed' | 'cost';
}

export interface EnhancedContextResult extends ContextResult {
  summary: string;
  keyFiles: string[];
  dependencies: string[];
  recommendations: string[];
}

/**
 * Context Service - Provides intelligent context building for AI operations
 * 
 * This service wraps the AIContextBuilder and provides a simpler interface
 * for the workflow controllers and agents.
 */
export class ContextService {
  private contextBuilder: AIContextBuilder;
  private workspace: string;
  private db: Database;
  
  constructor(workspace: string, db: Database) {
    this.workspace = workspace;
    this.db = db;
    this.contextBuilder = new AIContextBuilder(workspace, db);
  }
  
  /**
   * Build context for AI operations
   */
  async buildContext(options: ContextServiceOptions): Promise<EnhancedContextResult> {
    const request: ContextBuildRequest = {
      task: options.query,
      files: options.files,
      includeCodeMaps: options.includeCodeMaps || false,
      includeRecentChanges: options.includeRecentChanges || false,
      maxTokens: options.maxTokens,
      modelTarget: options.modelTarget,
      priority: options.priority || 'accuracy'
    };
    
    const result = await this.contextBuilder.buildContext(request);
    
    // Enhance the result with additional analysis
    const enhanced: EnhancedContextResult = {
      ...result,
      summary: this.generateContextSummary(result, options.query),
      keyFiles: this.identifyKeyFiles(result),
      dependencies: await this.analyzeDependencies(result.files),
      recommendations: this.generateRecommendations(result, options)
    };
    
    return enhanced;
  }
  
  /**
   * Build lightweight context for simple operations
   */
  async buildLightweightContext(query: string, maxTokens: number = 50000): Promise<ContextResult> {
    return this.contextBuilder.buildContext({
      task: query,
      maxTokens,
      priority: 'speed'
    });
  }
  
  /**
   * Build comprehensive context for complex operations
   */
  async buildComprehensiveContext(
    query: string, 
    includeRecent: boolean = true,
    maxTokens: number = 500000
  ): Promise<ContextResult> {
    return this.contextBuilder.buildContext({
      task: query,
      includeCodeMaps: true,
      includeRecentChanges: includeRecent,
      maxTokens,
      priority: 'accuracy'
    });
  }
  
  /**
   * Get context for specific files
   */
  async buildFileContext(files: string[], query: string, maxTokens: number = 100000): Promise<ContextResult> {
    return this.contextBuilder.buildContext({
      task: query,
      files,
      maxTokens,
      priority: 'accuracy'
    });
  }
  
  /**
   * Suggest related files based on current selection
   */
  async suggestRelatedFiles(currentFiles: string[], limit: number = 5): Promise<string[]> {
    return this.contextBuilder.suggestRelatedFiles(currentFiles, limit);
  }
  
  /**
   * Record feedback on context quality
   */
  async recordContextFeedback(
    contextId: string,
    rating: number,
    type: 'accuracy' | 'completeness' | 'relevance',
    notes?: string
  ): Promise<void> {
    await this.contextBuilder.recordFeedback(contextId, rating, type, notes);
  }
  
  /**
   * Get context statistics and performance metrics
   */
  async getContextStats(): Promise<any> {
    return this.contextBuilder.getContextStats();
  }
  
  /**
   * Clean up old context cache
   */
  async cleanupContext(maxAgeMs: number = 7 * 24 * 3600 * 1000): Promise<void> {
    await this.contextBuilder.cleanupCache(maxAgeMs);
  }
  
  /**
   * Private helper methods
   */
  private generateContextSummary(result: ContextResult, query: string): string {
    const fileCount = result.files.length;
    const tokenCount = result.totalTokens;
    const cost = result.estimatedCost;
    const model = result.modelRecommendation;
    
    const parts = [
      `Selected ${fileCount} files (${tokenCount.toLocaleString()} tokens)`,
      `for "${query.slice(0, 50)}${query.length > 50 ? '...' : ''}".`,
      `Recommended model: ${model}.`
    ];
    
    if (cost > 0) {
      parts.push(`Estimated cost: $${cost.toFixed(4)}.`);
    }
    
    if (result.cacheHit) {
      parts.push('(Cache hit)');
    }
    
    return parts.join(' ');
  }
  
  private identifyKeyFiles(result: ContextResult): string[] {
    // Get top-scored files (top 20% or max 5)
    const sortedFiles = Object.entries(result.scores)
      .sort(([, a], [, b]) => b - a);
    
    const keyFileCount = Math.min(5, Math.ceil(sortedFiles.length * 0.2));
    return sortedFiles.slice(0, keyFileCount).map(([file]) => file);
  }
  
  private async analyzeDependencies(files: string[]): Promise<string[]> {
    // Simple dependency analysis - in production this would be more sophisticated
    const dependencies = new Set<string>();
    
    for (const file of files) {
      try {
        const content = await Bun.file(file).text();
        
        // Extract import statements
        const importMatches = content.match(/(?:import|require|from)\s+['"][^'"]+['"]/g);
        if (importMatches) {
          for (const match of importMatches) {
            const dep = match.match(/['"]([^'"]+)['"]/)?.[1];
            if (dep && !dep.startsWith('.')) {
              dependencies.add(dep);
            }
          }
        }
      } catch {
        // Ignore files that can't be read
      }
    }
    
    return Array.from(dependencies).slice(0, 10); // Top 10 dependencies
  }
  
  private generateRecommendations(result: ContextResult, options: ContextServiceOptions): string[] {
    const recommendations = [];
    
    // Token usage recommendations
    if (result.totalTokens > 100000) {
      recommendations.push('Consider using a large-context model like Gemini 2.0 Flash for better performance');
    } else if (result.totalTokens < 10000) {
      recommendations.push('Small context - consider using a fast model like Claude Haiku for quick results');
    }
    
    // Cost optimization recommendations
    if (result.estimatedCost > 0.05) {
      recommendations.push('High cost operation - consider using local models for simple tasks');
    } else if (result.estimatedCost === 0) {
      recommendations.push('Free model recommended - excellent for cost optimization');
    }
    
    // Context quality recommendations
    if (result.files.length < 3) {
      recommendations.push('Limited context - consider including more related files for better accuracy');
    } else if (result.files.length > 20) {
      recommendations.push('Large context - ensure all files are truly relevant to avoid noise');
    }
    
    // Model-specific recommendations
    if (result.modelRecommendation.includes('gemini')) {
      recommendations.push('Gemini selected for large context - excellent for comprehensive analysis');
    } else if (result.modelRecommendation.includes('claude')) {
      recommendations.push('Claude selected for code quality - expect high-quality results');
    } else if (result.modelRecommendation.includes('qwen') || result.modelRecommendation.includes('ollama')) {
      recommendations.push('Local model selected - private and cost-effective');
    }
    
    // Task-specific recommendations
    if (options.query.toLowerCase().includes('refactor')) {
      recommendations.push('Refactoring task detected - ensure comprehensive test coverage');
    } else if (options.query.toLowerCase().includes('debug')) {
      recommendations.push('Debugging task - consider including error logs and related test files');
    } else if (options.query.toLowerCase().includes('test')) {
      recommendations.push('Testing task - verify related source files are included');
    }
    
    return recommendations;
  }
  
  /**
   * Utility methods for context validation
   */
  validateContextSize(files: string[], maxTokens: number): Promise<boolean> {
    // Quick validation without full context building
    return Promise.resolve(files.length * 1000 < maxTokens); // Rough estimate
  }
  
  async estimateContextCost(files: string[], model: string): Promise<number> {
    const totalSize = await Promise.all(
      files.map(async file => {
        try {
          const size = await Bun.file(file).size;
          return size;
        } catch {
          return 0;
        }
      })
    );
    
    const totalTokens = totalSize.reduce((sum, size) => sum + size / 4, 0); // Rough tokenization
    
    // Get model cost from router config
    const costs = {
      'claude-3-5-sonnet': 0.003,
      'claude-3-5-haiku': 0.0008,
      'gemini-2.0-flash': 0,
      'o1': 0.015,
      'deepseek-chat': 0.00014,
      'qwen2.5-coder:14b': 0
    };
    
    const costPerToken = costs[model as keyof typeof costs] || 0.003;
    return totalTokens * costPerToken;
  }
  
  /**
   * Context optimization methods
   */
  async optimizeContextForModel(files: string[], targetModel: string): Promise<string[]> {
    // Get model limits
    const modelLimits = {
      'claude-3-5-sonnet': 200000,
      'claude-3-5-haiku': 200000,
      'gemini-2.0-flash': 1000000,
      'o1': 128000,
      'deepseek-chat': 64000,
      'qwen2.5-coder:14b': 32000
    };
    
    const maxTokens = modelLimits[targetModel as keyof typeof modelLimits] || 100000;
    
    // Simple optimization - remove largest files first if over limit
    let currentTokens = 0;
    const optimizedFiles = [];
    
    // Sort files by size (smaller first for better inclusion rate)
    const filesWithSizes = await Promise.all(
      files.map(async file => ({
        file,
        size: await this.getFileTokenCount(file)
      }))
    );
    
    filesWithSizes.sort((a, b) => a.size - b.size);
    
    for (const { file, size } of filesWithSizes) {
      if (currentTokens + size <= maxTokens * 0.9) { // 90% utilization
        optimizedFiles.push(file);
        currentTokens += size;
      }
    }
    
    return optimizedFiles;
  }
  
  private async getFileTokenCount(file: string): Promise<number> {
    try {
      const size = await Bun.file(file).size;
      return Math.ceil(size / 4); // Rough tokenization
    } catch {
      return 0;
    }
  }
}