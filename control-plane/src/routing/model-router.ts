import {
  RouteRequest,
  ModelResponse,
  ModelConfig,
  ModelMetrics,
  CostReport
} from '../types/routing';
import { CostOptimizer } from './cost-optimizer';
import { LoadBalancer } from './load-balancer';
import { RateLimiter } from './rate-limiter';
import { Database } from 'bun:sqlite';

export class ModelRouter {
  private models: Map<string, ModelConfig>;
  private loadBalancer: LoadBalancer;
  private costOptimizer: CostOptimizer;
  private rateLimiter: RateLimiter;
  private metrics: Map<string, ModelMetrics>;
  private db?: Database;
  
  constructor(db?: Database) {
    this.models = this.loadModelConfigs();
    this.loadBalancer = new LoadBalancer(this.models);
    this.costOptimizer = new CostOptimizer();
    this.rateLimiter = new RateLimiter();
    this.metrics = new Map();
    this.db = db;
    
    this.initializeMetrics();
  }
  
  private loadModelConfigs(): Map<string, ModelConfig> {
    const configs = new Map<string, ModelConfig>();
    
    // Claude models
    configs.set('claude-3-opus', {
      name: 'claude-3-opus',
      provider: 'anthropic',
      endpoint: 'https://api.anthropic.com/v1/messages',
      apiKey: process.env.ANTHROPIC_API_KEY,
      maxTokens: 100000,
      costPerToken: 0.00003,
      latency: 2000,
      capabilities: ['reasoning', 'coding', 'analysis'],
      rateLimit: {
        requestsPerMinute: 50,
        tokensPerMinute: 100000
      }
    });
    
    configs.set('claude-3-sonnet', {
      name: 'claude-3-sonnet',
      provider: 'anthropic',
      endpoint: 'https://api.anthropic.com/v1/messages',
      apiKey: process.env.ANTHROPIC_API_KEY,
      maxTokens: 100000,
      costPerToken: 0.00001,
      latency: 1500,
      capabilities: ['coding', 'analysis'],
      rateLimit: {
        requestsPerMinute: 100,
        tokensPerMinute: 200000
      }
    });
    
    configs.set('claude-3-haiku', {
      name: 'claude-3-haiku',
      provider: 'anthropic',
      endpoint: 'https://api.anthropic.com/v1/messages',
      apiKey: process.env.ANTHROPIC_API_KEY,
      maxTokens: 100000,
      costPerToken: 0.0000025,
      latency: 800,
      capabilities: ['coding', 'simple-tasks'],
      rateLimit: {
        requestsPerMinute: 200,
        tokensPerMinute: 400000
      }
    });
    
    // OpenAI models
    configs.set('gpt-4-turbo', {
      name: 'gpt-4-turbo',
      provider: 'openai',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      apiKey: process.env.OPENAI_API_KEY,
      maxTokens: 128000,
      costPerToken: 0.00002,
      latency: 2500,
      capabilities: ['reasoning', 'coding', 'analysis'],
      rateLimit: {
        requestsPerMinute: 60,
        tokensPerMinute: 150000
      }
    });
    
    configs.set('gpt-4', {
      name: 'gpt-4',
      provider: 'openai',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      apiKey: process.env.OPENAI_API_KEY,
      maxTokens: 8192,
      costPerToken: 0.00003,
      latency: 3000,
      capabilities: ['reasoning', 'coding', 'analysis'],
      rateLimit: {
        requestsPerMinute: 40,
        tokensPerMinute: 80000
      }
    });
    
    configs.set('gpt-3.5-turbo', {
      name: 'gpt-3.5-turbo',
      provider: 'openai',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      apiKey: process.env.OPENAI_API_KEY,
      maxTokens: 16385,
      costPerToken: 0.000001,
      latency: 500,
      capabilities: ['coding', 'simple-tasks'],
      rateLimit: {
        requestsPerMinute: 200,
        tokensPerMinute: 500000
      }
    });
    
    // Google models
    configs.set('gemini-pro', {
      name: 'gemini-pro',
      provider: 'google',
      endpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro',
      apiKey: process.env.GOOGLE_API_KEY,
      maxTokens: 32000,
      costPerToken: 0.00001,
      latency: 1800,
      capabilities: ['reasoning', 'coding', 'analysis'],
      rateLimit: {
        requestsPerMinute: 60,
        tokensPerMinute: 120000
      }
    });
    
    return configs;
  }
  
