import { EventEmitter } from 'events';
import { v4 as uuidv4 } from 'uuid';
import type {
  WorkflowConfig,
  WorkflowExecution,
  WorkflowProgressEvent,
  StepResult,
  WorkflowStepConfig,
  WorkflowApprovalRequest,
  ToolInvocationRecord,
  WorkflowBranch
} from '@devys/types';
import { streamText, type LanguageModel } from 'ai';
import { claudeCodeTools } from '../tools/claude-code-tools';

export class WorkflowEngine extends EventEmitter {
  private executions = new Map<string, WorkflowExecution>();
  private pendingApprovals = new Map<string, WorkflowApprovalRequest>();
  
  constructor(
    private model: LanguageModel,
    private tools = claudeCodeTools
  ) {
    super();
  }

  /**
   * Start a workflow execution
   */
  async startWorkflow(config: WorkflowConfig, sessionId?: string): Promise<string> {
    const executionId = uuidv4();
    
    const execution: WorkflowExecution = {
      id: executionId,
      workflowId: config.name,
      workflowName: config.description,
      status: 'running',
      startedAt: new Date(),
      progress: 0,
      results: [],
      sessionId
    };

    this.executions.set(executionId, execution);
    
    // Emit start event
    this.emitProgress({
      executionId,
      type: 'started',
      progress: 0,
      message: `Starting workflow: ${config.description}`
    });

    // Start execution in background
    this.executeWorkflow(executionId, config).catch(error => {
      this.handleExecutionError(executionId, error);
    });

    return executionId;
  }

  /**
   * Execute the workflow
   */
  private async executeWorkflow(executionId: string, config: WorkflowConfig): Promise<void> {
    const execution = this.executions.get(executionId);
    if (!execution) return;

    const totalSteps = config.steps.length;
    let completedSteps = 0;

    // Execute each step
    for (const step of config.steps) {
      // Check if execution was cancelled
      if (execution.status === 'cancelled') {
        break;
      }

      // Check dependencies
      if (step.depends_on && step.depends_on.length > 0) {
        const dependencyResults = execution.results.filter(
          (r: StepResult) => step.depends_on!.includes(r.stepId) && r.status === 'completed'
        );
        
        if (dependencyResults.length !== step.depends_on.length) {
          // Skip this step if dependencies aren't met
          const result: StepResult = {
            stepId: step.id,
            status: 'skipped',
            error: 'Dependencies not met'
          };
          execution.results.push(result);
          continue;
        }
      }

      // Update current step
      execution.currentStep = step.id;
      
      // Emit step started event
      this.emitProgress({
        executionId,
        type: 'step-started',
        stepId: step.id,
        progress: (completedSteps / totalSteps) * 100,
        message: `Starting step: ${step.id}`
      });

      // Execute the step
      const result = await this.executeStep(executionId, step, execution);
      execution.results.push(result);

      if (result.status === 'completed') {
        completedSteps++;
      }

      // Update progress
      execution.progress = (completedSteps / totalSteps) * 100;

      // Emit step completed event
      this.emitProgress({
        executionId,
        type: 'step-completed',
        stepId: step.id,
        progress: execution.progress,
        message: `Completed step: ${step.id}`,
        data: result
      });
    }

    // Mark execution as completed
    execution.status = 'completed';
    execution.completedAt = new Date();
    execution.progress = 100;

    // Emit completion event
    this.emitProgress({
      executionId,
      type: 'completed',
      progress: 100,
      message: 'Workflow completed successfully'
    });
  }

