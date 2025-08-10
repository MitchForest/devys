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