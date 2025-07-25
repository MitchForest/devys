export interface FileTab {
  id: string;
  path: string;
  name: string;
  content?: string;
  isDirty: boolean;
  language?: string;
}

// Import AI types from ai.ts
import type {
  ChatMessage,
  FileAttachment,
  ChatSession,
  WorkflowStep,
  Workflow,
  Agent,
  Memory,
  ProjectContext,
  AIError,
  StreamingOptions,
  ToolDefinition,
  ToolInvocation,
  GitStatus,
  GitFileStatus,
  FileNode
} from '../ai';

// Re-export AI types
export type {
  ChatMessage,
  FileAttachment,
  ChatSession,
  WorkflowStep,
  Workflow,
  Agent,
  Memory,
  ProjectContext,
  AIError,
  StreamingOptions,
  ToolDefinition,
  ToolInvocation,
  GitStatus,
  GitFileStatus,
  FileNode
};

export interface ToolResult {
  tool_use_id: string;
  content: unknown;
}

export interface AIRequest {
  messages: ChatMessage[];
  tools?: ToolDefinition[];
  temperature?: number;
  max_tokens?: number;
}

export interface AIResponse {
  content: string;
  tool_calls?: ToolInvocation[];
}

export interface ServerStatus {
  connected: boolean;
  error?: string;
}

export interface TerminalSession {
  id: string;
  title: string;
  active?: boolean; // Optional for backward compatibility
  isActive?: boolean; // Support both naming conventions
  command?: string;
  cwd?: string; // Optional for backward compatibility
  output: string[];
}