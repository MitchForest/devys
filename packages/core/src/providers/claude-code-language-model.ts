import {
  LanguageModelV2,
  LanguageModelV2CallOptions,
  LanguageModelV2StreamPart,
  LanguageModelV2CallWarning,
  LanguageModelV2Content,
  LanguageModelV2FinishReason,
  ProviderV2,
} from '@ai-sdk/provider';
import { generateId } from '@ai-sdk/provider-utils';
import { 
  query as claudeCodeQuery, 
  type SDKMessage, 
  type SDKAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage
} from '@anthropic-ai/claude-code';

export interface ClaudeCodeLanguageModelSettings {
  /**
   * The model to use (opus or sonnet)
   */
  model: 'opus' | 'sonnet';
  
  /**
   * Custom system prompt
   */
  systemPrompt?: string;
  
  /**
   * Maximum number of turns for multi-turn conversations
   */
  maxTurns?: number;
  
  /**
   * Working directory for Claude Code operations
   */
  cwd?: string;
  
  /**
   * API key for authentication
   */
  apiKey?: string;
  
  /**
   * Session ID for continuing conversations
   */
  sessionId?: string;
  
  /**
   * Permission mode for Claude Code operations
   */
  permissionMode?: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';
  
  /**
   * Allowed tools for this session
   */
  allowedTools?: string[];
  
  /**
   * Disallowed tools for this session
   */
  disallowedTools?: string[];
}

/**
 * Claude Code language model implementation for AI SDK v5
 * This wraps the Claude Code SDK to work with AI SDK patterns
 */
export class ClaudeCodeLanguageModel implements LanguageModelV2 {
  readonly specificationVersion = 'v2' as const;
  readonly provider = 'claude-code';
  readonly modelId: string;
  readonly settings: ClaudeCodeLanguageModelSettings;
  readonly supportedUrls = {} as Record<string, RegExp[]>; // Required by interface

  constructor(settings: ClaudeCodeLanguageModelSettings) {
    this.modelId = settings.model;
    this.settings = settings;
    
    // Set API key if provided
    if (settings.apiKey) {
      process.env.ANTHROPIC_API_KEY = settings.apiKey;
    }
  }

  async doGenerate(options: LanguageModelV2CallOptions) {
    // Convert messages to prompt
    const prompt = this.convertToPrompt(options);
    
    // Collect all messages from Claude Code
    const messages: SDKMessage[] = [];
    const sdkMessages = claudeCodeQuery({
      prompt,
      abortController: options.abortSignal ? new AbortController() : undefined,
      options: {
        maxTurns: this.settings.maxTurns || 1,
        cwd: this.settings.cwd,
      }
    });

    for await (const message of sdkMessages) {
      messages.push(message);
    }

    // Convert to AI SDK format
    return this.convertToResult(messages);
  }

