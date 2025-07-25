import React from 'react';
import { User, Bot, Wrench, Copy, Check } from 'lucide-react';
import { cn } from '../../lib/utils';
import type { ChatMessage as ChatMessageType } from '@devys/types';
import { ToolExecutionCard, type ToolArgs, type ToolResult } from './tool-execution-card';
import { MarkdownRenderer } from './markdown-renderer';

interface ChatMessageProps {
  message: ChatMessageType;
  isLoading?: boolean;
  onToolResult?: (toolCallId: string, result: unknown) => void;
}

export function ChatMessage({ message, isLoading, onToolResult: _onToolResult }: ChatMessageProps) {
  const [copied, setCopied] = React.useState(false);
  const isUser = message.role === 'user';
  const isAssistant = message.role === 'assistant';
  const isTool = message.role === 'tool';

  const handleCopy = async () => {
    await navigator.clipboard.writeText(message.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Handle tool execution messages differently
  if (isTool && message.toolInvocations && message.toolInvocations.length > 0) {
    return (
      <div className="px-4 py-2">
        {message.toolInvocations.map((invocation, index) => (
          <ToolExecutionCard
            key={index}
            toolName={invocation.toolName}
            args={invocation.args as ToolArgs}
            result={invocation.result as ToolResult | undefined}
            isExecuting={invocation.state === 'executing'}
          />
        ))}
      </div>
    );
  }

  return (
    <div
      className={cn(
        'group flex gap-3 px-4 py-3 hover:bg-surface-2/50 transition-colors',
        isUser && 'bg-surface-2/30'
      )}
    >
      {/* Avatar */}
      <div
        className={cn(
          'flex-shrink-0 w-8 h-8 rounded-md flex items-center justify-center',
          isUser ? 'bg-primary/10 text-primary' : 
          isTool ? 'bg-surface-4 text-muted' : 'bg-surface-3 text-muted'
        )}
      >
        {isUser ? <User className="h-4 w-4" /> : 
         isTool ? <Wrench className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
      </div>

      {/* Content */}
      <div className="flex-1 space-y-2 overflow-hidden">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium">
            {isUser ? 'You' : 'Claude'}
          </span>
          <span className="text-xs text-muted">
            {new Date(message.timestamp || message.createdAt || new Date()).toLocaleTimeString()}
          </span>
        </div>

        <div className="prose prose-sm max-w-none dark:prose-invert">
          {isLoading ? (
            <div className="flex items-center gap-1">
              <span className="animate-pulse">●</span>
              <span className="animate-pulse animation-delay-150">●</span>
              <span className="animate-pulse animation-delay-300">●</span>
            </div>
          ) : (
            <MessageContent content={message.content} />
          )}
        </div>

        {/* Tool invocations */}
        {message.toolInvocations && message.toolInvocations.length > 0 && (
          <div className="mt-2 space-y-2">
            {message.toolInvocations.map((invocation, index) => (
              <ToolInvocation key={index} invocation={invocation as { toolName: string; args?: Record<string, unknown>; result?: unknown }} />
            ))}
          </div>
        )}

        {/* Actions */}
        {isAssistant && !isLoading && (
          <div className="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              onClick={handleCopy}
              className="flex items-center gap-1 text-xs text-muted hover:text-foreground transition-colors"
            >
              {copied ? (
                <Check className="h-3 w-3" />
              ) : (
                <Copy className="h-3 w-3" />
              )}
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function MessageContent({ content }: { content: string }) {
  return <MarkdownRenderer content={content} />;
}


function ToolInvocation({ invocation }: { invocation: { toolName: string; args?: Record<string, unknown>; result?: unknown } }) {
  return (
    <div className="bg-surface-2 rounded-md p-3 text-sm">
      <div className="flex items-center gap-2 mb-1">
        <span className="text-xs font-medium text-muted">Tool:</span>
        <span className="text-xs">{invocation.toolName}</span>
      </div>
      {invocation.args && (
        <pre className="text-xs text-muted overflow-x-auto">
          {JSON.stringify(invocation.args, null, 2)}
        </pre>
      )}
    </div>
  );
}