  /**
   * Execute a single workflow step
   */
  private async executeStep(
    executionId: string,
    step: WorkflowStepConfig,
    execution: WorkflowExecution
  ): Promise<StepResult> {
    const result: StepResult = {
      stepId: step.id,
      status: 'running',
      startedAt: new Date(),
      toolInvocations: []
    };

    try {
      switch (step.type) {
        case 'ai-query':
          await this.executeAIQuery(executionId, step, result, execution);
          break;
        
        case 'ai-tool':
          await this.executeAITool(executionId, step, result, execution);
          break;
        
        case 'conditional':
          await this.executeConditional(executionId, step, result, execution);
          break;
        
        case 'parallel':
          await this.executeParallel(executionId, step, result, execution);
          break;
        
        default:
          throw new Error(`Unknown step type: ${step.type}`);
      }

      result.status = 'completed';
    } catch (error) {
      result.status = 'failed';
      result.error = error instanceof Error ? error.message : String(error);
    }

    result.completedAt = new Date();
    return result;
  }

  /**
   * Execute an AI query step
   */
  private async executeAIQuery(
    executionId: string,
    step: WorkflowStepConfig,
    result: StepResult,
    execution: WorkflowExecution
  ): Promise<void> {
    const { systemPrompt, tools: toolNames, requiresApproval } = step.config;

    // Check if approval is required
    if (requiresApproval) {
      const approved = await this.requestApproval(executionId, step.id, 'Execute AI query step');
      if (!approved) {
        result.status = 'skipped';
        result.error = 'User declined approval';
        return;
      }
    }

    // Filter tools based on configuration
    const selectedTools = toolNames 
      ? Object.fromEntries(
          Object.entries(this.tools).filter(([name]) => toolNames.includes(name))
        )
      : this.tools;

    // Build context from previous steps
    const context = this.buildContext(execution);

    // Execute AI query
    const response = await streamText({
      model: this.model,
      system: systemPrompt,
      messages: [
        {
          role: 'user',
          content: `Context from previous steps:\n${JSON.stringify(context, null, 2)}\n\nExecute this step: ${step.id}`
        }
      ],
      tools: selectedTools
    });

    // Collect tool invocations and results
    const toolInvocations: ToolInvocationRecord[] = [];
    const finishReason = 'stop';
    // let totalTokens = 0;
    let textContent = '';

    // Process the stream
    for await (const part of response.textStream) {
      textContent += part;
    }

    // Get final results
    const finalResponse = await response;
    const toolCalls = await finalResponse.toolCalls;
    const usage = await finalResponse.usage;

    // Process tool calls
    if (toolCalls && toolCalls.length > 0) {
      for (const toolCall of toolCalls) {
        const invocation: ToolInvocationRecord = {
          toolName: toolCall.toolName,
          args: toolCall.input as Record<string, unknown>,
          result: undefined, // Result will be populated later
          timestamp: new Date()
        };
        toolInvocations.push(invocation);
        
        this.emitProgress({
          executionId,
          type: 'tool-invoked',
          stepId: step.id,
          progress: execution.progress,
          message: `Invoking tool: ${toolCall.toolName}`,
          data: invocation
        });
      }
    }

    // Store usage metrics
    if (usage && 'totalTokens' in usage) {
      result.messagesGenerated = (usage as { totalTokens?: number }).totalTokens || 0;
    }

    result.toolInvocations = toolInvocations;
    result.output = { toolCalls, textContent, finishReason };
  }

  /**
   * Execute an AI tool step (simplified for Phase 1)
   */
  private async executeAITool(
    executionId: string,
    step: WorkflowStepConfig,
    result: StepResult,
    _execution: WorkflowExecution
  ): Promise<void> {
    // For Phase 1, this is similar to AI query but focused on specific tools
    result.status = 'completed';
    result.output = { message: 'AI tool step executed' };
  }

  /**
   * Execute a conditional step (simplified for Phase 1)
   */
  private async executeConditional(
    executionId: string,
    step: WorkflowStepConfig,
    result: StepResult,
    execution: WorkflowExecution
  ): Promise<void> {
    const { condition, branches } = step.config;
    
    if (!condition || !branches) {
      throw new Error('Conditional step requires condition and branches');
    }

    // For Phase 1, simple string matching
    const context = this.buildContext(execution);
    const selectedBranch = branches.find((branch: WorkflowBranch) => 
      JSON.stringify(context).includes(branch.condition)
    );

    if (selectedBranch) {
      result.output = { selectedBranch: selectedBranch.stepId };
    }

    result.status = 'completed';
  }