  private initializeMetrics() {
    for (const [name, config] of this.models) {
      this.metrics.set(name, {
        model: name,
        totalRequests: 0,
        successRate: 1.0,
        averageLatency: config.latency,
        totalTokens: 0,
        totalCost: 0,
        errors: 0
      });
    }
  }
  
  async route(request: RouteRequest): Promise<ModelResponse> {
    // Check rate limits
    await this.rateLimiter.checkLimit(request.preferredModel);
    
    // Select optimal model based on request characteristics
    const selectedModel = this.selectModel(request);
    
    try {
      // Attempt with selected model
      return await this.callModel(selectedModel, request);
    } catch (error) {
      console.warn(`Model ${selectedModel} failed:`, error);
      
      // Fallback logic
      for (const fallbackModel of request.fallbackModels) {
        try {
          console.log(`Falling back to ${fallbackModel}`);
          return await this.callModel(fallbackModel, request);
        } catch (fallbackError) {
          console.warn(`Fallback model ${fallbackModel} failed:`, fallbackError);
          continue;
        }
      }
      
      throw new Error('All models failed');
    }
  }
  
  private selectModel(request: RouteRequest): string {
    // Factor in complexity
    if (request.complexity === 'simple') {
      // Use cheaper, faster models for simple tasks
      return this.costOptimizer.selectCheapestModel(
        this.models,
        request.maxTokens
      );
    }
    
    // Factor in urgency
    if (request.urgency === 'high') {
      // Use fastest model regardless of cost
      return this.loadBalancer.selectFastestAvailable();
    }
    
    // Check if preferred model is available
    if (this.isModelAvailable(request.preferredModel)) {
      const load = this.loadBalancer.getModelLoad(request.preferredModel);
      if (load < 0.8) { // Less than 80% loaded
        return request.preferredModel;
      }
    }
    
    // Otherwise optimize for cost/performance balance
    return this.costOptimizer.selectOptimalModel(
      this.models,
      request.maxTokens,
      request.complexity || 'moderate'
    );
  }
  
  private isModelAvailable(modelName: string): boolean {
    const config = this.models.get(modelName);
    if (!config) return false;
    
    // Check if API key is configured
    if (config.provider !== 'local' && !config.apiKey) {
      return false;
    }
    
    // Check error rate
    const metrics = this.metrics.get(modelName);
    if (metrics && metrics.successRate < 0.5) {
      return false; // Too many errors recently
    }
    
    return true;
  }
  
  async callModel(modelName: string, request: RouteRequest): Promise<ModelResponse> {
    const model = this.models.get(modelName);
    if (!model) throw new Error(`Model ${modelName} not configured`);
    
    const startTime = Date.now();
    
    // Build provider-specific request
    const providerRequest = this.buildProviderRequest(model, request);
    
    // Make API call
    const response = await this.makeApiCall(model, providerRequest);
    
    // Extract content and count tokens
    const content = this.extractContent(response, model.provider);
    const tokensUsed = this.countTokens(content);
    
    // Calculate metrics
    const duration = Date.now() - startTime;
    const cost = tokensUsed * model.costPerToken;
    
    // Update metrics
    await this.updateMetrics(modelName, {
      success: true,
      duration,
      tokensUsed,
      cost
    });
    
    return {
      content,
      model: modelName,
      tokensUsed,
      duration,
      cost
    };
  }
  
  private buildProviderRequest(model: ModelConfig, request: RouteRequest): any {
    switch (model.provider) {
      case 'anthropic':
        return {
          model: model.name.replace('claude-3-', 'claude-3.'),
          messages: [
            {
              role: 'user',
              content: request.prompt
            }
          ],
          max_tokens: Math.min(request.maxTokens, model.maxTokens),
          temperature: request.temperature
        };
        
      case 'openai':
        return {
          model: model.name,
          messages: [
            {
              role: 'user',
              content: request.prompt
            }
          ],
          max_tokens: Math.min(request.maxTokens, model.maxTokens),
          temperature: request.temperature
        };
        
      case 'google':
        return {
          contents: [
            {
              parts: [
                {
                  text: request.prompt
                }
              ]
            }
          ],
          generationConfig: {
            maxOutputTokens: Math.min(request.maxTokens, model.maxTokens),
            temperature: request.temperature
          }
        };
        
      default:
        throw new Error(`Unsupported provider: ${model.provider}`);
    }
  }
  
