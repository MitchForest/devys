import { EventEmitter } from 'events';
import { Database } from 'bun:sqlite';
import {
  WorkflowMode,
  WorkflowStatus,
  WorkflowState,
  ModeTransition,
  WorkflowEvent,
  WorkflowProgress,
  WorkflowSummary
} from '../types/workflow';
import {
  Plan,
  PlanStep,
  EditResult,
  ReviewResult,
  EditTask,
  ReviewContext
} from '../types/agents';
import { PlannerAgent } from '../agents/planner-agent';
import { EditorAgent } from '../agents/editor-agent';
import { ReviewerAgent } from '../agents/reviewer-agent';
import { BaseAgent } from '../agents/base-agent';

export class WorkflowModeController extends EventEmitter {
  private workflows: Map<string, WorkflowState>;
  private agents: Map<string, BaseAgent>;
  private db: Database;
  private activeWorkflows: Set<string>;
  private workflowTimers: Map<string, NodeJS.Timeout>;
  
  constructor(private workspace: string, db: Database) {
    super();
    this.workflows = new Map();
    this.agents = this.initializeAgents(db);
    this.db = db;
    this.activeWorkflows = new Set();
    this.workflowTimers = new Map();
    
    this.initializeDatabase();
    this.loadActiveWorkflows();
  }
  
  private initializeAgents(db: Database): Map<string, BaseAgent> {
    const agents = new Map<string, BaseAgent>();
    
    agents.set('planner', new PlannerAgent(this.workspace, db));
    agents.set('editor', new EditorAgent(this.workspace, db));
    agents.set('reviewer', new ReviewerAgent(this.workspace, db));
    
    return agents;
  }
  
  private initializeDatabase() {
    // Create workflow tables
    this.db.run(`
      CREATE TABLE IF NOT EXISTS workflows (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        task TEXT NOT NULL,
        mode TEXT NOT NULL,
        status TEXT NOT NULL,
        progress INTEGER DEFAULT 0,
        plan TEXT,
        edits TEXT,
        review TEXT,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        errors TEXT
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS workflow_transitions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workflow_id TEXT NOT NULL,
        from_mode TEXT NOT NULL,
        to_mode TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        reason TEXT,
        data TEXT,
        FOREIGN KEY (workflow_id) REFERENCES workflows(id)
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS workflow_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workflow_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        event TEXT NOT NULL,
        data TEXT,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (workflow_id) REFERENCES workflows(id)
      )
    `);
  }
  
  private loadActiveWorkflows() {
    const rows = this.db.query(
      "SELECT * FROM workflows WHERE status IN ('active', 'paused')"
    ).all() as any[];
    
    for (const row of rows) {
      const workflow: WorkflowState = {
        id: row.id,
        mode: row.mode,
        sessionId: row.session_id,
        task: row.task,
        plan: row.plan ? JSON.parse(row.plan) : undefined,
        edits: row.edits ? JSON.parse(row.edits) : undefined,
        review: row.review ? JSON.parse(row.review) : undefined,
        startTime: row.start_time,
        transitions: [],
        status: row.status,
        progress: row.progress,
        errors: row.errors ? JSON.parse(row.errors) : []
      };
      
      // Load transitions
      const transitions = this.db.query(
        "SELECT * FROM workflow_transitions WHERE workflow_id = ? ORDER BY timestamp"
      ).all(workflow.id) as any[];
      
      workflow.transitions = transitions.map(t => ({
        from: t.from_mode,
        to: t.to_mode,
        timestamp: t.timestamp,
        reason: t.reason,
        data: t.data ? JSON.parse(t.data) : undefined
      }));
      
      this.workflows.set(workflow.id, workflow);
      
      if (workflow.status === 'active') {
        this.activeWorkflows.add(workflow.id);
      }
    }
    
    console.log(`Loaded ${this.workflows.size} workflows (${this.activeWorkflows.size} active)`);
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
      progress: 0,
      errors: []
    };
    
    // Store in memory
    this.workflows.set(workflowId, workflow);
    this.activeWorkflows.add(workflowId);
    
    // Persist to database
    this.saveWorkflow(workflow);
    
    // Log event
    this.logEvent(workflow, 'workflow-started', { task });
    
    // Start in Plan Mode
    this.enterPlanMode(workflow);
    
