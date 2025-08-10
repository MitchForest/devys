import { MCPServer } from './mcp-server';
import {
  MCPCapability,
  MCPRequest,
  MCPResponse,
  MCPConnection,
  MCPErrorCodes
} from '../types/mcp';
import { ModelRouter } from '../routing/model-router';
import { CostOptimizer } from '../routing/cost-optimizer';
import { LoadBalancer } from '../routing/load-balancer';
import { RateLimiter } from '../routing/rate-limiter';
import { Database } from 'bun:sqlite';

/**
 * Model MCP Server - Provides model orchestration via MCP protocol
 * Implements intelligent routing, cost optimization, and load balancing
 */
export class ModelMCPServer extends MCPServer {
  private modelRouter: ModelRouter;
  private costOptimizer: CostOptimizer;
  private loadBalancer: LoadBalancer;
  private rateLimiter: RateLimiter;
  private activeRequests: Map<string, {
    startTime: number;
    model: string;
    provider: string;
    tokens: number;
  }>;
  
  constructor(
    port: number,
    db: Database
  ) {
    super(
      {
        name: 'model-mcp',
        port,
        host: 'localhost',
        maxConnections: 100,
        heartbeatInterval: 30000
      },
      db
    );
    
    this.modelRouter = new ModelRouter(db);
    this.costOptimizer = new CostOptimizer(db);
    this.loadBalancer = new LoadBalancer();
    this.rateLimiter = new RateLimiter(db);
    this.activeRequests = new Map();
    
    this.initializeDatabase();
  }
  
  /**
   * Initialize model-specific database tables
   */
  private initializeDatabase() {
    if (!this.db) return;
    
    // Model usage tracking
    this.db.run(`
      CREATE TABLE IF NOT EXISTS model_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER,
        output_tokens INTEGER,
        cost REAL,
        duration INTEGER,
        success INTEGER,
        error TEXT,
        timestamp INTEGER NOT NULL
      )
    `);
    
    // Model performance metrics
    this.db.run(`
      CREATE TABLE IF NOT EXISTS model_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        avg_latency REAL,
        success_rate REAL,
        avg_tokens_per_second REAL,
        total_requests INTEGER,
        total_tokens INTEGER,
        total_cost REAL,
        updated_at INTEGER NOT NULL
      )
    `);
  }
  
