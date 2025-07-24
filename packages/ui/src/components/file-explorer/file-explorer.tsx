import React, { useState } from 'react';
import { Search, FolderOpen, Plus, RefreshCw } from 'lucide-react';
import { FileTree } from './file-tree';
import { Button } from '../ui/button';
import type { FileNode } from '@claude-code-ide/types';

interface FileExplorerProps {
  nodes: FileNode[];
  selectedPath?: string;
  onSelectFile?: (path: string) => void;
  onCreateFile?: (parentPath: string) => void;
  onCreateFolder?: (parentPath: string) => void;
  onRename?: (path: string, newName: string) => void;
  onDelete?: (path: string) => void;
  onCopyPath?: (path: string) => void;
  onCopyRelativePath?: (path: string) => void;
  onCut?: (path: string) => void;
  onCopy?: (path: string) => void;
  onPaste?: (path: string) => void;
  onRefresh?: () => void;
  projectName?: string;
}

export function FileExplorer({
  nodes,
  selectedPath,
  onSelectFile,
  onCreateFile,
  onCreateFolder,
  onRename,
  onDelete,
  onCopyPath,
  onCopyRelativePath,
  onCut,
  onCopy,
  onPaste,
  onRefresh
}: FileExplorerProps) {
  const [searchQuery, setSearchQuery] = useState('');

  const filterNodes = (nodes: FileNode[], query: string): FileNode[] => {
    if (!query) return nodes;
    
    return nodes.reduce<FileNode[]>((acc, node) => {
      const matches = node.name.toLowerCase().includes(query.toLowerCase());
      
      if (node.type === 'directory' && node.children) {
        const filteredChildren = filterNodes(node.children, query);
        if (filteredChildren.length > 0) {
          acc.push({
            ...node,
            children: filteredChildren,
            isExpanded: true
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
      <div className="p-3 border-b border-border">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-sm font-semibold uppercase text-muted-foreground">Explorer</h2>
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
              onClick={() => onCreateFolder?.('/')}
            >
              <FolderOpen className="h-3 w-3" />
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
          <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search files..."
            className="w-full pl-8 pr-3 py-1 text-sm bg-secondary/50 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-ring"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto p-2">
        {filteredNodes.length > 0 ? (
          <FileTree
            nodes={filteredNodes}
            selectedPath={selectedPath}
            onSelectFile={onSelectFile}
            onCreateFile={onCreateFile}
            onCreateFolder={onCreateFolder}
            onRename={onRename}
            onDelete={onDelete}
            onCopyPath={onCopyPath}
            onCopyRelativePath={onCopyRelativePath}
            onCut={onCut}
            onCopy={onCopy}
            onPaste={onPaste}
          />
        ) : (
          <div className="text-center text-sm text-muted-foreground py-8">
            {searchQuery ? 'No files found' : 'No files in workspace'}
          </div>
        )}
      </div>
    </div>
  );
}