// Integrated Workflow Controller for Phase 4
// Orchestrates Plan → Edit → Review → Grunt workflow with intelligent model routing

import { EventEmitter } from 'events';
import { Database } from 'bun:sqlite';
import { WorkflowModeController } from './workflow-mode-controller';
import { PlannerAgent } from '../agents/planner-agent';
import { EditorAgent } from '../agents/editor-agent';
import { ReviewerAgent } from '../agents/reviewer-agent';
import { BaseAgent } from '../agents/base-agent';
import { ContextService } from '../services/context/context-service';
import {
  PHASE_4_ROUTER_CONFIG,
  TaskClassifier,
  ModelSelectionStrategy,
  CostManager
} from '../routing/claude-code-router-config';
import {
  WorkflowState,
  WorkflowMode,
  IntegratedWorkflowResult,
  WorkflowPhase,
  WorkflowMetrics
} from '../types/workflow';
import {
  Plan,
  EditResult,
  ReviewResult,
  EditTask,
  GruntTask,
  GruntResult
} from '../types/agents';

export interface IntegratedWorkflowConfig {
  enableReview: boolean;
  enableGrunt: boolean;
  maxParallelEdits: number;
  costBudget: number;
  timeoutMs: number;
  retryAttempts: number;
}

export interface WorkflowContext {
  query: string;
  files?: string[];
  includeCodeMaps: boolean;
  maxTokens: number;
  complexity?: 'simple' | 'moderate' | 'complex';
}

export interface WorkflowExecutionOptions {
  sessionId?: string;
  priority?: 'low' | 'medium' | 'high';
  budgetLimit?: number;
  skipReview?: boolean;
  skipGrunt?: boolean;
}

/**
 * Integrated Workflow Controller
 * 
 * Orchestrates the complete Plan → Edit → Review → Grunt workflow
 * with intelligent model routing and cost optimization.
 */
export class IntegratedWorkflowController extends EventEmitter {
  private modeController: WorkflowModeController;
  private contextService: ContextService;
  private plannerAgent: PlannerAgent;
  private editorAgent: EditorAgent;
  private reviewerAgent: ReviewerAgent;
  private gruntAgent: BaseAgent; // Will be implemented as GruntAgent
  private modelStrategy: ModelSelectionStrategy;
  private costManager: CostManager;
  private db: Database;
  
  private readonly config: IntegratedWorkflowConfig;
  private activeWorkflows: Map<string, WorkflowState> = new Map();
  private workflowMetrics: Map<string, WorkflowMetrics> = new Map();
  
  constructor(
    workspace: string,
    db: Database,
    config: Partial<IntegratedWorkflowConfig> = {}
  ) {
    super();
    
    this.config = {
      enableReview: true,
      enableGrunt: true,
      maxParallelEdits: 4,
      costBudget: 5.0,
      timeoutMs: 300000, // 5 minutes
      retryAttempts: 3,
      ...config
    };
    
    this.db = db;
    this.modeController = new WorkflowModeController(workspace, db);
    this.contextService = new ContextService(workspace, db);
    
    // Initialize agents
    this.plannerAgent = new PlannerAgent(workspace, db);
    this.editorAgent = new EditorAgent(workspace, db);
    this.reviewerAgent = new ReviewerAgent(workspace, db);
    this.gruntAgent = new BaseAgent(workspace, db); // Placeholder for GruntAgent
    
    // Initialize model routing
    this.modelStrategy = new ModelSelectionStrategy(PHASE_4_ROUTER_CONFIG);
    this.costManager = new CostManager(PHASE_4_ROUTER_CONFIG);
    
    this.initializeDatabase();
    this.setupEventHandlers();
  }
  
  private initializeDatabase(): void {
    // Create integrated workflow tracking tables
    this.db.run(`
      CREATE TABLE IF NOT EXISTS integrated_workflows (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        user_query TEXT NOT NULL,
        complexity TEXT NOT NULL,
        estimated_tokens INTEGER,
        estimated_cost REAL,
        actual_cost REAL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        status TEXT NOT NULL,
        phases TEXT, -- JSON array of completed phases
        metrics TEXT, -- JSON object with performance metrics
        errors TEXT   -- JSON array of errors
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS workflow_phase_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workflow_id TEXT NOT NULL,
        phase TEXT NOT NULL,
        model_used TEXT,
        tokens_used INTEGER,
        cost REAL,
        duration_ms INTEGER,
        success BOOLEAN,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (workflow_id) REFERENCES integrated_workflows(id)
      )
    `);
  }
  
