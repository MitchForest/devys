import React from 'react';
import { User, Bot, Copy, Check, Wrench } from 'lucide-react';
import { cn } from '../../lib/utils';
import type { ChatMessage as ChatMessageType } from '@claude-code-ide/types';
import { ToolExecutionCard } from './tool-execution-card';

interface ChatMessageProps {
  message: ChatMessageType;
  isLoading?: boolean;
}

export function ChatMessage({ message, isLoading }: ChatMessageProps) {
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
            args={invocation.args}
            result={invocation.result}
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
              <ToolInvocation key={index} invocation={invocation} />
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
  // Parse markdown and code blocks
  const parts = content.split(/(```[\s\S]*?```)/g);

  return (
    <>
      {parts.map((part, index) => {
        if (part.startsWith('```')) {
          const lines = part.split('\n');
          const language = lines[0].replace('```', '').trim();
          const code = lines.slice(1, -1).join('\n');

          return (
            <CodeBlock
              key={index}
              language={language}
              code={code}
            />
          );
        }

        return (
          <span
            key={index}
            dangerouslySetInnerHTML={{
              __html: part
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/\*(.*?)\*/g, '<em>$1</em>')
                .replace(/`(.*?)`/g, '<code>$1</code>')
                .replace(/\n/g, '<br />')
            }}
          />
        );
      })}
    </>
  );
}

function CodeBlock({ language, code }: { language: string; code: string }) {
  const [copied, setCopied] = React.useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="relative group my-2">
      <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
        <button
          onClick={handleCopy}
          className="flex items-center gap-1 text-xs bg-surface-2 hover:bg-surface-3 px-2 py-1 rounded transition-colors"
        >
          {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <pre className="bg-surface-3 rounded-md p-3 overflow-x-auto">
        <code className={`language-${language}`}>{code}</code>
      </pre>
    </div>
  );
}

function ToolInvocation({ invocation }: { invocation: any }) {
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