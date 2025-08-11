// Model Routing MCP Server for Phase 4
// Provides intelligent model selection and routing capabilities via MCP

import {
  Server,
  ListToolsRequestSchema,
  CallToolRequestSchema,
  ErrorCode,
  McpError,
} from '@modelcontextprotocol/sdk/server.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { Database } from 'bun:sqlite';
import { 
  PHASE_4_ROUTER_CONFIG,
  TaskClassifier,
  ModelSelectionStrategy,
  CostManager
} from '../routing/claude-code-router-config';
import { ModelRouter } from '../routing/model-router';

interface RouteModelParams {
  task: string;
  complexity?: 'simple' | 'moderate' | 'complex';
  tokenEstimate?: number;
  priority?: 'low' | 'medium' | 'high';
  budgetLimit?: number;
  preferLocal?: boolean;
}

interface ModelCapabilitiesParams {
  model?: string;
  task?: string;
}

interface CostAnalysisParams {
  model: string;
  estimatedTokens: number;
  alternatives?: boolean;
}

interface ModelStatusParams {
  provider?: string;
  includeMetrics?: boolean;
}

/**
 * Model Routing MCP Server
 * 
 * Provides tools for intelligent model selection, cost analysis, and routing optimization
 * through the Model Context Protocol.
 */
class ModelRoutingMCPServer {
  private server: Server;
  private db: Database;
  private modelRouter: ModelRouter;
  private costManager: CostManager;
  private modelStrategy: ModelSelectionStrategy;
  
