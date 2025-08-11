// Claude Code Router Configuration for Phase 4
// Intelligent model routing with cost optimization and grunt mode support

export interface ModelConfig {
  maxTokens: number;
  cost: number;
}

export interface ProviderConfig {
  apiKey?: string;
  baseUrl?: string;
  models: Record<string, ModelConfig>;
}

export interface TaskRoutingConfig {
  primary: string;
  fallback: string;
  maxRetries: number;
  tokenBudget?: number;
  complexity?: 'simple' | 'moderate' | 'complex';
}

export interface RouterConfig {
  providers: {
    anthropic: ProviderConfig;
    google: ProviderConfig;
    openai: ProviderConfig;
    deepseek: ProviderConfig;
    ollama: ProviderConfig;
  };
  
  routing: {
    plan: TaskRoutingConfig;
    edit: TaskRoutingConfig;
    review: TaskRoutingConfig;
    grunt: TaskRoutingConfig;
  };
  
  // Global configuration
  global: {
    maxConcurrentRequests: number;
    costBudgetDaily: number;
    preferLocalModels: boolean;
    fallbackToCloud: boolean;
    retryAttempts: number;
    timeoutMs: number;
  };
}

/**
 * Phase 4 Router Configuration
 * Optimized for cost-effectiveness with intelligent model selection
 */
export const PHASE_4_ROUTER_CONFIG: RouterConfig = {
  providers: {
    anthropic: {
      apiKey: process.env.ANTHROPIC_API_KEY,
      models: {
        'claude-3-5-sonnet': { maxTokens: 200000, cost: 0.003 },
        'claude-3-5-haiku': { maxTokens: 200000, cost: 0.0008 },
        'claude-3-opus': { maxTokens: 200000, cost: 0.015 }
      }
    },
    google: {
      apiKey: process.env.GOOGLE_API_KEY,
      models: {
        'gemini-2.0-flash-thinking': { maxTokens: 1000000, cost: 0.0 },
        'gemini-2.0-flash': { maxTokens: 1000000, cost: 0.0 },
        'gemini-1.5-pro': { maxTokens: 2000000, cost: 0.0 }
      }
    },
    openai: {
      apiKey: process.env.OPENAI_API_KEY,
      models: {
        'o1': { maxTokens: 128000, cost: 0.015 },
        'o1-mini': { maxTokens: 128000, cost: 0.003 },
        'gpt-4o': { maxTokens: 128000, cost: 0.0025 },
        'gpt-4o-mini': { maxTokens: 128000, cost: 0.00015 }
      }
    },
    deepseek: {
      apiKey: process.env.DEEPSEEK_API_KEY,
      baseUrl: 'https://api.deepseek.com/v1',
      models: {
        'deepseek-chat': { maxTokens: 64000, cost: 0.00014 },
        'deepseek-reasoner': { maxTokens: 64000, cost: 0.00055 },
        'deepseek-coder': { maxTokens: 64000, cost: 0.00014 }
      }
    },
    ollama: {
      baseUrl: process.env.OLLAMA_URL || 'http://localhost:11434',
      models: {
        'qwen2.5-coder:14b': { maxTokens: 32000, cost: 0.0 },
        'llama3.3:70b': { maxTokens: 128000, cost: 0.0 },
        'codestral:22b': { maxTokens: 32000, cost: 0.0 },
        'deepseek-r1:7b': { maxTokens: 64000, cost: 0.0 }
      }
    }
  },
  
  routing: {
    plan: {
      primary: 'gemini-2.0-flash-thinking',  // 1M context for comprehensive planning
      fallback: 'o1-mini',
      maxRetries: 2,
      tokenBudget: 900000, // Leave room for Gemini's 1M context
      complexity: 'complex'
    },
    edit: {
      primary: 'claude-3-5-sonnet',  // Best code generation
      fallback: 'deepseek-coder',
      maxRetries: 3,
      tokenBudget: 150000, // Optimize for Claude
      complexity: 'moderate'
    },
    review: {
      primary: 'o1',  // Deep reasoning for review
      fallback: 'claude-3-5-haiku',
      maxRetries: 1,
      tokenBudget: 100000,
      complexity: 'complex'
    },
    grunt: {
      primary: 'qwen2.5-coder:14b',  // Local for simple tasks
      fallback: 'deepseek-chat',
      maxRetries: 5,
      tokenBudget: 32000,
      complexity: 'simple'
    }
  },
  
  global: {
    maxConcurrentRequests: 10,
    costBudgetDaily: 5.00, // $5 daily budget
    preferLocalModels: true,
    fallbackToCloud: true,
    retryAttempts: 3,
    timeoutMs: 30000
  }
};

