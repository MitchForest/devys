# Claude Code SDK Reference

This document serves as our reference for the Claude Code TypeScript SDK.

## Installation
```bash
npm install @anthropic-ai/claude-code
```

## Core API

### query Function
The main entry point for interacting with Claude Code.

```typescript
import { query } from '@anthropic-ai/claude-code';

const response = query({
  prompt: string | AsyncIterable<SDKUserMessage>,
  abortController?: AbortController,
  options?: Options
});

// Stream responses
for await (const message of response) {
  console.log(message);
}
```

### Options
```typescript
interface Options {
  // Execution control
  maxTurns?: number;         // Max conversation turns (default: 10)
  maxThinkingTokens?: number; // Max tokens for thinking
  
  // Tool permissions
  allowedTools?: string[];    // e.g., ['Read', 'Write', 'Bash(git:*)']
  disallowedTools?: string[]; // e.g., ['Bash(rm:*)']
  
  // System prompts
  customSystemPrompt?: string;
  appendSystemPrompt?: string;
  
  // Environment
  cwd?: string;              // Working directory
  executable?: 'bun' | 'deno' | 'node';
  executableArgs?: string[];
  
  // Model selection
  model?: 'opus' | 'sonnet';
  fallbackModel?: string;
  
  // MCP servers
  mcpServers?: Record<string, McpServerConfig>;
  
  // Permission modes
  permissionMode?: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';
  
  // Session control
  continue?: boolean;        // Continue previous session
  resume?: string;          // Resume specific session ID
  
  // Callbacks
  stderr?: (data: string) => void;
}
```

## Message Types

### SDKMessage Union
```typescript
type SDKMessage = 
  | SDKAssistantMessage
  | SDKUserMessage
  | SDKResultMessage
  | SDKSystemMessage;
```

### SDKAssistantMessage
```typescript
interface SDKAssistantMessage {
  type: 'assistant';
  message: {
    id: string;
    content: Array<{
      type: 'text';
      text: string;
    } | {
      type: 'tool_use';
      id: string;
      name: string;
      input: any;
    }>;
    role: 'assistant';
    model: string;
    usage?: Usage;
  };
  parent_tool_use_id: string | null;
  session_id: string;
}
```

### SDKUserMessage
```typescript
interface SDKUserMessage {
  type: 'user';
  message: {
    role: 'user';
    content: string | Array<ContentBlock>;
  };
  parent_tool_use_id: string | null;
  session_id: string;
}
```

### SDKResultMessage
```typescript
interface SDKResultMessage {
  type: 'result';
  subtype: 'success' | 'error_max_turns' | 'error_during_execution';
  duration_ms: number;
  duration_api_ms: number;
  is_error: boolean;
  num_turns: number;
  result?: string;         // Only for success
  session_id: string;
  total_cost_usd: number;
  usage: NonNullableUsage;
}
```

### SDKSystemMessage
```typescript
interface SDKSystemMessage {
  type: 'system';
  subtype: 'init';
  apiKeySource: 'user' | 'project' | 'org' | 'temporary';
  cwd: string;
  session_id: string;
  tools: string[];
  mcp_servers: Array<{
    name: string;
    status: string;
  }>;
  model: string;
  permissionMode: PermissionMode;
}
```

## Built-in Tools

Claude Code comes with powerful built-in tools:

### File Operations
- **Read**: Read file contents
- **Write**: Write/create files
- **FileEdit**: Edit specific parts of files
- **FileMultiEdit**: Multiple edits in one operation
- **Glob**: Find files by pattern
- **Grep**: Search file contents
- **LS**: List directory contents

### Code Operations
- **Bash**: Execute shell commands
- **BashOutput**: Get output from background shells
- **KillShell**: Terminate shell sessions

### Specialized Tools
- **Agent**: Spawn sub-agents for complex tasks
- **WebFetch**: Fetch and analyze web content
- **WebSearch**: Search the web
- **NotebookRead/Edit**: Jupyter notebook operations
- **TodoWrite**: Task management
- **ExitPlanMode**: Switch from planning to execution

### MCP (Model Context Protocol)
- **ListMcpResources**: List available MCP resources
- **ReadMcpResource**: Read MCP resource content
- **McpInput**: Execute MCP tool

## Tool Permission Syntax

```typescript
// Allow all instances of a tool
allowedTools: ['Read', 'Write']

// Allow specific command patterns
allowedTools: ['Bash(git:*)', 'Bash(npm:install)']

// Disallow dangerous operations
disallowedTools: ['Bash(rm:*)', 'Bash(sudo:*)']
```

## Session Management

### Continue Previous Session
```typescript
const response = query({
  prompt: 'Continue working on the feature',
  options: { continue: true }
});
```

### Resume Specific Session
```typescript
const response = query({
  prompt: 'Fix the bug we found',
  options: { resume: 'session-id-123' }
});
```

## Error Handling

```typescript
import { AbortError } from '@anthropic-ai/claude-code';

try {
  for await (const message of response) {
    // Process messages
  }
} catch (error) {
  if (error instanceof AbortError) {
    // Handle cancellation
  } else {
    // Handle other errors
  }
}
```

## MCP Server Configuration

```typescript
const options = {
  mcpServers: {
    filesystem: {
      command: 'mcp-server-filesystem',
      args: ['--root', '/path/to/files']
    },
    github: {
      type: 'sse',
      url: 'https://api.github.com/mcp',
      headers: { 'Authorization': 'Bearer token' }
    }
  }
};
```

## Best Practices

1. **Tool Permissions**: Be explicit about allowed/disallowed tools
2. **Working Directory**: Set `cwd` for file operations
3. **Max Turns**: Limit conversation turns to prevent runaway execution
4. **Error Handling**: Always handle AbortError for cancellations
5. **Session Management**: Use continue/resume for multi-step workflows

## Key Differences from Claude API

1. **Built-in Tools**: No need to define basic file/shell operations
2. **Streaming by Default**: All responses stream
3. **Session Aware**: Can continue/resume conversations
4. **Permission System**: Fine-grained control over tool usage
5. **Sub-Agents**: Can spawn specialized agents for subtasks
6. **MCP Support**: Integrate external data sources