  private async makeApiCall(model: ModelConfig, request: any): Promise<any> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    
    // Add provider-specific headers
    switch (model.provider) {
      case 'anthropic':
        headers['x-api-key'] = model.apiKey!;
        headers['anthropic-version'] = '2023-06-01';
        break;
        
      case 'openai':
        headers['Authorization'] = `Bearer ${model.apiKey}`;
        break;
        
      case 'google':
        // Google uses API key in URL
        break;
    }
    
    const url = model.provider === 'google' 
      ? `${model.endpoint}:generateContent?key=${model.apiKey}`
      : model.endpoint;
    
    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(request)
    });
    
    if (!response.ok) {
      const error = await response.text();
      throw new Error(`API call failed: ${response.status} - ${error}`);
    }
    
    return await response.json();
  }
  
  private extractContent(response: any, provider: string): string {
    switch (provider) {
      case 'anthropic':
        return response.content?.[0]?.text || '';
        
      case 'openai':
        return response.choices?.[0]?.message?.content || '';
        
      case 'google':
        return response.candidates?.[0]?.content?.parts?.[0]?.text || '';
        
      default:
        return '';
    }
  }
  
  private countTokens(text: string): number {
    // Simple approximation - in production would use proper tokenizer
    return Math.ceil(text.length / 4);
  }
  
  private async updateMetrics(
    modelName: string,
    result: {
      success: boolean;
      duration: number;
      tokensUsed: number;
      cost: number;
    }
  ) {
    const metrics = this.metrics.get(modelName);
    if (!metrics) return;
    
    metrics.totalRequests++;
    
    if (result.success) {
      // Update success rate (exponential moving average)
      metrics.successRate = metrics.successRate * 0.95 + 0.05;
      
      // Update average latency
      metrics.averageLatency = 
        (metrics.averageLatency * (metrics.totalRequests - 1) + result.duration) / 
        metrics.totalRequests;
      
      // Update totals
      metrics.totalTokens += result.tokensUsed;
      metrics.totalCost += result.cost;
    } else {
      metrics.errors++;
      metrics.successRate = metrics.successRate * 0.95;
    }
    
    // Persist to database if available
    if (this.db) {
      this.db.run(
        `INSERT INTO model_metrics 
         (model, success, tokens_used, cost, duration, timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          modelName,
          result.success ? 1 : 0,
          result.tokensUsed,
          result.cost,
          result.duration,
          Date.now()
        ]
      );
    }
  }
  
  async routeParallel(requests: RouteRequest[]): Promise<ModelResponse[]> {
    // Group by complexity for optimal model selection
    const grouped = this.groupByComplexity(requests);
    
    // Assign models to minimize total cost and time
    const assignments = this.optimizeParallelAssignments(grouped);
    
    // Execute in parallel with rate limiting
    return await this.rateLimiter.executeParallel(
      assignments.map(a => () => this.route(a))
    );
  }
  
  private groupByComplexity(
    requests: RouteRequest[]
  ): Map<string, RouteRequest[]> {
    const grouped = new Map<string, RouteRequest[]>();
    
    for (const request of requests) {
      const complexity = request.complexity || 'moderate';
      const existing = grouped.get(complexity) || [];
      existing.push(request);
      grouped.set(complexity, existing);
    }
    
    return grouped;
  }
  
  private optimizeParallelAssignments(
    grouped: Map<string, RouteRequest[]>
  ): RouteRequest[] {
    const optimized: RouteRequest[] = [];
    
    for (const [complexity, requests] of grouped) {
      // Select best model for this complexity
      const optimalModel = this.costOptimizer.selectOptimalModel(
        this.models,
        Math.max(...requests.map(r => r.maxTokens)),
        complexity as any
      );
      
      // Update requests to use optimal model
      for (const request of requests) {
        optimized.push({
          ...request,
          preferredModel: optimalModel
        });
      }
    }
    
    return optimized;
  }
  
  getMetrics(): Map<string, ModelMetrics> {
    return this.metrics;
  }
  
  getCostReport(): CostReport {
    return this.costOptimizer.getCostReport(this.metrics);
  }
}