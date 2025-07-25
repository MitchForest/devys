# AI SDK v5 Complete Reference Guide

This document serves as our definitive reference for AI SDK v5 patterns, APIs, and implementation details.

## Table of Contents
1. [useChat Hook](#usechat-hook)
2. [Streaming](#streaming)
3. [Language Models](#language-models)
4. [Tool Calling](#tool-calling)
5. [Server Endpoints](#server-endpoints)
6. [Custom Providers](#custom-providers)
7. [Agents](#agents)

## useChat Hook

The `useChat` hook is the primary way to build chat interfaces with AI SDK v5.

### Basic Usage
```typescript
import { useChat } from '@ai-sdk/react';

const { 
  messages,     // Current chat messages array
  sendMessage,  // Function to send a new message
  status,       // Current chat status
  error,        // Any error during message processing
  stop,         // Stop current message generation
  reload,       // Regenerate last message
  setMessages   // Manually modify message history
} = useChat({
  transport: new DefaultChatTransport({
    api: '/api/chat'
  })
});
```

### Status Values
- `submitted`: Message sent, awaiting response start
- `streaming`: Response actively streaming
- `ready`: Full response received
- `error`: API request failed

### Configuration Options
```typescript
useChat({
  transport: new DefaultChatTransport({
    api: '/api/chat',
    headers: { /* custom headers */ },
    body: { /* additional body data */ }
  }),
  
  // Event callbacks
  onFinish: (message) => {
    // Called when assistant message completes
  },
  onError: (error) => {
    // Called on request errors
  },
  onData: (data) => {
    // Called when data chunks are received
  },
  
  // Advanced options
  experimental_throttle: 50, // Throttle UI updates (ms)
  initialMessages: [],       // Initial message history
});
```

### Message Structure
```typescript
interface UIMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  parts: MessagePart[];
  createdAt: Date;
  toolInvocations?: ToolInvocation[];
}
```

### Key Methods
- `sendMessage({ role: 'user', content: 'Hello' })`: Send a new message
- `stop()`: Interrupt current message generation
- `reload()`: Regenerate the last message
- `setMessages(messages)`: Manually update message history

## Streaming

Streaming enables real-time display of AI responses as they're generated.

### Core Concepts
- **Purpose**: Display partial responses immediately instead of waiting for complete generation
- **Benefits**: Reduces perceived latency (5-40s wait times become interactive)
- **Use Cases**: Chatbots, conversational UIs, real-time content generation

### Server-Side Streaming with streamText
```typescript
import { streamText } from 'ai';
import { createClaudeCode } from './providers/claude-code-language-model';

export async function POST(req: Request) {
  const { messages } = await req.json();
  
  const result = await streamText({
    model: createClaudeCode().languageModel('opus'),
    messages,
    maxSteps: 5, // Enable multi-step for tool use
  });

  // Convert to stream response
  return result.toDataStreamResponse();
}
```

### Custom Streaming with createUIMessageStream
```typescript
import { createUIMessageStream, createUIMessageStreamResponse } from 'ai';

const stream = createUIMessageStream({
  execute: async ({ writer }) => {
    // Send transient status updates
    writer.write({
      type: 'data-notification',
      data: { message: 'Processing...', level: 'info' },
      transient: true // Not persisted in message history
    });
    
    // Stream sources for RAG
    writer.write({
      type: 'source',
      value: { title: 'Document', url: '...' }
    });
    
    // Merge with model stream
    const result = await streamText({ model, messages });
    writer.merge(result.toUIMessageStream());
  }
});

return createUIMessageStreamResponse({ stream });
```

### Stream Part Types
1. **Persistent Parts**: Added to message history
   - Text content
   - Tool calls
   - Tool results

2. **Transient Parts**: Only accessible via `onData` callback
   - Status notifications
   - Progress updates
   - Debugging info

3. **Sources**: For RAG implementations
   - Document references
   - Citations

## Language Models

### LanguageModelV2 Interface
```typescript
interface LanguageModelV2 {
  readonly specificationVersion: 'v2';
  readonly provider: string;
  readonly modelId: string;
  readonly supportedUrls: string[];
  
  doGenerate(options: LanguageModelV2CallOptions): Promise<{
    content: LanguageModelV2Content[];
    finishReason: LanguageModelV2FinishReason;
    usage: LanguageModelV2Usage;
    warnings: LanguageModelV2CallWarning[];
  }>;
  
  doStream(options: LanguageModelV2CallOptions): Promise<{
    stream: ReadableStream<LanguageModelV2StreamPart>;
    request?: { body?: unknown };
    response?: { headers?: Record<string, string> };
  }>;
}
```

### Stream Parts
```typescript
type LanguageModelV2StreamPart = 
  | { type: 'stream-start'; warnings: LanguageModelV2CallWarning[] }
  | { type: 'text-start'; id: string }
  | { type: 'text-delta'; id: string; delta: string }
  | { type: 'text-end'; id: string }
  | { type: 'tool-input-start'; id: string; toolName: string }
  | { type: 'tool-input-delta'; id: string; delta: string }
  | { type: 'tool-input-end'; id: string }
  | { type: 'finish'; usage: LanguageModelV2Usage; finishReason: LanguageModelV2FinishReason };
```

### Usage Tracking
```typescript
interface LanguageModelV2Usage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}
```

## Tool Calling

### Tool Definition
```typescript
import { tool } from 'ai';
import { z } from 'zod';

const weatherTool = tool({
  description: 'Get weather information',
  inputSchema: z.object({  // Changed from 'parameters' to 'inputSchema'
    location: z.string()
  }),
  execute: async ({ location }) => {
    // Tool implementation
    return { temperature: 72, condition: 'sunny' };
  }
});

// For tools that return non-text content
const screenshotTool = tool({
  description: 'Take a screenshot',
  inputSchema: z.object({}),
  execute: async () => {
    const imageData = await takeScreenshot();
    return imageData; // base64 string
  },
  toModelOutput: result => ({  // Changed from 'experimental_toToolResultContent'
    type: 'content',
    value: [{ type: 'media', mediaType: 'image/png', data: result }],
  }),
});
```

### Three Types of Tools

1. **Server-Side Auto-Executed Tools**
```typescript
// In API route
const result = await streamText({
  model,
  messages,
  tools,
  maxSteps: 5, // Auto-execute tool results
});
```

2. **Client-Side Auto-Executed Tools**
```typescript
// In useChat
useChat({
  transport,
  onToolCall: async ({ toolCall }) => {
    if (toolCall.toolName === 'getCurrentLocation') {
      const location = await navigator.geolocation.getCurrentPosition();
      return { location };
    }
  }
});
```

3. **User Interaction Tools**
```typescript
// Display in UI for user confirmation
{message.toolInvocations?.map(invocation => (
  <ToolConfirmation 
    key={invocation.toolCallId}
    invocation={invocation}
    onConfirm={(result) => addToolResult(invocation.toolCallId, result)}
  />
))}
```

### Tool Streaming
- Tool call streaming is now **always enabled by default** (no more `toolCallStreaming` option)
- Real-time UI updates as tool arguments stream in
- Tool results can be streamed back

### Tool Property Changes
- `args` → `input` (for tool calls)
- `result` → `output` (for tool results)

```typescript
// Handling tool streams
for await (const part of result.fullStream) {
  switch (part.type) {
    case 'tool-call':
      console.log('Tool input:', part.input); // Changed from 'args'
      break;
    case 'tool-result':
      console.log('Tool output:', part.output); // Changed from 'result'
      break;
  }
}
```

### Tool UI Part States
Tool UI parts now have more granular states:

```typescript
// New states for tool parts
switch (part.state) {
  case 'input-streaming':  // Tool input being streamed (was 'partial-call')
    return <div>Loading...</div>;
  case 'input-available':  // Tool input complete (was 'call')
    return <div>Executing with {JSON.stringify(part.input)}</div>;
  case 'output-available': // Tool execution successful (was 'result')
    return <div>Result: {part.output}</div>;
  case 'output-error':     // Tool execution failed (new state)
    return <div>Error: {part.errorText}</div>;
}
```

## Server Endpoints

### Basic Chat Endpoint
```typescript
import { streamText } from 'ai';

export async function POST(req: Request) {
  const { messages, sessionId, attachments } = await req.json();
  
  const result = await streamText({
    model: yourModel,
    messages,
    system: 'You are a helpful assistant',
    temperature: 0.7,
    maxTokens: 1000,
    tools, // Optional tools
    maxSteps: 5, // For multi-turn tool use
  });
  
  return result.toDataStreamResponse({
    headers: {
      'X-Session-Id': sessionId
    }
  });
}
```

### Advanced Streaming with Custom Data
```typescript
import { createUIMessageStream, createUIMessageStreamResponse } from 'ai';

export async function POST(req: Request) {
  const stream = createUIMessageStream({
    execute: async ({ writer }) => {
      // Custom logic before model call
      writer.write({
        type: 'thinking',
        data: { content: 'Analyzing request...' },
        transient: true
      });
      
      // Call model
      const result = await streamText({ model, messages });
      
      // Merge model stream
      writer.merge(result.toUIMessageStream());
      
      // Custom logic after model
      writer.write({
        type: 'metadata',
        data: { processingTime: Date.now() }
      });
    }
  });
  
  return createUIMessageStreamResponse({ stream });
}
```

## Custom Providers

### Provider Implementation
```typescript
import { ProviderV2 } from '@ai-sdk/provider';

export class CustomProvider implements ProviderV2 {
  languageModel(modelId: string): LanguageModelV2 {
    return new CustomLanguageModel({ model: modelId });
  }
  
  textEmbeddingModel(): never {
    throw new Error('Not supported');
  }
}
```

### Language Model Implementation
```typescript
class CustomLanguageModel implements LanguageModelV2 {
  readonly specificationVersion = 'v2' as const;
  readonly provider = 'custom';
  readonly modelId: string;
  readonly supportedUrls = [];
  
  async doGenerate(options: LanguageModelV2CallOptions) {
    // Convert prompt to your format
    const prompt = this.convertPrompt(options.prompt);
    
    // Call your API
    const response = await yourAPI.generate(prompt);
    
    // Return formatted result
    return {
      content: [{ type: 'text', text: response.text }],
      finishReason: 'stop',
      usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
      warnings: []
    };
  }
  
  async doStream(options: LanguageModelV2CallOptions) {
    const stream = new ReadableStream<LanguageModelV2StreamPart>({
      async start(controller) {
        // Start stream
        controller.enqueue({ 
          type: 'stream-start', 
          warnings: [] 
        });
        
        // Stream your content
        const response = await yourAPI.stream(prompt);
        for await (const chunk of response) {
          controller.enqueue({
            type: 'text-delta',
            id: 'text-1',
            delta: chunk.text
          });
        }
        
        // Finish stream
        controller.enqueue({
          type: 'finish',
          usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
          finishReason: 'stop'
        });
        
        controller.close();
      }
    });
    
    return { stream };
  }
}
```

## Agents

### Multi-Step Conversations
```typescript
const result = await streamText({
  model,
  messages,
  tools,
  maxSteps: 10, // Allow up to 10 tool calls
  onStepFinish: (step) => {
    console.log('Step completed:', step);
  }
});
```

### Agent Patterns
1. **Tool-Using Agents**: Leverage tools to accomplish tasks
2. **Multi-Turn Agents**: Handle complex conversations with context
3. **Sub-Agent Spawning**: Create specialized agents for subtasks

### Example Agent Implementation
```typescript
async function agentExecutor({ task, tools }) {
  const messages = [
    { role: 'system', content: 'You are a helpful agent.' },
    { role: 'user', content: task }
  ];
  
  const result = await streamText({
    model,
    messages,
    tools,
    maxSteps: 20,
    onStepFinish: async (step) => {
      // Log each step for debugging
      console.log(`Step ${step.stepNumber}:`, step);
      
      // Could spawn sub-agents here
      if (step.toolCalls?.some(tc => tc.toolName === 'complex-task')) {
        await spawnSubAgent(step);
      }
    }
  });
  
  return result;
}
```

## Best Practices

### Error Handling
```typescript
try {
  const result = await streamText({ model, messages });
  return result.toDataStreamResponse();
} catch (error) {
  if (error.name === 'AbortError') {
    // Handle cancellation
  } else if (error.code === 'RATE_LIMIT') {
    // Handle rate limits
  } else {
    // Generic error handling
  }
}
```

### Performance Optimization
1. Use `experimental_throttle` to reduce re-renders
2. Implement proper abort handling
3. Cache model instances
4. Stream large responses
5. Use `maxSteps` judiciously

### Type Safety
```typescript
// Define custom message types
type MyUIMessage = UIMessage<{
  customData: string;
}>;

// Use with useChat
const { messages } = useChat<MyUIMessage>({
  transport: new DefaultChatTransport({
    api: '/api/chat'
  })
});
```

## Migration from v4 to v5

### useChat Hook Changes
- `handleSubmit` → `sendMessage`
- `input/handleInputChange` → Manage manually with `useState`
- `isLoading` → `status === 'streaming'`
- `append` → `sendMessage`
- `api` option → Direct `api` option (no transport needed in v5)

### Tool Definition Changes
- `parameters` → `inputSchema`
- `experimental_toToolResultContent` → `toModelOutput`
- Tool streaming is now always enabled (no `toolCallStreaming` option)

### Tool Property Changes
- `args` → `input` (in tool calls)
- `result` → `output` (in tool results)

### Tool UI Part Changes
- Generic `tool-invocation` → Specific `tool-${toolName}` types
- States: `partial-call` → `input-streaming`, `call` → `input-available`, `result` → `output-available`
- New state: `output-error` for failed tool executions

### Error Class Renames
- Check documentation for specific error class changes

## Resources
- [Chatbot Guide](https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot)
- [Streaming Guide](https://v5.ai-sdk.dev/docs/foundations/streaming)
- [Tool Usage](https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot-tool-usage)
- [Custom Providers](https://v5.ai-sdk.dev/docs/ai-sdk-core/middleware)
- [Stream Helpers](https://v5.ai-sdk.dev/docs/reference/stream-helpers)
- [Migration](https://v5.ai-sdk.dev/docs/migration-guides/migration-guide-5-0)
- [UseChat](https://v5.ai-sdk.dev/docs/reference/ai-sdk-ui/use-chat)
- [Tools and Tool Calling](https://v5.ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling)
- [Agents](https://v5.ai-sdk.dev/docs/foundations/agents)
- [Example Custom Provider Implementation](https://github.com/ben-vargas/ai-sdk-provider-claude-code)
- [Stream Text](https://v5.ai-sdk.dev/docs/reference/ai-sdk-core/stream-text) 