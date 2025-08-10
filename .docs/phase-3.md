# Phase 3: Multi-Model AI Orchestration via Claude Code Router

## Executive Summary

Phase 3 implements a sophisticated multi-model AI orchestration system that integrates claude-code-router for intelligent model selection, creates specialized agents (planner, editor, reviewer), and establishes a comprehensive workflow system with Plan Mode, Edit Mode, and optional Review Mode. This phase transforms the context intelligence from Phase 2 into actionable AI capabilities through agent specialization, prompt management, and model routing strategies.

## Core Objectives

1. **Agent Specialization System**: Planner → Editor → Reviewer workflow with distinct capabilities
2. **Claude Code CLI Integration**: Full integration with slash commands, hooks, and sub-agents
3. **Model Router Implementation**: Intelligent routing based on task complexity and cost
4. **Prompt Template Management**: Reusable, versioned prompts with variable interpolation
5. **Context Assembly Pipeline**: Agent-specific context optimization
6. **Workflow Mode System**: Plan Mode → Edit Mode → Review Mode orchestration
7. **MCP Server Architecture**: Model Context Protocol servers for external tool integration
8. **Real-time Progress Tracking**: WebSocket-based status updates and progress monitoring

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interface Layer                      │
│  Claude Code CLI ←→ WebSocket ←→ Browser/Terminal Client    │
└────────────────────┬─────────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────────┐
│                  Orchestration Layer                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            Workflow Mode Controller                   │   │
│  │  • Plan Mode → Edit Mode → Review Mode              │   │
│  │  • State management and transitions                 │   │
│  │  • Progress tracking and cancellation               │   │
│  └────────────────────┬─────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                    Agent System Layer                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │     Planner Agent    │    Editor Agent    │          │   │
│  │  • Task decomposition│  • Code generation │          │   │
│  │  • Strategy planning │  • File operations │          │   │
│  │  • Success criteria  │  • Parallel edits  │          │   │
│  │                      │                    │          │   │
│  │     Reviewer Agent   │    Grunt Agent*    │          │   │
│  │  • Change validation │  • Git operations  │          │   │
│  │  • Test verification │  • Documentation   │          │   │
│  │  • Quality checks    │  • Linting/format  │          │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                  Model Router Layer                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           claude-code-router Integration             │   │
│  │  • Model selection (Claude, GPT-4, Gemini, etc)     │   │
│  │  • Cost optimization and token management           │   │
│  │  • Parallel request handling                        │   │
│  │  • Fallback and retry logic                         │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                 Context Assembly Layer                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Prompt Template Management                 │   │
│  │  • System prompts per agent                         │   │
│  │  • Variable interpolation                           │   │
│  │  • Version control                                  │   │
│  │                                                      │   │
│  │           Context Composition Pipeline               │   │
│  │  • Agent-specific formatting                        │   │
│  │  • File maps vs code maps selection                 │   │
│  │  • Token optimization per model                     │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│              Infrastructure Layer (Phase 1-2)                │
│  • Context Intelligence (Merkle trees, parsing)              │
│  • PTY Sidecar (terminal integration)                        │
│  • Control Plane (session management)                        │
└───────────────────────────────────────────────────────────────┘
```

## Implementation Components

### Component 1: Agent System

#### 1.1 Agent Base Class

```typescript
// control-plane/src/agents/base-agent.ts

interface AgentCapabilities {
  maxTokens: number;
  preferredModel: string;
  fallbackModels: string[];
  temperature: number;
  systemPromptTemplate: string;
  tools: string[];
}

interface AgentContext {
  task: string;
  workspace: string;
  sessionId: string;
  previousResults?: any;
  constraints?: string[];
  successCriteria?: string[];
}

interface AgentResult {
  success: boolean;
  output: any;
  tokensUsed: number;
  modelUsed: string;
  duration: number;
  errors?: string[];
  nextSteps?: string[];
}

abstract class BaseAgent {
  protected capabilities: AgentCapabilities;
  protected promptManager: PromptManager;
  protected modelRouter: ModelRouter;
  protected contextGenerator: ContextGenerator;
  
  constructor(
    protected name: string,
    protected workspace: string
  ) {
    this.capabilities = this.defineCapabilities();
    this.promptManager = new PromptManager();
    this.modelRouter = new ModelRouter();
    this.contextGenerator = new ContextGenerator(workspace);
  }
  
  abstract defineCapabilities(): AgentCapabilities;
  abstract validateInput(context: AgentContext): boolean;
  abstract formatContext(context: AgentContext): any;
  abstract processResult(rawResult: any): AgentResult;
  
  async execute(context: AgentContext): Promise<AgentResult> {
    // Validate input
    if (!this.validateInput(context)) {
      throw new Error(`Invalid input for ${this.name} agent`);
    }
    
    // Generate context based on agent needs
    const formattedContext = await this.formatContext(context);
    
    // Build prompt from template
    const prompt = await this.promptManager.buildPrompt(
      this.capabilities.systemPromptTemplate,
      formattedContext
    );
    
    // Route to appropriate model
    const result = await this.modelRouter.route({
      prompt,
      preferredModel: this.capabilities.preferredModel,
      fallbackModels: this.capabilities.fallbackModels,
      maxTokens: this.capabilities.maxTokens,
      temperature: this.capabilities.temperature
    });
    
    // Process and return result
    return this.processResult(result);
  }
}
```

#### 1.2 Planner Agent

```typescript
// control-plane/src/agents/planner-agent.ts

interface PlanStep {
  id: string;
  description: string;
  fileOperations: FileOperation[];
  dependencies: string[];
  estimatedTokens: number;
  assignedAgent: 'editor' | 'reviewer' | 'grunt';
}

interface FileOperation {
  type: 'create' | 'edit' | 'delete' | 'move';
  path: string;
  description: string;
  priority: number;
}

interface Plan {
  steps: PlanStep[];
  successCriteria: string[];
  estimatedTotalTokens: number;
  estimatedDuration: number;
  risks: string[];
}