  async doStream(
    options: LanguageModelV2CallOptions
  ): Promise<{
    stream: ReadableStream<LanguageModelV2StreamPart>;
    request?: { body?: unknown };
    response?: { headers?: Record<string, string> };
  }> {
    // Convert messages to prompt
    const prompt = this.convertToPrompt(options);
    const settings = this.settings;
    
    // Track session information
    let currentSessionId: string | null = null;
    const usage = {
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
    };
    
    // Create abort controller that properly connects to options.abortSignal
    const abortController = new AbortController();
    if (options.abortSignal) {
      options.abortSignal.addEventListener('abort', () => abortController.abort());
    }
    
    // Create a readable stream
    const stream = new ReadableStream<LanguageModelV2StreamPart>({
      async start(controller) {
        try {
          // Start streaming
          controller.enqueue({ 
            type: 'stream-start',
            warnings: [] as LanguageModelV2CallWarning[]
          });
          
          // Stream messages from Claude Code
          const sdkMessages = claudeCodeQuery({
            prompt,
            abortController,
            options: {
              maxTurns: settings.maxTurns || 10,
              cwd: settings.cwd || process.cwd(),
              model: settings.model,
              customSystemPrompt: settings.systemPrompt,
              permissionMode: settings.permissionMode,
              allowedTools: settings.allowedTools,
              disallowedTools: settings.disallowedTools,
              continue: settings.sessionId ? true : false,
              resume: settings.sessionId,
            }
          });
          
          for await (const message of sdkMessages) {
            // Extract session ID from messages
            if ('session_id' in message && message.session_id) {
              currentSessionId = message.session_id;
            }
            
            // Transform SDK messages to stream parts
            const streamParts = transformToStreamParts(message);
            
            for (const part of streamParts) {
              controller.enqueue(part);
            }
            
            // Extract usage from result messages
            if (message.type === 'result') {
              const resultMsg = message as SDKResultMessage;
              if (resultMsg.usage) {
                usage.inputTokens = resultMsg.usage.input_tokens || 0;
                usage.outputTokens = resultMsg.usage.output_tokens || 0;
                usage.totalTokens = usage.inputTokens + usage.outputTokens;
              }
            }
          }
          
          // Finish the stream
          controller.enqueue({
            type: 'finish',
            usage,
            finishReason: 'stop' as LanguageModelV2FinishReason
          });
          
          controller.close();
        } catch (error) {
          controller.error(error);
        }
      }
    });

    return { 
      stream,
      response: currentSessionId ? { headers: { 'x-session-id': currentSessionId } } : undefined
    };

    function transformToStreamParts(message: SDKMessage): LanguageModelV2StreamPart[] {
      const parts: LanguageModelV2StreamPart[] = [];
      
      switch (message.type) {
        case 'assistant': {
          const assistantMessage = message as SDKAssistantMessage;
          const messageId = generateId();
          
          // Process content blocks from assistant message
          if (assistantMessage.message.content) {
            for (const block of assistantMessage.message.content) {
              if (block.type === 'text' && block.text) {
                // Start text
                parts.push({
                  type: 'text-start',
                  id: messageId,
                });
                
                // Text delta
                parts.push({
                  type: 'text-delta',
                  id: messageId,
                  delta: block.text,
                });
                
                // End text
                parts.push({
                  type: 'text-end',
                  id: messageId,
                });
              } else if (block.type === 'tool_use') {
                // Tool input start
                parts.push({
                  type: 'tool-input-start',
                  id: block.id,
                  toolName: block.name,
                });
                
                // Tool input delta - stream the entire input as JSON
                const inputJson = JSON.stringify(block.input || {});
                parts.push({
                  type: 'tool-input-delta',
                  id: block.id,
                  delta: inputJson,
                });
                
                // Tool input end
                parts.push({
                  type: 'tool-input-end',
                  id: block.id,
                });
                
                // Special handling for Bash tool - route to terminal
                if (block.name === 'Bash' && block.input && typeof block.input === 'object') {
                  const input = block.input as { command?: string };
                  if (input.command) {
                    // Import dynamically to avoid circular dependency
                    import('../services/terminal-bridge').then(({ terminalBridge }) => {
                      if (input.command) {
                        terminalBridge.routeCommand(input.command);
                      }
                    }).catch(() => {
                      // Terminal bridge not available
                    });
                  }
                }
              }
            }
          }
          break;
        }
        
        case 'system': {
          const systemMessage = message as SDKSystemMessage;
          // For system messages, we can emit metadata about the session
          if (systemMessage.subtype === 'init') {
            // This is useful for debugging but not shown to user
            // eslint-disable-next-line no-console
            console.log(`Claude Code session initialized:`, {
              sessionId: systemMessage.session_id,
              model: systemMessage.model,
              tools: systemMessage.tools?.length || 0,
              cwd: systemMessage.cwd
            });
          }
          break;
        }
        
        case 'user': {
          // User messages from Claude Code (e.g., from sub-agents)
          // These are typically already handled in the prompt
          break;
        }
        
        case 'result': {
          const resultMessage = message as SDKResultMessage;
          // Result messages indicate completion
          if (resultMessage.is_error) {
            console.error(`Claude Code error:`, resultMessage.subtype);
          }
          break;
        }
      }
      
      return parts;
    }
  }