/**
 * Task complexity classifier
 * Determines appropriate model routing based on task characteristics
 */
export class TaskClassifier {
  /**
   * Classify task complexity based on description and context
   */
  static classifyTask(description: string, context?: any): 'simple' | 'moderate' | 'complex' {
    const lowerDesc = description.toLowerCase();
    
    // Simple tasks (suitable for local/free models)
    const simpleIndicators = [
      'format', 'lint', 'test', 'commit', 'git',
      'delete', 'remove', 'cleanup', 'style',
      'documentation', 'comment', 'readme'
    ];
    
    // Complex tasks (require premium models)
    const complexIndicators = [
      'architecture', 'design', 'refactor', 'optimize',
      'security', 'performance', 'algorithm', 'debug',
      'review', 'analyze', 'plan', 'strategy'
    ];
    
    // Check for complex indicators first
    if (complexIndicators.some(indicator => lowerDesc.includes(indicator))) {
      return 'complex';
    }
    
    // Check for simple indicators
    if (simpleIndicators.some(indicator => lowerDesc.includes(indicator))) {
      return 'simple';
    }
    
    // Consider context size
    if (context?.tokenCount) {
      if (context.tokenCount > 50000) return 'complex';
      if (context.tokenCount < 5000) return 'simple';
    }
    
    // Default to moderate
    return 'moderate';
  }
  
  /**
   * Determine if task can be parallelized
   */
  static canParallelize(description: string): boolean {
    const parallelizableIndicators = [
      'multiple files', 'batch', 'all files',
      'across project', 'entire codebase'
    ];
    
    return parallelizableIndicators.some(indicator => 
      description.toLowerCase().includes(indicator)
    );
  }
  
  /**
   * Estimate token requirements for task
   */
  static estimateTokenRequirement(
    description: string,
    fileCount: number = 1,
    averageFileSize: number = 1000
  ): number {
    let baseTokens = description.length / 4; // Rough tokenization
    
    // Add context tokens
    let contextTokens = fileCount * averageFileSize / 4;
    
    // Add overhead for system prompts and responses
    let overheadTokens = 2000;
    
    // Adjust based on task complexity
    const complexity = this.classifyTask(description);
    const complexityMultiplier = {
      'simple': 1.2,
      'moderate': 1.5,
      'complex': 2.0
    }[complexity];
    
    return Math.ceil((baseTokens + contextTokens + overheadTokens) * complexityMultiplier);
  }
}

/**
 * Model selection strategies for different scenarios
 */
export class ModelSelectionStrategy {
  constructor(private config: RouterConfig) {}
  
  /**
   * Select model for grunt work (prioritize local/free)
   */
  selectGruntModel(tokenRequirement: number): string {
    const { grunt } = this.config.routing;
    
    // Try primary (should be local)
    const primary = grunt.primary;
    if (this.canHandleTokens(primary, tokenRequirement)) {
      return primary;
    }
    
    // Fallback to cloud but cheap model
    return grunt.fallback;
  }
  
  /**
   * Select model for high-quality work
   */
  selectPremiumModel(task: 'plan' | 'edit' | 'review', tokenRequirement: number): string {
    const routing = this.config.routing[task];
    
    // Check if primary can handle the tokens
    if (this.canHandleTokens(routing.primary, tokenRequirement)) {
      return routing.primary;
    }
    
    // Find alternative with sufficient context
    const alternatives = this.findAlternativesWithCapacity(tokenRequirement);
    if (alternatives.length > 0) {
      // Sort by cost and return cheapest
      return alternatives.sort((a, b) => this.getModelCost(a) - this.getModelCost(b))[0];
    }
    
    // Fallback
    return routing.fallback;
  }
  