  /**
   * Define server capabilities
   */
  defineCapabilities(): MCPCapability[] {
    return [
      {
        name: 'models',
        version: '1.0.0',
        methods: [
          'complete',
          'stream',
          'embed',
          'listModels',
          'getModelInfo',
          'selectModel',
          'estimateCost',
          'getUsage',
          'getMetrics',
          'switchProvider'
        ],
        schema: {
          type: 'object',
          properties: {
            method: {
              type: 'string',
              enum: [
                'complete',
                'stream',
                'embed',
                'listModels',
                'getModelInfo',
                'selectModel',
                'estimateCost',
                'getUsage',
                'getMetrics',
                'switchProvider'
              ]
            },
            params: {
              type: 'object'
            }
          }
        }
      },
      {
        name: 'routing',
        version: '1.0.0',
        methods: [
          'getRoutingStrategy',
          'setRoutingStrategy',
          'getProviderStatus',
          'setProviderPriority'
        ],
        schema: {
          type: 'object',
          properties: {
            method: {
              type: 'string',
              enum: [
                'getRoutingStrategy',
                'setRoutingStrategy',
                'getProviderStatus',
                'setProviderPriority'
              ]
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
    const requestId = crypto.randomUUID();
    const startTime = Date.now();
    
    try {
      // Check rate limits
      const allowed = await this.rateLimiter.checkLimit(
        connection.clientId,
        request.method
      );
      
      if (!allowed) {
        throw this.createError(
          MCPErrorCodes.RATE_LIMIT,
          'Rate limit exceeded'
        );
      }
      
      let result: any;
      
      switch (request.method) {
        case 'complete':
          result = await this.handleComplete(request.params, requestId);
          break;
          
        case 'stream':
          result = await this.handleStream(request.params, requestId, connection);
          break;
          
        case 'embed':
          result = await this.handleEmbed(request.params, requestId);
          break;
          
        case 'listModels':
          result = await this.handleListModels(request.params);
          break;
          
        case 'getModelInfo':
          result = await this.handleGetModelInfo(request.params);
          break;
          
        case 'selectModel':
          result = await this.handleSelectModel(request.params);
          break;
          
        case 'estimateCost':
          result = await this.handleEstimateCost(request.params);
          break;
          
        case 'getUsage':
          result = await this.handleGetUsage(request.params);
          break;
          
        case 'getMetrics':
          result = await this.handleGetMetrics(request.params);
          break;
          
        case 'switchProvider':
          result = await this.handleSwitchProvider(request.params);
          break;
          
        case 'getRoutingStrategy':
          result = await this.handleGetRoutingStrategy();
          break;
          
        case 'setRoutingStrategy':
          result = await this.handleSetRoutingStrategy(request.params);
          break;
          
        case 'getProviderStatus':
          result = await this.handleGetProviderStatus();
          break;
          
        case 'setProviderPriority':
          result = await this.handleSetProviderPriority(request.params);
          break;
          
        default:
          throw this.createError(
            MCPErrorCodes.METHOD_NOT_FOUND,
            `Unknown method: ${request.method}`
          );
      }
      
      // Track successful request
      const duration = Date.now() - startTime;
      this.trackUsage(requestId, connection.id, request.method, duration, true);
      
      return {
        id: request.id,
        result
      };
      
    } catch (error) {
      // Track failed request
      const duration = Date.now() - startTime;
      this.trackUsage(requestId, connection.id, request.method, duration, false, error.message);
      
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
   * Handle completion request
   */
  private async handleComplete(params: any, requestId: string): Promise<any> {
    if (!params.prompt) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Prompt is required'
      );
    }
    
    // Select optimal model
    const selectedModel = await this.costOptimizer.selectOptimalModel({
      taskType: params.taskType || 'general',
      maxTokens: params.maxTokens || 1000,
      temperature: params.temperature || 0.7,
      budget: params.budget
    });
    
    // Track active request
    this.activeRequests.set(requestId, {
      startTime: Date.now(),
      model: selectedModel.model,
      provider: selectedModel.provider,
      tokens: 0
    });
    
    try {
      // Route to provider
      const response = await this.modelRouter.complete({
        provider: selectedModel.provider,
        model: selectedModel.model,
        prompt: params.prompt,
        systemPrompt: params.systemPrompt,
        maxTokens: params.maxTokens,
        temperature: params.temperature,
        topP: params.topP,
        stopSequences: params.stopSequences
      });
      
      // Update token count
      const activeRequest = this.activeRequests.get(requestId)!;
      activeRequest.tokens = response.usage.totalTokens;
      
      // Calculate cost
      const cost = this.costOptimizer.calculateCost(
        selectedModel.provider,
        selectedModel.model,
        response.usage.inputTokens,
        response.usage.outputTokens
      );
      
      // Log usage
      this.logModelUsage({
        requestId,
        provider: selectedModel.provider,
        model: selectedModel.model,
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        cost,
        duration: Date.now() - activeRequest.startTime
      });
      
      return {
        completion: response.completion,
        model: selectedModel.model,
        provider: selectedModel.provider,
        usage: {
          ...response.usage,
          cost
        },
        requestId
      };
      
    } finally {
      this.activeRequests.delete(requestId);
    }
  }
  
  /**
   * Handle streaming request
   */
  private async handleStream(
    params: any,
    requestId: string,
    connection: MCPConnection
  ): Promise<any> {
    if (!params.prompt) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Prompt is required'
      );
    }
    
    // Select optimal model for streaming
    const selectedModel = await this.costOptimizer.selectOptimalModel({
      taskType: params.taskType || 'general',
      maxTokens: params.maxTokens || 1000,
      temperature: params.temperature || 0.7,
      budget: params.budget,
      streaming: true
    });
    
    // Track active request
    this.activeRequests.set(requestId, {
      startTime: Date.now(),
      model: selectedModel.model,
      provider: selectedModel.provider,
      tokens: 0
    });
    
    try {
      // Create stream
      const stream = await this.modelRouter.stream({
        provider: selectedModel.provider,
        model: selectedModel.model,
        prompt: params.prompt,
        systemPrompt: params.systemPrompt,
        maxTokens: params.maxTokens,
        temperature: params.temperature
      });
      
      // Return stream info
      return {
        streamId: requestId,
        model: selectedModel.model,
        provider: selectedModel.provider,
        message: 'Stream started. Listen for stream events.'
      };
      
      // Note: Actual streaming would need WebSocket implementation
      // to send chunks to the client
      
    } catch (error) {
      this.activeRequests.delete(requestId);
      throw error;
    }
  }
  
  /**
   * Handle embedding request
   */
  private async handleEmbed(params: any, requestId: string): Promise<any> {
    if (!params.text && !params.texts) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Text or texts parameter is required'
      );
    }
    
    const texts = params.texts || [params.text];
    
    // Select embedding model
    const selectedModel = await this.loadBalancer.selectProvider('embedding');
    
    // Generate embeddings
    const embeddings = await this.modelRouter.embed({
      provider: selectedModel.provider,
      model: selectedModel.model,
      texts,
      dimensions: params.dimensions
    });
    
    // Calculate cost
    const tokenCount = texts.join(' ').split(' ').length * 1.3; // Rough estimate
    const cost = this.costOptimizer.calculateCost(
      selectedModel.provider,
      selectedModel.model,
      tokenCount,
      0
    );
    
    return {
      embeddings: embeddings.vectors,
      model: selectedModel.model,
      provider: selectedModel.provider,
      dimensions: embeddings.dimensions,
      usage: {
        tokens: tokenCount,
        cost
      },
      requestId
    };
  }
  
  /**
   * List available models
   */
  private async handleListModels(params: any): Promise<any> {
    const provider = params.provider;
    const taskType = params.taskType;
    
    const models = await this.modelRouter.listModels(provider);
    
    // Filter by task type if specified
    const filtered = taskType
      ? models.filter((m: any) => m.capabilities.includes(taskType))
      : models;
    
    return {
      models: filtered.map((m: any) => ({
        id: m.id,
        name: m.name,
        provider: m.provider,
        capabilities: m.capabilities,
        contextWindow: m.contextWindow,
        pricing: m.pricing,
        status: m.status
      })),
      totalCount: filtered.length
    };
  }
  
  /**
   * Get model information
   */
  private async handleGetModelInfo(params: any): Promise<any> {
    if (!params.model) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Model parameter is required'
      );
    }
    
