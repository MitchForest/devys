import React, { useState } from 'react';
import { 
  FileEdit, 
  Terminal, 
  FileText, 
  FilePlus, 
  FolderOpen,
  Search,
  GitBranch,
  ChevronDown,
  ChevronRight,
  Check,
  X
} from 'lucide-react';
import { cn } from '../../lib/utils';

interface ToolExecutionCardProps {
  toolName: string;
  args: any;
  result?: any;
  isExecuting?: boolean;
  onApprove?: () => void;
  onReject?: () => void;
}

export function ToolExecutionCard({ 
  toolName, 
  args, 
  result,
  isExecuting = false,
  onApprove,
  onReject
}: ToolExecutionCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  const getIcon = () => {
    switch (toolName) {
      case 'str_replace':
        return <FileEdit className="h-4 w-4" />;
      case 'bash':
        return <Terminal className="h-4 w-4" />;
      case 'read_file':
        return <FileText className="h-4 w-4" />;
      case 'write_file':
      case 'create_file':
        return <FilePlus className="h-4 w-4" />;
      case 'list_files':
        return <FolderOpen className="h-4 w-4" />;
      case 'search':
        return <Search className="h-4 w-4" />;
      case 'git':
        return <GitBranch className="h-4 w-4" />;
      default:
        return <Terminal className="h-4 w-4" />;
    }
  };

  const getTitle = () => {
    switch (toolName) {
      case 'str_replace':
        return `Editing ${args.path}`;
      case 'bash':
        return `Running: ${args.command}`;
      case 'read_file':
        return `Reading ${args.path}`;
      case 'write_file':
        return `Writing to ${args.path}`;
      case 'create_file':
        return `Creating ${args.path}`;
      case 'list_files':
        return `Listing ${args.path || 'directory'}`;
      case 'search':
        return `Searching for "${args.pattern}"`;
      case 'git':
        return `Git: ${args.command}`;
      default:
        return toolName;
    }
  };

  return (
    <div className={cn(
      "my-2 rounded-md border bg-surface-2",
      isExecuting && "animate-pulse"
    )}>
      {/* Header */}
      <div 
        className="flex items-center gap-2 p-3 cursor-pointer hover:bg-surface-3 transition-colors"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <button className="hover:bg-surface-4 rounded p-1">
          {isExpanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
        </button>
        <div className={cn(
          "flex items-center gap-2 flex-1",
          isExecuting ? "text-muted" : "text-foreground"
        )}>
          {getIcon()}
          <span className="text-sm font-medium">{getTitle()}</span>
        </div>
        
        {/* Status indicator */}
        {isExecuting && (
          <span className="text-xs text-muted">Executing...</span>
        )}
        {!isExecuting && result?.success && (
          <Check className="h-4 w-4 text-green-500" />
        )}
        {!isExecuting && result?.error && (
          <X className="h-4 w-4 text-destructive" />
        )}
      </div>

      {/* Expanded content */}
      {isExpanded && (
        <div className="border-t border-border">
          {/* Tool-specific content */}
          <ToolContent 
            toolName={toolName} 
            args={args} 
            result={result}
            isExecuting={isExecuting}
          />
          
          {/* Approval buttons for certain tools */}
          {(toolName === 'str_replace' || toolName === 'write_file' || toolName === 'create_file') && 
           !isExecuting && onApprove && onReject && (
            <div className="flex gap-2 p-3 border-t border-border">
              <button
                onClick={onApprove}
                className="flex items-center gap-1 px-3 py-1 bg-primary text-primary-foreground rounded-md text-sm hover:bg-primary/90"
              >
                <Check className="h-3 w-3" />
                Approve
              </button>
              <button
                onClick={onReject}
                className="flex items-center gap-1 px-3 py-1 bg-surface-3 text-foreground rounded-md text-sm hover:bg-surface-4"
              >
                <X className="h-3 w-3" />
                Reject
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function ToolContent({ toolName, args, result, isExecuting }: any) {
  switch (toolName) {
    case 'str_replace':
      return <FileEditContent args={args} result={result} />;
    
    case 'bash':
      return <TerminalContent args={args} result={result} isExecuting={isExecuting} />;
    
    case 'read_file':
      return <FileReadContent args={args} result={result} />;
    
    case 'write_file':
    case 'create_file':
      return <FileWriteContent args={args} result={result} />;
    
    case 'search':
      return <SearchContent args={args} result={result} />;
    
    default:
      return <GenericContent args={args} result={result} />;
  }
}

function FileEditContent({ args, result }: any) {
  return (
    <div className="p-3 space-y-2">
      {args.old_str && (
        <div>
          <div className="text-xs text-muted mb-1">Remove:</div>
          <pre className="bg-red-500/10 text-red-500 p-2 rounded text-xs overflow-x-auto">
            {args.old_str}
          </pre>
        </div>
      )}
      {args.new_str && (
        <div>
          <div className="text-xs text-muted mb-1">Add:</div>
          <pre className="bg-green-500/10 text-green-500 p-2 rounded text-xs overflow-x-auto">
            {args.new_str}
          </pre>
        </div>
      )}
      {result?.error && (
        <div className="text-xs text-destructive">{result.error}</div>
      )}
    </div>
  );
}

function TerminalContent({ args, result, isExecuting }: any) {
  return (
    <div className="p-3">
      <div className="bg-surface-1 rounded p-3 font-mono text-xs">
        <div className="text-muted mb-2">$ {args.command}</div>
        {result?.output && (
          <pre className="whitespace-pre-wrap text-foreground">
            {result.output}
          </pre>
        )}
        {result?.error && (
          <pre className="whitespace-pre-wrap text-destructive">
            {result.error}
          </pre>
        )}
        {isExecuting && (
          <div className="text-muted animate-pulse">Running...</div>
        )}
      </div>
    </div>
  );
}

function FileReadContent({ args, result }: any) {
  const [showFull, setShowFull] = useState(false);
  const content = result?.content || '';
  const lines = content.split('\n');
  const preview = lines.slice(0, 10).join('\n');
  const hasMore = lines.length > 10;

  return (
    <div className="p-3">
      <pre className="bg-surface-1 rounded p-3 text-xs overflow-x-auto">
        {showFull ? content : preview}
      </pre>
      {hasMore && !showFull && (
        <button
          onClick={() => setShowFull(true)}
          className="text-xs text-primary hover:underline mt-2"
        >
          Show all {lines.length} lines
        </button>
      )}
      {result?.error && (
        <div className="text-xs text-destructive mt-2">{result.error}</div>
      )}
    </div>
  );
}

function FileWriteContent({ args, result }: any) {
  return (
    <div className="p-3">
      {args.content && (
        <pre className="bg-surface-1 rounded p-3 text-xs overflow-x-auto max-h-48">
          {args.content}
        </pre>
      )}
      {result?.message && (
        <div className="text-xs text-muted mt-2">{result.message}</div>
      )}
      {result?.error && (
        <div className="text-xs text-destructive mt-2">{result.error}</div>
      )}
    </div>
  );
}

function SearchContent({ args, result }: any) {
  return (
    <div className="p-3 space-y-2">
      <div className="text-xs text-muted">
        Pattern: <code className="bg-surface-3 px-1 rounded">{args.pattern}</code>
      </div>
      {result?.matches && (
        <div className="space-y-1">
          {result.matches.map((match: any, i: number) => (
            <div key={i} className="text-xs">
              <span className="text-primary">{match.file}:{match.line}</span>
              <pre className="bg-surface-1 rounded p-1 mt-1">{match.content}</pre>
            </div>
          ))}
        </div>
      )}
      {result?.error && (
        <div className="text-xs text-destructive">{result.error}</div>
      )}
    </div>
  );
}

function GenericContent({ args, result }: any) {
  return (
    <div className="p-3 space-y-2">
      <div>
        <div className="text-xs text-muted mb-1">Arguments:</div>
        <pre className="bg-surface-1 rounded p-2 text-xs overflow-x-auto">
          {JSON.stringify(args, null, 2)}
        </pre>
      </div>
      {result && (
        <div>
          <div className="text-xs text-muted mb-1">Result:</div>
          <pre className="bg-surface-1 rounded p-2 text-xs overflow-x-auto">
            {JSON.stringify(result, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}