import { Plan, EditResult, ReviewResult } from './agents';

export type WorkflowMode = 'plan' | 'edit' | 'review' | 'complete';
export type WorkflowStatus = 'active' | 'paused' | 'completed' | 'failed';

export interface WorkflowState {
  id: string;
  mode: WorkflowMode;
  sessionId: string;
  task: string;
  plan?: Plan;
  edits?: EditResult[];
  review?: ReviewResult;
  startTime: number;
  transitions: ModeTransition[];
  status: WorkflowStatus;
  progress: number; // 0-100
  currentStep?: string;
  errors: string[];
}

export interface ModeTransition {
  from: WorkflowMode;
  to: WorkflowMode;
  timestamp: number;
  reason: string;
  data?: any;
}

export interface WorkflowEvent {
  workflowId: string;
  sessionId: string;
  event: string;
  data: any;
  timestamp: number;
}

export interface WorkflowProgress {
  workflowId: string;
  mode: WorkflowMode;
  message: string;
  percent: number;
  step?: string;
}

export interface WorkflowSummary {
  id: string;
  task: string;
  status: WorkflowStatus;
  duration: number;
  stepsCompleted: number;
  totalSteps: number;
  filesModified: string[];
  filesCreated: string[];
  filesDeleted: string[];
  errors: string[];
  successCriteriaMet: boolean;
  reviewScore?: number;
}

// New types for Phase 4 Integrated Workflow
export interface IntegratedWorkflowResult {
  workflowId: string;
  success: boolean;
  phases: WorkflowPhase[];
  metrics: WorkflowMetrics;
  duration: number;
  error?: string;
}

export interface WorkflowPhase {
  phase: 'plan' | 'edit' | 'review' | 'grunt';
  success: boolean;
  model: string;
  tokensUsed: number;
  cost: number;
  duration: number;
  plan?: any;
  edits?: any;
  review?: any;
  grunt?: any;
  stepId?: string;
  errors?: string[];
}

export interface WorkflowMetrics {
  workflowId: string;
  totalTokens: number;
  totalCost: number;
  duration: number;
  phaseCounts: {
    plan: number;
    edit: number;
    review: number;
    grunt: number;
  };
  modelUsage: Map<string, number>;
}