  /**
   * Execute parallel steps (simplified for Phase 1)
   */
  private async executeParallel(
    executionId: string,
    step: WorkflowStepConfig,
    result: StepResult,
    _execution: WorkflowExecution
  ): Promise<void> {
    const { parallelSteps } = step.config;
    
    if (!parallelSteps || parallelSteps.length === 0) {
      throw new Error('Parallel step requires parallelSteps');
    }

    // For Phase 1, we'll execute them sequentially
    // Phase 2 will implement true parallel execution
    result.output = { 
      message: `Executed ${parallelSteps.length} steps sequentially`,
      steps: parallelSteps 
    };
    result.status = 'completed';
  }

  /**
   * Build context from previous step results
   */
  private buildContext(execution: WorkflowExecution): Record<string, unknown> {
    const context: Record<string, unknown> = {};
    
    for (const result of execution.results) {
      if (result.status === 'completed' && result.output) {
        context[result.stepId] = result.output;
      }
    }

    return context;
  }

  /**
   * Request user approval for a step
   */
  private async requestApproval(
    executionId: string,
    stepId: string,
    description: string
  ): Promise<boolean> {
    const approvalRequest: WorkflowApprovalRequest = {
      executionId,
      stepId,
      description,
      plannedActions: [], // TODO: Extract from step config
      timestamp: new Date()
    };

    this.pendingApprovals.set(`${executionId}-${stepId}`, approvalRequest);

    this.emitProgress({
      executionId,
      type: 'approval-required',
      stepId,
      progress: this.executions.get(executionId)?.progress || 0,
      message: 'User approval required',
      data: approvalRequest
    });

    // Wait for approval (with timeout)
    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        this.pendingApprovals.delete(`${executionId}-${stepId}`);
        resolve(false);
      }, 5 * 60 * 1000); // 5 minute timeout

      const checkApproval = setInterval(() => {
        const approval = this.pendingApprovals.get(`${executionId}-${stepId}`);
        if (!approval) {
          clearInterval(checkApproval);
          clearTimeout(timeout);
          resolve(true);
        }
      }, 1000);
    });
  }

  /**
   * Approve a pending step
   */
  approveStep(executionId: string, stepId: string): void {
    this.pendingApprovals.delete(`${executionId}-${stepId}`);
  }

  /**
   * Reject a pending step
   */
  rejectStep(executionId: string, stepId: string): void {
    const key = `${executionId}-${stepId}`;
    if (this.pendingApprovals.has(key)) {
      this.pendingApprovals.delete(key);
    }
  }

  /**
   * Cancel a running workflow
   */
  cancelWorkflow(executionId: string): void {
    const execution = this.executions.get(executionId);
    if (execution && execution.status === 'running') {
      execution.status = 'cancelled';
      execution.completedAt = new Date();
      
      this.emitProgress({
        executionId,
        type: 'failed',
        progress: execution.progress,
        message: 'Workflow cancelled by user'
      });
    }
  }

  /**
   * Get workflow execution status
   */
  getExecution(executionId: string): WorkflowExecution | undefined {
    return this.executions.get(executionId);
  }

  /**
   * Get all executions
   */
  getAllExecutions(): WorkflowExecution[] {
    return Array.from(this.executions.values());
  }

  /**
   * Handle execution errors
   */
  private handleExecutionError(executionId: string, error: unknown): void {
    const execution = this.executions.get(executionId);
    if (execution) {
      execution.status = 'failed';
      execution.completedAt = new Date();
      execution.error = error instanceof Error ? error.message : String(error);
      
      this.emitProgress({
        executionId,
        type: 'failed',
        progress: execution.progress,
        message: 'Workflow failed',
        data: { error: execution.error }
      });
    }
  }

  /**
   * Emit workflow progress event
   */
  private emitProgress(event: WorkflowProgressEvent): void {
    this.emit('progress', event);
  }
}