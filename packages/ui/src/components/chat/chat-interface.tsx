import React, { useRef, useEffect, useState } from 'react';
import { useChat } from '@ai-sdk/react';
import { ChatMessage } from './chat-message';
import { ChatInput } from './chat-input';
import { cn } from '../../lib/utils';
import type { FileAttachment, ChatSession, ChatMessage as ChatMessageType } from '@claude-code-ide/types';

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
  apiEndpoint = '/api/chat',
  className
}: ChatInterfaceProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [isAutoScrollEnabled, setIsAutoScrollEnabled] = useState(true);
  const [input, setInput] = useState('');

  // Use AI SDK v5's useChat hook
  const {
    messages,
    sendMessage,
    stop,
    status,
    error,
    setMessages,
    addToolResult
  } = useChat({
    api: apiEndpoint,
    body: {
      sessionId: session?.id,
      attachments: attachedFiles
    },
    onFinish: ({ message }) => {
      // Update session with new message
      if (session && onSessionUpdate) {
        const chatMessage: ChatMessageType = {
          id: message.id,
          role: message.role as 'user' | 'assistant' | 'system' | 'tool',
          content: message.content,
          timestamp: new Date(),
          createdAt: new Date(),
          toolInvocations: message.toolInvocations
        };
        
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
      const initialMessages = session.messages.map(msg => ({
        id: msg.id,
        role: msg.role as 'user' | 'assistant' | 'system',
        content: msg.content,
        createdAt: msg.timestamp || msg.createdAt || new Date(),
        toolInvocations: msg.toolInvocations
      }));
      setMessages(initialMessages as any);
    }
  }, [session?.id, setMessages]);

  // Handle form submission
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (input.trim() && status !== 'streaming') {
      sendMessage({
        text: input.trim()
      });
      setInput('');
    }
  };

  // Handle input change
  const handleInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
  };

  // Auto-scroll to bottom when new messages arrive
  const scrollToBottom = () => {
    if (isAutoScrollEnabled) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  // Handle scroll to determine if auto-scroll should be enabled
  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const element = e.currentTarget;
    const isNearBottom = element.scrollHeight - element.scrollTop - element.clientHeight < 50;
    setIsAutoScrollEnabled(isNearBottom);
  };

  // Convert AI SDK message to our ChatMessage type for rendering
  const convertToChatMessage = (message: any): ChatMessageType => {
    return {
      id: message.id,
      role: message.role as 'user' | 'assistant' | 'system' | 'tool',
      content: message.content,
      timestamp: message.createdAt || new Date(),
      createdAt: message.createdAt || new Date(),
      toolInvocations: message.toolInvocations
    };
  };

  // Determine loading state
  const isLoading = status === 'streaming' || status === 'submitted';

  // Handle tool execution results
  const handleToolResult = (toolCallId: string, result: any) => {
    addToolResult({ toolCallId, result });
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