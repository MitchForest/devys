export interface FileNode {
  id: string;
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: FileNode[];
  isExpanded?: boolean;
  gitStatus?: GitStatus;
}

export type GitStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';

export interface FileTab {
  id: string;
  path: string;
  name: string;
  content?: string;
  isDirty: boolean;
  language?: string;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
  attachments?: FileAttachment[];
}

export interface FileAttachment {
  path: string;
  name: string;
  content?: string;
}

export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  createdAt: Date;
  updatedAt: Date;
}

export interface WorkflowStep {
  id: string;
  type: 'ai-query' | 'command' | 'approval';
  status: 'pending' | 'running' | 'completed' | 'failed';
  config: Record<string, unknown>;
  result?: unknown;
  error?: string;
}

export interface Workflow {
  id: string;
  name: string;
  description: string;
  steps: WorkflowStep[];
  status: 'idle' | 'running' | 'completed' | 'failed';
  progress: number;
}

export interface ProjectContext {
  projectPath: string;
  projectType?: string;
  dependencies: string[];
  conventions: CodeConvention[];
  recentChanges: ChangeRecord[];
}

export interface CodeConvention {
  type: 'naming' | 'structure' | 'style';
  pattern: string;
  examples: string[];
}

export interface ChangeRecord {
  timestamp: Date;
  files: string[];
  description: string;
  author: string;
}

export interface TerminalSession {
  id: string;
  title: string;
  active: boolean;
  output: string[];
}