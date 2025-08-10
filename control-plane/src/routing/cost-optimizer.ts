import { ModelConfig, ModelMetrics, CostReport } from '../types/routing';

export class CostOptimizer {
  private costHistory: Map<string, number[]>;
  private performanceHistory: Map<string, number[]>;
  
  constructor() {
    this.costHistory = new Map();
    this.performanceHistory = new Map();
  }
  
  selectCheapestModel(
    models: Map<string, ModelConfig>,
    tokenBudget: number
  ): string {
    let cheapest: string | null = null;
    let lowestCost = Infinity;
    
    for (const [name, config] of models) {
      if (config.maxTokens >= tokenBudget) {
        const cost = config.costPerToken * tokenBudget;
        if (cost < lowestCost) {
          lowestCost = cost;
          cheapest = name;
        }
      }
    }
    
    return cheapest || 'claude-3-haiku'; // Default fallback
  }
  
  selectOptimalModel(
    models: Map<string, ModelConfig>,
    tokenBudget: number,
    complexity: 'simple' | 'moderate' | 'complex'
  ): string {
    const candidates = Array.from(models.values())
      .filter(m => m.maxTokens >= tokenBudget)
      .filter(m => this.supportsComplexity(m, complexity));
    
    if (candidates.length === 0) {
      // No suitable models, use most capable
      return 'claude-3-opus';
    }
    
    // Calculate score for each model
    const scored = candidates.map(model => ({
      model,
      score: this.calculateScore(model, tokenBudget, complexity)
    }));
    
    // Sort by score and return best
    scored.sort((a, b) => b.score - a.score);
    return scored[0].model.name;
  }
  
  private supportsComplexity(
    model: ModelConfig,
    complexity: 'simple' | 'moderate' | 'complex'
  ): boolean {
    switch (complexity) {
      case 'simple':
        return model.capabilities.includes('simple-tasks') || 
               model.capabilities.includes('coding');
        
      case 'moderate':
        return model.capabilities.includes('coding') || 
               model.capabilities.includes('analysis');
        
      case 'complex':
        return model.capabilities.includes('reasoning') || 
               model.capabilities.includes('analysis');
        
      default:
        return true;
    }
  }
  
  private calculateScore(
    model: ModelConfig,
    tokenBudget: number,
    complexity: string
  ): number {
    // Cost score (inverse - lower cost = higher score)
    const costScore = 1 / (model.costPerToken * tokenBudget + 0.001);
    
    // Performance score (inverse latency)
    const performanceScore = 1000 / model.latency;
    
    // Capability score
    const capabilityScore = this.getCapabilityScore(model, complexity);
    
    // Weights based on complexity
    let costWeight = 0.4;
    let performanceWeight = 0.3;
    let capabilityWeight = 0.3;
    
    if (complexity === 'simple') {
      costWeight = 0.6;
      performanceWeight = 0.3;
      capabilityWeight = 0.1;
    } else if (complexity === 'complex') {
      costWeight = 0.2;
      performanceWeight = 0.2;
      capabilityWeight = 0.6;
    }
    
    // Normalize scores
    const normalizedCost = Math.min(costScore / 100, 1);
    const normalizedPerf = Math.min(performanceScore / 10, 1);
    
    return (normalizedCost * costWeight) + 
           (normalizedPerf * performanceWeight) + 
           (capabilityScore * capabilityWeight);
  }
  
  private getCapabilityScore(model: ModelConfig, complexity: string): number {
    let score = 0;
    
    // Base scores for capabilities
    if (model.capabilities.includes('reasoning')) score += 1.0;
    if (model.capabilities.includes('analysis')) score += 0.8;
    if (model.capabilities.includes('coding')) score += 0.6;
    if (model.capabilities.includes('simple-tasks')) score += 0.4;
    
    // Adjust based on complexity match
    if (complexity === 'complex' && model.capabilities.includes('reasoning')) {
      score *= 1.5;
    } else if (complexity === 'simple' && model.capabilities.includes('simple-tasks')) {
      score *= 1.5;
    }
    
    // Normalize to 0-1 range
    return Math.min(score / 2, 1);
  }
  
  trackCost(model: string, cost: number) {
    if (!this.costHistory.has(model)) {
      this.costHistory.set(model, []);
    }
    
    const history = this.costHistory.get(model)!;
    history.push(cost);
    
    // Keep only last 100 entries
    if (history.length > 100) {
      history.shift();
    }
  }
  
  getCostReport(metrics: Map<string, ModelMetrics>): CostReport {
    const report: CostReport = {
      totalCost: 0,
      byModel: {},
      byTimeframe: {},
      projectedMonthlyCost: 0
    };
    
    // Calculate total cost from metrics
    for (const [model, modelMetrics] of metrics) {
      report.totalCost += modelMetrics.totalCost;
      report.byModel[model] = modelMetrics.totalCost;
    }
    
    // Calculate timeframe costs (simplified - would need timestamps in production)
    const now = new Date();
    const currentHour = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()} ${now.getHours()}:00`;
    report.byTimeframe[currentHour] = report.totalCost * 0.1; // Estimate 10% in last hour
    
    // Calculate projection (assuming consistent usage)
    const hoursElapsed = 24; // Assume 24 hours of data
    const dailyAverage = report.totalCost / (hoursElapsed / 24);
    report.projectedMonthlyCost = dailyAverage * 30;
    
    return report;
  }
  
  optimizeBudget(
    monthlyBudget: number,
    currentSpend: number,
    daysRemaining: number
  ): {
    dailyLimit: number;
    recommendedModels: string[];
    restrictions: string[];
  } {
    const remainingBudget = monthlyBudget - currentSpend;
    const dailyLimit = remainingBudget / daysRemaining;
    
    const recommendations: string[] = [];
    const restrictions: string[] = [];
    
    if (dailyLimit < 10) {
      // Very tight budget
      recommendations.push('claude-3-haiku', 'gpt-3.5-turbo');
      restrictions.push('Avoid claude-3-opus and gpt-4 except for critical tasks');
    } else if (dailyLimit < 50) {
      // Moderate budget
      recommendations.push('claude-3-sonnet', 'gemini-pro');
      restrictions.push('Use claude-3-opus sparingly');
    } else {
      // Comfortable budget
      recommendations.push('claude-3-sonnet', 'claude-3-opus', 'gpt-4-turbo');
    }
    
    return {
      dailyLimit,
      recommendedModels: recommendations,
      restrictions
    };
  }
}