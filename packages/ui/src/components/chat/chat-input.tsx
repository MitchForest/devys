import React, { useRef, useEffect } from 'react';
import { Send, Paperclip, X } from 'lucide-react';
import { cn } from '../../lib/utils';
import type { FileAttachment } from '@claude-code-ide/types';

interface ChatInputProps {
  value: string;
  onChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => void;
  onSubmit: (e: React.FormEvent) => void;
  onAttachFile?: () => void;
  attachedFiles?: FileAttachment[];
  onRemoveFile?: (fileId: string) => void;
  isLoading?: boolean;
  placeholder?: string;
  className?: string;
  onStop?: () => void;
}

export function ChatInput({
  value,
  onChange,
  onSubmit,
  onAttachFile,
  attachedFiles = [],
  onRemoveFile,
  isLoading = false,
  placeholder = 'Type a message...',
  className
}: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Auto-resize textarea
  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`;
    }
  }, [value]);

  // Focus on mount
  useEffect(() => {
    textareaRef.current?.focus();
  }, []);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (value.trim() && !isLoading) {
        onSubmit(e as any);
      }
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (value.trim() && !isLoading) {
      onSubmit(e);
    }
  };

  return (
    <form onSubmit={handleSubmit} className={cn('border-t border-border', className)}>
      {/* Attached files */}
      {attachedFiles.length > 0 && (
        <div className="px-4 pt-3 pb-2 flex flex-wrap gap-2">
          {attachedFiles.map((file) => (
            <div
              key={file.id || file.path}
              className="flex items-center gap-2 bg-surface-2 px-3 py-1 rounded-md text-sm"
            >
              <Paperclip className="h-3 w-3 text-muted" />
              <span className="text-xs">{file.name}</span>
              {onRemoveFile && (
                <button
                  type="button"
                  onClick={() => onRemoveFile(file.id || file.path)}
                  className="hover:text-destructive transition-colors"
                >
                  <X className="h-3 w-3" />
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Input area */}
      <div className="flex items-end gap-2 p-4">
        {onAttachFile && (
          <button
            type="button"
            onClick={onAttachFile}
            disabled={isLoading}
            className={cn(
              'p-2 rounded-md transition-colors',
              'hover:bg-surface-2 text-muted hover:text-foreground',
              'disabled:opacity-50 disabled:cursor-not-allowed'
            )}
          >
            <Paperclip className="h-4 w-4" />
          </button>
        )}

        <div className="flex-1 relative">
          <textarea
            ref={textareaRef}
            value={value}
            onChange={onChange}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            disabled={isLoading}
            rows={1}
            className={cn(
              'w-full resize-none bg-surface-2 rounded-md px-3 py-2 pr-10',
              'placeholder:text-muted-foreground',
              'focus:outline-none focus:ring-2 focus:ring-ring',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              'max-h-32 overflow-y-auto'
            )}
            style={{ minHeight: '40px' }}
          />
        </div>

        <button
          type="submit"
          disabled={!value.trim() || isLoading}
          className={cn(
            'p-2 rounded-md transition-colors',
            'bg-primary text-primary-foreground hover:bg-primary/90',
            'disabled:opacity-50 disabled:cursor-not-allowed disabled:bg-surface-2 disabled:text-muted'
          )}
        >
          <Send className="h-4 w-4" />
        </button>
      </div>
    </form>
  );
}