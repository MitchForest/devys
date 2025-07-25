import React, { useRef, useEffect, useState, useCallback } from 'react';
import { useChat, type UIMessage as Message } from '@ai-sdk/react';
import { DefaultChatTransport } from 'ai';
import { ChatMessage } from './chat-message';
import { ChatInput } from './chat-input';
import { cn } from '../../lib/utils';
import type { FileAttachment, ChatSession, ChatMessage as ChatMessageType } from '@devys/types';

interface ChatInterfaceProps {
  session?: ChatSession;
  onSessionUpdate?: (session: ChatSession) => void;
  attachedFiles?: FileAttachment[];
  onAttachFile?: () => void;
  onRemoveFile?: (fileId: string) => void;
  apiEndpoint?: string;
  className?: string;
}

export function ChatInterface({
  session,
  onSessionUpdate,
  attachedFiles = [],
  onAttachFile,
  onRemoveFile,
  apiEndpoint = 'http://localhost:3001/api/chat',
  className
}: ChatInterfaceProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [isAutoScrollEnabled, setIsAutoScrollEnabled] = useState(true);
  const [input, setInput] = useState<string>('');

  // Use AI SDK v5's useChat hook
  const {
    messages,
    sendMessage,
    stop,
    status,
    error,
    setMessages: _setMessages,
    addToolResult
  } = useChat({
    transport: new DefaultChatTransport({
      api: apiEndpoint,
      body: {
        sessionId: session?.id,
        attachments: attachedFiles
      },
      headers: {
        'X-Session-Id': session?.id || ''
      }
    }),
    onFinish: ({ message }) => {
      // Update session with new message
      if (session && onSessionUpdate) {
        const chatMessage = convertToChatMessage(message);
        
        const updatedSession: ChatSession = {
          ...session,
          messages: [...session.messages, chatMessage],
          updatedAt: new Date()
        };
        onSessionUpdate(updatedSession);
      }
    },
    onError: (error) => {
      console.error('Chat error:', error);
    },
    experimental_throttle: 50 // Throttle UI updates for performance
  });

  // Set initial messages when session changes
  useEffect(() => {
    if (session?.messages) {
      // TODO: Sync session messages with useChat
      // The AI SDK's UIMessage type has a different structure than our ChatMessage
      // For now, let useChat manage its own state
    }
  }, [session?.id, session?.messages]);

  // Handle form submission
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (input.trim() && status !== 'streaming') {
      // Call sendMessage with just the content string
      // The AI SDK will handle creating the message object
      (sendMessage as any)(input.trim());
      setInput('');
    }
  };

  // Handle input change
  const handleInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
  };

  // Auto-scroll to bottom when new messages arrive
  const scrollToBottom = useCallback(() => {
    if (isAutoScrollEnabled) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [isAutoScrollEnabled]);

  useEffect(() => {
    scrollToBottom();
  }, [messages, scrollToBottom]);

  // Handle scroll to determine if auto-scroll should be enabled
  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const element = e.currentTarget;
    const isNearBottom = element.scrollHeight - element.scrollTop - element.clientHeight < 50;
    setIsAutoScrollEnabled(isNearBottom);
  };

  // Convert AI SDK message to our ChatMessage type for rendering
  const convertToChatMessage = (message: Message): ChatMessageType => {
    // Extract text content based on message structure
    let textContent = '';
    
    // Handle different message formats
    const msg = message as any;
    if (typeof msg.content === 'string') {
      textContent = msg.content;
    } else if ('content' in msg && msg.content) {
      textContent = String(msg.content);
    } else if ('text' in msg) {
      textContent = msg.text || '';
    }
    
    return {
      id: message.id,
      role: message.role as 'user' | 'assistant' | 'system' | 'tool',
      content: textContent,
      timestamp: new Date(),
      createdAt: new Date(),
      toolInvocations: (message as any).toolInvocations // Pass through tool invocations if they exist
    };
  };

  // Determine loading state
  const isLoading = status === 'streaming' || status === 'submitted';

  // Handle tool execution results
  const handleToolResult = (toolCallId: string, result: unknown) => {
    addToolResult({ tool: toolCallId, toolCallId, output: result });
  };

  return (
    <div className={cn("flex flex-col h-full", className)}>
      {/* Messages Area */}
      <div 
        className="flex-1 overflow-y-auto p-4 space-y-4"
        onScroll={handleScroll}
      >
        {messages.length === 0 ? (
          <div className="text-center text-gray-500 mt-8">
            <p className="text-lg">Welcome to Claude Code IDE</p>
            <p className="text-sm mt-2">Start a conversation or attach files to begin</p>
          </div>
        ) : (
          messages.map((message) => (
            <ChatMessage 
              key={message.id} 
              message={convertToChatMessage(message)}
              onToolResult={handleToolResult}
            />
          ))
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Error Display */}
      {error && (
        <div className="px-4 py-2 bg-red-50 border-t border-red-200 text-red-700 text-sm">
          Error: {error.message}
        </div>
      )}

      {/* Status Display for debugging */}
      {process.env.NODE_ENV === 'development' && (
        <div className="px-4 py-1 bg-gray-100 text-xs text-gray-600">
          Status: {status}
        </div>
      )}

      {/* Input Area */}
      <ChatInput
        value={input}
        onChange={handleInputChange}
        onSubmit={handleSubmit}
        isLoading={isLoading}
        attachedFiles={attachedFiles}
        onAttachFile={onAttachFile}
        onRemoveFile={onRemoveFile}
        onStop={stop}
        placeholder={isLoading ? 'Claude is thinking...' : 'Type your message...'}
      />
    </div>
  );
}