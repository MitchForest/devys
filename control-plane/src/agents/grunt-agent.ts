// Grunt Agent for Phase 4
// Handles simple, repetitive tasks using local/free models to optimize costs

import { BaseAgent } from './base-agent';
import { Database } from 'bun:sqlite';
import {
  GruntTask,
  GruntResult,
  GruntConfig,
  TaskClassifier as GruntTaskClassifier,
  TaskResult
} from '../types/agents';
import { PHASE_4_ROUTER_CONFIG, TaskClassifier } from '../routing/claude-code-router-config';
import { ModelRouter } from '../routing/model-router';

export interface OllamaModel {
  name: string;
  available: boolean;
  size: string;
  capabilities: string[];
}

/**
 * Task complexity classifier specifically for grunt work
 */
class GruntTaskComplexityClassifier {
  /**
   * Classify grunt task complexity
   */
  static classifyGruntTask(task: GruntTask): 'simple' | 'moderate' | 'complex' {
    switch (task.type) {
      case 'format':
      case 'lint':
      case 'cleanup':
      case 'delete':
        return 'simple';
      
      case 'test':
      case 'commit':
      case 'docs':
        return task.scope === 'single' ? 'simple' : 'moderate';
      
      case 'refactor':
      case 'optimize':
        return 'complex';
      
      default:
        return 'simple';
    }
  }
  
  /**
   * Determine if task can be parallelized
   */
  static canParallelize(tasks: GruntTask[]): boolean {
    // Can parallelize if no dependencies between tasks
    const dependencies = ['test', 'commit']; // These usually need to run after other tasks
    return !tasks.some(task => dependencies.includes(task.type));
  }
  
  /**
   * Group tasks for optimal execution
   */
  static groupTasksForExecution(tasks: GruntTask[]): GruntTask[][] {
    const groups: GruntTask[][] = [];
    const sequential: GruntTask[] = [];
    const parallel: GruntTask[] = [];
    
    for (const task of tasks) {
      if (task.type === 'commit' || task.type === 'test') {
        sequential.push(task);
      } else {
        parallel.push(task);
      }
    }
    
    // Add parallel tasks as one group
    if (parallel.length > 0) {
      groups.push(parallel);
    }
    
    // Add sequential tasks individually
    for (const task of sequential) {
      groups.push([task]);
    }
    
    return groups;
  }
}

/**
 * GruntAgent - Specialized agent for simple, repetitive tasks
 * 
 * Prioritizes local models to minimize costs while maintaining quality
 * for routine development tasks.
 */
export class GruntAgent extends BaseAgent {
  private localModels: Map<string, OllamaModel>;
  private modelRouter: ModelRouter;
  private taskQueue: GruntTask[];
  private executing: boolean;
  private maxConcurrency: number;
  
  constructor(workspace: string, db: Database) {
    super(workspace, db);
    
    this.localModels = new Map();
    this.modelRouter = new ModelRouter(db);
    this.taskQueue = [];
    this.executing = false;
    this.maxConcurrency = 4;
    
    this.initializeLocalModels();
    this.setupGruntTables();
  }
  
  private setupGruntTables(): void {
    this.db.run(`
      CREATE TABLE IF NOT EXISTS grunt_tasks (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        files TEXT, -- JSON array
        scope TEXT,
        message TEXT,
        status TEXT NOT NULL,
        model_used TEXT,
        tokens_used INTEGER,
        cost REAL,
        duration_ms INTEGER,
        output TEXT,
        errors TEXT, -- JSON array
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS grunt_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_type TEXT NOT NULL,
        model TEXT NOT NULL,
        success_rate REAL NOT NULL,
        avg_duration INTEGER NOT NULL,
        total_executions INTEGER NOT NULL,
        last_updated INTEGER NOT NULL
      )
    `);
  }
  
  private async initializeLocalModels(): Promise<void> {
    try {
      // Check if Ollama is available
      const ollamaUrl = PHASE_4_ROUTER_CONFIG.providers.ollama.baseUrl;
      const response = await fetch(`${ollamaUrl}/api/tags`);
      
      if (response.ok) {
        const data = await response.json();
        
        for (const model of data.models) {
          this.localModels.set(model.name, {
            name: model.name,
            available: true,
            size: model.size,
            capabilities: this.inferCapabilities(model.name)
          });
        }
        
        console.log(`Initialized ${this.localModels.size} local models`);
      }
    } catch (error) {
      console.warn('Ollama not available, falling back to cloud models:', error);
    }
  }
  
