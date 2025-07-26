import React, { useRef, useEffect, useState, useCallback } from 'react';
import { useChat } from '@ai-sdk/react';
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
  className
}: ChatInterfaceProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [isAutoScrollEnabled, setIsAutoScrollEnabled] = useState(true);

  // Manual input state management (v5 requirement)
  const [chatInput, setChatInput] = useState('');
  
  // Use AI SDK v5's useChat hook with proper transport configuration
  const { messages, sendMessage, stop, status, error, addToolResult } = useChat({
    transport: new DefaultChatTransport({
      api: 'http://localhost:3001/api/chat'
    })
  });
  
  // Determine loading state
  const isLoading = status === 'streaming';


  // Set initial messages when session changes
  useEffect(() => {
    if (session?.messages) {
      // TODO: Sync session messages with useChat
      // The AI SDK's UIMessage type has a different structure than our ChatMessage
      // For now, let useChat manage its own state
    }
  }, [session?.id, session?.messages]);

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatInput.trim() || isLoading) return;
    
    const userMessage = chatInput.trim();
    setChatInput('');
    
    // Use sendMessage from AI SDK v5 - it expects a simple object with text
    if (typeof sendMessage === 'function') {
      await sendMessage({
        text: userMessage
      });
    } else {
      console.error('sendMessage is not a function:', typeof sendMessage, sendMessage);
    }
  };

  // Handle input change
  const handleInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setChatInput(e.target.value);
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
  const convertToChatMessage = (message: any): ChatMessageType => {
    // Extract text content based on message structure
    let textContent = '';
    
    // AI SDK v5 messages use parts array
    if (message.parts && Array.isArray(message.parts)) {
      // Extract text from parts
      const textParts = message.parts
        .filter((part: any) => part.type === 'text')
        .map((part: any) => part.text)
        .join('');
      textContent = textParts;
    } else if (message.text) {
      // Direct text property
      textContent = message.text;
    } else if (message.content) {
      // Legacy content property
      textContent = typeof message.content === 'string' ? message.content : '';
    }
    
    return {
      id: message.id,
      role: message.role as 'user' | 'assistant' | 'system' | 'tool',
      content: textContent,
      timestamp: new Date(),
      createdAt: new Date(),
      toolInvocations: message.toolInvocations // Pass through tool invocations if they exist
    };
  };


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
            <p className="text-lg">Welcome to Devys</p>
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
        value={chatInput}
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