  constructor(db: Database) {
    this.db = db;
    this.modelRouter = new ModelRouter(db);
    this.costManager = new CostManager(PHASE_4_ROUTER_CONFIG);
    this.modelStrategy = new ModelSelectionStrategy(PHASE_4_ROUTER_CONFIG);
    
    this.server = new Server(
      {
        name: 'devys-model-routing-server',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );
    
    this.setupToolHandlers();
  }
  
  private setupToolHandlers(): void {
    // List available tools
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: 'route_model',
          description: 'Select optimal model for a given task based on complexity, cost, and requirements',
          inputSchema: {
            type: 'object',
            properties: {
              task: {
                type: 'string',
                description: 'Description of the task to be performed'
              },
              complexity: {
                type: 'string',
                enum: ['simple', 'moderate', 'complex'],
                description: 'Task complexity level (auto-detected if not provided)'
              },
              tokenEstimate: {
                type: 'number',
                description: 'Estimated token requirement for the task'
              },
              priority: {
                type: 'string',
                enum: ['low', 'medium', 'high'],
                description: 'Task priority level'
              },
              budgetLimit: {
                type: 'number',
                description: 'Maximum cost allowed for this task'
              },
              preferLocal: {
                type: 'boolean',
                description: 'Prefer local models when possible'
              }
            },
            required: ['task']
          }
        },
        {
          name: 'analyze_cost',
          description: 'Analyze cost implications and suggest alternatives for model selection',
          inputSchema: {
            type: 'object',
            properties: {
              model: {
                type: 'string',
                description: 'Model to analyze'
              },
              estimatedTokens: {
                type: 'number',
                description: 'Estimated token count'
              },
              alternatives: {
                type: 'boolean',
                description: 'Include alternative model suggestions',
                default: true
              }
            },
            required: ['model', 'estimatedTokens']
          }
        },
        {
          name: 'get_model_capabilities',
          description: 'Get detailed capabilities and specifications for models',
          inputSchema: {
            type: 'object',
            properties: {
              model: {
                type: 'string',
                description: 'Specific model to query (optional - returns all if not provided)'
              },
              task: {
                type: 'string',
                description: 'Filter models by task suitability'
              }
            }
          }
        },
        {
          name: 'get_model_status',
          description: 'Get current status, availability, and metrics for models',
          inputSchema: {
            type: 'object',
            properties: {
              provider: {
                type: 'string',
                description: 'Filter by provider (anthropic, openai, google, deepseek, ollama)'
              },
              includeMetrics: {
                type: 'boolean',
                description: 'Include performance metrics',
                default: true
              }
            }
          }
        },
        {
          name: 'optimize_parallel_routing',
          description: 'Optimize model routing for parallel task execution',
          inputSchema: {
            type: 'object',
            properties: {
              tasks: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    id: { type: 'string' },
                    description: { type: 'string' },
                    complexity: { type: 'string', enum: ['simple', 'moderate', 'complex'] },
                    tokenEstimate: { type: 'number' },
                    priority: { type: 'string', enum: ['low', 'medium', 'high'] }
                  },
                  required: ['id', 'description']
                },
                description: 'Array of tasks to route optimally'
              },
              maxConcurrency: {
                type: 'number',
                description: 'Maximum number of concurrent requests',
                default: 4
              },
              costBudget: {
                type: 'number',
                description: 'Total cost budget for all tasks'
              }
            },
            required: ['tasks']
          }
        },
        {
          name: 'get_cost_report',
          description: 'Generate detailed cost report and budget analysis',
          inputSchema: {
            type: 'object',
            properties: {
              timeframe: {
                type: 'string',
                enum: ['today', 'week', 'month'],
                description: 'Report timeframe',
                default: 'today'
              },
              breakdown: {
                type: 'boolean',
                description: 'Include breakdown by model and task type',
                default: true
              }
            }
          }
        }
      ],
    }));
    
    // Handle tool calls
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      try {
        const { name, arguments: args } = request.params;
        
        switch (name) {
          case 'route_model':
            return await this.handleRouteModel(args as RouteModelParams);
          
          case 'analyze_cost':
            return await this.handleAnalyzeCost(args as CostAnalysisParams);
          
          case 'get_model_capabilities':
            return await this.handleGetModelCapabilities(args as ModelCapabilitiesParams);
          
          case 'get_model_status':
            return await this.handleGetModelStatus(args as ModelStatusParams);
          
          case 'optimize_parallel_routing':
            return await this.handleOptimizeParallelRouting(args as any);
          
          case 'get_cost_report':
            return await this.handleGetCostReport(args as any);
          
          default:
            throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
        }
      } catch (error) {
        if (error instanceof McpError) {
          throw error;
        }
        throw new McpError(
          ErrorCode.InternalError,
          `Tool execution failed: ${error instanceof Error ? error.message : String(error)}`
        );
      }
    });
  }
  
  /**
   * Route model selection based on task parameters
   */
  private async handleRouteModel(params: RouteModelParams) {
    const {
      task,
      complexity: providedComplexity,
      tokenEstimate,
      priority = 'medium',
      budgetLimit,
      preferLocal = false
    } = params;
    
    // Auto-detect complexity if not provided
    const complexity = providedComplexity || TaskClassifier.classifyTask(task);
    
    // Estimate tokens if not provided
    const estimatedTokens = tokenEstimate || TaskClassifier.estimateTokenRequirement(task);
    
    // Check budget constraints
    if (budgetLimit && !this.costManager.canAffordRequest('claude-3-5-sonnet', estimatedTokens)) {
      const remainingBudget = this.costManager.getRemainingBudget();
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            error: 'Budget exceeded',
            remainingBudget,
            estimatedCost: estimatedTokens * 0.003, // Claude Sonnet cost
            suggestion: 'Use a cheaper model or reduce scope'
          }, null, 2)
        }]
      };
    }
    
    // Select model based on task characteristics
    let selectedModel: string;
    
    if (complexity === 'simple' && preferLocal) {
      selectedModel = this.modelStrategy.selectGruntModel(estimatedTokens);
    } else if (priority === 'high') {
      // High priority: use best available model regardless of cost
      if (estimatedTokens > 200000) {
        selectedModel = 'gemini-2.0-flash-thinking';
      } else {
        selectedModel = 'claude-3-5-sonnet';
      }
    } else {
      // Normal routing based on task requirements
      const taskType = this.inferTaskType(task);
      selectedModel = this.modelStrategy.selectPremiumModel(taskType, estimatedTokens);
    }
    
    // Get model details
    const modelConfig = this.getModelConfig(selectedModel);
    const estimatedCost = modelConfig ? estimatedTokens * modelConfig.cost : 0;
    
    // Find alternatives
    const alternatives = this.findAlternativeModels(selectedModel, estimatedTokens, complexity);
    
    const result = {
      selectedModel,
      reasoning: this.generateModelSelectionReasoning(task, complexity, selectedModel, estimatedTokens),
      estimatedTokens,
      estimatedCost,
      complexity,
      alternatives,
      modelConfig: modelConfig ? {
        maxTokens: modelConfig.maxTokens,
        costPerToken: modelConfig.cost,
        provider: this.getModelProvider(selectedModel)
      } : null,
      budgetImpact: {
        remainingBudget: this.costManager.getRemainingBudget(),
        percentageOfBudget: (estimatedCost / PHASE_4_ROUTER_CONFIG.global.costBudgetDaily) * 100
      }
    };
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(result, null, 2)
      }]
    };
  }
  
  /**
   * Analyze cost implications for model selection
   */
  private async handleAnalyzeCost(params: CostAnalysisParams) {
    const { model, estimatedTokens, alternatives = true } = params;
    
    const modelConfig = this.getModelConfig(model);
    if (!modelConfig) {
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({ error: `Model ${model} not found` }, null, 2)
        }]
      };
    }
    
    const cost = estimatedTokens * modelConfig.cost;
    const remainingBudget = this.costManager.getRemainingBudget();
    const canAfford = cost <= remainingBudget;
    
    const analysis = {
      model,
      estimatedTokens,
      cost,
      costPerToken: modelConfig.cost,
      remainingBudget,
      canAfford,
      budgetImpact: (cost / PHASE_4_ROUTER_CONFIG.global.costBudgetDaily) * 100,
      costBreakdown: {
        input: estimatedTokens * 0.7 * modelConfig.cost, // Assume 70% input
        output: estimatedTokens * 0.3 * modelConfig.cost  // Assume 30% output
      }
    };
    
    if (alternatives) {
      const alternativeModels = this.findAlternativeModels(model, estimatedTokens, 'moderate');
      (analysis as any).alternatives = alternativeModels.map(altModel => {
        const altConfig = this.getModelConfig(altModel);
        return {
          model: altModel,
          cost: altConfig ? estimatedTokens * altConfig.cost : 0,
          savings: altConfig ? cost - (estimatedTokens * altConfig.cost) : 0,
          savingsPercent: altConfig ? ((cost - (estimatedTokens * altConfig.cost)) / cost) * 100 : 0
        };
      });
    }
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(analysis, null, 2)
      }]
    };
  }
  
  /**
   * Get model capabilities and specifications
   */
  private async handleGetModelCapabilities(params: ModelCapabilitiesParams) {
    const { model, task } = params;
    
    if (model) {
      // Get specific model details
      const modelConfig = this.getModelConfig(model);
      const provider = this.getModelProvider(model);
      
      if (!modelConfig) {
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({ error: `Model ${model} not found` }, null, 2)
          }]
        };
      }
      
      const capabilities = {
        model,
        provider,
        maxTokens: modelConfig.maxTokens,
        costPerToken: modelConfig.cost,
        capabilities: this.getModelCapabilities(model),
        strengths: this.getModelStrengths(model),
        bestUseCases: this.getModelUseCases(model),
        averageLatency: this.getModelLatency(model)
      };
      
      return {
        content: [{
          type: 'text',
          text: JSON.stringify(capabilities, null, 2)
        }]
      };
    } else {
      // List all models with optional task filtering
      const allModels = this.getAllModelCapabilities();
      
      let filteredModels = allModels;
      if (task) {
        const taskComplexity = TaskClassifier.classifyTask(task);
        filteredModels = allModels.filter(m => this.isModelSuitableForTask(m.model, taskComplexity));
      }
      
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({ models: filteredModels }, null, 2)
        }]
      };
    }
  }
  
  /**
   * Get current model status and metrics
   */
  private async handleGetModelStatus(params: ModelStatusParams) {
    const { provider, includeMetrics = true } = params;
    
    const status: any = {
      timestamp: new Date().toISOString(),
      models: []
    };
    
    for (const [providerName, providerConfig] of Object.entries(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider && provider !== providerName) continue;
      
      for (const [modelName, modelConfig] of Object.entries(providerConfig.models)) {
        const modelStatus: any = {
          model: modelName,
          provider: providerName,
          available: await this.checkModelAvailability(modelName, providerName),
          maxTokens: modelConfig.maxTokens,
          cost: modelConfig.cost
        };
        
        if (includeMetrics) {
          const metrics = this.modelRouter.getMetrics().get(modelName);
          if (metrics) {
            modelStatus.metrics = {
              totalRequests: metrics.totalRequests,
              successRate: metrics.successRate,
              averageLatency: metrics.averageLatency,
              totalTokens: metrics.totalTokens,
              totalCost: metrics.totalCost,
              errors: metrics.errors
            };
          }
        }
        
        status.models.push(modelStatus);
      }
    }
    
    // Add budget information
    status.budget = {
      dailyLimit: PHASE_4_ROUTER_CONFIG.global.costBudgetDaily,
      remaining: this.costManager.getRemainingBudget(),
      used: PHASE_4_ROUTER_CONFIG.global.costBudgetDaily - this.costManager.getRemainingBudget()
    };
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(status, null, 2)
      }]
    };
  }
  
  /**
   * Optimize parallel task routing
   */
  private async handleOptimizeParallelRouting(params: any) {
    const { tasks, maxConcurrency = 4, costBudget } = params;
    
    // Analyze and classify tasks
    const analyzedTasks = tasks.map((task: any) => ({
      ...task,
      complexity: task.complexity || TaskClassifier.classifyTask(task.description),
      tokenEstimate: task.tokenEstimate || TaskClassifier.estimateTokenRequirement(task.description),
      canParallelize: TaskClassifier.canParallelize(task.description)
    }));
    
    // Group tasks by complexity and parallelization capability
    const parallelTasks = analyzedTasks.filter((t: any) => t.canParallelize);
    const sequentialTasks = analyzedTasks.filter((t: any) => !t.canParallelize);
    
    // Optimize model assignments
    const assignments = this.optimizeModelAssignments(parallelTasks, maxConcurrency, costBudget);
    
    const optimization = {
      totalTasks: tasks.length,
      parallelizable: parallelTasks.length,
      sequential: sequentialTasks.length,
      maxConcurrency,
      estimatedDuration: this.estimateParallelDuration(assignments),
      estimatedCost: this.estimateParallelCost(assignments),
      assignments: assignments.map((assignment: any) => ({
        taskId: assignment.taskId,
        model: assignment.model,
        estimatedTokens: assignment.estimatedTokens,
        estimatedCost: assignment.estimatedCost,
        priority: assignment.priority,
        executionGroup: assignment.executionGroup
      })),
      executionPlan: {
        groups: this.groupTasksForExecution(assignments, maxConcurrency),
        totalEstimatedTime: this.estimateTotalExecutionTime(assignments)
      }
    };
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(optimization, null, 2)
      }]
    };
  }
  
  /**
   * Generate cost report
   */
  private async handleGetCostReport(params: any) {
    const { timeframe = 'today', breakdown = true } = params;
    
    const report = this.modelRouter.getCostReport();
    
    const costReport = {
      timeframe,
      generatedAt: new Date().toISOString(),
      summary: {
        totalCost: report.totalCost,
        totalRequests: report.totalRequests,
        totalTokens: report.totalTokens,
        averageCostPerRequest: report.totalCost / Math.max(1, report.totalRequests),
        averageCostPerToken: report.totalCost / Math.max(1, report.totalTokens)
      },
      budget: {
        dailyLimit: PHASE_4_ROUTER_CONFIG.global.costBudgetDaily,
        used: PHASE_4_ROUTER_CONFIG.global.costBudgetDaily - this.costManager.getRemainingBudget(),
        remaining: this.costManager.getRemainingBudget(),
        utilizationPercent: ((PHASE_4_ROUTER_CONFIG.global.costBudgetDaily - this.costManager.getRemainingBudget()) / PHASE_4_ROUTER_CONFIG.global.costBudgetDaily) * 100
      }
    };
    
    if (breakdown) {
      const metrics = this.modelRouter.getMetrics();
      (costReport as any).breakdown = {
        byModel: Array.from(metrics.entries()).map(([model, data]) => ({
          model,
          requests: data.totalRequests,
          tokens: data.totalTokens,
          cost: data.totalCost,
          successRate: data.successRate,
          averageLatency: data.averageLatency
        })),
        byProvider: this.groupCostsByProvider(metrics)
      };
    }
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(costReport, null, 2)
      }]
    };
  }
  
  /**
   * Helper methods
   */
  private inferTaskType(task: string): 'plan' | 'edit' | 'review' | 'grunt' {
    const taskLower = task.toLowerCase();
    
    if (taskLower.includes('plan') || taskLower.includes('design') || taskLower.includes('architecture')) {
      return 'plan';
    }
    if (taskLower.includes('review') || taskLower.includes('analyze') || taskLower.includes('check')) {
      return 'review';
    }
    if (taskLower.includes('format') || taskLower.includes('lint') || taskLower.includes('test')) {
      return 'grunt';
    }
    return 'edit'; // Default
  }
  
  private generateModelSelectionReasoning(task: string, complexity: string, model: string, tokens: number): string {
    const reasons = [];
    
    reasons.push(`Task complexity: ${complexity}`);
    
    if (tokens > 200000) {
      reasons.push(`Large context requirement (${tokens} tokens) → selected high-context model`);
    } else if (tokens < 10000) {
      reasons.push(`Small context (${tokens} tokens) → selected efficient model for cost optimization`);
    }
    
    if (model.includes('gemini')) {
      reasons.push('Selected Gemini for large context and free usage');
    } else if (model.includes('claude')) {
      reasons.push('Selected Claude for superior code quality and reasoning');
    } else if (model.includes('ollama') || model.includes('qwen')) {
      reasons.push('Selected local model for cost optimization');
    } else if (model.includes('deepseek')) {
      reasons.push('Selected DeepSeek for cost-effective performance');
    }
    
    return reasons.join('. ');
  }
  
  private getModelConfig(model: string): { maxTokens: number; cost: number } | null {
    for (const provider of Object.values(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider.models[model]) {
        return provider.models[model];
      }
    }
    return null;
  }
  
  private getModelProvider(model: string): string {
    for (const [providerName, provider] of Object.entries(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider.models[model]) {
        return providerName;
      }
    }
    return 'unknown';
  }
  
  private findAlternativeModels(originalModel: string, tokens: number, complexity: string): string[] {
    const alternatives: string[] = [];
    const originalCost = this.getModelConfig(originalModel)?.cost || 0;
    
    for (const [providerName, provider] of Object.entries(PHASE_4_ROUTER_CONFIG.providers)) {
      for (const [modelName, config] of Object.entries(provider.models)) {
        if (modelName !== originalModel && 
            config.maxTokens >= tokens && 
            config.cost <= originalCost * 1.5) { // Within 150% of original cost
          alternatives.push(modelName);
        }
      }
    }
    
    return alternatives.slice(0, 3); // Top 3 alternatives
  }
  
  private async checkModelAvailability(model: string, provider: string): Promise<boolean> {
    // For now, assume all models are available
    // In production, this would check actual API availability
    if (provider === 'ollama') {
      try {
        const response = await fetch(`${PHASE_4_ROUTER_CONFIG.providers.ollama.baseUrl}/api/tags`);
        if (response.ok) {
          const data = await response.json();
          return data.models.some((m: any) => m.name === model);
        }
      } catch {
        return false;
      }
    }
    
    return true; // Assume cloud models are available
  }
  
  private getModelCapabilities(model: string): string[] {
    const capabilities: string[] = [];
    
    if (model.includes('claude')) {
      capabilities.push('reasoning', 'coding', 'analysis', 'creative-writing');
    } else if (model.includes('gemini')) {
      capabilities.push('large-context', 'multimodal', 'reasoning', 'coding');
    } else if (model.includes('gpt') || model.includes('o1')) {
      capabilities.push('reasoning', 'coding', 'creative-writing', 'analysis');
    } else if (model.includes('deepseek')) {
      capabilities.push('coding', 'reasoning', 'cost-effective');
    } else if (model.includes('qwen') || model.includes('llama')) {
      capabilities.push('local-execution', 'coding', 'privacy');
    }
    
    return capabilities;
  }
  
  private getModelStrengths(model: string): string[] {
    const strengthMap: Record<string, string[]> = {
      'claude-3-5-sonnet': ['Best-in-class coding', 'Complex reasoning', 'Following instructions'],
      'claude-3-5-haiku': ['Speed', 'Cost efficiency', 'Good coding'],
      'gemini-2.0-flash-thinking': ['Million+ token context', 'Free usage', 'Chain of thought'],
      'o1': ['Deep reasoning', 'Problem solving', 'Mathematical tasks'],
      'deepseek-chat': ['Cost effective', 'Good coding', 'Fast'],
      'qwen2.5-coder:14b': ['Local execution', 'Privacy', 'Zero cost', 'Coding focused']
    };
    
    return strengthMap[model] || ['General purpose'];
  }
  
  private getModelUseCases(model: string): string[] {
    const useCaseMap: Record<string, string[]> = {
      'claude-3-5-sonnet': ['Complex code refactoring', 'Architecture design', 'Code review'],
      'claude-3-5-haiku': ['Quick edits', 'Simple tasks', 'Formatting'],
      'gemini-2.0-flash-thinking': ['Large codebase analysis', 'Comprehensive planning', 'Research'],
      'o1': ['Debugging complex issues', 'Algorithm design', 'Problem analysis'],
      'deepseek-chat': ['Routine coding tasks', 'Documentation', 'Testing'],
      'qwen2.5-coder:14b': ['Local development', 'Offline coding', 'Privacy-sensitive tasks']
    };
    
    return useCaseMap[model] || ['General development tasks'];
  }
  
  private getModelLatency(model: string): number {
    // Estimated latencies in milliseconds
    const latencyMap: Record<string, number> = {
      'claude-3-5-sonnet': 2000,
      'claude-3-5-haiku': 800,
      'gemini-2.0-flash-thinking': 3000,
      'gemini-2.0-flash': 1500,
      'o1': 5000,
      'o1-mini': 3000,
      'deepseek-chat': 1000,
      'qwen2.5-coder:14b': 500,
      'llama3.3:70b': 1500
    };
    
    return latencyMap[model] || 2000;
  }
  
  private getAllModelCapabilities() {
    const models = [];
    
    for (const [providerName, provider] of Object.entries(PHASE_4_ROUTER_CONFIG.providers)) {
      for (const [modelName, config] of Object.entries(provider.models)) {
        models.push({
          model: modelName,
          provider: providerName,
          maxTokens: config.maxTokens,
          cost: config.cost,
          capabilities: this.getModelCapabilities(modelName),
          strengths: this.getModelStrengths(modelName),
          useCases: this.getModelUseCases(modelName),
          estimatedLatency: this.getModelLatency(modelName)
        });
      }
    }
    
    return models;
  }
  
  private isModelSuitableForTask(model: string, complexity: string): boolean {
    const modelCapabilities = this.getModelCapabilities(model);
    
    switch (complexity) {
      case 'simple':
        return true; // All models can handle simple tasks
      case 'moderate':
        return !model.includes('haiku'); // Exclude the lightest models
      case 'complex':
        return modelCapabilities.includes('reasoning') || modelCapabilities.includes('large-context');
      default:
        return true;
    }
  }
  
  private optimizeModelAssignments(tasks: any[], maxConcurrency: number, costBudget?: number): any[] {
    const assignments = [];
    
    // Sort tasks by priority and complexity
    const sortedTasks = tasks.sort((a, b) => {
      const priorityWeight = { high: 3, medium: 2, low: 1 };
      const complexityWeight = { complex: 3, moderate: 2, simple: 1 };
      
      const aScore = (priorityWeight[a.priority] || 2) + (complexityWeight[a.complexity] || 2);
      const bScore = (priorityWeight[b.priority] || 2) + (complexityWeight[b.complexity] || 2);
      
      return bScore - aScore;
    });
    
    let totalCost = 0;
    
    for (const task of sortedTasks) {
      const model = this.selectOptimalModelForTask(task);
      const config = this.getModelConfig(model);
      const cost = config ? task.tokenEstimate * config.cost : 0;
      
      if (!costBudget || totalCost + cost <= costBudget) {
        assignments.push({
          taskId: task.id,
          model,
          estimatedTokens: task.tokenEstimate,
          estimatedCost: cost,
          priority: task.priority,
          complexity: task.complexity,
          executionGroup: Math.floor(assignments.length / maxConcurrency)
        });
        
        totalCost += cost;
      }
    }
    
    return assignments;
  }
  
  private selectOptimalModelForTask(task: any): string {
    if (task.complexity === 'simple') {
      return 'qwen2.5-coder:14b'; // Local for simple tasks
    } else if (task.complexity === 'complex') {
      return task.tokenEstimate > 100000 ? 'gemini-2.0-flash-thinking' : 'claude-3-5-sonnet';
    } else {
      return 'deepseek-chat'; // Cost-effective for moderate tasks
    }
  }
  
  private estimateParallelDuration(assignments: any[]): number {
    // Group by execution group and find the longest group
    const groups = new Map<number, any[]>();
    
    for (const assignment of assignments) {
      const group = groups.get(assignment.executionGroup) || [];
      group.push(assignment);
      groups.set(assignment.executionGroup, group);
    }
    
    let maxDuration = 0;
    for (const group of groups.values()) {
      const groupDuration = Math.max(...group.map(a => this.getModelLatency(a.model) + (a.estimatedTokens / 10)));
      maxDuration = Math.max(maxDuration, groupDuration);
    }
    
    return maxDuration * groups.size; // Total for all groups
  }
  
  private estimateParallelCost(assignments: any[]): number {
    return assignments.reduce((total, assignment) => total + assignment.estimatedCost, 0);
  }
  
  private groupTasksForExecution(assignments: any[], maxConcurrency: number): any[] {
    const groups = [];
    const groupMap = new Map<number, any[]>();
    
    for (const assignment of assignments) {
      const group = groupMap.get(assignment.executionGroup) || [];
      group.push(assignment);
      groupMap.set(assignment.executionGroup, group);
    }
    
    for (const [groupIndex, tasks] of groupMap) {
      groups.push({
        groupIndex,
        tasks,
        estimatedDuration: Math.max(...tasks.map(t => this.getModelLatency(t.model))),
        totalCost: tasks.reduce((sum, t) => sum + t.estimatedCost, 0)
      });
    }
    
    return groups;
  }
  
  private estimateTotalExecutionTime(assignments: any[]): number {
    const groups = this.groupTasksForExecution(assignments, 4);
    return groups.reduce((total, group) => total + group.estimatedDuration, 0);
  }
  
  private groupCostsByProvider(metrics: Map<string, any>): any[] {
    const providerCosts = new Map<string, { cost: number; requests: number; tokens: number }>();
    
    for (const [model, data] of metrics) {
      const provider = this.getModelProvider(model);
      const existing = providerCosts.get(provider) || { cost: 0, requests: 0, tokens: 0 };
      existing.cost += data.totalCost;
      existing.requests += data.totalRequests;
      existing.tokens += data.totalTokens;
      providerCosts.set(provider, existing);
    }
    
    return Array.from(providerCosts.entries()).map(([provider, data]) => ({
      provider,
      ...data
    }));
  }
  
  async run(): Promise<void> {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Model Routing MCP Server running on stdio');
  }
}

// CLI entry point
if (import.meta.main) {
  const dbPath = process.env.DEVYS_DB_PATH || './control.db';
  const db = new Database(dbPath);
  
  const server = new ModelRoutingMCPServer(db);
  server.run().catch((error) => {
    console.error('Server error:', error);
    process.exit(1);
  });
}

export { ModelRoutingMCPServer };