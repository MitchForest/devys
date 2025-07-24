# Claude Code IDE Architecture Overview

## Vision
We're building a next-generation IDE that wraps Claude Code's powerful terminal-based agentic coding system in a modern visual interface. This gives developers the best of both worlds: Claude Code's advanced capabilities with an intuitive UI.

## Core Architecture

### Technology Stack
- **Frontend**: Tauri + React (Desktop app)
- **Chat UI**: AI SDK v5 (Vercel) for orchestration
- **AI Engine**: Claude Code SDK for actual AI capabilities
- **Custom Provider**: Bridge between AI SDK v5 and Claude Code

### Why This Architecture?

1. **AI SDK v5 for UI/Orchestration**
   - Industry-standard patterns for chat interfaces
   - Built-in streaming support
   - Tool visualization components
   - Message state management

2. **Claude Code SDK for AI Capabilities**
   - Pre-built coding tools (file ops, bash, git)
   - Sub-agent spawning
   - MCP (Model Context Protocol) support
   - Context-aware code understanding

3. **Custom Provider as the Bridge**
   - Implements AI SDK v5's `LanguageModelV2` interface
   - Translates Claude Code messages to AI SDK format
   - Preserves all Claude Code features

## Implementation

### Custom Claude Code Provider
```typescript
// packages/core/src/providers/claude-code-language-model.ts
export class ClaudeCodeLanguageModel implements LanguageModelV2 {
  async doStream(options: LanguageModelV2CallOptions) {
    const prompt = this.convertToPrompt(options);
    
    const stream = new ReadableStream<LanguageModelV2StreamPart>({
      async start(controller) {
        const sdkMessages = claudeCodeQuery({ prompt, options });
        
        for await (const message of sdkMessages) {
          // Transform Claude Code messages to AI SDK stream parts
          const streamParts = transformToStreamParts(message);
          for (const part of streamParts) {
            controller.enqueue(part);
          }
        }
      }
    });
    
    return { stream };
  }
}
```

### Chat Interface Integration
```typescript
// Using AI SDK v5's useChat hook
const { messages, sendMessage, status } = useChat({
  api: '/api/chat',
  onFinish: ({ message }) => {
    // Handle completed messages
  }
});

// Server endpoint using our custom provider
const result = await streamText({
  model: claudeCodeProvider.languageModel('sonnet'),
  messages: aiMessages,
  maxSteps: 10, // Enable multi-turn for tool use
});

return result.toTextStreamResponse();
```

### Message Flow
```
User Input → Chat UI → Server Endpoint → Custom Provider → Claude Code SDK
    ↑                                                            ↓
    ←────────── UI Updates ←── Stream Transform ←── SDK Messages
```

## Key Features

### 1. Visual Tool Execution
Claude Code's terminal tools become interactive UI components:
- File operations show in file explorer
- Bash commands display in integrated terminal
- Git operations update source control UI

### 2. Approval Workflows
Destructive operations require user confirmation:
- File deletions
- Git commits/pushes
- System commands

### 3. Context Preservation
- Attach files to conversations
- Session management
- Project-aware responses

### 4. Sub-Agent Support
- Spawn specialized agents for complex tasks
- Display nested conversations
- Aggregate results

### 5. MCP Integration
- Connect external data sources
- Database queries
- API integrations

## Reference Implementations

### Community Providers (for inspiration)
- [ai-sdk-provider-claude-code](https://github.com/ben-vargas/ai-sdk-provider-claude-code) - CLI wrapper approach
- Shows how to bridge Claude Code with AI SDK

### Official Documentation
- [AI SDK v5 Custom Providers](https://v5.ai-sdk.dev/providers/community-providers/custom-providers)
- [Claude Code SDK](https://docs.anthropic.com/en/docs/claude-code/sdk)

## Development Workflow

1. **Phase 1: Core Integration** ✅
   - Custom provider implementation
   - Basic chat functionality
   - Message streaming

2. **Phase 2: Tool Integration** (Current)
   - Map Claude Code tools to UI actions
   - Implement approval flows
   - Terminal integration

3. **Phase 3: Advanced Features**
   - Sub-agent support
   - MCP servers
   - Workflow automation

## Benefits of Our Approach

1. **No CLI Dependency**: Users don't need Claude Code CLI installed
2. **Full Feature Access**: All Claude Code capabilities available
3. **Modern UX**: Visual feedback for all operations
4. **Extensible**: Easy to add new UI for future Claude Code features
5. **Type Safety**: Full TypeScript throughout

## Example: File Edit Flow

1. User asks: "Update the config file to add dark mode"
2. Claude Code decides to use `FileEdit` tool
3. Our provider intercepts the tool call
4. UI shows diff preview with approval button
5. User approves
6. File is updated
7. File explorer refreshes
8. Success feedback in chat

This architecture gives us the power of Claude Code with the usability of a modern IDE.