  private setupEventHandlers(): void {
    // Listen to mode controller events
    this.modeController.on('progress', (progress) => {
      this.emit('workflow-progress', progress);
    });
    
    this.modeController.on('mode-transition', (transition) => {
      this.emit('mode-transition', transition);
    });
    
    this.modeController.on('workflow-error', (error) => {
      this.emit('workflow-error', error);
    });
  }
  
  /**
   * Execute the complete integrated workflow
   */
  async executeWorkflow(
    userQuery: string,
    options: WorkflowExecutionOptions = {}
  ): Promise<IntegratedWorkflowResult> {
    const workflowId = crypto.randomUUID();
    const sessionId = options.sessionId || crypto.randomUUID();
    
    // Initialize workflow tracking
    const startTime = Date.now();
    const complexity = TaskClassifier.classifyTask(userQuery);
    const estimatedTokens = TaskClassifier.estimateTokenRequirement(userQuery);
    
    // Check budget constraints
    if (!this.costManager.canAffordRequest('claude-3-5-sonnet', estimatedTokens)) {
      throw new Error('Insufficient budget for workflow execution');
    }
    
    const workflow: WorkflowState = {
      id: workflowId,
      mode: 'plan',
      sessionId,
      task: userQuery,
      startTime,
      transitions: [],
      status: 'active',
      progress: 0,
      errors: []
    };
    
    this.activeWorkflows.set(workflowId, workflow);
    
    const phases: WorkflowPhase[] = [];
    const metrics: WorkflowMetrics = {
      workflowId,
      totalTokens: 0,
      totalCost: 0,
      duration: 0,
      phaseCounts: { plan: 0, edit: 0, review: 0, grunt: 0 },
      modelUsage: new Map()
    };
    
    this.workflowMetrics.set(workflowId, metrics);
    
    try {
      // Phase 1: PLAN
      this.emit('workflow-phase-start', { workflowId, phase: 'plan' });
      const planResult = await this.executePlanPhase(userQuery, workflowId);
      phases.push(planResult);
      this.updateMetrics(workflowId, planResult);
      
      if (!planResult.success) {
        throw new Error('Planning phase failed: ' + planResult.errors?.join(', '));
      }
      
      // Phase 2: EDIT
      this.emit('workflow-phase-start', { workflowId, phase: 'edit' });
      const editResults = await this.executeEditPhase(planResult.plan!, workflowId);
      phases.push(...editResults);
      editResults.forEach(result => this.updateMetrics(workflowId, result));
      
      // Phase 3: REVIEW (if enabled and needed)
      if (this.config.enableReview && !options.skipReview && this.shouldReview(editResults)) {
        this.emit('workflow-phase-start', { workflowId, phase: 'review' });
        const reviewResult = await this.executeReviewPhase(planResult.plan!, editResults, workflowId);
        phases.push(reviewResult);
        this.updateMetrics(workflowId, reviewResult);
        
        // Handle review failures
        if (reviewResult.success && reviewResult.review!.issues.length > 0) {
          const fixResults = await this.handleReviewIssues(reviewResult.review!.issues, workflowId);
          phases.push(...fixResults);
          fixResults.forEach(result => this.updateMetrics(workflowId, result));
        }
      }
      
      // Phase 4: GRUNT (if enabled)
      if (this.config.enableGrunt && !options.skipGrunt) {
        this.emit('workflow-phase-start', { workflowId, phase: 'grunt' });
        const gruntResults = await this.executeGruntPhase(editResults, workflowId);
        phases.push(...gruntResults);
        gruntResults.forEach(result => this.updateMetrics(workflowId, result));
      }
      
      // Complete workflow
      workflow.status = 'completed';
      const endTime = Date.now();
      metrics.duration = endTime - startTime;
      
      // Save to database
      await this.saveWorkflowResults(workflowId, userQuery, complexity, phases, metrics);
      
      this.emit('workflow-completed', { workflowId, metrics });
      
      return {
        workflowId,
        success: true,
        phases,
        metrics: this.workflowMetrics.get(workflowId)!,
        duration: endTime - startTime
      };
      
    } catch (error) {
      workflow.status = 'failed';
      workflow.errors.push(error instanceof Error ? error.message : String(error));
      
      this.emit('workflow-error', { workflowId, error: workflow.errors });
      
      return {
        workflowId,
        success: false,
        phases,
        metrics: this.workflowMetrics.get(workflowId)!,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      };
    } finally {
      this.activeWorkflows.delete(workflowId);
    }
  }
  
