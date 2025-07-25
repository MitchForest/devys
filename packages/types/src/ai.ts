// Define ToolInvocation locally to avoid dependency issues
export interface ToolInvocation {
  toolCallId: string;
  toolName: string;
  args: unknown;
  state: 'executing' | 'completed' | 'failed';
  result?: unknown;
}

// Core message types following AI SDK v5 conventions
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  toolInvocations?: ToolInvocation[];
  timestamp: Date; // For compatibility with existing UI
  createdAt?: Date;
  updatedAt?: Date;
  attachments?: FileAttachment[];
}

// Session types for chat persistence
export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  createdAt: Date;
  updatedAt: Date;
  status?: 'active' | 'completed' | 'error';
  model?: string;
  projectPath?: string;
  metadata?: Record<string, unknown>;
}

// File attachment for context
export interface FileAttachment {
  id: string; // Required for UI components
  path: string;
  name: string;
  content?: string;
  language?: string;
  selected?: boolean;
}

// AI Provider configuration
export interface AIProviderConfig {
  apiKey?: string;
  baseUrl?: string;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
}

// Streaming response types
export interface StreamingOptions {
  onStart?: () => void;
  onToken?: (token: string) => void;
  onCompletion?: (completion: string) => void;
  onError?: (error: Error) => void;
  onFinish?: (message: ChatMessage) => void;
}

// Tool types for AI SDK v5
export interface ToolDefinition {
  name: string;
  description: string;
  parameters: Record<string, unknown>; // JSON Schema
  execute: (args: unknown) => Promise<unknown>;
}

// Workflow types
export interface Workflow {
  id: string;
  name: string;
  description?: string;
  steps: WorkflowStep[];
  context?: Record<string, unknown>;
  createdAt: Date;
  updatedAt: Date;
}

export interface WorkflowStep {
  id: string;
  type: 'analyze' | 'plan' | 'execute' | 'verify';
  name: string;
  description?: string;
  input?: Record<string, unknown>;
  output?: Record<string, unknown>;
  status: 'pending' | 'running' | 'completed' | 'failed';
  error?: string;
}

// Agent types
export interface Agent {
  id: string;
  name: string;
  type: 'coordinator' | 'planner' | 'executor' | 'verifier' | 'specialist';
  description?: string;
  capabilities: string[];
  tools?: ToolDefinition[];
  systemPrompt?: string;
}

// Memory types
export interface Memory {
  id: string;
  type: 'conversation' | 'workflow' | 'project';
  content: string;
  metadata?: Record<string, unknown>;
  embedding?: number[];
  createdAt: Date;
  expiresAt?: Date;
}

// Project context types
export interface ProjectContext {
  projectPath: string;
  fileTree?: FileNode[];
  openFiles?: string[];
  recentFiles?: string[];
  gitBranch?: string;
  gitStatus?: GitFileStatus[];
}

export interface FileNode {
  id: string;
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: FileNode[];
  gitStatus?: GitStatus;
}

export type GitStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';

export interface GitFileStatus {
  path: string;
  status: GitStatus;
}

// Error types
export interface AIError extends Error {
  code: string;
  details?: Record<string, unknown>;
  retryable?: boolean;
}