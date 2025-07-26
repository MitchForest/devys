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
  type SDKSystemMessage,
  type SDKUserMessage
} from '@anthropic-ai/claude-code';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

// Create require function for ES modules
const require = createRequire(import.meta.url);

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
   * API key for authentication (DEPRECATED - Claude Code uses 'claude setup-token' for auth)
   * @deprecated Use 'claude setup-token' command instead
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
   * Allowed tools for this session (space-separated or comma-separated)
   */
  allowedTools?: string | string[];
  
  /**
   * Disallowed tools for this session (space-separated or comma-separated)
   */
  disallowedTools?: string | string[];
  
  /**
   * Output format for Claude Code
   */
  outputFormat?: 'text' | 'json' | 'stream-json';
  
  /**
   * Run in non-interactive print mode
   */
  print?: boolean;
  
  /**
   * Resume a specific session by ID
   */
  resume?: string;
  
  /**
   * Continue the most recent session
   */
  continue?: boolean;
  
  /**
   * MCP configuration file path
   */
  mcpConfig?: string;
  
  /**
   * Permission prompt tool for non-interactive runs (e.g., 'mcp__permissions__approve')
   */
  permissionPromptTool?: string;
  
  /**
   * Skip all permission prompts (dangerous!)
   */
  dangerouslySkipPermissions?: boolean;
  
  /**
   * Assume yes to all prompts (dangerous!)
   */
  dangerouslyAssumeYesToAllPrompts?: boolean;
  
  /**
   * Memory paths to load (e.g., ['./CLAUDE.md', '~/.claude/CLAUDE.md'])
   */
  memoryPaths?: string[];
  
  /**
   * Append to system prompt
   */
  appendSystemPrompt?: string;
  
  /**
   * Shell configuration options
   */
  shell?: {
    isInteractive?: boolean;
    stdinIsTTY?: boolean;
    runningOnCICD?: boolean;
    promptType?: string;
  };
  
  /**
   * Transcript configuration
   */
  transcriptMode?: string;
  transcriptPath?: string;
  logTo?: string;
  cacheDir?: string;
  
  /**
   * Jupyter kernel configuration
   */
  jupyterKernelName?: string;
  jupyterInstallKernel?: boolean;
  
  /**
   * Experimental features
   */
  experimentalAllowAllToolUseInCostExcel?: boolean;
  
  /**
   * Hooks for tool execution control
   */
  hooks?: {
    preToolUse?: (tool: string, input: any) => Promise<{ allow: boolean; input?: any }>;
    postToolUse?: (tool: string, result: any) => Promise<void>;
    stop?: () => Promise<{ allow: boolean; reason?: string }>;
    userPromptSubmit?: (prompt: string) => Promise<{ allow: boolean; updatedPrompt?: string }>;
  };
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
    
    // Claude Code uses its own authentication via 'claude setup-token'
    // Not the standard ANTHROPIC_API_KEY
    // Remove API key setting as it's not used by Claude Code SDK
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
        // Explicitly set the path to the CLI
        pathToClaudeCodeExecutable: require.resolve('@anthropic-ai/claude-code/cli.js')
        // Claude Code uses its own authentication via 'claude setup-token'
      } as any // Type definition is missing env property
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
    
    // Create abort controller - Claude Code SDK expects its own controller
    const abortController = options.abortSignal ? new AbortController() : undefined;
    if (options.abortSignal && abortController) {
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
          
          // Debug environment
          console.log('[Claude Code] Environment check:', {
            cwd: settings.cwd || process.cwd(),
            // Claude Code uses its own auth via 'claude setup-token'
            note: 'Authentication handled by Claude Code CLI'
          });
          
          // Convert allowed/disallowed tools to string format if needed
          const allowedToolsStr = Array.isArray(settings.allowedTools) 
            ? settings.allowedTools.join(',') 
            : settings.allowedTools;
          const disallowedToolsStr = Array.isArray(settings.disallowedTools) 
            ? settings.disallowedTools.join(',') 
            : settings.disallowedTools;
          
          // Debug: Log the full command options
          console.log('[Claude Code] Query options:', {
            prompt: typeof prompt === 'string' ? prompt.substring(0, 100) + '...' : '<AsyncIterable>',
            hasAbortController: !!abortController,
            optionsPreview: {
              print: settings.print !== false,
              outputFormat: settings.outputFormat || 'stream-json',
              cwd: settings.cwd || process.cwd()
            }
          });
          
          // Stream messages from Claude Code
          const sdkMessages = claudeCodeQuery({
            prompt,
            abortController,
            options: {
              // Core options
              maxTurns: settings.maxTurns || 10,
              cwd: settings.cwd || process.cwd(),
              model: settings.model,
              
              // Prompt configuration
              customSystemPrompt: settings.systemPrompt,
              appendSystemPrompt: settings.appendSystemPrompt,
              
              // Permission and tools
              permissionMode: settings.permissionMode,
              allowedTools: allowedToolsStr,
              disallowedTools: disallowedToolsStr,
              permissionPromptTool: settings.permissionPromptTool,
              dangerouslySkipPermissions: settings.dangerouslySkipPermissions,
              dangerouslyAssumeYesToAllPrompts: settings.dangerouslyAssumeYesToAllPrompts,
              
              // Session management
              continue: settings.continue || (settings.sessionId ? true : false),
              resume: settings.resume || settings.sessionId,
              
              // Output configuration
              outputFormat: settings.outputFormat || 'stream-json',
              print: settings.print !== false, // Default to true for non-interactive
              
              // MCP and memory
              mcpConfig: settings.mcpConfig,
              memoryPaths: settings.memoryPaths,
              
              // Shell configuration - Force non-interactive for server context
              ...(settings.shell ? {
                'shell.isInteractive': settings.shell.isInteractive,
                'shell.stdinIsTTY': settings.shell.stdinIsTTY,
                'shell.runningOnCICD': settings.shell.runningOnCICD,
                'shell.promptType': settings.shell.promptType,
              } : {
                // Default to non-interactive settings
                'shell.isInteractive': false,
                'shell.stdinIsTTY': false,
                'shell.runningOnCICD': true, // This forces non-interactive behavior
              }),
              
              // Transcript and logging
              transcriptMode: settings.transcriptMode,
              transcriptPath: settings.transcriptPath,
              logTo: settings.logTo,
              cacheDir: settings.cacheDir,
              
              // Jupyter
              jupyterKernelName: settings.jupyterKernelName,
              jupyterInstallKernel: settings.jupyterInstallKernel,
              
              // Experimental
              experimentalAllowAllToolUseInCostExcel: settings.experimentalAllowAllToolUseInCostExcel,
              
              // Explicitly set the path to the CLI
              pathToClaudeCodeExecutable: require.resolve('@anthropic-ai/claude-code/cli.js')
              // Claude Code uses its own authentication via 'claude setup-token'
              // Environment is inherited from the parent process
            } as any // Type definition is missing env property
          });
          
          for await (const message of sdkMessages) {
            console.log(`[Claude Code] Received message:`, message.type);
            
            // Extract session ID from messages
            if ('session_id' in message && message.session_id) {
              currentSessionId = message.session_id;
            }
            
            // Transform SDK messages to stream parts
            const streamParts = await transformToStreamParts(message);
            
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
          console.error('[Claude Code] Stream error:', error);
          controller.error(error);
        }
      }
    });

    return { 
      stream,
      response: currentSessionId ? { headers: { 'x-session-id': currentSessionId } } : undefined
    };

    async function transformToStreamParts(message: SDKMessage): Promise<LanguageModelV2StreamPart[]> {
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

  private convertToPrompt(options: LanguageModelV2CallOptions): string | AsyncIterable<SDKUserMessage> {
    const prompt = options.prompt;
    
    // Create an async iterable of messages for Claude Code SDK
    async function* generateMessages(): AsyncIterable<SDKUserMessage> {
      // Send each message as a separate SDK message
      for (const message of prompt) {
        if (message.role === 'user') {
          const content = typeof message.content === 'string' 
            ? message.content 
            : message.content.map((p: any) => p.text || '').join('');
          
          yield {
            type: 'user',
            message: {
              role: 'user',
              content: content
            },
            parent_tool_use_id: null,
            session_id: ''
          } as SDKUserMessage;
        }
      }
    }
    
    // Return the last user message for simple cases
    const userMessages = prompt.filter(m => m.role === 'user');
    if (userMessages.length > 0) {
      const lastUser = userMessages[userMessages.length - 1];
      const content = this.extractMessageContent(lastUser.content);
      console.log('[Claude Code] Prompt:', content);
      return content;
    }
    
    return '';
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
  private cwd?: string;
  private defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;

  constructor(options: { 
    apiKey?: string; // Deprecated - Claude Code uses 'claude setup-token'
    cwd?: string;
    defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;
  } = {}) {
    // apiKey is deprecated - Claude Code uses its own authentication
    this.cwd = options.cwd;
    this.defaultSettings = options.defaultSettings;
  }

  languageModel(modelId: string, settings?: Partial<ClaudeCodeLanguageModelSettings>): ClaudeCodeLanguageModel {
    if (modelId !== 'opus' && modelId !== 'sonnet') {
      throw new Error(`Invalid model ID: ${modelId}. Must be 'opus' or 'sonnet'`);
    }
    
    return new ClaudeCodeLanguageModel({
      model: modelId as 'opus' | 'sonnet',
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
 * 
 * Note: Claude Code uses its own authentication system.
 * Run 'claude setup-token' to authenticate before using.
 */
export function createClaudeCode(options: { 
  apiKey?: string; // Deprecated - use 'claude setup-token' instead
  cwd?: string;
  defaultSettings?: Partial<ClaudeCodeLanguageModelSettings>;
} = {}) {
  return new ClaudeCodeProvider(options);
}