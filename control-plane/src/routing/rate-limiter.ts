export class RateLimiter {
  private requestCounts: Map<string, number[]>;
  private tokenCounts: Map<string, number[]>;
  private windowSize: number = 60000; // 1 minute window
  
  constructor() {
    this.requestCounts = new Map();
    this.tokenCounts = new Map();
  }
  
  async checkLimit(model: string): Promise<void> {
    const now = Date.now();
    
    // Clean old entries
    this.cleanOldEntries(model, now);
    
    // Get current counts
    const requests = this.requestCounts.get(model) || [];
    const requestCount = requests.length;
    
    // Check against limits (would be configured per model in production)
    const maxRequests = this.getMaxRequests(model);
    
    if (requestCount >= maxRequests) {
      // Calculate wait time
      const oldestRequest = Math.min(...requests);
      const waitTime = this.windowSize - (now - oldestRequest);
      
      if (waitTime > 0) {
        console.log(`Rate limit reached for ${model}, waiting ${waitTime}ms`);
        await new Promise(resolve => setTimeout(resolve, waitTime));
      }
    }
    
    // Record this request
    requests.push(now);
    this.requestCounts.set(model, requests);
  }
  
  async checkTokenLimit(model: string, tokens: number): Promise<void> {
    const now = Date.now();
    
    // Clean old entries
    this.cleanOldTokenEntries(model, now);
    
    // Get current token count
    const tokenEntries = this.tokenCounts.get(model) || [];
    const currentTokens = tokenEntries.reduce((sum, entry) => sum + entry, 0);
    
    // Check against limits
    const maxTokens = this.getMaxTokens(model);
    
    if (currentTokens + tokens > maxTokens) {
      // Need to wait for some tokens to expire
      const waitTime = this.calculateTokenWaitTime(model, tokens, maxTokens);
      
      if (waitTime > 0) {
        console.log(`Token limit reached for ${model}, waiting ${waitTime}ms`);
        await new Promise(resolve => setTimeout(resolve, waitTime));
      }
    }
    
    // Record these tokens
    tokenEntries.push(tokens);
    this.tokenCounts.set(model, tokenEntries);
  }
  
  private cleanOldEntries(model: string, now: number) {
    const requests = this.requestCounts.get(model) || [];
    const filtered = requests.filter(time => now - time < this.windowSize);
    this.requestCounts.set(model, filtered);
  }
  
  private cleanOldTokenEntries(model: string, now: number) {
    // For tokens, we need to track both count and timestamp
    // Simplified implementation - in production would track both
    const tokens = this.tokenCounts.get(model) || [];
    // Keep only recent entries (simplified)
    if (tokens.length > 100) {
      this.tokenCounts.set(model, tokens.slice(-50));
    }
  }
  
  private getMaxRequests(model: string): number {
    // Model-specific limits
    const limits: Record<string, number> = {
      'claude-3-opus': 50,
      'claude-3-sonnet': 100,
      'claude-3-haiku': 200,
      'gpt-4-turbo': 60,
      'gpt-4': 40,
      'gpt-3.5-turbo': 200,
      'gemini-pro': 60
    };
    
    return limits[model] || 100;
  }
  
  private getMaxTokens(model: string): number {
    // Tokens per minute
    const limits: Record<string, number> = {
      'claude-3-opus': 100000,
      'claude-3-sonnet': 200000,
      'claude-3-haiku': 400000,
      'gpt-4-turbo': 150000,
      'gpt-4': 80000,
      'gpt-3.5-turbo': 500000,
      'gemini-pro': 120000
    };
    
    return limits[model] || 100000;
  }
  
  private calculateTokenWaitTime(
    model: string,
    requestedTokens: number,
    maxTokens: number
  ): number {
    // Simplified calculation
    // In production, would track token timestamps and calculate precise wait time
    const currentTokens = (this.tokenCounts.get(model) || [])
      .reduce((sum, t) => sum + t, 0);
    
    if (currentTokens + requestedTokens <= maxTokens) {
      return 0;
    }
    
    // Estimate wait time based on how much we're over
    const overageRatio = (currentTokens + requestedTokens - maxTokens) / maxTokens;
    return Math.min(this.windowSize * overageRatio, this.windowSize);
  }
  
  async executeParallel<T>(
    tasks: Array<() => Promise<T>>
  ): Promise<T[]> {
    // Group tasks by estimated model (simplified - would need actual model info)
    const batchSize = 5; // Process 5 at a time
    const results: T[] = [];
    
    for (let i = 0; i < tasks.length; i += batchSize) {
      const batch = tasks.slice(i, i + batchSize);
      
      // Execute batch in parallel
      const batchResults = await Promise.all(
        batch.map(task => this.executeWithRetry(task))
      );
      
      results.push(...batchResults);
      
      // Small delay between batches to avoid overwhelming
      if (i + batchSize < tasks.length) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }
    
    return results;
  }
  
  private async executeWithRetry<T>(
    task: () => Promise<T>,
    maxRetries: number = 3
  ): Promise<T> {
    let lastError: any;
    
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await task();
      } catch (error) {
        lastError = error;
        
        // Check if it's a rate limit error
        if (this.isRateLimitError(error)) {
          // Exponential backoff
          const waitTime = Math.pow(2, attempt) * 1000;
          console.log(`Rate limit error, retrying in ${waitTime}ms`);
          await new Promise(resolve => setTimeout(resolve, waitTime));
        } else {
          // Not a rate limit error, don't retry
          throw error;
        }
      }
    }
    
    throw lastError;
  }
  
  private isRateLimitError(error: any): boolean {
    const errorStr = error.toString().toLowerCase();
    return errorStr.includes('rate') || 
           errorStr.includes('429') ||
           errorStr.includes('quota') ||
           errorStr.includes('limit');
  }
  
  getRateLimitStatus(): Map<string, {
    requestsUsed: number;
    requestsLimit: number;
    tokensUsed: number;
    tokensLimit: number;
    resetIn: number;
  }> {
    const status = new Map();
    const now = Date.now();
    
    const models = [
      'claude-3-opus',
      'claude-3-sonnet',
      'claude-3-haiku',
      'gpt-4-turbo',
      'gpt-4',
      'gpt-3.5-turbo',
      'gemini-pro'
    ];
    
    for (const model of models) {
      const requests = (this.requestCounts.get(model) || [])
        .filter(time => now - time < this.windowSize);
      
      const tokens = (this.tokenCounts.get(model) || [])
        .reduce((sum, t) => sum + t, 0);
      
      const oldestRequest = requests.length > 0 
        ? Math.min(...requests)
        : now;
      
      status.set(model, {
        requestsUsed: requests.length,
        requestsLimit: this.getMaxRequests(model),
        tokensUsed: tokens,
        tokensLimit: this.getMaxTokens(model),
        resetIn: Math.max(0, this.windowSize - (now - oldestRequest))
      });
    }
    
    return status;
  }
}