export interface FileNode {
  id: string;
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: FileNode[];
  isExpanded?: boolean;
  gitStatus?: 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';
}

export interface FileTab {
  id: string;
  path: string;
  name: string;
  content?: string;
  isDirty: boolean;
  language?: string;
}

// Re-export AI types from ai.ts to avoid duplication
export {
  type ChatMessage,
  type FileAttachment,
  type ChatSession,
  type WorkflowStep,
  type Workflow,
  type Agent,
  type Memory,
  type ProjectContext,
  type AIError,
  type StreamingOptions,
  type ToolDefinition,
  type GitStatus,
  type GitFileStatus,
  // FileNode is already defined in this file
} from '../ai';

export interface ToolResult {
  tool_use_id: string;
  content: any;
}

export interface AIRequest {
  messages: any[];
  tools?: any[];
  temperature?: number;
  max_tokens?: number;
}

export interface AIResponse {
  content: string;
  tool_calls?: any[];
}

export interface ServerStatus {
  connected: boolean;
  error?: string;
}

export interface TerminalSession {
  id: string;
  title: string;
  isActive: boolean;
  command?: string;
  cwd?: string;
  output?: string[];
}