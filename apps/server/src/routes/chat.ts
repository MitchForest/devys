import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { streamText } from 'ai';
import { createClaudeCode } from '@claude-code-ide/core/providers/claude-code-language-model';
import type { ChatMessage, FileAttachment } from '@claude-code-ide/types';

// Request validation schema
const ChatRequestSchema = z.object({
  messages: z.array(z.object({
    id: z.string(),
    role: z.enum(['user', 'assistant', 'system', 'tool']),
    content: z.string(),
    timestamp: z.union([z.string(), z.date()]).optional(),
    createdAt: z.union([z.string(), z.date()]).optional(),
    toolInvocations: z.array(z.any()).optional(),
    attachments: z.array(z.object({
      id: z.string().optional(),
      path: z.string(),
      name: z.string(),
      content: z.string().optional(),
      language: z.string().optional(),
      selected: z.boolean().optional()
    })).optional()
  })),
  sessionId: z.string().optional(),
  attachments: z.array(z.object({
    id: z.string().optional(),
    path: z.string(),
    name: z.string(),
    content: z.string().optional(),
    language: z.string().optional(),
    selected: z.boolean().optional()
  })).optional()
});

export const chatRoute = new Hono();

// Initialize Claude Code provider
const claudeCodeProvider = createClaudeCode({
  apiKey: process.env.ANTHROPIC_API_KEY,
  cwd: process.cwd()
});

// Chat endpoint with streaming using AI SDK v5 patterns
chatRoute.post('/', zValidator('json', ChatRequestSchema), async (c) => {
  try {
    const { messages, sessionId, attachments } = c.req.valid('json');

    // Convert messages to AI SDK format
    const aiMessages = messages.map(msg => ({
      role: msg.role as 'user' | 'assistant' | 'system',
      content: msg.content,
      // Include tool invocations if present
      toolInvocations: msg.toolInvocations
    }));

    // Add file attachments to the system message if present
    let systemMessage = '';
    if (attachments && attachments.length > 0) {
      systemMessage = 'Attached files:\n';
      for (const file of attachments) {
        systemMessage += `\nFile: ${file.name} (${file.path})\n`;
        if (file.content) {
          systemMessage += `Content:\n\`\`\`${file.language || ''}\n${file.content}\n\`\`\`\n`;
        }
      }
    }

    // If we have attachments, prepend a system message
    if (systemMessage) {
      aiMessages.unshift({
        role: 'system',
        content: systemMessage,
        toolInvocations: undefined
      });
    }

    // Stream the response using AI SDK v5
    const result = await streamText({
      model: claudeCodeProvider.languageModel(process.env.CLAUDE_MODEL || 'sonnet'),
      messages: aiMessages,
      system: process.env.CLAUDE_SYSTEM_PROMPT,
      temperature: parseFloat(process.env.CLAUDE_TEMPERATURE || '0.7'),
      maxTokens: parseInt(process.env.CLAUDE_MAX_TOKENS || '4096'),
      // Enable multi-step for tool use
      maxSteps: parseInt(process.env.CLAUDE_MAX_TURNS || '10'),
      // Tool definitions will be added here when we implement tool support
      // tools: claudeCodeTools,
    });

    // Return the stream response with proper headers
    return result.toTextStreamResponse({
      headers: {
        'X-Session-Id': sessionId || ''
      }
    });
  } catch (error) {
    console.error('Chat error:', error);
    
    // Return error response
    return c.json({ 
      error: error instanceof Error ? error.message : 'An error occurred during chat processing'
    }, 500);
  }
});

// Health check endpoint
chatRoute.get('/health', (c) => {
  return c.json({ 
    status: 'ok',
    provider: 'claude-code',
    model: process.env.CLAUDE_MODEL || 'sonnet'
  });
});