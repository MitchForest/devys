# Phase 2 Implementation Plan: Claude Code Chat UI Integration

## Executive Summary

This plan synthesizes the requirements from the prompt and adapts them to the existing Devys codebase, which already has:
- A working ClaudeCodeLanguageModel implementation using AI SDK v5
- A chat interface using AI SDK v5's useChat hook
- A Hono server with chat endpoints
- CodeMirror and xterm integration

## Current State Analysis

### What We Have
1. **Claude Code Integration** (`packages/core/src/providers/claude-code-language-model.ts`)
   - Working AI SDK v5 LanguageModelV2 implementation
   - Streaming support with proper tool call handling
   - Session support via sessionId parameter
   - Tool routing (e.g., Bash commands to terminal)

2. **Chat UI** (`packages/ui/src/components/chat/chat-interface.tsx`)
   - Uses AI SDK v5's useChat hook
   - Handles streaming messages
   - File attachment support

3. **Server** (`apps/server/src/routes/chat.ts`)
   - Hono-based chat endpoint
   - Session management with SQLite
   - File attachment processing

### What We Need to Add
1. **Enhanced Session Management**
   - `.pm` folder structure for project management
   - Session documentation and tracking

2. **Sub-Agent Orchestration**
   - Planner/orchestrator agent
   - Worker agents for specific tasks
   - Communication between agents

3. **Hooks System**
   - Pre/post tool execution hooks
   - Quality gates (testing, linting, typechecking)
   - TDD workflow support

4. **Command Palette Integration**
   - Slash commands
   - Agent selection
   - Workflow triggering

## Implementation Phases

### Phase 1: Enhanced Claude Code Provider (Priority: High)

**Goal**: Extend the existing ClaudeCodeLanguageModel to support all Claude Code SDK features

```typescript
// packages/core/src/providers/claude-code-language-model.ts
export interface ClaudeCodeLanguageModelSettings {
  // ... existing settings ...
  
  // New settings
  outputFormat?: 'text' | 'json' | 'stream-json';
  print?: boolean;
  resume?: string;
  continue?: boolean;
  allowedTools?: string;
  disallowedTools?: string;
  mcpConfig?: string;
  permissionPromptTool?: string;
  dangerouslySkipPermissions?: boolean;
  dangerouslyAssumeYesToAllPrompts?: boolean;
  memoryPaths?: string[];
  hooks?: {
    preToolUse?: (tool: string, input: any) => Promise<{ allow: boolean; input?: any }>;
    postToolUse?: (tool: string, result: any) => Promise<void>;
    stop?: () => Promise<{ allow: boolean; reason?: string }>;
  };
}
```

**Implementation Steps**:
1. Update the settings interface with all CLI flags
2. Pass these settings to the SDK query function
3. Add hook execution logic in the streaming handler
4. Implement MCP configuration loading

### Phase 2: Session Management & Project Documentation (Priority: High)

**Goal**: Create `.pm` folder structure and session tracking

```typescript
// packages/core/src/services/project-manager.ts
export class ProjectManager {
  constructor(private projectPath: string) {}
  
  async createSession(sessionId: string): Promise<void> {
    // Create .pm/sessions/{sessionId}/ folder
    // Initialize session.md with metadata
  }
  
  async logToolExecution(sessionId: string, tool: string, input: any, result: any): Promise<void> {
    // Append to session.md
    // Track files created/modified/deleted
  }
  
  async finalizeSession(sessionId: string, summary: string): Promise<void> {
    // Generate final report
    // Update index.md with session link
  }
}
```

**Folder Structure**:
```
.pm/
├── index.md                    # Session index
├── sessions/
│   ├── {session-id}/
│   │   ├── session.md         # Session log
│   │   ├── files-changed.md   # List of affected files
│   │   └── artifacts/         # Generated diagrams, reports
│   └── ...
└── agents/
    ├── planner.md             # Planner agent config
    └── workers/               # Worker agent configs
```

### Phase 3: Sub-Agent System (Priority: High)

**Goal**: Implement agent orchestration with Claude Code sub-agents

```typescript
// packages/core/src/services/sub-agent-manager.ts
export class SubAgentManager {
  private agents: Map<string, SubAgent> = new Map();
  
  async registerAgent(name: string, config: SubAgentConfig): Promise<void> {
    // Create .claude/agents/{name}.md
    // Register agent with specific tools
  }
  
  async delegateTask(agentName: string, task: string, context: any): Promise<any> {
    // Create new Claude Code instance with agent config
    // Execute task with limited context
    // Return results to orchestrator
  }
}
```