class PlannerAgent extends BaseAgent {
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 8000,
      preferredModel: 'claude-3-opus',
      fallbackModels: ['gpt-4-turbo', 'claude-3-sonnet'],
      temperature: 0.3,
      systemPromptTemplate: 'planner-system-v1',
      tools: ['file_tree', 'symbol_search', 'dependency_graph']
    };
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    // Get full repository context for planning
    const repoContext = await this.contextGenerator.generateContext({
      maxTokens: 6000,
      includeFileMap: true,
      includeCodeMap: true,
      includeContent: false // Don't need full content for planning
    });
    
    // Get working set for recent context
    const workingSet = await this.contextGenerator.getWorkingSet();
    
    return {
      task: context.task,
      repoStructure: repoContext.fileMap,
      codeSymbols: repoContext.codeMap,
      recentFiles: workingSet.recentlyModified,
      gitStatus: workingSet.gitChanges,
      constraints: context.constraints,
      successCriteria: context.successCriteria
    };
  }
  
  processResult(rawResult: any): AgentResult {
    // Parse the plan from model output
    const plan = this.parsePlan(rawResult.content);
    
    // Validate plan structure
    this.validatePlan(plan);
    
    // Optimize step ordering
    const optimizedPlan = this.optimizePlanOrder(plan);
    
    return {
      success: true,
      output: optimizedPlan,
      tokensUsed: rawResult.tokensUsed,
      modelUsed: rawResult.model,
      duration: rawResult.duration,
      nextSteps: optimizedPlan.steps.map(s => s.description)
    };
  }
  
  private parsePlan(content: string): Plan {
    // Extract structured plan from model response
    // Uses markers like ### STEP 1, ### SUCCESS CRITERIA, etc.
    const steps: PlanStep[] = [];
    const successCriteria: string[] = [];
    
    // Parse step sections
    const stepMatches = content.matchAll(/### STEP (\d+): (.*?)\n([\s\S]*?)(?=### STEP|\### SUCCESS|$)/g);
    for (const match of stepMatches) {
      const [_, id, description, details] = match;
      steps.push(this.parseStep(id, description, details));
    }
    
    // Parse success criteria
    const criteriaMatch = content.match(/### SUCCESS CRITERIA\n([\s\S]*?)(?=###|$)/);
    if (criteriaMatch) {
      successCriteria.push(...this.parseCriteria(criteriaMatch[1]));
    }
    
    return {
      steps,
      successCriteria,
      estimatedTotalTokens: steps.reduce((sum, s) => sum + s.estimatedTokens, 0),
      estimatedDuration: steps.length * 2000, // 2 seconds per step estimate
      risks: this.identifyRisks(steps)
    };
  }
  
  private optimizePlanOrder(plan: Plan): Plan {
    // Topological sort based on dependencies
    const sorted = this.topologicalSort(plan.steps);
    
    // Group independent steps for parallel execution
    const parallelGroups = this.groupParallelSteps(sorted);
    
    return {
      ...plan,
      steps: sorted,
      parallelGroups
    };
  }
}
```

#### 1.3 Editor Agent

```typescript
// control-plane/src/agents/editor-agent.ts

interface EditTask {
  stepId: string;
  fileOperations: FileOperation[];
  context: EditContext;
}

interface EditContext {
  targetFiles: string[];
  codeMap: CodeMap;
  relevantSymbols: Symbol[];
  examples?: CodeExample[];
}

interface EditResult {
  filesModified: string[];
  filesCreated: string[];
  filesDeleted: string[];
  diffs: Diff[];
  errors: string[];
}

class EditorAgent extends BaseAgent {
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 4000,
      preferredModel: 'claude-3-sonnet',
      fallbackModels: ['gpt-4', 'claude-3-haiku'],
      temperature: 0.1,
      systemPromptTemplate: 'editor-system-v1',
      tools: ['file_read', 'file_write', 'symbol_lookup']
    };
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    const editTask = context.task as EditTask;
    
    // Get only relevant files for this edit
    const targetContext = await this.contextGenerator.generateContext({
      files: editTask.context.targetFiles,
      maxTokens: 3000,
      includeFileMap: false,
      includeCodeMap: true,
      includeContent: true // Need full content for editing
    });
    
    return {
      step: editTask.stepId,
      operations: editTask.fileOperations,
      files: targetContext.selectedFiles,
      symbols: editTask.context.relevantSymbols,
      codeMap: targetContext.codeMap,
      examples: editTask.context.examples
    };
  }
  
  async execute(context: AgentContext): Promise<AgentResult> {
    const editTask = context.task as EditTask;
    const results: EditResult[] = [];
    
    // Group operations by file for efficiency
    const operationsByFile = this.groupOperationsByFile(editTask.fileOperations);
    
    // Execute edits in parallel when possible
    const parallelGroups = this.identifyParallelEdits(operationsByFile);
    
    for (const group of parallelGroups) {
      const groupResults = await Promise.all(
        group.map(fileOps => this.executeFileOperations(fileOps))
      );
      results.push(...groupResults);
    }
    
    // Merge results
    const merged = this.mergeEditResults(results);
    
    return {
      success: merged.errors.length === 0,
      output: merged,
      tokensUsed: results.reduce((sum, r) => sum + r.tokensUsed, 0),
      modelUsed: this.capabilities.preferredModel,
      duration: Date.now() - startTime,
      errors: merged.errors
    };
  }
  
  private async executeFileOperations(
    operations: FileOperation[]
  ): Promise<EditResult> {
    // Use multi-model approach for complex edits
    if (operations.length > 3) {
      return this.executeWithModelRouter(operations);
    }
    
    // Simple edits can use faster model
    return this.executeWithFastModel(operations);
  }
  
  private identifyParallelEdits(
    operationsByFile: Map<string, FileOperation[]>
  ): FileOperation[][][] {
    // Analyze dependencies between files
    const dependencies = this.analyzeDependencies(operationsByFile);
    
    // Group independent operations for parallel execution
    return this.createParallelGroups(operationsByFile, dependencies);
  }
}
```

#### 1.4 Reviewer Agent

```typescript
// control-plane/src/agents/reviewer-agent.ts

interface ReviewContext {
  plan: Plan;
  edits: EditResult[];
  originalContext: any;
  successCriteria: string[];
}

interface ReviewResult {
  passed: boolean;
  score: number;
  issues: ReviewIssue[];
  suggestions: string[];
  testResults?: TestResult[];
}

interface ReviewIssue {
  severity: 'critical' | 'warning' | 'info';
  file: string;
  line?: number;
  message: string;
  suggestedFix?: string;
}

class ReviewerAgent extends BaseAgent {
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 3000,
      preferredModel: 'gemini-pro',
      fallbackModels: ['claude-3-sonnet', 'gpt-4'],
      temperature: 0.2,
      systemPromptTemplate: 'reviewer-system-v1',
      tools: ['diff_analyzer', 'test_runner', 'lint_checker']
    };
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    const reviewContext = context as ReviewContext;
    
    // Get diffs and surrounding context
    const diffsWithContext = await this.getDiffsWithContext(reviewContext.edits);
    
    // Run automated checks
    const automatedChecks = await this.runAutomatedChecks(reviewContext.edits);
    
    return {
      plan: reviewContext.plan,
      changes: diffsWithContext,
      successCriteria: reviewContext.successCriteria,
      automatedChecks,
      originalRequest: reviewContext.originalContext.task
    };
  }
  
  processResult(rawResult: any): AgentResult {
    const review = this.parseReview(rawResult.content);
    
    // Enhance with automated test results
    review.testResults = await this.runTests(review);
    
    // Calculate overall score
    review.score = this.calculateScore(review);
    
    // Determine if changes pass review
    review.passed = review.score >= 0.8 && 
                   review.issues.filter(i => i.severity === 'critical').length === 0;
    
    return {
      success: true,
      output: review,
      tokensUsed: rawResult.tokensUsed,
      modelUsed: rawResult.model,
      duration: rawResult.duration,
      nextSteps: review.passed ? ['deploy'] : ['fix_issues']
    };
  }
  
  private async getDiffsWithContext(edits: EditResult[]): Promise<DiffWithContext[]> {
    const diffs: DiffWithContext[] = [];
    
    for (const edit of edits) {
      for (const diff of edit.diffs) {
        const context = await this.getFileContext(diff.file, diff.lineStart, diff.lineEnd);
        diffs.push({
          ...diff,
          context,
          relatedSymbols: await this.getRelatedSymbols(diff.file)
        });
      }
    }
    
    return diffs;
  }
  
  private calculateScore(review: ReviewResult): number {
    let score = 1.0;
    
    // Deduct for issues
    for (const issue of review.issues) {
      switch (issue.severity) {
        case 'critical': score -= 0.3; break;
        case 'warning': score -= 0.1; break;
        case 'info': score -= 0.02; break;
      }
    }
    
    // Deduct for failed tests
    if (review.testResults) {
      const passRate = review.testResults.filter(t => t.passed).length / review.testResults.length;
      score *= passRate;
    }
    
    return Math.max(0, Math.min(1, score));
  }
}
```

### Component 2: Model Router

#### 2.1 Claude Code Router Integration

```typescript
// control-plane/src/routing/model-router.ts