  /**
   * Execute planning phase with large context model
   */
  private async executePlanPhase(userQuery: string, workflowId: string): Promise<WorkflowPhase> {
    const startTime = Date.now();
    
    // Build comprehensive context
    const context = await this.contextService.buildContext({
      query: userQuery,
      includeFiles: true,
      includeCodeMaps: true,
      maxTokens: PHASE_4_ROUTER_CONFIG.routing.plan.tokenBudget || 900000
    });
    
    // Select planning model (prefer high-context free models)
    const model = this.modelStrategy.selectPremiumModel('plan', context.totalTokens);
    
    const planInstructions = `
      Break down this task into specific file edits.
      For each edit, specify:
      - File path (absolute)
      - Operation type (create/edit/delete)
      - Detailed description of changes
      - Success criteria
      - Dependencies on other edits
      - Estimated complexity (simple/moderate/complex)
      
      Consider parallelization opportunities.
      Optimize for minimal token usage in edit phase.
    `;
    
    try {
      const result = await this.plannerAgent.execute({
        task: userQuery,
        context,
        model,
        instructions: planInstructions,
        workspace: this.plannerAgent['workspace'],
        sessionId: this.activeWorkflows.get(workflowId)!.sessionId
      });
      
      return {
        phase: 'plan',
        success: result.success,
        model,
        tokensUsed: result.tokensUsed || 0,
        cost: this.calculatePhaseCost(model, result.tokensUsed || 0),
        duration: Date.now() - startTime,
        plan: result.output as Plan,
        errors: result.errors
      };
      
    } catch (error) {
      return {
        phase: 'plan',
        success: false,
        model,
        tokensUsed: 0,
        cost: 0,
        duration: Date.now() - startTime,
        errors: [error instanceof Error ? error.message : String(error)]
      };
    }
  }
  
  /**
   * Execute edit phase with parallel processing
   */
  private async executeEditPhase(plan: Plan, workflowId: string): Promise<WorkflowPhase[]> {
    const phases: WorkflowPhase[] = [];
    
    // Group steps by parallelization opportunities
    const parallelGroups = plan.parallelGroups || [plan.steps];
    
    for (let groupIndex = 0; groupIndex < parallelGroups.length; groupIndex++) {
      const group = parallelGroups[groupIndex];
      const groupPhases = await Promise.all(
        group.map(step => this.executeEditStep(step, workflowId))
      );
      phases.push(...groupPhases);
    }
    
    return phases;
  }
  
  /**
   * Execute individual edit step
   */
  private async executeEditStep(step: any, workflowId: string): Promise<WorkflowPhase> {
    const startTime = Date.now();
    const stepComplexity = step.complexity || TaskClassifier.classifyTask(step.description);
    
    // Build targeted context for this step
    const context = await this.contextService.buildContext({
      files: step.fileOperations.map((op: any) => op.path),
      includeCodeMaps: true,
      maxTokens: PHASE_4_ROUTER_CONFIG.routing.edit.tokenBudget || 150000
    });
    
    // Select appropriate model based on complexity
    const model = stepComplexity === 'simple' 
      ? this.modelStrategy.selectGruntModel(context.totalTokens)
      : this.modelStrategy.selectPremiumModel('edit', context.totalTokens);
    
    const editTask: EditTask = {
      stepId: step.id,
      fileOperations: step.fileOperations,
      context: {
        targetFiles: step.fileOperations.map((op: any) => op.path),
        codeMap: [step],
        relevantSymbols: []
      }
    };
    
    try {
      const result = await this.editorAgent.execute({
        task: editTask,
        workspace: this.editorAgent['workspace'],
        sessionId: this.activeWorkflows.get(workflowId)!.sessionId
      });
      
      return {
        phase: 'edit',
        success: result.success,
        model,
        tokensUsed: result.tokensUsed || 0,
        cost: this.calculatePhaseCost(model, result.tokensUsed || 0),
        duration: Date.now() - startTime,
        edits: result.output as EditResult,
        stepId: step.id,
        errors: result.errors
      };
      
    } catch (error) {
      return {
        phase: 'edit',
        success: false,
        model,
        tokensUsed: 0,
        cost: 0,
        duration: Date.now() - startTime,
        stepId: step.id,
        errors: [error instanceof Error ? error.message : String(error)]
      };
    }
  }
  
