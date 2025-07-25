// Workflow Engine specific types for Phase 1
// These extend the basic workflow types in ai.ts

export interface WorkflowConfig {
  version: string;
  name: string;
  description: string;
  steps: WorkflowStepConfig[];
}

export interface WorkflowStepConfig {
  id: string;
  type: 'ai-query' | 'ai-tool' | 'conditional' | 'parallel';
  config: StepConfig;
  depends_on?: string[]; // IDs of steps that must complete before this one
}

export interface StepConfig {
  systemPrompt?: string;
  tools?: string[];
  maxTurns?: number;
  requiresApproval?: boolean;
  condition?: string; // For conditional steps
  branches?: WorkflowBranch[]; // For conditional steps
  parallelSteps?: string[]; // For parallel steps
}

export interface WorkflowBranch {
  condition: string;
  stepId: string;
}

export interface WorkflowExecution {
  id: string;
  workflowId: string;
  workflowName: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  startedAt: Date;
  completedAt?: Date;
  currentStep?: string;
  progress: number; // 0-100
  results: StepResult[];
  error?: string;
  sessionId?: string; // Link to chat session if applicable
}

export interface StepResult {
  stepId: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'skipped' | 'awaiting-approval';
  startedAt?: Date;
  completedAt?: Date;
  output?: unknown;
  error?: string;
  toolInvocations?: ToolInvocationRecord[];
  messagesGenerated?: number;
}

export interface ToolInvocationRecord {
  toolName: string;
  args: Record<string, unknown>;
  result?: unknown;
  approved?: boolean;
  timestamp: Date;
}

// Workflow progress events for real-time updates
export interface WorkflowProgressEvent {
  executionId: string;
  type: 'started' | 'step-started' | 'step-completed' | 'tool-invoked' | 'approval-required' | 'completed' | 'failed';
  stepId?: string;
  progress: number;
  message?: string;
  data?: unknown;
}

// Approval request for steps that require user confirmation
export interface WorkflowApprovalRequest {
  executionId: string;
  stepId: string;
  description: string;
  plannedActions: PlannedAction[];
  timestamp: Date;
}

export interface PlannedAction {
  type: 'file-write' | 'file-delete' | 'command-run' | 'tool-invoke';
  description: string;
  details: Record<string, unknown>;
}

// Memory and context types for workflow execution
export interface WorkflowSummary {
  id: string;
  executionId: string;
  timestamp: string;
  request: string;
  outcome: string;
  filesChanged: string[];
  keyDecisions: Decision[];
  lessonsLearned: string[];
}

export interface Decision {
  id: string;
  stepId: string;
  description: string;
  reasoning: string;
  alternatives?: string[];
}

// Built-in workflow templates
export const WORKFLOW_TEMPLATES = {
  ANALYZE_EXECUTE: 'analyze-execute',
  CODE_REVIEW: 'code-review',
  DEBUG_FIX: 'debug-fix',
  REFACTOR: 'refactor',
  TEST_GENERATION: 'test-generation'
} as const;

export type WorkflowTemplate = typeof WORKFLOW_TEMPLATES[keyof typeof WORKFLOW_TEMPLATES];