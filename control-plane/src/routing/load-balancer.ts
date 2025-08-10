import { ModelConfig } from '../types/routing';

export class LoadBalancer {
  private modelLoad: Map<string, number>;
  private modelQueues: Map<string, Promise<any>[]>;
  private models: Map<string, ModelConfig>;
  
  constructor(models: Map<string, ModelConfig>) {
    this.models = models;
    this.modelLoad = new Map();
    this.modelQueues = new Map();
    
    // Initialize load tracking
    for (const model of models.keys()) {
      this.modelLoad.set(model, 0);
      this.modelQueues.set(model, []);
    }
  }
  
  selectFastestAvailable(): string {
    let fastest: string | null = null;
    let minLatency = Infinity;
    
    for (const [name, config] of this.models) {
      const load = this.modelLoad.get(name) || 0;
      
      // Skip if overloaded
      if (load > 0.9) continue;
      
      // Adjust latency based on current load
      const adjustedLatency = config.latency * (1 + load);
      
      if (adjustedLatency < minLatency) {
        minLatency = adjustedLatency;
        fastest = name;
      }
    }
    
    return fastest || 'claude-3-sonnet'; // Default fallback
  }
  
  selectLeastLoaded(): string {
    let leastLoaded: string | null = null;
    let minLoad = Infinity;
    
    for (const [model, load] of this.modelLoad) {
      if (load < minLoad) {
        minLoad = load;
        leastLoaded = model;
      }
    }
    
    return leastLoaded || 'claude-3-sonnet';
  }
  
  getModelLoad(model: string): number {
    return this.modelLoad.get(model) || 0;
  }
  
  async executeWithBackpressure<T>(
    model: string,
    task: () => Promise<T>
  ): Promise<T> {
    // Track load
    this.incrementLoad(model);
    
    try {
      // Get queue for this model
      const queue = this.modelQueues.get(model) || [];
      
      // Check if we should wait
      if (queue.length > 10) {
        console.log(`Model ${model} queue is full (${queue.length}), waiting...`);
        // Wait for some tasks to complete
        await Promise.race(queue);
      }
      
      // Execute task
      const promise = task();
      queue.push(promise);
      this.modelQueues.set(model, queue);
      
      const result = await promise;
      
      // Remove from queue
      const index = queue.indexOf(promise);
      if (index > -1) {
        queue.splice(index, 1);
      }
      
      return result;
      
    } finally {
      this.decrementLoad(model);
    }
  }
  
  private incrementLoad(model: string) {
    const current = this.modelLoad.get(model) || 0;
    const maxRequests = this.models.get(model)?.rateLimit?.requestsPerMinute || 100;
    
    // Calculate load as percentage of rate limit
    const newLoad = Math.min(1, current + (1 / maxRequests));
    this.modelLoad.set(model, newLoad);
    
    // Schedule decrement after 1 minute
    setTimeout(() => this.decrementLoad(model), 60000);
  }
  
  private decrementLoad(model: string) {
    const current = this.modelLoad.get(model) || 0;
    const maxRequests = this.models.get(model)?.rateLimit?.requestsPerMinute || 100;
    
    const newLoad = Math.max(0, current - (1 / maxRequests));
    this.modelLoad.set(model, newLoad);
  }
  
  distributeLoad(tasks: Array<() => Promise<any>>): Map<string, Array<() => Promise<any>>> {
    const distribution = new Map<string, Array<() => Promise<any>>>();
    
    // Initialize distribution map
    for (const model of this.models.keys()) {
      distribution.set(model, []);
    }
    
    // Sort models by current load (ascending)
    const sortedModels = Array.from(this.modelLoad.entries())
      .sort((a, b) => a[1] - b[1])
      .map(entry => entry[0]);
    
    // Distribute tasks round-robin starting with least loaded
    let modelIndex = 0;
    for (const task of tasks) {
      const model = sortedModels[modelIndex % sortedModels.length];
      distribution.get(model)!.push(task);
      modelIndex++;
    }
    
    return distribution;
  }
  
  async waitForCapacity(model: string, timeout: number = 5000): Promise<boolean> {
    const startTime = Date.now();
    
    while (Date.now() - startTime < timeout) {
      const load = this.modelLoad.get(model) || 0;
      if (load < 0.8) {
        return true;
      }
      
      // Wait a bit before checking again
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    return false;
  }
  
  getStatus(): {
    models: Array<{
      name: string;
      load: number;
      queueLength: number;
      available: boolean;
    }>;
    recommendations: string[];
  } {
    const models = [];
    const recommendations = [];
    
    for (const [name, config] of this.models) {
      const load = this.modelLoad.get(name) || 0;
      const queue = this.modelQueues.get(name) || [];
      
      models.push({
        name,
        load,
        queueLength: queue.length,
        available: load < 0.9
      });
      
      if (load < 0.3) {
        recommendations.push(`${name} is underutilized`);
      } else if (load > 0.8) {
        recommendations.push(`${name} is heavily loaded, consider using alternatives`);
      }
    }
    
    return { models, recommendations };
  }
}