interface RouteRequest {
  prompt: string;
  preferredModel: string;
  fallbackModels: string[];
  maxTokens: number;
  temperature: number;
  urgency?: 'low' | 'normal' | 'high';
  complexity?: 'simple' | 'moderate' | 'complex';
}

interface ModelConfig {
  name: string;
  provider: 'anthropic' | 'openai' | 'google' | 'local';
  endpoint: string;
  apiKey: string;
  maxTokens: number;
  costPerToken: number;
  latency: number; // average ms
  capabilities: string[];
}

class ModelRouter {
  private models: Map<string, ModelConfig>;
  private loadBalancer: LoadBalancer;
  private costOptimizer: CostOptimizer;
  private rateLimiter: RateLimiter;
  
  constructor() {
    this.models = this.loadModelConfigs();
    this.loadBalancer = new LoadBalancer(this.models);
    this.costOptimizer = new CostOptimizer();
    this.rateLimiter = new RateLimiter();
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
      // Fallback logic
      for (const fallbackModel of request.fallbackModels) {
        try {
          console.warn(`Falling back to ${fallbackModel} due to error:`, error);
          return await this.callModel(fallbackModel, request);
        } catch (fallbackError) {
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
    
    // Default to preferred model if available
    if (this.isModelAvailable(request.preferredModel)) {
      return request.preferredModel;
    }
    
    // Otherwise optimize for cost/performance balance
    return this.costOptimizer.selectOptimalModel(
      this.models,
      request.maxTokens,
      request.complexity
    );
  }
  
  async callModel(modelName: string, request: RouteRequest): Promise<ModelResponse> {
    const model = this.models.get(modelName);
    if (!model) throw new Error(`Model ${modelName} not configured`);
    
    const startTime = Date.now();
    
    // Build provider-specific request
    const providerRequest = this.buildProviderRequest(model, request);
    
    // Make API call
    const response = await this.makeApiCall(model, providerRequest);
    
    // Track metrics
    const duration = Date.now() - startTime;
    const tokensUsed = this.countTokens(response);
    const cost = tokensUsed * model.costPerToken;
    
    this.trackMetrics({
      model: modelName,
      duration,
      tokensUsed,
      cost,
      success: true
    });
    
    return {
      content: response.content,
      model: modelName,
      tokensUsed,
      duration,
      cost
    };
  }
  
  // Parallel execution for independent tasks
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
}
```

#### 2.2 Cost and Performance Optimization

```typescript
// control-plane/src/routing/optimization.ts

class CostOptimizer {
  private costHistory: Map<string, number[]>;
  private performanceHistory: Map<string, number[]>;
  
  selectOptimalModel(
    models: Map<string, ModelConfig>,
    tokenBudget: number,
    complexity: string
  ): string {
    const candidates = Array.from(models.values())
      .filter(m => m.maxTokens >= tokenBudget)
      .filter(m => this.supportsComplexity(m, complexity));
    
    // Calculate score for each model
    const scored = candidates.map(model => ({
      model,
      score: this.calculateScore(model, tokenBudget, complexity)
    }));
    
    // Sort by score and return best
    scored.sort((a, b) => b.score - a.score);
    return scored[0].model.name;
  }
  
  private calculateScore(
    model: ModelConfig,
    tokenBudget: number,
    complexity: string
  ): number {
    const costScore = 1 / (model.costPerToken * tokenBudget);
    const performanceScore = 1 / model.latency;
    const capabilityScore = this.getCapabilityScore(model, complexity);
    
    // Weighted combination
    return (costScore * 0.4) + (performanceScore * 0.3) + (capabilityScore * 0.3);
  }
  
  trackCost(model: string, cost: number) {
    if (!this.costHistory.has(model)) {
      this.costHistory.set(model, []);
    }
    this.costHistory.get(model)!.push(cost);
    
    // Keep only last 100 entries
    const history = this.costHistory.get(model)!;
    if (history.length > 100) {
      history.shift();
    }
  }
  
  getCostReport(): CostReport {
    const report: CostReport = {
      totalCost: 0,
      byModel: {},
      byTimeframe: {},
      projectedMonthlyCost: 0
    };
    
    for (const [model, costs] of this.costHistory) {
      const total = costs.reduce((sum, c) => sum + c, 0);
      report.totalCost += total;
      report.byModel[model] = total;
    }
    
    // Calculate projection
    const dailyAverage = report.totalCost / 30;
    report.projectedMonthlyCost = dailyAverage * 30;
    
    return report;
  }
}

class LoadBalancer {
  private modelLoad: Map<string, number>;
  private modelQueues: Map<string, Promise<any>[]>;
  
  selectFastestAvailable(): string {
    let fastest: string | null = null;
    let minLoad = Infinity;
    
    for (const [model, load] of this.modelLoad) {
      if (load < minLoad) {
        minLoad = load;
        fastest = model;
      }
    }
    
    return fastest || 'claude-3-sonnet';
  }
  
  async executeWithBackpressure<T>(
    model: string,
    task: () => Promise<T>
  ): Promise<T> {
    // Track load
    this.incrementLoad(model);
    
    try {
      // Check if we should wait
      const queue = this.modelQueues.get(model) || [];
      if (queue.length > 10) {
        // Wait for some tasks to complete
        await Promise.race(queue);
      }
      
      // Execute task
      const promise = task();
      queue.push(promise);
      
      const result = await promise;
      
      // Remove from queue
      const index = queue.indexOf(promise);
      if (index > -1) queue.splice(index, 1);
      
      return result;
    } finally {
      this.decrementLoad(model);
    }
  }
}
```

### Component 3: Prompt Management

#### 3.1 Template System

```typescript
// control-plane/src/prompts/prompt-manager.ts

interface PromptTemplate {
  id: string;
  name: string;
  version: string;
  agent: 'planner' | 'editor' | 'reviewer' | 'grunt';
  template: string;
  variables: VariableDefinition[];
  examples?: Example[];
  metadata: {
    author: string;
    created: Date;
    modified: Date;
    performance: PerformanceMetrics;
  };
}

interface VariableDefinition {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'object' | 'array';
  required: boolean;
  default?: any;
  description: string;
  validator?: (value: any) => boolean;
}

class PromptManager {
  private templates: Map<string, PromptTemplate>;
  private activeTemplates: Map<string, string>; // agent -> template id
  private db: Database;
  
  constructor() {
    this.db = new Database('prompts.db');
    this.loadTemplates();
    this.loadActiveTemplates();
  }
  
  async buildPrompt(templateId: string, context: any): Promise<string> {
    const template = this.templates.get(templateId);
    if (!template) throw new Error(`Template ${templateId} not found`);
    
    // Validate all required variables are present
    this.validateContext(template, context);
    
    // Interpolate variables
    let prompt = template.template;
    
    for (const variable of template.variables) {
      const value = context[variable.name] ?? variable.default;
      const formatted = this.formatValue(value, variable.type);
      
      // Replace all occurrences of {{variable}}
      const regex = new RegExp(`{{${variable.name}}}`, 'g');
      prompt = prompt.replace(regex, formatted);
    }
    
    // Add examples if provided
    if (template.examples && template.examples.length > 0) {
      prompt += '\n\n## Examples:\n';
      for (const example of template.examples) {
        prompt += this.formatExample(example);
      }
    }
    
    return prompt;
  }
  
  private validateContext(template: PromptTemplate, context: any) {
    for (const variable of template.variables) {
      if (variable.required && !(variable.name in context)) {
        throw new Error(`Required variable ${variable.name} not provided`);
      }
      
      if (variable.validator && variable.name in context) {
        if (!variable.validator(context[variable.name])) {
          throw new Error(`Variable ${variable.name} failed validation`);
        }
      }
    }
  }
  
  private formatValue(value: any, type: string): string {
    switch (type) {
      case 'string':
        return String(value);
      case 'number':
        return String(value);
      case 'boolean':
        return value ? 'true' : 'false';
      case 'object':
      case 'array':
        return JSON.stringify(value, null, 2);
      default:
        return String(value);
    }
  }
  
  async createTemplate(template: Omit<PromptTemplate, 'id'>): Promise<string> {
    const id = crypto.randomUUID();
    const fullTemplate: PromptTemplate = {
      id,
      ...template,
      metadata: {
        ...template.metadata,
        created: new Date(),
        modified: new Date()
      }
    };
    
    // Store in database
    this.db.run(
      `INSERT INTO templates (id, name, version, agent, template, variables, metadata)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        fullTemplate.name,
        fullTemplate.version,
        fullTemplate.agent,
        fullTemplate.template,
        JSON.stringify(fullTemplate.variables),
        JSON.stringify(fullTemplate.metadata)
      ]
    );
    
    // Cache in memory
    this.templates.set(id, fullTemplate);
    
    return id;
  }
  
  async updateTemplate(id: string, updates: Partial<PromptTemplate>) {
    const existing = this.templates.get(id);
    if (!existing) throw new Error(`Template ${id} not found`);
    
    const updated = {
      ...existing,
      ...updates,
      metadata: {
        ...existing.metadata,
        modified: new Date()
      }
    };
    
    // Update database
    this.db.run(
      `UPDATE templates 
       SET name = ?, version = ?, template = ?, variables = ?, metadata = ?
       WHERE id = ?`,
      [
        updated.name,
        updated.version,
        updated.template,
        JSON.stringify(updated.variables),
        JSON.stringify(updated.metadata),
        id
      ]
    );
    
    // Update cache
    this.templates.set(id, updated);
  }
  
  // Version management
  async forkTemplate(id: string, newVersion: string): Promise<string> {
    const existing = this.templates.get(id);
    if (!existing) throw new Error(`Template ${id} not found`);
    
    return this.createTemplate({
      ...existing,
      version: newVersion,
      metadata: {
        ...existing.metadata,
        author: 'forked',
        performance: {} // Reset performance metrics
      }
    });
  }
  
  // A/B testing support
  async compareTemplates(
    templateA: string,
    templateB: string,
    testContext: any,
    iterations: number = 10
  ): Promise<ComparisonResult> {
    const resultsA: any[] = [];
    const resultsB: any[] = [];
    
    for (let i = 0; i < iterations; i++) {
      // Test template A
      const promptA = await this.buildPrompt(templateA, testContext);
      const resultA = await this.testPrompt(promptA);
      resultsA.push(resultA);
      
      // Test template B
      const promptB = await this.buildPrompt(templateB, testContext);
      const resultB = await this.testPrompt(promptB);
      resultsB.push(resultB);
    }
    
    return this.analyzeResults(resultsA, resultsB);
  }
}
```

#### 3.2 Default Prompt Templates

```typescript
// control-plane/src/prompts/templates/planner-system-v1.ts

export const PLANNER_SYSTEM_V1: PromptTemplate = {
  id: 'planner-system-v1',
  name: 'Planner System Prompt',
  version: '1.0.0',
  agent: 'planner',
  template: `You are a senior software architect tasked with planning the implementation of a development task.

## Your Role
- Analyze the codebase structure and existing patterns
- Break down the task into clear, actionable steps
- Identify dependencies and potential risks
- Define clear success criteria

## Context
Task: {{task}}

Repository Structure:
{{repoStructure}}

Code Symbols:
{{codeSymbols}}

Recent Activity:
- Recently modified files: {{recentFiles}}
- Git changes: {{gitStatus}}

## Constraints
{{constraints}}

## Instructions
1. Analyze the task and codebase to understand what needs to be done
2. Create a step-by-step plan with specific file operations
3. For each step, specify:
   - Clear description of what needs to be done
   - Which files need to be created/modified/deleted
   - Any dependencies on other steps
   - Which agent should handle it (editor for code changes, reviewer for validation)
4. Define success criteria that can be objectively verified
5. Identify potential risks or complications

## Output Format
Structure your response as follows:

### STEP 1: [Brief description]
**Files to modify:**
- path/to/file1.ts: [what changes]
- path/to/file2.ts: [what changes]

**Files to create:**
- path/to/newfile.ts: [purpose]

**Dependencies:** None | Step X
**Assigned to:** editor | reviewer
**Estimated tokens:** [number]

### STEP 2: [Brief description]
...

### SUCCESS CRITERIA
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### RISKS
- Risk 1: [description and mitigation]
- Risk 2: [description and mitigation]

Be specific and actionable. Each step should be independently verifiable.`,
  variables: [
    {
      name: 'task',
      type: 'string',
      required: true,
      description: 'The user task to plan'
    },
    {
      name: 'repoStructure',
      type: 'object',
      required: true,
      description: 'File map of the repository'
    },
    {
      name: 'codeSymbols',
      type: 'object',
      required: true,
      description: 'Code map with symbols'
    },
    {
      name: 'recentFiles',
      type: 'array',
      required: false,
      default: [],
      description: 'Recently modified files'
    },
    {
      name: 'gitStatus',
      type: 'array',
      required: false,
      default: [],
      description: 'Current git changes'
    },
    {
      name: 'constraints',
      type: 'array',
      required: false,
      default: [],
      description: 'Task constraints'
    }
  ],
  metadata: {
    author: 'system',
    created: new Date(),
    modified: new Date(),
    performance: {
      avgTokensUsed: 3500,
      avgDuration: 2500,
      successRate: 0.92
    }
  }
};
```

### Component 4: Workflow Mode Controller

#### 4.1 Mode Definitions

```typescript
// control-plane/src/workflow/mode-controller.ts

type WorkflowMode = 'plan' | 'edit' | 'review' | 'complete';

interface WorkflowState {
  id: string;
  mode: WorkflowMode;
  sessionId: string;
  task: string;
  plan?: Plan;
  edits?: EditResult[];
  review?: ReviewResult;
  startTime: number;
  transitions: ModeTransition[];
  status: 'active' | 'paused' | 'completed' | 'failed';
  progress: number; // 0-100
}

interface ModeTransition {
  from: WorkflowMode;
  to: WorkflowMode;
  timestamp: number;
  reason: string;
  data?: any;
}

class WorkflowModeController {
  private workflows: Map<string, WorkflowState>;
  private agents: Map<string, BaseAgent>;
  private eventEmitter: EventEmitter;
  
  constructor() {
    this.workflows = new Map();
    this.agents = this.initializeAgents();
    this.eventEmitter = new EventEmitter();
  }
  
  async startWorkflow(sessionId: string, task: string): Promise<string> {
    const workflowId = crypto.randomUUID();
    
    const workflow: WorkflowState = {
      id: workflowId,
      mode: 'plan',
      sessionId,
      task,
      startTime: Date.now(),
      transitions: [],
      status: 'active',
      progress: 0
    };
    
    this.workflows.set(workflowId, workflow);
    
    // Start in Plan Mode
    this.enterPlanMode(workflow);
    
    return workflowId;
  }
  
  private async enterPlanMode(workflow: WorkflowState) {
    this.emitProgress(workflow, 'Planning task...', 10);
    
    try {
      // Execute planner agent
      const planner = this.agents.get('planner') as PlannerAgent;
      const result = await planner.execute({
        task: workflow.task,
        workspace: this.getWorkspace(workflow.sessionId),
        sessionId: workflow.sessionId
      });
      
      if (!result.success) {
        throw new Error('Planning failed: ' + result.errors?.join(', '));
      }
      
      workflow.plan = result.output as Plan;
      this.emitProgress(workflow, 'Plan created', 25);
      
      // Transition to Edit Mode
      this.transitionTo(workflow, 'edit', 'Plan completed');
      
    } catch (error) {
      this.handleError(workflow, error, 'plan');
    }
  }
  
  private async enterEditMode(workflow: WorkflowState) {
    if (!workflow.plan) {
      throw new Error('No plan available for edit mode');
    }
    
    this.emitProgress(workflow, 'Executing edits...', 30);
    
    const editor = this.agents.get('editor') as EditorAgent;
    const edits: EditResult[] = [];
    
    // Execute steps in order (with parallelization where possible)
    const parallelGroups = this.groupParallelSteps(workflow.plan.steps);
    
    for (let i = 0; i < parallelGroups.length; i++) {
      const group = parallelGroups[i];
      const progress = 30 + (i / parallelGroups.length) * 40;
      
      this.emitProgress(
        workflow,
        `Executing step group ${i + 1}/${parallelGroups.length}`,
        progress
      );
      
      // Execute group in parallel
      const groupResults = await Promise.all(
        group.map(step => this.executeStep(editor, step, workflow))
      );
      
      edits.push(...groupResults);
    }
    
    workflow.edits = edits;
    this.emitProgress(workflow, 'Edits completed', 70);
    
    // Check if review is enabled
    if (this.isReviewEnabled(workflow)) {
      this.transitionTo(workflow, 'review', 'Edits completed, starting review');
    } else {
      this.transitionTo(workflow, 'complete', 'Edits completed, review skipped');
    }
  }
  
  private async enterReviewMode(workflow: WorkflowState) {
    if (!workflow.plan || !workflow.edits) {
      throw new Error('Missing plan or edits for review');
    }
    
    this.emitProgress(workflow, 'Reviewing changes...', 75);
    
    const reviewer = this.agents.get('reviewer') as ReviewerAgent;
    
    const result = await reviewer.execute({
      task: {
        plan: workflow.plan,
        edits: workflow.edits,
        originalContext: { task: workflow.task },
        successCriteria: workflow.plan.successCriteria
      },
      workspace: this.getWorkspace(workflow.sessionId),
      sessionId: workflow.sessionId
    });
    
    workflow.review = result.output as ReviewResult;
    
    if (workflow.review.passed) {
      this.emitProgress(workflow, 'Review passed', 95);
      this.transitionTo(workflow, 'complete', 'Review passed');
    } else {
      this.emitProgress(workflow, 'Review found issues', 80);
      
      // Could loop back to edit mode for fixes
      if (this.shouldAutoFix(workflow.review)) {
        this.transitionTo(workflow, 'edit', 'Auto-fixing review issues');
      } else {
        this.transitionTo(workflow, 'complete', 'Review completed with issues');
      }
    }
  }
  
  private async enterCompleteMode(workflow: WorkflowState) {
    workflow.status = 'completed';
    workflow.progress = 100;
    
    // Generate summary
    const summary = this.generateWorkflowSummary(workflow);
    
    this.emitEvent(workflow, 'workflow-completed', summary);
    
    // Archive workflow
    await this.archiveWorkflow(workflow);
  }
  
  private transitionTo(
    workflow: WorkflowState,
    newMode: WorkflowMode,
    reason: string
  ) {
    const transition: ModeTransition = {
      from: workflow.mode,
      to: newMode,
      timestamp: Date.now(),
      reason
    };
    
    workflow.transitions.push(transition);
    workflow.mode = newMode;
    
    this.emitEvent(workflow, 'mode-transition', transition);
    
    // Enter new mode
    switch (newMode) {
      case 'plan':
        this.enterPlanMode(workflow);
        break;
      case 'edit':
        this.enterEditMode(workflow);
        break;
      case 'review':
        this.enterReviewMode(workflow);
        break;
      case 'complete':
        this.enterCompleteMode(workflow);
        break;
    }
  }
  
  // External control methods
  async pauseWorkflow(workflowId: string) {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    workflow.status = 'paused';
    this.emitEvent(workflow, 'workflow-paused', {});
  }
  
  async resumeWorkflow(workflowId: string) {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    workflow.status = 'active';
    this.emitEvent(workflow, 'workflow-resumed', {});
    
    // Resume from current mode
    this.transitionTo(workflow, workflow.mode, 'Resumed');
  }
  
  async cancelWorkflow(workflowId: string) {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    workflow.status = 'failed';
    this.emitEvent(workflow, 'workflow-cancelled', {});
    
    // Clean up any resources
    await this.cleanupWorkflow(workflow);
  }
  
  // Progress tracking
  private emitProgress(workflow: WorkflowState, message: string, percent: number) {
    workflow.progress = percent;
    
    this.emitEvent(workflow, 'progress', {
      message,
      percent,
      mode: workflow.mode
    });
  }
  
  private emitEvent(workflow: WorkflowState, event: string, data: any) {
    this.eventEmitter.emit(event, {
      workflowId: workflow.id,
      sessionId: workflow.sessionId,
      ...data
    });
  }
  
  // Subscribe to workflow events
  on(event: string, handler: (data: any) => void) {
    this.eventEmitter.on(event, handler);
  }
  
  off(event: string, handler: (data: any) => void) {
    this.eventEmitter.off(event, handler);
  }
}
```

### Component 5: Claude Code CLI Integration

#### 5.1 Slash Commands

```typescript
// control-plane/src/claude/slash-commands.ts

interface SlashCommand {
  name: string;
  description: string;
  aliases: string[];
  parameters: CommandParameter[];
  handler: (params: any) => Promise<any>;
  permissions: string[];
}

class SlashCommandRegistry {
  private commands: Map<string, SlashCommand>;
  
  constructor() {
    this.commands = new Map();
    this.registerDefaultCommands();
  }
  
  private registerDefaultCommands() {
    // /plan - Start planning mode
    this.register({
      name: 'plan',
      description: 'Create a plan for a development task',
      aliases: ['p'],
      parameters: [
        { name: 'task', type: 'string', required: true }
      ],
      handler: async (params) => {
        const workflow = await workflowController.startWorkflow(
          params.sessionId,
          params.task
        );
        return { workflowId: workflow, mode: 'plan' };
      },
      permissions: ['execute']
    });
    
    // /edit - Execute edits from plan
    this.register({
      name: 'edit',
      description: 'Execute edits from the current plan',
      aliases: ['e'],
      parameters: [
        { name: 'stepId', type: 'string', required: false }
      ],
      handler: async (params) => {
        return await workflowController.executeEdit(
          params.workflowId,
          params.stepId
        );
      },
      permissions: ['execute']
    });
    
    // /review - Review changes
    this.register({
      name: 'review',
      description: 'Review the changes made',
      aliases: ['r'],
      parameters: [],
      handler: async (params) => {
        return await workflowController.startReview(params.workflowId);
      },
      permissions: ['execute']
    });
    
    // /status - Check workflow status
    this.register({
      name: 'status',
      description: 'Check the status of current workflow',
      aliases: ['s'],
      parameters: [],
      handler: async (params) => {
        return await workflowController.getStatus(params.workflowId);
      },
      permissions: ['read']
    });
    
    // /abort - Cancel current workflow
    this.register({
      name: 'abort',
      description: 'Cancel the current workflow',
      aliases: ['cancel', 'stop'],
      parameters: [],
      handler: async (params) => {
        return await workflowController.cancelWorkflow(params.workflowId);
      },
      permissions: ['execute']
    });
    
    // /context - Manage context
    this.register({
      name: 'context',
      description: 'View or modify the current context',
      aliases: ['ctx'],
      parameters: [
        { name: 'action', type: 'string', choices: ['view', 'add', 'remove'] },
        { name: 'files', type: 'array', required: false }
      ],
      handler: async (params) => {
        return await contextManager.handleContextCommand(params);
      },
      permissions: ['read', 'write']
    });
  }
  
  async execute(command: string, params: any): Promise<any> {
    const cmd = this.commands.get(command) || 
                this.findByAlias(command);
    
    if (!cmd) {
      throw new Error(`Unknown command: ${command}`);
    }
    
    // Validate parameters
    this.validateParams(cmd, params);
    
    // Check permissions
    await this.checkPermissions(cmd, params.userId);
    
    // Execute handler
    return await cmd.handler(params);
  }
}
```

#### 5.2 Hooks System

```typescript
// control-plane/src/claude/hooks.ts

interface Hook {
  id: string;
  type: 'pre' | 'post';
  event: string;
  handler: (context: HookContext) => Promise<HookResult>;
  priority: number;
  enabled: boolean;
}

interface HookContext {
  event: string;
  data: any;
  session: SessionContext;
  cancel?: () => void;
  modify?: (data: any) => void;
}

interface HookResult {
  continue: boolean;
  modifiedData?: any;
  message?: string;
}

class HookManager {
  private hooks: Map<string, Hook[]>;
  
  constructor() {
    this.hooks = new Map();
    this.registerDefaultHooks();
  }
  
  private registerDefaultHooks() {
    // Pre-edit validation hook
    this.register({
      id: 'validate-edit',
      type: 'pre',
      event: 'edit',
      priority: 10,
      enabled: true,
      handler: async (context) => {
        // Validate that files exist
        const files = context.data.files;
        for (const file of files) {
          if (!await this.fileExists(file)) {
            return {
              continue: false,
              message: `File ${file} does not exist`
            };
          }
        }
        return { continue: true };
      }
    });
    
    // Post-edit testing hook
    this.register({
      id: 'run-tests',
      type: 'post',
      event: 'edit',
      priority: 5,
      enabled: true,
      handler: async (context) => {
        // Run affected tests
        const testResults = await this.runAffectedTests(context.data.files);
        
        if (testResults.failed > 0) {
          return {
            continue: true,
            message: `Warning: ${testResults.failed} tests failed`
          };
        }
        
        return { continue: true };
      }
    });
    
    // Pre-commit hook
    this.register({
      id: 'pre-commit',
      type: 'pre',
      event: 'commit',
      priority: 20,
      enabled: true,
      handler: async (context) => {
        // Run linting
        const lintResults = await this.runLinter(context.data.files);
        
        if (lintResults.errors > 0) {
          // Auto-fix if possible
          if (lintResults.fixable) {
            await this.fixLintErrors(context.data.files);
            context.modify({ filesFixed: true });
          }
        }
        
        return { continue: true };
      }
    });
  }
  
  async executeHooks(
    type: 'pre' | 'post',
    event: string,
    context: HookContext
  ): Promise<HookResult[]> {
    const eventHooks = this.hooks.get(event) || [];
    const relevantHooks = eventHooks
      .filter(h => h.type === type && h.enabled)
      .sort((a, b) => b.priority - a.priority);
    
    const results: HookResult[] = [];
    
    for (const hook of relevantHooks) {
      try {
        const result = await hook.handler(context);
        results.push(result);
        
        if (!result.continue) {
          // Hook cancelled execution
          break;
        }
        
        if (result.modifiedData) {
          // Update context for next hooks
          context.data = result.modifiedData;
        }
      } catch (error) {
        console.error(`Hook ${hook.id} failed:`, error);
        // Continue with other hooks
      }
    }
    
    return results;
  }
  
  register(hook: Hook) {
    const eventHooks = this.hooks.get(hook.event) || [];
    eventHooks.push(hook);
    this.hooks.set(hook.event, eventHooks);
  }
  
  unregister(hookId: string) {
    for (const [event, hooks] of this.hooks) {
      const index = hooks.findIndex(h => h.id === hookId);
      if (index >= 0) {
        hooks.splice(index, 1);
        break;
      }
    }
  }
  
  enable(hookId: string) {
    this.setEnabled(hookId, true);
  }
  
  disable(hookId: string) {
    this.setEnabled(hookId, false);
  }
  
  private setEnabled(hookId: string, enabled: boolean) {
    for (const hooks of this.hooks.values()) {
      const hook = hooks.find(h => h.id === hookId);
      if (hook) {
        hook.enabled = enabled;
        break;
      }
    }
  }
}
```

### Component 6: MCP Server Implementation

#### 6.1 MCP Server Base

```typescript
// control-plane/src/mcp/mcp-server.ts

interface MCPCapability {
  name: string;
  version: string;
  methods: string[];
  schema: any;
}

interface MCPRequest {
  id: string;
  method: string;
  params: any;
}

interface MCPResponse {
  id: string;
  result?: any;
  error?: MCPError;
}

abstract class MCPServer {
  protected capabilities: MCPCapability[];
  protected ws: WebSocketServer;
  
  constructor(
    protected name: string,
    protected port: number
  ) {
    this.capabilities = this.defineCapabilities();
    this.ws = this.createWebSocketServer();
  }
  
  abstract defineCapabilities(): MCPCapability[];
  abstract handleRequest(request: MCPRequest): Promise<MCPResponse>;
  
  private createWebSocketServer(): WebSocketServer {
    const server = new WebSocketServer({ port: this.port });
    
    server.on('connection', (socket) => {
      console.log(`MCP client connected to ${this.name}`);
      
      // Send capabilities on connect
      socket.send(JSON.stringify({
        type: 'capabilities',
        capabilities: this.capabilities
      }));
      
      socket.on('message', async (data) => {
        try {
          const request = JSON.parse(data.toString()) as MCPRequest;
          const response = await this.handleRequest(request);
          socket.send(JSON.stringify(response));
        } catch (error) {
          socket.send(JSON.stringify({
            id: 'error',
            error: {
              code: -32603,
              message: error.message
            }
          }));
        }
      });
    });
    
    return server;
  }
  
  start() {
    console.log(`MCP Server ${this.name} listening on port ${this.port}`);
  }
  
  stop() {
    this.ws.close();
  }
}
```

#### 6.2 Context MCP Server

```typescript
// control-plane/src/mcp/context-mcp-server.ts

class ContextMCPServer extends MCPServer {
  private contextGenerator: ContextGenerator;
  
  constructor() {
    super('context-server', 3001);
    this.contextGenerator = new ContextGenerator(
      process.env.WORKSPACE || process.cwd()
    );
  }
  
  defineCapabilities(): MCPCapability[] {
    return [
      {
        name: 'context',
        version: '1.0.0',
        methods: [
          'getFileMap',
          'getCodeMap',
          'getFullContext',
          'searchSymbols',
          'getWorkingSet'
        ],
        schema: {
          // JSON Schema for methods
        }
      }
    ];
  }
  
  async handleRequest(request: MCPRequest): Promise<MCPResponse> {
    switch (request.method) {
      case 'getFileMap':
        return {
          id: request.id,
          result: await this.getFileMap(request.params)
        };
        
      case 'getCodeMap':
        return {
          id: request.id,
          result: await this.getCodeMap(request.params)
        };
        
      case 'getFullContext':
        return {
          id: request.id,
          result: await this.getFullContext(request.params)
        };
        
      case 'searchSymbols':
        return {
          id: request.id,
          result: await this.searchSymbols(request.params)
        };
        
      case 'getWorkingSet':
        return {
          id: request.id,
          result: await this.getWorkingSet()
        };
        
      default:
        return {
          id: request.id,
          error: {
            code: -32601,
            message: `Method ${request.method} not found`
          }
        };
    }
  }
  
  private async getFileMap(params: any) {
    const context = await this.contextGenerator.generateContext({
      patterns: params.patterns,
      maxTokens: params.maxTokens || 1000,
      includeFileMap: true,
      includeCodeMap: false,
      includeContent: false
    });
    
    return context.fileMap;
  }
  
  private async getCodeMap(params: any) {
    const context = await this.contextGenerator.generateContext({
      files: params.files,
      maxTokens: params.maxTokens || 5000,
      includeFileMap: false,
      includeCodeMap: true,
      includeContent: false
    });
    
    return context.codeMap;
  }
  
  private async getFullContext(params: any) {
    return await this.contextGenerator.generateContext(params);
  }
  
  private async searchSymbols(params: any) {
    // Search for symbols by name/type
    const { query, type, limit = 10 } = params;
    
    const context = await this.contextGenerator.generateContext({
      includeCodeMap: true
    });
    
    const symbols = context.codeMap?.symbols || [];
    
    return symbols
      .filter(s => {
        const matchesQuery = s.name.includes(query);
        const matchesType = !type || s.type === type;
        return matchesQuery && matchesType;
      })
      .slice(0, limit);
  }
  
  private async getWorkingSet() {
    const tracker = new WorkingSetTracker(process.env.WORKSPACE!);
    return await tracker.getWorkingSet();
  }
}
```

## Testing Strategy

### Unit Tests

```typescript
// control-plane/test/unit/agents.test.ts

describe('PlannerAgent', () => {
  let agent: PlannerAgent;
  
  beforeEach(() => {
    agent = new PlannerAgent('planner', '/test/workspace');
  });
  
  test('creates valid plan for simple task', async () => {
    const context: AgentContext = {
      task: 'Add a new API endpoint for user profile',
      workspace: '/test/workspace',
      sessionId: 'test-session'
    };
    
    const result = await agent.execute(context);
    
    expect(result.success).toBe(true);
    expect(result.output).toHaveProperty('steps');
    expect(result.output.steps.length).toBeGreaterThan(0);
    expect(result.output).toHaveProperty('successCriteria');
  });
  
  test('handles complex multi-file operations', async () => {
    const context: AgentContext = {
      task: 'Refactor authentication system to use JWT',
      workspace: '/test/workspace',
      sessionId: 'test-session'
    };
    
    const result = await agent.execute(context);
    
    expect(result.success).toBe(true);
    expect(result.output.steps.length).toBeGreaterThan(3);
    
    // Check for proper dependency ordering
    const steps = result.output.steps;
    for (const step of steps) {
      if (step.dependencies.length > 0) {
        const depIndex = steps.findIndex(s => s.id === step.dependencies[0]);
        const stepIndex = steps.findIndex(s => s.id === step.id);
        expect(depIndex).toBeLessThan(stepIndex);
      }
    }
  });
});

describe('ModelRouter', () => {
  let router: ModelRouter;
  
  beforeEach(() => {
    router = new ModelRouter();
  });
  
  test('selects appropriate model based on complexity', async () => {
    const simpleRequest: RouteRequest = {
      prompt: 'Simple task',
      preferredModel: 'claude-3-opus',
      fallbackModels: ['gpt-4'],
      maxTokens: 500,
      temperature: 0.5,
      complexity: 'simple'
    };
    
    const complexRequest: RouteRequest = {
      prompt: 'Complex task',
      preferredModel: 'claude-3-opus',
      fallbackModels: ['gpt-4'],
      maxTokens: 4000,
      temperature: 0.5,
      complexity: 'complex'
    };
    
    // Simple tasks should use cheaper models
    const simpleModel = router.selectModel(simpleRequest);
    expect(['claude-3-haiku', 'gpt-3.5-turbo']).toContain(simpleModel);
    
    // Complex tasks should use more capable models
    const complexModel = router.selectModel(complexRequest);
    expect(['claude-3-opus', 'gpt-4']).toContain(complexModel);
  });
  
  test('handles fallback on model failure', async () => {
    const request: RouteRequest = {
      prompt: 'Test prompt',
      preferredModel: 'failing-model',
      fallbackModels: ['claude-3-sonnet', 'gpt-4'],
      maxTokens: 1000,
      temperature: 0.5
    };
    
    const response = await router.route(request);
    
    expect(response.model).not.toBe('failing-model');
    expect(['claude-3-sonnet', 'gpt-4']).toContain(response.model);
  });
});
```

### Integration Tests

```typescript
// control-plane/test/integration/workflow.test.ts

describe('End-to-End Workflow', () => {
  let controller: WorkflowModeController;
  let contextGen: ContextGenerator;
  
  beforeAll(async () => {
    // Setup test environment
    await setupTestWorkspace();
    controller = new WorkflowModeController();
    contextGen = new ContextGenerator('/test/workspace');
  });
  
  test('completes full plan-edit-review workflow', async () => {
    const workflowId = await controller.startWorkflow(
      'test-session',
      'Add user authentication endpoints'
    );
    
    // Wait for plan mode to complete
    await waitForMode(controller, workflowId, 'edit');
    
    const status1 = await controller.getStatus(workflowId);
    expect(status1.mode).toBe('edit');
    expect(status1.plan).toBeDefined();
    
    // Wait for edit mode to complete
    await waitForMode(controller, workflowId, 'review');
    
    const status2 = await controller.getStatus(workflowId);
    expect(status2.mode).toBe('review');
    expect(status2.edits).toBeDefined();
    
    // Wait for review to complete
    await waitForMode(controller, workflowId, 'complete');
    
    const final = await controller.getStatus(workflowId);
    expect(final.status).toBe('completed');
    expect(final.review).toBeDefined();
  }, 30000); // 30 second timeout
  
  test('handles parallel edits correctly', async () => {
    const workflowId = await controller.startWorkflow(
      'test-session',
      'Create CRUD operations for posts'
    );
    
    await waitForMode(controller, workflowId, 'edit');
    
    // Check that independent files were edited in parallel
    const status = await controller.getStatus(workflowId);
    const edits = status.edits!;
    
    // Group edits by timestamp to check parallelization
    const editGroups = groupByTimestamp(edits, 100); // 100ms window
    
    expect(editGroups.length).toBeGreaterThan(1);
    expect(editGroups.some(g => g.length > 1)).toBe(true);
  });
});
```

## Implementation Timeline

### Week 1: Core Agent System

#### Day 1-2: Agent Framework
- [ ] Implement BaseAgent class
- [ ] Create PlannerAgent with task decomposition
- [ ] Create EditorAgent with file operations
- [ ] Create ReviewerAgent with validation
- [ ] Unit tests for each agent

#### Day 3-4: Model Router
- [ ] Implement ModelRouter with provider abstraction
- [ ] Add cost optimization logic
- [ ] Add load balancing and rate limiting
- [ ] Create fallback mechanism
- [ ] Performance benchmarks

#### Day 5: Prompt Management
- [ ] Build PromptManager with template system
- [ ] Create default templates for each agent
- [ ] Add variable interpolation
- [ ] Implement version management
- [ ] Template testing framework

### Week 2: Integration & Workflow

#### Day 6-7: Workflow Controller
- [ ] Implement WorkflowModeController
- [ ] Create state management system
- [ ] Add mode transitions
- [ ] Build progress tracking
- [ ] WebSocket event streaming

#### Day 8-9: Claude Code Integration
- [ ] Implement slash command registry
- [ ] Create hook system
- [ ] Add sub-agent support
- [ ] Memory management (CLAUDE.md)
- [ ] Integration with CLI

#### Day 10: MCP Servers
- [ ] Create base MCP server class
- [ ] Implement Context MCP server
- [ ] Add discovery mechanism
- [ ] Test with Claude Code
- [ ] Documentation

### Week 3: Testing & Polish

#### Day 11-12: Integration Testing
- [ ] End-to-end workflow tests
- [ ] Multi-model integration tests
- [ ] Performance testing
- [ ] Error recovery testing
- [ ] Load testing

#### Day 13-14: Documentation & Deployment
- [ ] API documentation
- [ ] Usage examples
- [ ] Configuration guide
- [ ] Deployment scripts
- [ ] Migration from Phase 2

## Success Criteria

### Required Features
- [ ] Three specialized agents (planner, editor, reviewer) working
- [ ] Model routing with fallback support
- [ ] Prompt template management system
- [ ] Workflow mode controller (plan → edit → review)
- [ ] Claude Code CLI integration (slash commands, hooks)
- [ ] MCP server implementation
- [ ] Real-time progress tracking via WebSocket
- [ ] Parallel execution for independent tasks

### Performance Targets
- [ ] Plan generation < 3 seconds for typical tasks
- [ ] Edit execution < 2 seconds per file
- [ ] Review completion < 5 seconds
- [ ] Model fallback < 500ms
- [ ] WebSocket latency < 100ms
- [ ] 95%+ success rate for workflows

### Quality Metrics
- [ ] 80%+ test coverage
- [ ] Zero memory leaks
- [ ] Graceful error handling
- [ ] Clear audit trail
- [ ] Comprehensive logging

## Configuration

### Agent Configuration

```yaml
# .devys/agents.yaml
agents:
  planner:
    model: claude-3-opus
    maxTokens: 8000
    temperature: 0.3
    timeout: 30000
    retries: 2
    
  editor:
    model: claude-3-sonnet
    maxTokens: 4000
    temperature: 0.1
    parallelism: 4
    
  reviewer:
    model: gemini-pro
    maxTokens: 3000
    temperature: 0.2
    autoFix: true

models:
  claude-3-opus:
    provider: anthropic
    apiKey: ${ANTHROPIC_API_KEY}
    costPerToken: 0.00003
    
  gpt-4-turbo:
    provider: openai
    apiKey: ${OPENAI_API_KEY}
    costPerToken: 0.00002
    
  gemini-pro:
    provider: google
    apiKey: ${GOOGLE_API_KEY}
    costPerToken: 0.00001

workflow:
  reviewMode: optional
  maxParallelEdits: 4
  autoRetry: true
  progressUpdates: true
```

### Prompt Templates

```yaml
# .devys/prompts/planner.yaml
id: planner-v1
agent: planner
version: 1.0.0
template: |
  You are a senior software architect...
  
variables:
  - name: task
    type: string
    required: true
  - name: context
    type: object
    required: true
```

## Risk Mitigation

### Technical Risks

1. **Model API Failures**
   - Mitigation: Comprehensive fallback system
   - Multiple provider support
   - Local model option for critical paths

2. **Context Size Limits**
   - Mitigation: Smart context selection from Phase 2
   - Chunking strategies for large operations
   - Progressive enhancement

3. **Workflow State Corruption**
   - Mitigation: Transactional state updates
   - Regular checkpointing
   - Recovery mechanisms

### Operational Risks

1. **Cost Overruns**
   - Mitigation: Token budgeting system
   - Cost alerts and limits
   - Model selection optimization

2. **Performance Degradation**
   - Mitigation: Caching at multiple levels
   - Parallel execution where possible
   - Performance monitoring

## Future Enhancements (Phase 4+)

1. **Grunt Agent** for repetitive tasks
2. **AI Context Builder** for automatic file selection
3. **Multi-workspace support**
4. **Team collaboration features**
5. **Custom agent creation SDK**
6. **Visual workflow builder**
7. **Integration with CI/CD pipelines**

---

*Phase 3 transforms the context intelligence from Phase 2 into a complete AI development assistant through intelligent orchestration, specialized agents, and seamless Claude Code integration.*

**Status: 📋 READY FOR IMPLEMENTATION**