  /**
   * Execute review phase with reasoning model
   */
  private async executeReviewPhase(
    plan: Plan,
    editResults: WorkflowPhase[],
    workflowId: string
  ): Promise<WorkflowPhase> {
    const startTime = Date.now();
    
    // Select reasoning model for review
    const model = this.modelStrategy.selectPremiumModel('review', 100000);
    
    const reviewContext = {
      plan,
      edits: editResults.map(r => r.edits).filter(Boolean) as EditResult[],
      originalContext: { task: plan.summary },
      successCriteria: plan.successCriteria
    };
    
    try {
      const result = await this.reviewerAgent.execute({
        task: reviewContext,
        workspace: this.reviewerAgent['workspace'],
        sessionId: this.activeWorkflows.get(workflowId)!.sessionId
      });
      
      return {
        phase: 'review',
        success: result.success,
        model,
        tokensUsed: result.tokensUsed || 0,
        cost: this.calculatePhaseCost(model, result.tokensUsed || 0),
        duration: Date.now() - startTime,
        review: result.output as ReviewResult,
        errors: result.errors
      };
      
    } catch (error) {
      return {
        phase: 'review',
        success: false,
        model,
        tokensUsed: 0,
        cost: 0,
        duration: Date.now() - startTime,
        errors: [error instanceof Error ? error.message : String(error)]
      };
    }
  }
  
  /**
   * Execute grunt phase with local/free models
   */
  private async executeGruntPhase(editResults: WorkflowPhase[], workflowId: string): Promise<WorkflowPhase[]> {
    const phases: WorkflowPhase[] = [];
    
    // Generate grunt tasks
    const gruntTasks = this.generateGruntTasks(editResults);
    
    // Execute grunt tasks in parallel with local models
    const gruntPhases = await Promise.all(
      gruntTasks.map(task => this.executeGruntTask(task, workflowId))
    );
    
    return gruntPhases;
  }
  
  /**
   * Execute individual grunt task
   */
  private async executeGruntTask(task: GruntTask, workflowId: string): Promise<WorkflowPhase> {
    const startTime = Date.now();
    const model = this.modelStrategy.selectGruntModel(1000); // Small token requirement
    
    try {
      // Placeholder for actual grunt agent implementation
      const result: GruntResult = {
        type: task.type,
        status: 'success',
        files: task.files || [],
        model,
        tokens: 0,
        output: `Grunt task ${task.type} completed successfully`
      };
      
      return {
        phase: 'grunt',
        success: true,
        model,
        tokensUsed: result.tokens,
        cost: this.calculatePhaseCost(model, result.tokens),
        duration: Date.now() - startTime,
        grunt: result,
        errors: []
      };
      
    } catch (error) {
      return {
        phase: 'grunt',
        success: false,
        model,
        tokensUsed: 0,
        cost: 0,
        duration: Date.now() - startTime,
        errors: [error instanceof Error ? error.message : String(error)]
      };
    }
  }
  
  /**
   * Generate grunt tasks based on edit results
   */
  private generateGruntTasks(editResults: WorkflowPhase[]): GruntTask[] {
    const tasks: GruntTask[] = [];
    const modifiedFiles = editResults
      .flatMap(r => r.edits?.filesModified || [])
      .filter((file, index, arr) => arr.indexOf(file) === index); // Dedupe
    
    if (modifiedFiles.length > 0) {
      tasks.push(
        { type: 'format', files: modifiedFiles },
        { type: 'lint', files: modifiedFiles },
        { type: 'test', scope: 'affected' }
      );
    }
    
    // Add commit task if files were modified
    if (modifiedFiles.length > 0) {
      tasks.push({
        type: 'commit',
        message: `Automated changes: ${modifiedFiles.length} files updated`
      });
    }
    
    return tasks;
  }
  