  private convertToPrompt(options: LanguageModelV2CallOptions): string {
    const prompt = options.prompt;
    let result = '';
    
    // Add system messages
    const systemMessages = prompt.filter(m => m.role === 'system');
    if (systemMessages.length > 0 || this.settings.systemPrompt) {
      const systemContent = systemMessages.length > 0 
        ? systemMessages.map(m => m.content).join('\n')
        : this.settings.systemPrompt || '';
      
      result += `System: ${systemContent}\n\n`;
    }
    
    // Convert messages to Claude Code format
    for (const message of prompt) {
      if (message.role === 'system') continue;
      
      if (message.role === 'user') {
        const content = this.extractMessageContent(message.content);
        result += `User: ${content}\n\n`;
      } else if (message.role === 'assistant') {
        const content = this.extractMessageContent(message.content);
        result += `Assistant: ${content}\n\n`;
      }
    }
    
    return result.trim();
  }

  private extractMessageContent(content: unknown): string {
    if (typeof content === 'string') {
      return content;
    }
    
    if (Array.isArray(content)) {
      return content
        .map(part => {
          if (part.type === 'text') {
            return part.text;
          }
          return '';
        })
        .join('');
    }
    
    return '';
  }

  private convertToResult(messages: SDKMessage[]) {
    const content: LanguageModelV2Content[] = [];
    
    for (const message of messages) {
      if (message.type === 'assistant') {
        const assistantMessage = message as SDKAssistantMessage;
        
        if (assistantMessage.message.content) {
          for (const block of assistantMessage.message.content) {
            if (block.type === 'text' && block.text) {
              content.push({
                type: 'text',
                text: block.text,
              });
            } else if (block.type === 'tool_use') {
              content.push({
                type: 'tool-call',
                toolCallId: block.id,
                toolName: block.name,
                input: block.input || {},
              });
            }
          }
        }
      }
    }
    
    return {
      content,
      finishReason: 'stop' as LanguageModelV2FinishReason,
      usage: {
        inputTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
      },
      warnings: [],
    };
  }
}

/**
 * Claude Code provider for AI SDK v5
 */
export class ClaudeCodeProvider implements ProviderV2 {
  private apiKey?: string;
  private cwd?: string;
  private defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;

  constructor(options: { 
    apiKey?: string; 
    cwd?: string;
    defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;
  } = {}) {
    this.apiKey = options.apiKey;
    this.cwd = options.cwd;
    this.defaultSettings = options.defaultSettings;
  }

  languageModel(modelId: string, settings?: Partial<ClaudeCodeLanguageModelSettings>): ClaudeCodeLanguageModel {
    if (modelId !== 'opus' && modelId !== 'sonnet') {
      throw new Error(`Invalid model ID: ${modelId}. Must be 'opus' or 'sonnet'`);
    }
    
    return new ClaudeCodeLanguageModel({
      model: modelId as 'opus' | 'sonnet',
      apiKey: this.apiKey,
      cwd: this.cwd,
      ...this.defaultSettings,
      ...settings,
    });
  }

  // Required for provider interface but not used for Claude Code
  textEmbeddingModel(): never {
    throw new Error('Text embedding not supported by Claude Code');
  }

  // Required for provider interface but not used for Claude Code
  imageModel(): never {
    throw new Error('Image generation not supported by Claude Code');
  }
}

/**
 * Create a Claude Code provider instance
 */
export function createClaudeCode(options: { 
  apiKey?: string; 
  cwd?: string;
  defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;
} = {}) {
  return new ClaudeCodeProvider(options);
}