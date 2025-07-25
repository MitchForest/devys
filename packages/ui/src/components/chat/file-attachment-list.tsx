import React from 'react';
import { X, File, FileCode, FileText, FileJson } from 'lucide-react';
import { cn } from '../../lib/utils';
import type { FileAttachment } from '@claude-code-ide/types';

interface FileAttachmentListProps {
  attachments: FileAttachment[];
  onRemove?: (fileId: string) => void;
  className?: string;
}

export function FileAttachmentList({ 
  attachments, 
  onRemove,
  className 
}: FileAttachmentListProps) {
  if (attachments.length === 0) return null;

  const getFileIcon = (file: FileAttachment) => {
    const ext = file.name.split('.').pop()?.toLowerCase();
    
    switch (ext) {
      case 'ts':
      case 'tsx':
      case 'js':
      case 'jsx':
      case 'py':
      case 'java':
      case 'cpp':
      case 'c':
      case 'go':
      case 'rs':
        return <FileCode className="h-4 w-4" />;
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml':
        return <FileJson className="h-4 w-4" />;
      case 'md':
      case 'txt':
      case 'log':
        return <FileText className="h-4 w-4" />;
      default:
        return <File className="h-4 w-4" />;
    }
  };

  return (
    <div className={cn("flex flex-wrap gap-2 p-2 border-t border-border", className)}>
      {attachments.map((file) => (
        <div
          key={file.id || file.path}
          className="flex items-center gap-2 px-3 py-1.5 bg-surface-2 rounded-md text-sm"
        >
          {getFileIcon(file)}
          <span className="max-w-[200px] truncate" title={file.path}>
            {file.name}
          </span>
          {file.content && (
            <span className="text-xs text-muted">
              ({Math.round(file.content.length / 1024)}KB)
            </span>
          )}
          {onRemove && (
            <button
              onClick={() => onRemove(file.id || file.path)}
              className="ml-1 p-0.5 hover:bg-surface-3 rounded"
              aria-label={`Remove ${file.name}`}
            >
              <X className="h-3 w-3" />
            </button>
          )}
        </div>
      ))}
    </div>
  );
}