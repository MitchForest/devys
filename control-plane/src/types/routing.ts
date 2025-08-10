export interface RouteRequest {
  prompt: string;
  preferredModel: string;
  fallbackModels: string[];
  maxTokens: number;
  temperature: number;
  urgency?: 'low' | 'normal' | 'high';
  complexity?: 'simple' | 'moderate' | 'complex';
}

export interface ModelResponse {
  content: string;
  model: string;
  tokensUsed: number;
  duration: number;
  cost: number;
}

export interface ModelConfig {
  name: string;
  provider: 'anthropic' | 'openai' | 'google' | 'local';
  endpoint: string;
  apiKey?: string;
  maxTokens: number;
  costPerToken: number;
  latency: number; // average ms
  capabilities: string[];
  rateLimit?: {
    requestsPerMinute: number;
    tokensPerMinute: number;
  };
}

export interface ModelMetrics {
  model: string;
  totalRequests: number;
  successRate: number;
  averageLatency: number;
  totalTokens: number;
  totalCost: number;
  errors: number;
}

export interface CostReport {
  totalCost: number;
  byModel: Record<string, number>;
  byTimeframe: Record<string, number>;
  projectedMonthlyCost: number;
}