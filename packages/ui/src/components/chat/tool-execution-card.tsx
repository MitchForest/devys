import React, { useState } from 'react';
import { 
  FileEdit, 
  Terminal, 
  FileText, 
  FilePlus, 
  FolderOpen,
  Search,
  ChevronDown,
  ChevronRight,
  Check,
  X
} from 'lucide-react';
import { cn } from '../../lib/utils';

export interface ToolArgs {
  file_path?: string;
  command?: string;
  pattern?: string;
  path?: string;
  content?: string;
  old_string?: string;
  new_string?: string;
  edits?: Array<{
    old_string?: string;
    new_string?: string;
    replace_all?: boolean;
  }>;
  query?: string;
  url?: string;
  description?: string;
  limit?: number;
  offset?: number;
}

export interface ToolResult {
  success?: boolean;
  error?: string;
  output?: string;
  content?: string;
  message?: string;
  files?: string[];
  // matches can be either file paths (string[]) or grep results
  matches?: string[] | GrepMatch[];
}

interface GrepMatch {
  file: string;
  line: number;
  content: string;
}

interface ToolExecutionCardProps {
  toolName: string;
  args: ToolArgs;
  result?: ToolResult;
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
      case 'FileEdit':
      case 'FileMultiEdit':
        return <FileEdit className="h-4 w-4" />;
      case 'Bash':
        return <Terminal className="h-4 w-4" />;
      case 'Read':
        return <FileText className="h-4 w-4" />;
      case 'Write':
        return <FilePlus className="h-4 w-4" />;
      case 'LS':
      case 'Glob':
        return <FolderOpen className="h-4 w-4" />;
      case 'Grep':
      case 'WebSearch':
        return <Search className="h-4 w-4" />;
      default:
        return <Terminal className="h-4 w-4" />;
    }
  };

  const getTitle = () => {
    switch (toolName) {
      case 'FileEdit':
        return `Editing ${args.file_path}`;
      case 'FileMultiEdit':
        return `Editing ${args.file_path} (${args.edits?.length || 0} changes)`;
      case 'Bash':
        return `Running: ${args.command}`;
      case 'Read':
        return `Reading ${args.file_path}`;
      case 'Write':
        return `Writing to ${args.file_path}`;
      case 'LS':
        return `Listing ${args.path || 'directory'}`;
      case 'Grep':
        return `Searching for "${args.pattern}"`;
      case 'Glob':
        return `Finding files: ${args.pattern}`;
      case 'WebSearch':
        return `Searching web: "${args.query}"`;
      case 'WebFetch':
        return `Fetching ${args.url}`;
      case 'Agent':
        return `Spawning agent: ${args.description}`;
      case 'TodoWrite':
        return `Updating todo list`;
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
          
          {/* Approval buttons for destructive tools */}
          {(toolName === 'FileEdit' || toolName === 'FileMultiEdit' || toolName === 'Write' || 
            toolName === 'Bash' || toolName === 'Agent') && 
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

function ToolContent({ toolName, args, result, isExecuting }: {
  toolName: string;
  args: ToolArgs;
  result?: ToolResult;
  isExecuting?: boolean;
}) {
  switch (toolName) {
    case 'FileEdit':
    case 'FileMultiEdit':
      return <FileEditContent args={args} result={result} toolName={toolName} />;
    
    case 'Bash':
      return <TerminalContent args={args} result={result} isExecuting={isExecuting} />;
    
    case 'Read':
      return <FileReadContent args={args} result={result} />;
    
    case 'Write':
      return <FileWriteContent args={args} result={result} />;
    
    case 'Grep':
      return <SearchContent args={args} result={result} />;
    
    case 'LS':
    case 'Glob':
      return <FileListContent args={args} result={result} />;
    
    default:
      return <GenericContent args={args} result={result} />;
  }
}

function FileEditContent({ args, result, toolName }: {
  args: ToolArgs;
  result?: ToolResult;
  toolName: string;
}) {
  // Handle FileMultiEdit
  if (toolName === 'FileMultiEdit' && args.edits) {
    return (
      <div className="p-3 space-y-3">
        {args.edits.map((edit, index: number) => (
          <div key={index} className="space-y-2 border-b border-border pb-2 last:border-0">
            <div className="text-xs text-muted">Edit {index + 1}:</div>
            {edit.old_string && (
              <div>
                <div className="text-xs text-muted mb-1">Remove:</div>
                <pre className="bg-red-500/10 text-red-500 p-2 rounded text-xs overflow-x-auto">
                  {edit.old_string}
                </pre>
              </div>
            )}
            {edit.new_string && (
              <div>
                <div className="text-xs text-muted mb-1">Add:</div>
                <pre className="bg-green-500/10 text-green-500 p-2 rounded text-xs overflow-x-auto">
                  {edit.new_string}
                </pre>
              </div>
            )}
          </div>
        ))}
        {result?.error && (
          <div className="text-xs text-destructive">{result.error}</div>
        )}
      </div>
    );
  }

  // Handle single FileEdit
  return (
    <div className="p-3 space-y-2">
      {args.old_string && (
        <div>
          <div className="text-xs text-muted mb-1">Remove:</div>
          <pre className="bg-red-500/10 text-red-500 p-2 rounded text-xs overflow-x-auto">
            {args.old_string}
          </pre>
        </div>
      )}
      {args.new_string && (
        <div>
          <div className="text-xs text-muted mb-1">Add:</div>
          <pre className="bg-green-500/10 text-green-500 p-2 rounded text-xs overflow-x-auto">
            {args.new_string}
          </pre>
        </div>
      )}
      {result?.error && (
        <div className="text-xs text-destructive">{result.error}</div>
      )}
    </div>
  );
}

function TerminalContent({ args, result, isExecuting }: {
  args: ToolArgs;
  result?: ToolResult;
  isExecuting?: boolean;
}) {
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

function FileReadContent({ args: _args, result }: {
  args: ToolArgs;
  result?: ToolResult;
}) {
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

function FileWriteContent({ args, result }: {
  args: ToolArgs;
  result?: ToolResult;
}) {
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

function SearchContent({ args, result }: {
  args: ToolArgs;
  result?: ToolResult;
}) {
  return (
    <div className="p-3 space-y-2">
      <div className="text-xs text-muted">
        Pattern: <code className="bg-surface-3 px-1 rounded">{args.pattern}</code>
      </div>
      {result?.matches && Array.isArray(result.matches) && (
        <div className="space-y-1">
          {result.matches.map((match: string | GrepMatch, i: number) => {
            if (typeof match === 'string') {
              return (
                <div key={i} className="text-xs font-mono">
                  {match}
                </div>
              );
            } else {
              return (
                <div key={i} className="text-xs">
                  <span className="text-primary">{match.file}:{match.line}</span>
                  <pre className="bg-surface-1 rounded p-1 mt-1">{match.content}</pre>
                </div>
              );
            }
          })}
        </div>
      )}
      {result?.error && (
        <div className="text-xs text-destructive">{result.error}</div>
      )}
    </div>
  );
}

function FileListContent({ args: _args, result }: {
  args: ToolArgs;
  result?: ToolResult;
}) {
  return (
    <div className="p-3">
      {result?.files && Array.isArray(result.files) && (
        <div className="space-y-1">
          {result.files.map((file: string, i: number) => (
            <div key={i} className="text-xs font-mono">
              {file}
            </div>
          ))}
        </div>
      )}
      {result?.matches && Array.isArray(result.matches) && (
        <div className="space-y-1">
          {/* FileListContent only deals with string matches (file paths) */}
          {(result.matches as string[]).map((match, i) => (
            <div key={i} className="text-xs font-mono">
              {match}
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

function GenericContent({ args, result }: {
  args: ToolArgs;
  result?: ToolResult;
}) {
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