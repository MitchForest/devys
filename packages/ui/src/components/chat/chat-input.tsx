import React, { useRef, useEffect } from 'react';
import { Send, Paperclip, X, Image, ArrowUp, AtSign, ChevronDown } from 'lucide-react';
import { cn } from '../../lib/utils';
import { Badge } from '../ui/badge';
import { Button } from '../ui/button';
import type { FileAttachment } from '@devys/types';

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
        onSubmit(e as unknown as React.FormEvent);
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
      <div className="p-4">
        <div className="bg-surface-2 rounded-lg p-3 space-y-2">
          {/* First row - Context badge */}
          <div className="flex items-center">
            <Badge
              variant="secondary"
              className="cursor-pointer hover:bg-hover transition-zed"
              onClick={() => console.log('Add context')}
            >
              <AtSign className="h-3 w-3 mr-1" />
              Add Context
            </Badge>
          </div>
          
          {/* Second row - Text input */}
          <div className="relative">
            <textarea
              ref={textareaRef}
              value={value}
              onChange={onChange}
              onKeyDown={handleKeyDown}
              placeholder="Plan, search, execute..."
              disabled={isLoading}
              rows={1}
              className={cn(
                'w-full resize-none bg-transparent',
                'placeholder:text-muted-foreground text-sm',
                'focus:outline-none',
                'disabled:opacity-50 disabled:cursor-not-allowed',
                'min-h-[2.5rem] max-h-32'
              )}
            />
          </div>
          
          {/* Third row - Model selector and action buttons */}
          <div className="flex items-center justify-between">
            <Badge
              variant="secondary"
              className="cursor-pointer hover:bg-hover transition-zed"
              onClick={() => console.log('Select model')}
            >
              Claude 3.5 Sonnet
              <ChevronDown className="h-3 w-3 ml-1" />
            </Badge>
            
            <div className="flex items-center gap-2">
              {onAttachFile && (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={onAttachFile}
                  disabled={isLoading}
                  className="h-7 w-7"
                >
                  <Image className="h-4 w-4" />
                </Button>
              )}
              <Button
                type="submit"
                size="icon"
                disabled={!value.trim() || isLoading}
                className="h-7 w-7 rounded-full"
              >
                <ArrowUp className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      </div>
    </form>
  );
}