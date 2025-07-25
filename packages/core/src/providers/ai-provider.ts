import type { 
  ChatMessage, 
  StreamingOptions, 
  ToolDefinition,
  ProjectContext,
  FileAttachment,
  AIProviderConfig
} from '@devys/types';

/**
 * Base interface for AI providers
 */
export interface AIProvider {
  /**
   * Provider name for display
   */
  name: string;

  /**
   * Stream a chat response
   */
  streamChat(
    messages: ChatMessage[],
    options?: StreamingOptions & {
      tools?: Record<string, ToolDefinition>;
      projectContext?: ProjectContext;
      attachments?: FileAttachment[];
    }
  ): AsyncGenerator<ChatMessage>;

  /**
   * Generate a single chat response (non-streaming)
   */
  generateChat(
    messages: ChatMessage[],
    options?: {
      tools?: Record<string, ToolDefinition>;
      projectContext?: ProjectContext;
      attachments?: FileAttachment[];
    }
  ): Promise<ChatMessage>;

  /**
   * Update provider configuration
   */
  updateConfig(config: Partial<AIProviderConfig>): void;
}

/**
 * Factory for creating AI providers
 */
export interface AIProviderFactory {
  create(config: AIProviderConfig): AIProvider;
}