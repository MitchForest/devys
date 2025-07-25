import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { streamText } from 'ai';
import { createClaudeCode } from '@devys/core';
import { db } from '@devys/db';
import { randomUUID } from 'crypto';

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

// Initialize Claude Code provider with default settings
const claudeCodeProvider = createClaudeCode({
  apiKey: process.env.ANTHROPIC_API_KEY,
  cwd: process.cwd(),
  defaultSettings: {
    permissionMode: 'default', // Require approval for destructive operations
    maxTurns: 10, // Allow multi-turn conversations
  }
});

// Chat endpoint with streaming using AI SDK v5 patterns
chatRoute.post('/', zValidator('json', ChatRequestSchema), async (c) => {
  try {
    const { messages, sessionId: providedSessionId, attachments } = c.req.valid('json');
    
    // Get or create session
    let sessionId = providedSessionId;
    let session = null;
    
    if (sessionId) {
      session = db.getSession(sessionId);
      if (!session) {
        // Create new session with provided ID
        session = db.createSession(sessionId, process.cwd(), process.env.CLAUDE_MODEL || 'sonnet');
      }
    } else {
      // Generate new session ID
      sessionId = randomUUID();
      session = db.createSession(sessionId, process.cwd(), process.env.CLAUDE_MODEL || 'sonnet');
    }
    
    // Save incoming user message to database
    const lastUserMessage = messages[messages.length - 1];
    if (lastUserMessage && lastUserMessage.role === 'user') {
      db.addMessage({
        id: lastUserMessage.id || randomUUID(),
        session_id: sessionId,
        role: 'user',
        content: lastUserMessage.content,
        parent_message_id: messages.length > 1 ? messages[messages.length - 2]?.id : undefined
      });
    }

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
          // Truncate very large files to avoid token limits
          const maxLength = 10000; // ~2500 tokens
          const content = file.content.length > maxLength 
            ? file.content.substring(0, maxLength) + '\n... [truncated]'
            : file.content;
          systemMessage += `Content:\n\`\`\`${file.language || ''}\n${content}\n\`\`\`\n`;
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

    // Create model with session support
    const model = claudeCodeProvider.languageModel(
      process.env.CLAUDE_MODEL || 'sonnet',
      {
        sessionId: sessionId,
        cwd: process.cwd(), // Use the project working directory
      }
    );

    // Stream the response using AI SDK v5
    // Note: Claude Code handles its own tools internally, so we don't pass tools here
    const result = await streamText({
      model,
      messages: aiMessages,
      system: process.env.CLAUDE_SYSTEM_PROMPT,
      temperature: parseFloat(process.env.CLAUDE_TEMPERATURE || '0.7'),
      maxRetries: 3,
      onFinish: async ({ text, usage, finishReason }) => {
        // Save assistant message to database
        const assistantMessageId = randomUUID();
        db.addMessage({
          id: assistantMessageId,
          session_id: sessionId,
          role: 'assistant',
          content: text,
          parent_message_id: lastUserMessage?.id
        });
        
        // Update session status
        db.updateSession(sessionId, {
          status: finishReason === 'stop' ? 'active' : 'error'
        });
        
        // Update session metadata with usage info
        if (usage && usage.totalTokens) {
          db.updateSessionMetadata(sessionId, {
            total_tokens_used: usage.totalTokens,
            total_cost_usd: usage.totalTokens * 0.00001 // Rough estimate
          });
        }
      }
    });

    // Create response headers
    const responseHeaders: Record<string, string> = {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    };
    
    // Add session ID to headers if available
    if (sessionId) {
      responseHeaders['X-Session-Id'] = sessionId;
    }

    // Return the stream response with proper headers
    return result.toTextStreamResponse({
      headers: responseHeaders
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

// Get session endpoint
chatRoute.get('/sessions/:sessionId', (c) => {
  const sessionId = c.req.param('sessionId');
  const session = db.getSession(sessionId);
  
  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }
  
  const messages = db.getSessionMessages(sessionId);
  
  return c.json({
    session,
    messages
  });
});

// List sessions endpoint
chatRoute.get('/sessions', (c) => {
  const limit = parseInt(c.req.query('limit') || '20');
  const offset = parseInt(c.req.query('offset') || '0');
  
  const sessions = db.listSessions(limit, offset);
  
  return c.json({
    sessions,
    limit,
    offset
  });
});