  /**
   * Select model for parallel execution
   */
  selectParallelModels(tasks: Array<{ tokens: number; complexity: string }>): string[] {
    const selections: string[] = [];
    
    for (const task of tasks) {
      if (task.complexity === 'simple') {
        selections.push(this.selectGruntModel(task.tokens));
      } else {
        // Distribute across available premium models
        const available = this.getAvailablePremiumModels();
        const selected = available[selections.length % available.length];
        selections.push(selected);
      }
    }
    
    return selections;
  }
  
  private canHandleTokens(modelName: string, tokens: number): boolean {
    const model = this.findModelConfig(modelName);
    return model ? model.maxTokens >= tokens : false;
  }
  
  private findModelConfig(modelName: string): ModelConfig | null {
    for (const provider of Object.values(this.config.providers)) {
      if (provider.models[modelName]) {
        return provider.models[modelName];
      }
    }
    return null;
  }
  
  private findAlternativesWithCapacity(tokenRequirement: number): string[] {
    const alternatives: string[] = [];
    
    for (const [providerName, provider] of Object.entries(this.config.providers)) {
      for (const [modelName, model] of Object.entries(provider.models)) {
        if (model.maxTokens >= tokenRequirement) {
          alternatives.push(modelName);
        }
      }
    }
    
    return alternatives;
  }
  
  private getModelCost(modelName: string): number {
    const model = this.findModelConfig(modelName);
    return model?.cost || Infinity;
  }
  
  private getAvailablePremiumModels(): string[] {
    return [
      'claude-3-5-sonnet',
      'gemini-2.0-flash',
      'o1-mini',
      'deepseek-coder'
    ].filter(model => this.findModelConfig(model));
  }
}

/**
 * Cost tracking and budget management
 */
export class CostManager {
  private dailyCost: number = 0;
  private lastResetDate: string = new Date().toDateString();
  
  constructor(private config: RouterConfig) {}
  
  /**
   * Check if request is within budget
   */
  canAffordRequest(modelName: string, estimatedTokens: number): boolean {
    this.checkDailyReset();
    
    const model = this.findModelConfig(modelName);
    if (!model) return false;
    
    const estimatedCost = estimatedTokens * model.cost;
    return (this.dailyCost + estimatedCost) <= this.config.global.costBudgetDaily;
  }
  
  /**
   * Record actual cost
   */
  recordCost(modelName: string, actualTokens: number): void {
    this.checkDailyReset();
    
    const model = this.findModelConfig(modelName);
    if (model) {
      this.dailyCost += actualTokens * model.cost;
    }
  }
  
  /**
   * Get remaining daily budget
   */
  getRemainingBudget(): number {
    this.checkDailyReset();
    return Math.max(0, this.config.global.costBudgetDaily - this.dailyCost);
  }
  
  /**
   * Suggest cheaper alternative
   */
  suggestCheaperAlternative(originalModel: string, tokenRequirement: number): string | null {
    const originalCost = this.getModelCost(originalModel);
    
    // Find cheaper models with sufficient capacity
    const alternatives: Array<{ name: string; cost: number }> = [];
    
    for (const [providerName, provider] of Object.entries(this.config.providers)) {
      for (const [modelName, model] of Object.entries(provider.models)) {
        if (model.maxTokens >= tokenRequirement && model.cost < originalCost) {
          alternatives.push({ name: modelName, cost: model.cost });
        }
      }
    }
    
    if (alternatives.length === 0) return null;
    
    // Return cheapest alternative
    alternatives.sort((a, b) => a.cost - b.cost);
    return alternatives[0].name;
  }
  
  private checkDailyReset(): void {
    const today = new Date().toDateString();
    if (this.lastResetDate !== today) {
      this.dailyCost = 0;
      this.lastResetDate = today;
    }
  }
  
  private findModelConfig(modelName: string): ModelConfig | null {
    for (const provider of Object.values(this.config.providers)) {
      if (provider.models[modelName]) {
        return provider.models[modelName];
      }
    }
    return null;
  }
  
  private getModelCost(modelName: string): number {
    const model = this.findModelConfig(modelName);
    return model?.cost || Infinity;
  }
}

export default PHASE_4_ROUTER_CONFIG;