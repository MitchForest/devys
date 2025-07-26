# Codebase Analysis: AI SDK v5 and Claude Code SDK Compliance

## Executive Summary

This document analyzes the current Devys codebase against the AI SDK v5 and Claude Code SDK documentation to identify what's properly implemented and what needs refactoring.

## AI SDK v5 Compliance

### ✅ Correctly Implemented

1. **useChat Hook Integration**
   - Proper use of `DefaultChatTransport` with API endpoint configuration
   - Correct `sendMessage({ text: string })` format
   - Status management (`streaming`, `ready`, `error`)
   - Manual input state management as required by v5

2. **Custom Provider Pattern**
   - `ClaudeCodeLanguageModel` implements `LanguageModelV2` interface correctly
   - Proper `doStream()` method returning `ReadableStream<LanguageModelV2StreamPart>`
   - Correct stream part types (`stream-start`, `text-delta`, `tool-input-*`, `finish`)
   - Usage tracking implementation

3. **Server-Side Streaming**
   - Uses `streamText()` with proper model configuration
   - Returns `result.toTextStreamResponse()` for streaming
   - Proper error handling and session management

### ❌ Needs Refactoring

1. **Tool Integration**
   - Currently passing tool calls as stream parts but not using AI SDK v5 tool patterns
   - Missing proper tool definitions with `inputSchema` (using Zod)
   - No implementation of `toModelOutput` for non-text tool results
   - Tool UI states not properly mapped to new granular states

2. **Message Structure**
   - Using custom `ChatMessage` type instead of `UIMessage`
   - Missing proper `parts` array handling
   - Tool invocations not following AI SDK v5 structure

3. **Advanced Features Missing**
   - No `onStepFinish` callback implementation
   - Missing `maxSteps` configuration for multi-turn conversations
   - No custom data streaming with `createUIMessageStream`
   - Missing transient parts for status updates

## Claude Code SDK Compliance

### ✅ Correctly Implemented

1. **Basic Integration**
   - Proper use of `query()` function
   - Streaming message handling with `for await`
   - Session ID extraction and management
   - Environment variable passing (with workaround)

2. **Message Type Handling**
   - Correctly processes `SDKAssistantMessage`
   - Handles `SDKSystemMessage` for initialization
   - Extracts usage from `SDKResultMessage`

3. **Configuration**
   - Model selection (`opus`/`sonnet`)
   - Working directory (`cwd`) configuration
   - Custom system prompt support
   - Max turns configuration

### ❌ Needs Refactoring

1. **Tool Permissions**
   - Not using `allowedTools`/`disallowedTools` patterns
   - No fine-grained permission control (e.g., `Bash(git:*)`)
   - Permission mode hardcoded to 'default'

2. **Advanced Features Missing**
   - No MCP server configuration support
   - No sub-agent spawning capability
   - Missing session continue/resume functionality
   - No custom executable configuration
   - No `stderr` callback implementation

3. **Tool Routing**
   - Basic Bash command routing to terminal but incomplete
   - Other tools (Read, Write, FileEdit) not integrated with UI
   - No approval workflow for destructive operations

## Refactoring Priorities

### High Priority

1. **Tool System Overhaul**
   ```typescript
   // Define Claude Code tools as AI SDK v5 tools
   const fileEditTool = tool({
     description: 'Edit a file',
     inputSchema: z.object({
       path: z.string(),
       oldContent: z.string(),
       newContent: z.string()
     }),
     execute: async ({ path, oldContent, newContent }) => {
       // Route to UI for approval
       return await approvalDialog.show({ path, oldContent, newContent });
     }
   });
   ```

2. **Message Structure Alignment**
   - Migrate from custom `ChatMessage` to AI SDK v5 `UIMessage`
   - Implement proper `parts` array for multi-modal content
   - Add tool invocation UI states

3. **Session Management**
   - Implement continue/resume functionality
   - Add session persistence across restarts
   - Proper session UI in chat interface

### Medium Priority

1. **Tool UI Visualization**
   - Create components for each Claude Code tool
   - Implement approval dialogs for Write/FileEdit
   - Show real-time tool execution status
   - Add diff viewer for file changes

2. **Advanced Streaming**
   - Use `createUIMessageStream` for custom data
   - Add transient status notifications
   - Implement progress indicators for long operations

3. **Permission System**
   - Add UI for configuring allowed/disallowed tools
   - Implement pattern-based permissions
   - Different permission modes (plan, acceptEdits, etc.)

### Low Priority

1. **MCP Server Support**
   - Add MCP configuration UI
   - Implement MCP tool discovery
   - Handle MCP resource listing

2. **Sub-Agent Features**
   - Implement Agent tool handling
   - Create UI for nested conversations
   - Add agent result aggregation

3. **Advanced Configuration**
   - Custom executable selection
   - Stderr output handling
   - Thinking tokens configuration

## Implementation Recommendations

### 1. Create Tool Adapter Layer
```typescript
// Transform Claude Code tools to AI SDK v5 tools
class ClaudeCodeToolAdapter {
  static adaptTool(toolName: string): CoreTool {
    switch(toolName) {
      case 'Read':
        return tool({
          description: 'Read file contents',
          inputSchema: z.object({ path: z.string() }),
          execute: async ({ path }) => {
            // Implementation
          }
        });
    }
  }
}
```

### 2. Implement Approval System
```typescript
interface ApprovalRequest {
  tool: string;
  input: unknown;
  onApprove: () => void;
  onReject: () => void;
}

class ApprovalQueue {
  private queue: ApprovalRequest[] = [];
  
  async requestApproval(request: ApprovalRequest): Promise<boolean> {
    // Show in UI and wait for user decision
  }
}
```

### 3. Enhanced Session Management
```typescript
interface SessionManager {
  continue(sessionId: string): void;
  resume(sessionId: string): void;
  save(session: ChatSession): void;
  restore(sessionId: string): ChatSession;
}
```

## Conclusion

The current implementation has a solid foundation with proper AI SDK v5 provider integration and basic Claude Code SDK usage. The main areas needing work are:

1. **Tool System**: Full integration of Claude Code tools with AI SDK v5 patterns
2. **UI Components**: Proper visualization for tool execution and approval
3. **Session Features**: Continue/resume and persistence
4. **Advanced Features**: MCP, sub-agents, and fine-grained permissions

The refactoring should focus on high-priority items first to deliver the most value to users while maintaining backward compatibility where possible.