    const info = await this.modelRouter.getModelInfo(
      params.provider,
      params.model
    );
    
    return {
      model: info.model,
      provider: info.provider,
      capabilities: info.capabilities,
      contextWindow: info.contextWindow,
      pricing: info.pricing,
      performance: info.performance,
      description: info.description
    };
  }
  
  /**
   * Select best model for task
   */
  private async handleSelectModel(params: any): Promise<any> {
    const criteria = {
      taskType: params.taskType || 'general',
      maxTokens: params.maxTokens,
      budget: params.budget,
      latencyRequirement: params.latencyRequirement,
      qualityRequirement: params.qualityRequirement
    };
    
    const selected = await this.costOptimizer.selectOptimalModel(criteria);
    
    return {
      model: selected.model,
      provider: selected.provider,
      reasoning: selected.reasoning,
      estimatedCost: selected.estimatedCost,
      estimatedLatency: selected.estimatedLatency,
      alternatives: selected.alternatives
    };
  }
  
  /**
   * Estimate cost for request
   */
  private async handleEstimateCost(params: any): Promise<any> {
    if (!params.prompt) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Prompt is required'
      );
    }
    
    const estimates = [];
    
    // Get estimates from different providers
    const providers = params.providers || ['anthropic', 'openai', 'google'];
    
    for (const provider of providers) {
      const models = await this.modelRouter.listModels(provider);
      
      for (const model of models) {
        const inputTokens = Math.ceil(params.prompt.length / 4);
        const outputTokens = params.maxTokens || 1000;
        
        const cost = this.costOptimizer.calculateCost(
          provider,
          model.id,
          inputTokens,
          outputTokens
        );
        
        estimates.push({
          provider,
          model: model.id,
          inputTokens,
          outputTokens,
          cost,
          totalTokens: inputTokens + outputTokens
        });
      }
    }
    
    // Sort by cost
    estimates.sort((a, b) => a.cost - b.cost);
    
    return {
      estimates,
      cheapest: estimates[0],
      mostExpensive: estimates[estimates.length - 1]
    };
  }
  
  /**
   * Get usage statistics
   */
  private async handleGetUsage(params: any): Promise<any> {
    const since = params.since || Date.now() - 24 * 60 * 60 * 1000; // Last 24 hours
    const groupBy = params.groupBy || 'provider';
    
    const usage = this.db?.query(`
      SELECT 
        ${groupBy} as groupKey,
        COUNT(*) as requestCount,
        SUM(input_tokens) as inputTokens,
        SUM(output_tokens) as outputTokens,
        SUM(cost) as totalCost,
        AVG(duration) as avgDuration,
        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successCount
      FROM model_usage
      WHERE timestamp >= ?
      GROUP BY ${groupBy}
      ORDER BY totalCost DESC
    `).all(since) as any[];
    
    const total = usage.reduce((acc, row) => ({
      requestCount: acc.requestCount + row.requestCount,
      inputTokens: acc.inputTokens + row.inputTokens,
      outputTokens: acc.outputTokens + row.outputTokens,
      totalCost: acc.totalCost + row.totalCost,
      successCount: acc.successCount + row.successCount
    }), {
      requestCount: 0,
      inputTokens: 0,
      outputTokens: 0,
      totalCost: 0,
      successCount: 0
    });
    
    return {
      usage: usage.map(row => ({
        [groupBy]: row.groupKey,
        requestCount: row.requestCount,
        inputTokens: row.inputTokens,
        outputTokens: row.outputTokens,
        totalCost: row.totalCost,
        avgDuration: row.avgDuration,
        successRate: row.successCount / row.requestCount
      })),
      total,
      period: {
        start: since,
        end: Date.now()
      }
    };
  }
  
  /**
   * Get performance metrics
   */
  private async handleGetMetrics(params: any): Promise<any> {
    const provider = params.provider;
    const model = params.model;
    
    let query = `
      SELECT * FROM model_metrics
      WHERE 1=1
    `;
    const queryParams: any[] = [];
    
    if (provider) {
      query += ' AND provider = ?';
      queryParams.push(provider);
    }
    
    if (model) {
      query += ' AND model = ?';
      queryParams.push(model);
    }
    
    query += ' ORDER BY updated_at DESC';
    
    const metrics = this.db?.query(query).all(...queryParams) as any[];
    
    return {
      metrics: metrics.map(m => ({
        provider: m.provider,
        model: m.model,
        avgLatency: m.avg_latency,
        successRate: m.success_rate,
        avgTokensPerSecond: m.avg_tokens_per_second,
        totalRequests: m.total_requests,
        totalTokens: m.total_tokens,
        totalCost: m.total_cost,
        updatedAt: m.updated_at
      })),
      activeRequests: this.activeRequests.size,
      serverUptime: this.metrics.uptime
    };
  }
  
  /**
   * Switch provider for a model
   */
  private async handleSwitchProvider(params: any): Promise<any> {
    if (!params.fromProvider || !params.toProvider) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'fromProvider and toProvider are required'
      );
    }
    
    await this.loadBalancer.setProviderWeight(
      params.fromProvider,
      0
    );
    
    await this.loadBalancer.setProviderWeight(
      params.toProvider,
      1.0
    );
    
    return {
      success: true,
      message: `Switched from ${params.fromProvider} to ${params.toProvider}`,
      activeRequests: this.activeRequests.size
    };
  }
  
  /**
   * Get routing strategy
   */
  private async handleGetRoutingStrategy(): Promise<any> {
    const strategy = this.loadBalancer.getStrategy();
    const weights = this.loadBalancer.getProviderWeights();
    
    return {
      strategy,
      weights,
      activeProviders: Object.keys(weights).filter(p => weights[p] > 0)
    };
  }
  
  /**
   * Set routing strategy
   */
  private async handleSetRoutingStrategy(params: any): Promise<any> {
    if (!params.strategy) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Strategy parameter is required'
      );
    }
    
    this.loadBalancer.setStrategy(params.strategy);
    
    if (params.weights) {
      for (const [provider, weight] of Object.entries(params.weights)) {
        await this.loadBalancer.setProviderWeight(provider, weight as number);
      }
    }
    
    return {
      success: true,
      strategy: params.strategy,
      weights: params.weights
    };
  }
  
  /**
   * Get provider status
   */
  private async handleGetProviderStatus(): Promise<any> {
    const providers = await this.modelRouter.getProviderStatus();
    
    return {
      providers: providers.map((p: any) => ({
        name: p.name,
        status: p.status,
        health: p.health,
        latency: p.latency,
        errorRate: p.errorRate,
        requestsInFlight: p.requestsInFlight,
        lastError: p.lastError,
        lastSuccessAt: p.lastSuccessAt
      }))
    };
  }
  
  /**
   * Set provider priority
   */
  private async handleSetProviderPriority(params: any): Promise<any> {
    if (!params.provider || params.priority === undefined) {
      throw this.createError(
        MCPErrorCodes.INVALID_PARAMS,
        'Provider and priority are required'
      );
    }
    
    await this.loadBalancer.setProviderPriority(
      params.provider,
      params.priority
    );
    
    return {
      success: true,
      provider: params.provider,
      priority: params.priority
    };
  }
  
  /**
   * Track usage for billing and metrics
   */
  private trackUsage(
    requestId: string,
    connectionId: string,
    method: string,
    duration: number,
    success: boolean,
    error?: string
  ) {
    if (!this.db) return;
    
    const activeRequest = this.activeRequests.get(requestId);
    
    if (activeRequest) {
      this.db.run(
        `INSERT INTO model_usage
         (request_id, connection_id, provider, model, input_tokens, output_tokens, cost, duration, success, error, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          requestId,
          connectionId,
          activeRequest.provider,
          activeRequest.model,
          0, // Would need actual token counts
          0,
          0, // Would need actual cost
          duration,
          success ? 1 : 0,
          error || null,
          Date.now()
        ]
      );
    }
  }
  
  /**
   * Log detailed model usage
   */
  private logModelUsage(usage: {
    requestId: string;
    provider: string;
    model: string;
    inputTokens: number;
    outputTokens: number;
    cost: number;
    duration: number;
  }) {
    if (!this.db) return;
    
    this.db.run(
      `INSERT INTO model_usage
       (request_id, connection_id, provider, model, input_tokens, output_tokens, cost, duration, success, timestamp)
       VALUES (?, '', ?, ?, ?, ?, ?, ?, 1, ?)`,
      [
        usage.requestId,
        usage.provider,
        usage.model,
        usage.inputTokens,
        usage.outputTokens,
        usage.cost,
        usage.duration,
        Date.now()
      ]
    );
    
    // Update aggregated metrics
    this.updateModelMetrics(usage);
  }
  
  /**
   * Update model performance metrics
   */
  private updateModelMetrics(usage: any) {
    if (!this.db) return;
    
    // Check if metrics exist
    const existing = this.db.query(
      `SELECT * FROM model_metrics WHERE provider = ? AND model = ?`
    ).get(usage.provider, usage.model) as any;
    
    if (existing) {
      // Update existing metrics
      const totalRequests = existing.total_requests + 1;
      const totalTokens = existing.total_tokens + usage.inputTokens + usage.outputTokens;
      const totalCost = existing.total_cost + usage.cost;
      const avgLatency = (existing.avg_latency * existing.total_requests + usage.duration) / totalRequests;
      const tokensPerSecond = (usage.inputTokens + usage.outputTokens) / (usage.duration / 1000);
      const avgTokensPerSecond = (existing.avg_tokens_per_second * existing.total_requests + tokensPerSecond) / totalRequests;
      
      this.db.run(
        `UPDATE model_metrics
         SET avg_latency = ?, avg_tokens_per_second = ?, total_requests = ?,
             total_tokens = ?, total_cost = ?, updated_at = ?
         WHERE provider = ? AND model = ?`,
        [
          avgLatency,
          avgTokensPerSecond,
          totalRequests,
          totalTokens,
          totalCost,
          Date.now(),
          usage.provider,
          usage.model
        ]
      );
    } else {
      // Create new metrics
      const tokensPerSecond = (usage.inputTokens + usage.outputTokens) / (usage.duration / 1000);
      
      this.db.run(
        `INSERT INTO model_metrics
         (provider, model, avg_latency, success_rate, avg_tokens_per_second,
          total_requests, total_tokens, total_cost, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          usage.provider,
          usage.model,
          usage.duration,
          1.0,
          tokensPerSecond,
          1,
          usage.inputTokens + usage.outputTokens,
          usage.cost,
          Date.now()
        ]
      );
    }
  }
  
  /**
   * Start the server
   */
  async start(): Promise<void> {
    // Initialize router and optimizer
    await this.modelRouter.initialize();
    await this.costOptimizer.initialize();
    
    // Start base server
    await super.start();
    
    console.log(`Model MCP Server ready on port ${this.config.port}`);
    
    // Emit ready event
    this.emit('models-ready', {
      providers: await this.modelRouter.getProviders(),
      capabilities: this.capabilities
    });
  }
  
  /**
   * Stop the server
   */
  async stop(): Promise<void> {
    // Cancel active requests
    for (const requestId of this.activeRequests.keys()) {
      console.log(`Cancelling active request: ${requestId}`);
    }
    this.activeRequests.clear();
    
    // Stop base server
    await super.stop();
    
    console.log('Model MCP Server stopped');
  }
}