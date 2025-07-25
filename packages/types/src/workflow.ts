export interface WorkflowConfig {
  version: string;
  name: string;
  description: string;
  steps: WorkflowStep[];
}

export interface WorkflowStep {
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
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  startedAt: Date;
  completedAt?: Date;
  currentStep?: string;
  progress: number; // 0-100
  results: StepResult[];
  error?: string;
}

export interface StepResult {
  stepId: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'skipped';
  startedAt?: Date;
  completedAt?: Date;
  output?: unknown;
  error?: string;
  toolInvocations?: ToolInvocation[];
}

export interface ToolInvocation {
  toolName: string;
  args: Record<string, unknown>;
  result?: unknown;
  approved?: boolean;
  timestamp: Date;
}

export interface WorkflowSummary {
  id: string;
  timestamp: string;
  request: string;
  outcome: string;
  filesChanged: string[];
  keyDecisions: Decision[];
  lessonsLearned: string[];
}

export interface Decision {
  id: string;
  description: string;
  reasoning: string;
  alternatives?: string[];
}

export interface ProjectContext {
  projectType: string;
  conventions: Convention[];
  dependencies: Dependency[];
  recentChanges: Change[];
  knownIssues: Issue[];
}

export interface Convention {
  type: 'naming' | 'structure' | 'style' | 'pattern';
  description: string;
  examples: string[];
}

export interface Dependency {
  name: string;
  version: string;
  type: 'runtime' | 'dev';
}

export interface Change {
  timestamp: string;
  description: string;
  files: string[];
}

export interface Issue {
  id: string;
  description: string;
  severity: 'low' | 'medium' | 'high';
  status: 'open' | 'resolved';
}