**Agent Types**:
1. **Planner Agent**: High-level planning, task breakdown
2. **Implementation Agent**: Code writing with specific tools
3. **Test Runner**: Test execution and validation
4. **QA Reviewer**: Code review and quality checks
5. **Documentation Agent**: Update docs and comments

### Phase 4: Hooks System (Priority: Medium)

**Goal**: Implement quality gates and automated workflows

```typescript
// packages/core/src/services/hooks-manager.ts
export class HooksManager {
  async executePreToolHook(tool: string, input: any): Promise<HookResult> {
    // Load hooks from .claude/settings.json
    // Execute hook commands
    // Return allow/deny decision
  }
  
  async executePostToolHook(tool: string, result: any): Promise<void> {
    // Run linting/formatting after file edits
    // Update project manager logs
  }
  
  async executeStopHook(context: any): Promise<{ allow: boolean; reason?: string }> {
    // Check if tests pass
    // Verify typecheck status
    // Block stop if quality gates fail
  }
}
```

**Hook Configuration** (`.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "bun run check"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "bun run lint:fix"
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bun test"
      }]
    }]
  }
}
```

### Phase 5: Enhanced Chat UI (Priority: Medium)

**Goal**: Add command palette and agent selection to chat interface

```typescript
// packages/ui/src/components/chat/command-palette.tsx
export function CommandPalette({ onCommand }: CommandPaletteProps) {
  // Slash command detection
  // Agent selection UI
  // Custom command execution
}
```

**UI Enhancements**:
1. Command palette overlay (Cmd+K)
2. Agent selector in chat header
3. Session info display
4. Tool execution visualization
5. File change indicators

### Phase 6: MCP Integration (Priority: Low)

**Goal**: Add Model Context Protocol server support

```typescript
// packages/core/src/services/mcp-manager.ts
export class MCPManager {
  async addServer(name: string, command: string): Promise<void> {
    // Add to .mcp.json
    // Start server process
  }
  
  async listTools(): Promise<MCPTool[]> {
    // Query available tools from servers
  }
}
```

## Testing Strategy

### 1. Simple Test Case
```typescript
// User: "Create a hello world function"
// Expected: Claude Code creates function, user sees it in editor
```

### 2. Multi-Agent Test Case
```typescript
// User: "Implement a todo list component with tests"
// Expected: 
// - Planner creates task breakdown
// - Implementation agent creates component
// - Test agent writes tests
// - QA agent reviews code
```

### 3. Hook Test Case
```typescript
// User: "Fix the type errors in the project"
// Expected:
// - Claude runs typecheck
// - Fixes errors
// - Hooks prevent completion until typecheck passes
```

## Implementation Order

1. **Week 1**: Enhanced Claude Code Provider
   - Add all SDK options
   - Test with simple commands
   - Verify streaming works correctly

2. **Week 2**: Session Management
   - Create ProjectManager service
   - Implement .pm folder structure
   - Add session tracking to chat route

3. **Week 3**: Sub-Agent System
   - Create SubAgentManager
   - Add agent registration
   - Test with simple planner/worker flow

4. **Week 4**: Hooks & Quality Gates
   - Implement HooksManager
   - Add pre/post tool hooks
   - Test TDD workflow

5. **Week 5**: UI Enhancements
   - Add command palette
   - Implement agent selector
   - Polish chat interface

6. **Week 6**: MCP & Advanced Features
   - Add MCP server support
   - Implement custom slash commands
   - Final testing and polish

## Key Differences from Original Plans

1. **No Next.js**: We're using Vite + React for the desktop app
2. **Existing Integration**: We already have a working Claude Code provider
3. **Tauri Desktop**: Not a web app, so some features need desktop-specific handling
4. **Hono Server**: Using Hono instead of Next.js API routes
5. **Monorepo Structure**: Organized as apps/ and packages/

## Success Metrics

1. **Basic Functionality**: User can chat with Claude Code and see results in editor
2. **Multi-Turn**: Sessions persist and can be resumed
3. **Agent Orchestration**: Complex tasks are broken down and delegated
4. **Quality Gates**: Tests/linting/typecheck run automatically
5. **Documentation**: Each session creates comprehensive .pm files

## Next Steps

1. Start with enhancing the ClaudeCodeLanguageModel to support all SDK options
2. Test with simple commands to ensure stability
3. Incrementally add features while maintaining working state
4. Regular testing with real-world scenarios