    return workflowId;
  }
  
  private async enterPlanMode(workflow: WorkflowState) {
    this.emitProgress(workflow, 'Starting planning phase...', 10);
    
    try {
      // Execute planner agent
      const planner = this.agents.get('planner') as PlannerAgent;
      
      const result = await planner.execute({
        task: workflow.task,
        workspace: this.workspace,
        sessionId: workflow.sessionId
      });
      
      if (!result.success) {
        throw new Error('Planning failed: ' + result.errors?.join(', '));
      }
      
      workflow.plan = result.output as Plan;
      this.emitProgress(workflow, 'Plan created successfully', 25);
      
      // Save plan
      this.saveWorkflow(workflow);
      
      // Log the plan
      this.logEvent(workflow, 'plan-created', {
        steps: workflow.plan.steps.length,
        estimatedTokens: workflow.plan.estimatedTotalTokens
      });
      
      // Transition to Edit Mode
      await this.transitionTo(workflow, 'edit', 'Plan completed');
      
    } catch (error) {
      this.handleError(workflow, error, 'plan');
    }
  }
  
  private async enterEditMode(workflow: WorkflowState) {
    if (!workflow.plan) {
      throw new Error('No plan available for edit mode');
    }
    
    this.emitProgress(workflow, 'Starting edit phase...', 30);
    
    const editor = this.agents.get('editor') as EditorAgent;
    const edits: EditResult[] = [];
    
    try {
      // Execute steps in order (with parallelization where possible)
      const parallelGroups = workflow.plan.parallelGroups || [workflow.plan.steps];
      
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
        
        // Check for errors
        const errors = groupResults.filter(r => r.errors.length > 0);
        if (errors.length > 0) {
          workflow.errors.push(...errors.flatMap(e => e.errors));
        }
      }
      
      workflow.edits = edits;
      this.saveWorkflow(workflow);
      
      this.emitProgress(workflow, 'Edits completed', 70);
      
      // Log edit results
      this.logEvent(workflow, 'edits-completed', {
        filesModified: edits.flatMap(e => e.filesModified).length,
        filesCreated: edits.flatMap(e => e.filesCreated).length,
        filesDeleted: edits.flatMap(e => e.filesDeleted).length,
        errors: workflow.errors.length
      });
      
      // Check if review is enabled
      if (this.isReviewEnabled(workflow)) {
        await this.transitionTo(workflow, 'review', 'Edits completed, starting review');
      } else {
        await this.transitionTo(workflow, 'complete', 'Edits completed, review skipped');
      }
      
    } catch (error) {
      this.handleError(workflow, error, 'edit');
    }
  }
  
  private async executeStep(
    editor: EditorAgent,
    step: PlanStep,
    workflow: WorkflowState
  ): Promise<EditResult> {
    workflow.currentStep = step.id;
    
    this.emitProgress(
      workflow,
      `Executing: ${step.description}`,
      workflow.progress
    );
    
    // Build edit task
    const editTask: EditTask = {
      stepId: step.id,
      fileOperations: step.fileOperations,
      context: {
        targetFiles: step.fileOperations.map(op => op.path),
        codeMap: workflow.plan?.steps || [],
        relevantSymbols: []
      }
    };
    
    // Execute editor
    const result = await editor.execute({
      task: editTask,
      workspace: this.workspace,
      sessionId: workflow.sessionId
    });
    
    if (!result.success) {
      return {
        filesModified: [],
        filesCreated: [],
        filesDeleted: [],
        diffs: [],
        errors: result.errors || [`Step ${step.id} failed`]
      };
    }
    
    return result.output as EditResult;
  }
  
  private async enterReviewMode(workflow: WorkflowState) {
    if (!workflow.plan || !workflow.edits) {
      throw new Error('Missing plan or edits for review');
    }
    
    this.emitProgress(workflow, 'Starting review phase...', 75);
    
    try {
      const reviewer = this.agents.get('reviewer') as ReviewerAgent;
      
      const reviewContext: ReviewContext = {
        plan: workflow.plan,
        edits: workflow.edits,
        originalContext: { task: workflow.task },
        successCriteria: workflow.plan.successCriteria
      };
      
      const result = await reviewer.execute({
        task: reviewContext,
        workspace: this.workspace,
        sessionId: workflow.sessionId
      });
      
      if (!result.success) {
        throw new Error('Review failed: ' + result.errors?.join(', '));
      }
      
      workflow.review = result.output as ReviewResult;
      this.saveWorkflow(workflow);
      
      // Log review results
      this.logEvent(workflow, 'review-completed', {
        passed: workflow.review.passed,
        score: workflow.review.score,
        issues: workflow.review.issues.length
      });
      
      if (workflow.review.passed) {
        this.emitProgress(workflow, 'Review passed', 95);
        await this.transitionTo(workflow, 'complete', 'Review passed');
      } else {
        this.emitProgress(workflow, 'Review found issues', 80);
        
        // Could loop back to edit mode for fixes
        if (this.shouldAutoFix(workflow.review)) {
          await this.transitionTo(workflow, 'edit', 'Auto-fixing review issues');
        } else {
          await this.transitionTo(workflow, 'complete', 'Review completed with issues');
        }
      }
      
    } catch (error) {
      this.handleError(workflow, error, 'review');
    }
  }
  
  private async enterCompleteMode(workflow: WorkflowState) {
    workflow.status = 'completed';
    workflow.progress = 100;
    workflow.currentStep = undefined;
    
    // Generate summary
    const summary = this.generateWorkflowSummary(workflow);
    
    // Save final state
    this.saveWorkflow(workflow);
    
    // Log completion
    this.logEvent(workflow, 'workflow-completed', summary);
    
    // Emit completion event
    this.emitEvent(workflow, 'workflow-completed', summary);
    
    // Clean up
    this.activeWorkflows.delete(workflow.id);
    
    // Clear any timers
    const timer = this.workflowTimers.get(workflow.id);
    if (timer) {
      clearTimeout(timer);
      this.workflowTimers.delete(workflow.id);
    }
    
    this.emitProgress(workflow, 'Workflow completed', 100);
  }
  
  private async transitionTo(
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
    
    // Save transition
    this.db.run(
      `INSERT INTO workflow_transitions (workflow_id, from_mode, to_mode, timestamp, reason)
       VALUES (?, ?, ?, ?, ?)`,
      [workflow.id, transition.from, transition.to, transition.timestamp, transition.reason]
    );
    
    // Save workflow state
    this.saveWorkflow(workflow);
    
    // Emit transition event
    this.emitEvent(workflow, 'mode-transition', transition);
    
    // Enter new mode
    switch (newMode) {
      case 'plan':
        await this.enterPlanMode(workflow);
        break;
      case 'edit':
        await this.enterEditMode(workflow);
        break;
      case 'review':
        await this.enterReviewMode(workflow);
        break;
      case 'complete':
        await this.enterCompleteMode(workflow);
        break;
    }
  }
  
  // External control methods
  async pauseWorkflow(workflowId: string): Promise<void> {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    if (workflow.status !== 'active') {
      throw new Error(`Cannot pause workflow in ${workflow.status} state`);
    }
    
    workflow.status = 'paused';
    this.activeWorkflows.delete(workflowId);
    this.saveWorkflow(workflow);
    
    this.emitEvent(workflow, 'workflow-paused', {});
  }
  
  async resumeWorkflow(workflowId: string): Promise<void> {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    if (workflow.status !== 'paused') {
      throw new Error(`Cannot resume workflow in ${workflow.status} state`);
    }
    
    workflow.status = 'active';
    this.activeWorkflows.add(workflowId);
    this.saveWorkflow(workflow);
    
    this.emitEvent(workflow, 'workflow-resumed', {});
    
    // Resume from current mode
    await this.transitionTo(workflow, workflow.mode, 'Resumed');
  }
  
  async cancelWorkflow(workflowId: string): Promise<void> {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) throw new Error('Workflow not found');
    
    workflow.status = 'failed';
    workflow.errors.push('Workflow cancelled by user');
    this.activeWorkflows.delete(workflowId);
    this.saveWorkflow(workflow);
    
    this.emitEvent(workflow, 'workflow-cancelled', {});
    
    // Clear any timers
    const timer = this.workflowTimers.get(workflowId);
    if (timer) {
      clearTimeout(timer);
      this.workflowTimers.delete(workflowId);
    }
  }
  
  async getWorkflow(workflowId: string): Promise<WorkflowState | null> {
    return this.workflows.get(workflowId) || null;
  }
  
  async getStatus(workflowId: string): Promise<WorkflowState | null> {
    return this.getWorkflow(workflowId);
  }
  
  getActiveWorkflows(): WorkflowState[] {
    return Array.from(this.activeWorkflows)
      .map(id => this.workflows.get(id)!)
      .filter(w => w != null);
  }
  
  // Helper methods
  private isReviewEnabled(workflow: WorkflowState): boolean {
    // Check configuration or workflow settings
    // For now, always enable review
    return true;
  }
  
  private shouldAutoFix(review: ReviewResult): boolean {
    // Only auto-fix if there are no critical issues
    const criticalIssues = review.issues.filter(i => i.severity === 'critical');
    return criticalIssues.length === 0 && review.score > 0.6;
  }
  
  private handleError(workflow: WorkflowState, error: any, phase: string) {
    console.error(`Error in ${phase} phase for workflow ${workflow.id}:`, error);
    
    workflow.status = 'failed';
    workflow.errors.push(`${phase} error: ${error.message}`);
    
    this.saveWorkflow(workflow);
    this.emitEvent(workflow, 'workflow-error', { phase, error: error.message });
    
    // Clean up
    this.activeWorkflows.delete(workflow.id);
  }
  
  private emitProgress(workflow: WorkflowState, message: string, percent: number) {
    workflow.progress = percent;
    
    const progress: WorkflowProgress = {
      workflowId: workflow.id,
      mode: workflow.mode,
      message,
      percent,
      step: workflow.currentStep
    };
    
    this.emit('progress', progress);
    this.logEvent(workflow, 'progress', progress);
  }
  
  private emitEvent(workflow: WorkflowState, event: string, data: any) {
    const workflowEvent: WorkflowEvent = {
      workflowId: workflow.id,
      sessionId: workflow.sessionId,
      event,
      data,
      timestamp: Date.now()
    };
    
    this.emit(event, workflowEvent);
  }
  
  private logEvent(workflow: WorkflowState, event: string, data: any) {
    this.db.run(
      `INSERT INTO workflow_events (workflow_id, session_id, event, data, timestamp)
       VALUES (?, ?, ?, ?, ?)`,
      [
        workflow.id,
        workflow.sessionId,
        event,
        JSON.stringify(data),
        Date.now()
      ]
    );
  }
  
  private saveWorkflow(workflow: WorkflowState) {
    this.db.run(
      `INSERT OR REPLACE INTO workflows 
       (id, session_id, task, mode, status, progress, plan, edits, review, start_time, end_time, errors)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        workflow.id,
        workflow.sessionId,
        workflow.task,
        workflow.mode,
        workflow.status,
        workflow.progress,
        workflow.plan ? JSON.stringify(workflow.plan) : null,
        workflow.edits ? JSON.stringify(workflow.edits) : null,
        workflow.review ? JSON.stringify(workflow.review) : null,
        workflow.startTime,
        workflow.status === 'completed' || workflow.status === 'failed' ? Date.now() : null,
        workflow.errors.length > 0 ? JSON.stringify(workflow.errors) : null
      ]
    );
  }
  
  private generateWorkflowSummary(workflow: WorkflowState): WorkflowSummary {
    const duration = Date.now() - workflow.startTime;
    
    const filesModified = workflow.edits?.flatMap(e => e.filesModified) || [];
    const filesCreated = workflow.edits?.flatMap(e => e.filesCreated) || [];
    const filesDeleted = workflow.edits?.flatMap(e => e.filesDeleted) || [];
    
    const stepsCompleted = workflow.edits?.length || 0;
    const totalSteps = workflow.plan?.steps.length || 0;
    
    const successCriteriaMet = workflow.review?.passed || false;
    
    return {
      id: workflow.id,
      task: workflow.task,
      status: workflow.status,
      duration,
      stepsCompleted,
      totalSteps,
      filesModified: [...new Set(filesModified)],
      filesCreated: [...new Set(filesCreated)],
      filesDeleted: [...new Set(filesDeleted)],
      errors: workflow.errors,
      successCriteriaMet,
      reviewScore: workflow.review?.score
    };
  }
}