  private inferCapabilities(modelName: string): string[] {
    const capabilities: string[] = [];
    
    if (modelName.includes('coder')) {
      capabilities.push('coding', 'formatting', 'linting');
    }
    if (modelName.includes('llama')) {
      capabilities.push('general', 'reasoning', 'writing');
    }
    if (modelName.includes('qwen')) {
      capabilities.push('coding', 'analysis', 'documentation');
    }
    
    return capabilities;
  }
  
  /**
   * Execute routine tasks with cost optimization
   */
  async executeRoutineTasks(config: GruntConfig): Promise<GruntResult> {
    const startTime = Date.now();
    const results: TaskResult[] = [];
    let totalTokens = 0;
    let totalCost = 0;
    
    try {
      // Classify and group tasks
      const classifiedTasks = config.tasks.map(task => ({
        ...task,
        complexity: GruntTaskComplexityClassifier.classifyGruntTask(task)
      }));
      
      // Group tasks for optimal execution
      const taskGroups = GruntTaskComplexityClassifier.groupTasksForExecution(classifiedTasks);
      
      // Execute task groups
      for (const group of taskGroups) {
        const groupResults = await this.executeTaskGroup(group);
        results.push(...groupResults);
        
        // Accumulate metrics
        totalTokens += groupResults.reduce((sum, r) => sum + (r.tokens || 0), 0);
        totalCost += groupResults.reduce((sum, r) => sum + (r.cost || 0), 0);
      }
      
      return {
        results,
        tokenUsage: totalTokens,
        cost: totalCost,
        duration: Date.now() - startTime,
        tasksCompleted: results.length,
        tasksSuccessful: results.filter(r => r.status === 'success').length
      };
      
    } catch (error) {
      console.error('Grunt execution failed:', error);
      
      return {
        results,
        tokenUsage: totalTokens,
        cost: totalCost,
        duration: Date.now() - startTime,
        tasksCompleted: results.length,
        tasksSuccessful: results.filter(r => r.status === 'success').length,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  
  /**
   * Execute a group of tasks (potentially in parallel)
   */
  private async executeTaskGroup(tasks: GruntTask[]): Promise<TaskResult[]> {
    if (tasks.length === 1) {
      // Single task
      return [await this.executeTask(tasks[0])];
    } else {
      // Multiple tasks - execute in parallel if safe
      if (GruntTaskComplexityClassifier.canParallelize(tasks)) {
        return await Promise.all(tasks.map(task => this.executeTask(task)));
      } else {
        // Execute sequentially
        const results: TaskResult[] = [];
        for (const task of tasks) {
          const result = await this.executeTask(task);
          results.push(result);
          
          // Stop if task fails and it's critical
          if (result.status === 'failed' && this.isCriticalTask(task)) {
            break;
          }
        }
        return results;
      }
    }
  }
  
  /**
   * Execute individual task with model selection
   */
  private async executeTask(task: GruntTask): Promise<TaskResult> {
    const startTime = Date.now();
    const taskId = crypto.randomUUID();
    
    // Select appropriate model
    const model = this.selectGruntModel(task);
    
    // Save task to database
    this.saveGruntTask(taskId, task, 'running');
    
    try {
      let result: TaskResult;
      
      switch (task.type) {
        case 'format':
          result = await this.formatFiles(task.files || [], model);
          break;
        case 'lint':
          result = await this.lintFiles(task.files || [], model);
          break;
        case 'test':
          result = await this.runTests(task.scope || 'all', model);
          break;
        case 'commit':
          result = await this.commitChanges(task.message || 'Automated commit', model);
          break;
        case 'docs':
          result = await this.generateDocs(task.files || [], model);
          break;
        case 'cleanup':
          result = await this.cleanupFiles(task.files || [], model);
          break;
        default:
          throw new Error(`Unknown grunt task type: ${task.type}`);
      }
      
      // Update task in database
      this.updateGruntTask(taskId, result, 'completed');
      
      // Update metrics
      await this.updateGruntMetrics(task.type, model, true, Date.now() - startTime);
      
      return result;
      
    } catch (error) {
      const errorResult: TaskResult = {
        type: task.type,
        status: 'failed',
        files: task.files || [],
        model,
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        error: error instanceof Error ? error.message : String(error)
      };
      
      // Update task and metrics
      this.updateGruntTask(taskId, errorResult, 'failed');
      await this.updateGruntMetrics(task.type, model, false, Date.now() - startTime);
      
      return errorResult;
    }
  }
  
  /**
   * Select optimal model for grunt task
   */
  private selectGruntModel(task: GruntTask): string {
    const complexity = GruntTaskComplexityClassifier.classifyGruntTask(task);
    
    // For simple tasks, prefer local models
    if (complexity === 'simple') {
      const localModel = this.getAvailableLocalModel(task.type);
      if (localModel) {
        return localModel;
      }
    }
    
    // For moderate tasks, use fast cloud models
    if (complexity === 'moderate') {
      return 'deepseek-chat'; // Fast and cheap
    }
    
    // For complex tasks, use capable models
    return 'claude-3-5-haiku'; // Good balance of speed and capability
  }
  
  /**
   * Get available local model for task type
   */
  private getAvailableLocalModel(taskType: string): string | null {
    const preferences = {
      'format': 'qwen2.5-coder:14b',
      'lint': 'qwen2.5-coder:14b',
      'docs': 'llama3.3:70b',
      'test': 'qwen2.5-coder:14b',
      'commit': 'llama3.3:70b',
      'cleanup': 'qwen2.5-coder:14b'
    };
    
    const preferred = preferences[taskType as keyof typeof preferences];
    if (preferred && this.localModels.get(preferred)?.available) {
      return preferred;
    }
    
    // Fallback to any available coding model
    for (const [name, model] of this.localModels) {
      if (model.available && model.capabilities.includes('coding')) {
        return name;
      }
    }
    
    return null;
  }
  
  /**
   * Task implementation methods
   */
  private async formatFiles(files: string[], model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    try {
      // First try native formatters
      if (files.length > 0) {
        const { stdout, stderr, exitCode } = Bun.spawn(['prettier', '--write', ...files]);
        
        if (exitCode === 0) {
          return {
            type: 'format',
            status: 'success',
            files,
            model: 'prettier',
            tokens: 0,
            cost: 0,
            duration: Date.now() - startTime,
            output: 'Files formatted successfully with Prettier'
          };
        }
      }
      
      // Fallback to AI if native formatter fails
      if (this.isLocalModel(model)) {
        return await this.formatWithLocalModel(files, model);
      } else {
        return await this.formatWithCloudModel(files, model);
      }
      
    } catch (error) {
      return {
        type: 'format',
        status: 'failed',
        files,
        model,
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  
  private async formatWithLocalModel(files: string[], model: string): Promise<TaskResult> {
    // Use Ollama API for formatting
    const prompt = `Format these TypeScript/JavaScript files according to best practices:\n\n${files.map(f => `File: ${f}`).join('\n')}`;
    
    const response = await this.callLocalModel(model, prompt);
    
    return {
      type: 'format',
      status: 'success',
      files,
      model,
      tokens: response.tokens,
      cost: 0, // Local models are free
      duration: response.duration,
      output: response.content
    };
  }
  
  private async formatWithCloudModel(files: string[], model: string): Promise<TaskResult> {
    // Use model router for cloud formatting
    const prompt = `Format these files according to best practices:\n\n${files.join('\n')}`;
    
    const response = await this.modelRouter.route({
      prompt,
      preferredModel: model,
      fallbackModels: ['deepseek-chat'],
      maxTokens: 10000,
      complexity: 'simple',
      urgency: 'low'
    });
    
    return {
      type: 'format',
      status: 'success',
      files,
      model: response.model,
      tokens: response.tokensUsed,
      cost: response.cost,
      duration: response.duration,
      output: response.content
    };
  }
  
  private async lintFiles(files: string[], model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    try {
      // Try ESLint first
      const { stdout, stderr, exitCode } = Bun.spawn(['eslint', '--fix', ...files]);
      const output = await new Response(stdout).text();
      
      return {
        type: 'lint',
        status: exitCode === 0 ? 'success' : 'partial',
        files,
        model: 'eslint',
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        output: output || 'Linting completed'
      };
      
    } catch (error) {
      // Fallback to AI linting if ESLint fails
      return await this.lintWithAI(files, model, startTime);
    }
  }
  
  private async lintWithAI(files: string[], model: string, startTime: number): Promise<TaskResult> {
    const prompt = `Review and suggest fixes for these files:\n\n${files.join('\n')}`;
    
    if (this.isLocalModel(model)) {
      const response = await this.callLocalModel(model, prompt);
      return {
        type: 'lint',
        status: 'success',
        files,
        model,
        tokens: response.tokens,
        cost: 0,
        duration: Date.now() - startTime,
        output: response.content
      };
    } else {
      const response = await this.modelRouter.route({
        prompt,
        preferredModel: model,
        fallbackModels: ['deepseek-chat'],
        maxTokens: 20000,
        complexity: 'simple'
      });
      
      return {
        type: 'lint',
        status: 'success',
        files,
        model: response.model,
        tokens: response.tokensUsed,
        cost: response.cost,
        duration: Date.now() - startTime,
        output: response.content
      };
    }
  }
  
  private async runTests(scope: string, model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    const testCommand = scope === 'affected' 
      ? ['bun', 'test', '--changed']
      : ['bun', 'test'];
    
    try {
      const process = Bun.spawn(testCommand);
      const { stdout, exitCode } = process;
      const output = await new Response(stdout).text();
      
      if (exitCode === 0) {
        return {
          type: 'test',
          status: 'success',
          files: [],
          model: 'bun',
          tokens: 0,
          cost: 0,
          duration: Date.now() - startTime,
          output: 'All tests passed'
        };
      } else {
        // Use AI to analyze test failures
        return await this.analyzeTestFailures(output, model, startTime);
      }
      
    } catch (error) {
      return {
        type: 'test',
        status: 'failed',
        files: [],
        model,
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  
  private async analyzeTestFailures(output: string, model: string, startTime: number): Promise<TaskResult> {
    const prompt = `Analyze these test failures and suggest fixes:\n\n${output}`;
    
    const response = await this.modelRouter.route({
      prompt,
      preferredModel: model,
      fallbackModels: ['deepseek-chat'],
      maxTokens: 15000,
      complexity: 'moderate'
    });
    
    return {
      type: 'test',
      status: 'failed',
      files: [],
      model: response.model,
      tokens: response.tokensUsed,
      cost: response.cost,
      duration: Date.now() - startTime,
      output: response.content,
      analysis: response.content
    };
  }
  
  private async commitChanges(message: string, model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    try {
      // Check git status
      const statusProcess = Bun.spawn(['git', 'status', '--porcelain']);
      const { stdout: statusOut } = statusProcess;
      const changes = await new Response(statusOut).text();
      
      if (!changes.trim()) {
        return {
          type: 'commit',
          status: 'success',
          files: [],
          model: 'git',
          tokens: 0,
          cost: 0,
          duration: Date.now() - startTime,
          output: 'No changes to commit'
        };
      }
      
      // Stage all changes
      Bun.spawn(['git', 'add', '.']).exitCode;
      
      // Create commit
      const commitProcess = Bun.spawn(['git', 'commit', '-m', message]);
      const { exitCode } = commitProcess;
      
      return {
        type: 'commit',
        status: exitCode === 0 ? 'success' : 'failed',
        files: changes.split('\n').map(line => line.slice(3)).filter(Boolean),
        model: 'git',
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        output: exitCode === 0 ? `Committed with message: ${message}` : 'Commit failed'
      };
      
    } catch (error) {
      return {
        type: 'commit',
        status: 'failed',
        files: [],
        model: 'git',
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  
  private async generateDocs(files: string[], model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    const prompt = `Generate documentation for these files:\n\n${files.join('\n')}`;
    
    const response = await this.modelRouter.route({
      prompt,
      preferredModel: model,
      fallbackModels: ['llama3.3:70b', 'deepseek-chat'],
      maxTokens: 30000,
      complexity: 'moderate'
    });
    
    return {
      type: 'docs',
      status: 'success',
      files,
      model: response.model,
      tokens: response.tokensUsed,
      cost: response.cost,
      duration: Date.now() - startTime,
      output: response.content
    };
  }
  
  private async cleanupFiles(files: string[], model: string): Promise<TaskResult> {
    const startTime = Date.now();
    
    try {
      // Simple file cleanup - remove empty files, temp files, etc.
      let cleaned = 0;
      
      for (const file of files) {
        if (await this.shouldCleanupFile(file)) {
          await Bun.write(file, ''); // Or delete if appropriate
          cleaned++;
        }
      }
      
      return {
        type: 'cleanup',
        status: 'success',
        files,
        model: 'filesystem',
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        output: `Cleaned up ${cleaned} files`
      };
      
    } catch (error) {
      return {
        type: 'cleanup',
        status: 'failed',
        files,
        model: 'filesystem',
        tokens: 0,
        cost: 0,
        duration: Date.now() - startTime,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  
  /**
   * Helper methods
   */
  private async shouldCleanupFile(file: string): Promise<boolean> {
    try {
      const stat = await Bun.file(file).size;
      return stat === 0; // Empty files
    } catch {
      return false;
    }
  }
  
  private isLocalModel(model: string): boolean {
    return this.localModels.has(model);
  }
  
  private async callLocalModel(model: string, prompt: string): Promise<{ content: string; tokens: number; duration: number }> {
    const startTime = Date.now();
    const ollamaUrl = PHASE_4_ROUTER_CONFIG.providers.ollama.baseUrl;
    
    const response = await fetch(`${ollamaUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        prompt,
        stream: false
      })
    });
    
    if (!response.ok) {
      throw new Error(`Ollama API error: ${response.statusText}`);
    }
    
    const data = await response.json();
    
    return {
      content: data.response,
      tokens: Math.ceil(data.response.length / 4), // Rough estimate
      duration: Date.now() - startTime
    };
  }
  
  private isCriticalTask(task: GruntTask): boolean {
    return ['test', 'commit'].includes(task.type);
  }
  
  private saveGruntTask(taskId: string, task: GruntTask, status: string): void {
    this.db.run(
      `INSERT INTO grunt_tasks (id, session_id, type, files, scope, message, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        taskId,
        'default',
        task.type,
        task.files ? JSON.stringify(task.files) : null,
        task.scope || null,
        task.message || null,
        status,
        Date.now()
      ]
    );
  }
  
  private updateGruntTask(taskId: string, result: TaskResult, status: string): void {
    this.db.run(
      `UPDATE grunt_tasks 
       SET status = ?, model_used = ?, tokens_used = ?, cost = ?, duration_ms = ?, output = ?, errors = ?, completed_at = ?
       WHERE id = ?`,
      [
        status,
        result.model,
        result.tokens || 0,
        result.cost || 0,
        result.duration || 0,
        result.output || null,
        result.error ? JSON.stringify([result.error]) : null,
        Date.now(),
        taskId
      ]
    );
  }
  
  private async updateGruntMetrics(taskType: string, model: string, success: boolean, duration: number): Promise<void> {
    // Update or insert metrics
    const existing = this.db.query(
      'SELECT * FROM grunt_metrics WHERE task_type = ? AND model = ?'
    ).get(taskType, model) as any;
    
    if (existing) {
      // Update existing metrics
      const newSuccessRate = success 
        ? (existing.success_rate * existing.total_executions + 1) / (existing.total_executions + 1)
        : (existing.success_rate * existing.total_executions) / (existing.total_executions + 1);
      
      const newAvgDuration = (existing.avg_duration * existing.total_executions + duration) / (existing.total_executions + 1);
      
      this.db.run(
        `UPDATE grunt_metrics 
         SET success_rate = ?, avg_duration = ?, total_executions = ?, last_updated = ?
         WHERE task_type = ? AND model = ?`,
        [
          newSuccessRate,
          newAvgDuration,
          existing.total_executions + 1,
          Date.now(),
          taskType,
          model
        ]
      );
    } else {
      // Insert new metrics
      this.db.run(
        `INSERT INTO grunt_metrics (task_type, model, success_rate, avg_duration, total_executions, last_updated)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          taskType,
          model,
          success ? 1.0 : 0.0,
          duration,
          1,
          Date.now()
        ]
      );
    }
  }
  
  /**
   * Public API methods
   */
  async getGruntMetrics(): Promise<any[]> {
    return this.db.query('SELECT * FROM grunt_metrics ORDER BY last_updated DESC').all();
  }
  
  async getRecentGruntTasks(limit: number = 50): Promise<any[]> {
    return this.db.query('SELECT * FROM grunt_tasks ORDER BY created_at DESC LIMIT ?').all(limit);
  }
  
  getAvailableLocalModels(): string[] {
    return Array.from(this.localModels.keys()).filter(name => 
      this.localModels.get(name)?.available
    );
  }
  
  getTaskQueue(): GruntTask[] {
    return [...this.taskQueue];
  }
  
  isExecuting(): boolean {
    return this.executing;
  }
}