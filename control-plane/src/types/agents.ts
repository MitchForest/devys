export interface AgentCapabilities {
  maxTokens: number;
  preferredModel: string;
  fallbackModels: string[];
  temperature: number;
  systemPromptTemplate: string;
  tools: string[];
}

export interface AgentContext {
  task: any;
  workspace: string;
  sessionId: string;
  previousResults?: any;
  constraints?: string[];
  successCriteria?: string[];
}

export interface AgentResult {
  success: boolean;
  output: any;
  tokensUsed: number;
  modelUsed: string;
  duration: number;
  errors?: string[];
  nextSteps?: string[];
}

export interface PlanStep {
  id: string;
  description: string;
  fileOperations: FileOperation[];
  dependencies: string[];
  estimatedTokens: number;
  assignedAgent: 'editor' | 'reviewer' | 'grunt';
}

export interface FileOperation {
  type: 'create' | 'edit' | 'delete' | 'move';
  path: string;
  description: string;
  priority: number;
}

export interface Plan {
  steps: PlanStep[];
  successCriteria: string[];
  estimatedTotalTokens: number;
  estimatedDuration: number;
  risks: string[];
  parallelGroups?: PlanStep[][];
}

export interface EditTask {
  stepId: string;
  fileOperations: FileOperation[];
  context: EditContext;
}

export interface EditContext {
  targetFiles: string[];
  codeMap: any;
  relevantSymbols: any[];
  examples?: CodeExample[];
}

export interface CodeExample {
  description: string;
  before: string;
  after: string;
}

export interface EditResult {
  filesModified: string[];
  filesCreated: string[];
  filesDeleted: string[];
  diffs: Diff[];
  errors: string[];
  tokensUsed?: number;
}

export interface Diff {
  file: string;
  lineStart: number;
  lineEnd: number;
  content: string;
}

export interface ReviewContext {
  plan: Plan;
  edits: EditResult[];
  originalContext: any;
  successCriteria: string[];
}

export interface ReviewResult {
  passed: boolean;
  score: number;
  issues: ReviewIssue[];
  suggestions: string[];
  testResults?: TestResult[];
}

export interface ReviewIssue {
  severity: 'critical' | 'warning' | 'info';
  file: string;
  line?: number;
  message: string;
  suggestedFix?: string;
}

export interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
  duration: number;
}

// New types for Phase 4 Grunt Agent
export interface GruntTask {
  type: 'format' | 'lint' | 'test' | 'commit' | 'docs' | 'cleanup';
  files?: string[];
  scope?: string;
  message?: string;
}

export interface GruntConfig {
  tasks: GruntTask[];
  preferLocal?: boolean;
  maxConcurrency?: number;
  budgetLimit?: number;
}

export interface TaskResult {
  type: string;
  status: 'success' | 'failed' | 'partial';
  files: string[];
  model: string;
  tokens: number;
  cost?: number;
  duration?: number;
  output?: string;
  error?: string;
  analysis?: string;
}

export interface GruntResult {
  results: TaskResult[];
  tokenUsage: number;
  cost: number;
  duration?: number;
  tasksCompleted: number;
  tasksSuccessful: number;
  error?: string;
}

export interface TaskClassifier {
  complexity: 'simple' | 'moderate' | 'complex';
  canParallelize: boolean;
  estimatedTokens: number;
  priority: 'low' | 'medium' | 'high';
}