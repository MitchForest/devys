import React, { useState } from 'react';
import { Search, FolderOpen, Plus, RefreshCw, Eye, EyeOff } from 'lucide-react';
import { FileTree } from './file-tree';
import { Button } from '../ui/button';
import type { FileNode } from '@devys/types';

interface FileExplorerProps {
  nodes: FileNode[];
  selectedPath?: string;
  onSelectFile?: (path: string) => void;
  onOpenFolder?: (path: string) => void;
  onCreateFile?: (parentPath: string) => void;
  onCreateFolder?: (parentPath: string) => void;
  onRename?: (path: string, newName: string) => void;
  onDelete?: (path: string) => void;
  onCopyPath?: (path: string) => void;
  onCopyRelativePath?: (path: string) => void;
  onCut?: (path: string) => void;
  onCopy?: (path: string) => void;
  onPaste?: (path: string) => void;
  onAttachToChat?: (path: string) => void;
  onRefresh?: () => void;
  onToggleHidden?: () => void;
  showHidden?: boolean;
  projectName?: string;
}

export function FileExplorer({
  nodes,
  selectedPath,
  onSelectFile,
  onOpenFolder,
  onCreateFile,
  onCreateFolder,
  onRename,
  onDelete,
  onCopyPath,
  onCopyRelativePath,
  onCut,
  onCopy,
  onPaste,
  onAttachToChat,
  onRefresh,
  onToggleHidden,
  showHidden: showHiddenProp = true
}: FileExplorerProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const showHidden = showHiddenProp;

  const filterNodes = (nodes: FileNode[], query: string): FileNode[] => {
    if (!query) return nodes;
    
    return nodes.reduce<FileNode[]>((acc, node) => {
      const matches = node.name.toLowerCase().includes(query.toLowerCase());
      
      if (node.type === 'directory' && node.children) {
        const filteredChildren = filterNodes(node.children, query);
        if (filteredChildren.length > 0) {
          acc.push({
            ...node,
            children: filteredChildren
          });
        } else if (matches) {
          acc.push(node);
        }
      } else if (matches) {
        acc.push(node);
      }
      
      return acc;
    }, []);
  };

  const filteredNodes = filterNodes(nodes, searchQuery);

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 py-2 border-b border-panel">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-xs font-medium text-muted">Explorer</h2>
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={() => onCreateFile?.('/')}
            >
              <Plus className="h-3 w-3" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={() => onOpenFolder?.('/')}
              title="Open Folder"
            >
              <FolderOpen className="h-3 w-3" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={onToggleHidden}
              title={showHidden ? "Hide system files" : "Show system files"}
            >
              {showHidden ? <Eye className="h-3 w-3" /> : <EyeOff className="h-3 w-3" />}
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={onRefresh}
            >
              <RefreshCw className="h-3 w-3" />
            </Button>
          </div>
        </div>
        
        <div className="relative">
          <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3 w-3 text-muted pointer-events-none" />
          <input
            type="text"
            placeholder="Search files..."
            className="w-full pl-7 pr-3 py-1.5 text-xs bg-surface-4 border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-ring transition-colors placeholder:text-muted placeholder:text-xs relative"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto scrollbar-zed px-2 py-1">
        {filteredNodes.length > 0 ? (
          <FileTree
            nodes={filteredNodes}
            selectedPath={selectedPath}
            onSelectFile={onSelectFile}
            onOpenFolder={onOpenFolder}
            onCreateFile={onCreateFile}
            onCreateFolder={onCreateFolder}
            onRename={onRename}
            onDelete={onDelete}
            onCopyPath={onCopyPath}
            onCopyRelativePath={onCopyRelativePath}
            onCut={onCut}
            onCopy={onCopy}
            onPaste={onPaste}
            onAttachToChat={onAttachToChat}
          />
        ) : (
          <div className="text-center text-sm text-muted py-8">
            {searchQuery ? 'No files found' : 'No files in workspace'}
          </div>
        )}
      </div>
    </div>
  );
}