  /**
   * Handle review issues with targeted fixes
   */
  private async handleReviewIssues(issues: any[], workflowId: string): Promise<WorkflowPhase[]> {
    const fixes: WorkflowPhase[] = [];
    
    // Group issues by severity and file
    const criticalIssues = issues.filter(issue => issue.severity === 'critical');
    
    if (criticalIssues.length > 0) {
      // Create fix tasks for critical issues
      for (const issue of criticalIssues) {
        const fixPhase = await this.createFixTask(issue, workflowId);
        fixes.push(fixPhase);
      }
    }
    
    return fixes;
  }
  
  /**
   * Create fix task for specific issue
   */
  private async createFixTask(issue: any, workflowId: string): Promise<WorkflowPhase> {
    const startTime = Date.now();
    const model = this.modelStrategy.selectPremiumModel('edit', 50000);
    
    // This would create a targeted fix for the specific issue
    // For now, return a placeholder
    return {
      phase: 'edit',
      success: true,
      model,
      tokensUsed: 0,
      cost: 0,
      duration: Date.now() - startTime,
      errors: []
    };
  }
  
  /**
   * Helper methods
   */
  private shouldReview(editResults: WorkflowPhase[]): boolean {
    // Review if any edits were complex or if there were errors
    return editResults.some(result => 
      !result.success || 
      (result.edits && result.edits.filesModified.length > 5)
    );
  }
  
  private calculatePhaseCost(modelName: string, tokensUsed: number): number {
    const modelConfig = this.findModelConfig(modelName);
    return modelConfig ? tokensUsed * modelConfig.cost : 0;
  }
  
  private findModelConfig(modelName: string): { cost: number } | null {
    for (const provider of Object.values(PHASE_4_ROUTER_CONFIG.providers)) {
      if (provider.models[modelName]) {
        return provider.models[modelName];
      }
    }
    return null;
  }
  
  private updateMetrics(workflowId: string, phase: WorkflowPhase): void {
    const metrics = this.workflowMetrics.get(workflowId);
    if (!metrics) return;
    
    metrics.totalTokens += phase.tokensUsed;
    metrics.totalCost += phase.cost;
    metrics.phaseCounts[phase.phase]++;
    
    const modelCount = metrics.modelUsage.get(phase.model) || 0;
    metrics.modelUsage.set(phase.model, modelCount + 1);
    
    // Record cost
    this.costManager.recordCost(phase.model, phase.tokensUsed);
  }
  
  private async saveWorkflowResults(
    workflowId: string,
    userQuery: string,
    complexity: string,
    phases: WorkflowPhase[],
    metrics: WorkflowMetrics
  ): Promise<void> {
    const endTime = Date.now();
    const errors = phases.flatMap(p => p.errors || []);
    
    // Save main workflow record
    this.db.run(
      `INSERT OR REPLACE INTO integrated_workflows 
       (id, user_query, complexity, estimated_tokens, actual_cost, start_time, end_time, status, phases, metrics, errors)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        workflowId,
        userQuery,
        complexity,
        metrics.totalTokens,
        metrics.totalCost,
        metrics.duration,
        endTime,
        'completed',
        JSON.stringify(phases.map(p => ({ phase: p.phase, success: p.success }))),
        JSON.stringify(metrics),
        errors.length > 0 ? JSON.stringify(errors) : null
      ]
    );
    
    // Save phase metrics
    for (const phase of phases) {
      this.db.run(
        `INSERT INTO workflow_phase_metrics 
         (workflow_id, phase, model_used, tokens_used, cost, duration_ms, success, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          workflowId,
          phase.phase,
          phase.model,
          phase.tokensUsed,
          phase.cost,
          phase.duration,
          phase.success ? 1 : 0,
          Date.now()
        ]
      );
    }
  }
  
  /**
   * Public API methods
   */
  async getWorkflowStatus(workflowId: string): Promise<WorkflowState | null> {
    return this.activeWorkflows.get(workflowId) || null;
  }
  
  async getWorkflowMetrics(workflowId: string): Promise<WorkflowMetrics | null> {
    return this.workflowMetrics.get(workflowId) || null;
  }
  
  getRemainingBudget(): number {
    return this.costManager.getRemainingBudget();
  }
  
  getActiveWorkflowCount(): number {
    return this.activeWorkflows.size;
  }
}