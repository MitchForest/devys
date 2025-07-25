/**
 * Claude Code tools wrapped for AI SDK v5
 * 
 * IMPORTANT: These are "stub" tools that exist only to inform the AI SDK
 * about Claude Code's tool capabilities. The actual tool execution happens
 * inside Claude Code SDK. These tools should NOT execute any actual operations.
 * 
 * The purpose is to:
 * 1. Allow AI SDK to parse and display tool calls in the UI
 * 2. Enable approval workflows before Claude Code executes tools
 * 3. Provide type safety for tool parameters
 */

import { tool } from 'ai';
import { z } from 'zod';

/**
 * Stub execute function for all Claude Code tools
 * These tools are display-only - actual execution happens in Claude Code
 */
const stubExecute = async (input: unknown) => {
  // Log for debugging
  // eslint-disable-next-line no-console
  console.log('Claude Code tool called:', input);
  // Return a placeholder - Claude Code handles the real execution
  return { 
    status: 'handled-by-claude-code',
    note: 'Tool execution is handled internally by Claude Code SDK'
  };
};

// File Operations

export const readTool = tool({
  description: 'Read the contents of a file',
  inputSchema: z.object({
    file_path: z.string().describe('The path to the file to read'),
    limit: z.number().optional().describe('Maximum number of lines to read'),
    offset: z.number().optional().describe('Line number to start reading from'),
  }),
  execute: stubExecute,
});

export const writeTool = tool({
  description: 'Write content to a file (creates or overwrites)',
  inputSchema: z.object({
    file_path: z.string().describe('The path to the file to write'),
    content: z.string().describe('The content to write to the file'),
  }),
  execute: stubExecute,
});

export const editTool = tool({
  description: 'Edit a specific part of a file',
  inputSchema: z.object({
    file_path: z.string().describe('The path to the file to edit'),
    old_string: z.string().describe('The exact text to replace'),
    new_string: z.string().describe('The new text to insert'),
    replace_all: z.boolean().optional().describe('Replace all occurrences'),
  }),
  execute: stubExecute,
});

export const multiEditTool = tool({
  description: 'Make multiple edits to a file in one operation',
  inputSchema: z.object({
    file_path: z.string().describe('The path to the file to edit'),
    edits: z.array(z.object({
      old_string: z.string(),
      new_string: z.string(),
      replace_all: z.boolean().optional(),
    })).describe('Array of edits to apply'),
  }),
  execute: stubExecute,
});

// Search Operations

export const grepTool = tool({
  description: 'Search for patterns in files using ripgrep',
  inputSchema: z.object({
    pattern: z.string().describe('The regex pattern to search for'),
    path: z.string().optional().describe('Directory or file to search in'),
    glob: z.string().optional().describe('Glob pattern to filter files'),
    type: z.string().optional().describe('File type to search (e.g., js, py)'),
    output_mode: z.enum(['content', 'files_with_matches', 'count']).optional(),
    '-n': z.boolean().optional().describe('Show line numbers'),
    '-i': z.boolean().optional().describe('Case insensitive search'),
  }),
  execute: stubExecute,
});

export const globTool = tool({
  description: 'Find files matching a pattern',
  inputSchema: z.object({
    pattern: z.string().describe('The glob pattern to match'),
    path: z.string().optional().describe('Directory to search in'),
  }),
  execute: stubExecute,
});

export const lsTool = tool({
  description: 'List files and directories',
  inputSchema: z.object({
    path: z.string().describe('The directory to list'),
    ignore: z.array(z.string()).optional().describe('Patterns to ignore'),
  }),
  execute: stubExecute,
});

// Terminal Operations

export const bashTool = tool({
  description: 'Execute bash commands',
  inputSchema: z.object({
    command: z.string().describe('The command to execute'),
    description: z.string().optional().describe('What this command does'),
    timeout: z.number().optional().describe('Timeout in milliseconds'),
  }),
  execute: stubExecute,
});

// Special Tools

export const agentTool = tool({
  description: 'Spawn a sub-agent for complex tasks',
  inputSchema: z.object({
    description: z.string().describe('Task description'),
    prompt: z.string().describe('The task for the agent'),
    subagent_type: z.string().describe('Type of specialized agent'),
  }),
  execute: stubExecute,
});

export const webFetchTool = tool({
  description: 'Fetch and analyze web content',
  inputSchema: z.object({
    url: z.string().url().describe('The URL to fetch'),
    prompt: z.string().describe('What to extract from the page'),
  }),
  execute: stubExecute,
});

export const webSearchTool = tool({
  description: 'Search the web for information',
  inputSchema: z.object({
    query: z.string().describe('The search query'),
    allowed_domains: z.array(z.string()).optional(),
    blocked_domains: z.array(z.string()).optional(),
  }),
  execute: stubExecute,
});

export const todoWriteTool = tool({
  description: 'Manage a todo list for tracking tasks',
  inputSchema: z.object({
    todos: z.array(z.object({
      id: z.string(),
      content: z.string(),
      status: z.enum(['pending', 'in_progress', 'completed']),
      priority: z.enum(['high', 'medium', 'low']),
    })).describe('The updated todo list'),
  }),
  execute: stubExecute,
});

// Notebook Operations

export const notebookReadTool = tool({
  description: 'Read a Jupyter notebook',
  inputSchema: z.object({
    notebook_path: z.string().describe('Path to the notebook'),
    cell_id: z.string().optional().describe('Specific cell to read'),
  }),
  execute: stubExecute,
});

export const notebookEditTool = tool({
  description: 'Edit a Jupyter notebook cell',
  inputSchema: z.object({
    notebook_path: z.string().describe('Path to the notebook'),
    new_source: z.string().describe('New cell content'),
    cell_id: z.string().optional(),
    cell_type: z.enum(['code', 'markdown']).optional(),
    edit_mode: z.enum(['replace', 'insert', 'delete']).optional(),
  }),
  execute: stubExecute,
});

// Plan Mode

export const exitPlanModeTool = tool({
  description: 'Exit planning mode and start implementation',
  inputSchema: z.object({
    plan: z.string().describe('The plan to execute'),
  }),
  execute: stubExecute,
});

/**
 * All Claude Code tools for use with AI SDK v5
 */
export const claudeCodeTools = {
  // File Operations
  Read: readTool,
  Write: writeTool,
  FileEdit: editTool,
  FileMultiEdit: multiEditTool,
  
  // Search Operations
  Grep: grepTool,
  Glob: globTool,
  LS: lsTool,
  
  // Terminal Operations
  Bash: bashTool,
  
  // Special Tools
  Agent: agentTool,
  WebFetch: webFetchTool,
  WebSearch: webSearchTool,
  TodoWrite: todoWriteTool,
  
  // Notebook Operations
  NotebookRead: notebookReadTool,
  NotebookEdit: notebookEditTool,
  
  // Plan Mode
  ExitPlanMode: exitPlanModeTool,
};

/**
 * Tool names that require user approval before execution
 */
export const APPROVAL_REQUIRED_TOOLS = [
  'Write',
  'FileEdit',
  'FileMultiEdit',
  'Bash',
  'Agent',
  'NotebookEdit',
];

/**
 * Check if a tool requires approval
 */
export function requiresApproval(toolName: string): boolean {
  return APPROVAL_REQUIRED_TOOLS.includes(toolName);
}