import React, { useState, useCallback } from 'react';
import { 
  ChevronRight, 
  ChevronDown, 
  File, 
  Folder, 
  FolderOpen,
  FileCode,
  FileJson,
  FileText,
  Image,
  Plus,
  Trash2,
  Edit3
} from 'lucide-react';
import { cn } from '../../lib/utils';
import type { FileNode, GitStatus } from '@claude-code-ide/types';

interface FileTreeProps {
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
}

const getFileIcon = (name: string) => {
  const ext = name.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'ts':
    case 'tsx':
    case 'js':
    case 'jsx':
      return FileCode;
    case 'json':
    case 'jsonc':
      return FileJson;
    case 'md':
    case 'txt':
      return FileText;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'svg':
      return Image;
    default:
      return File;
  }
};

const getGitStatusColor = (status?: GitStatus) => {
  switch (status) {
    case 'modified':
      return 'text-yellow-600 dark:text-yellow-400';
    case 'added':
      return 'text-green-600 dark:text-green-400';
    case 'deleted':
      return 'text-red-600 dark:text-red-400';
    case 'renamed':
      return 'text-blue-600 dark:text-blue-400';
    case 'untracked':
      return 'text-gray-500 dark:text-gray-400';
    default:
      return '';
  }
};

const getGitStatusIndicator = (status?: GitStatus) => {
  switch (status) {
    case 'modified':
      return 'M';
    case 'added':
      return 'A';
    case 'deleted':
      return 'D';
    case 'renamed':
      return 'R';
    case 'untracked':
      return 'U';
    default:
      return null;
  }
};

export function FileTree({ 
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
  onPaste
}: FileTreeProps) {
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [renamingPath, setRenamingPath] = useState<string | null>(null);

  const toggleFolder = useCallback((path: string) => {
    setExpandedFolders(prev => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  }, []);

  const handleRename = useCallback((path: string, newName: string) => {
    if (onRename && newName.trim()) {
      onRename(path, newName.trim());
    }
    setRenamingPath(null);
  }, [onRename]);

  const renderNode = (node: FileNode, depth: number = 0): React.ReactNode => {
    const isExpanded = expandedFolders.has(node.path);
    const isSelected = selectedPath === node.path;
    const isRenaming = renamingPath === node.path;
    const gitIndicator = getGitStatusIndicator(node.gitStatus);

    return (
      <div key={node.id}>
        <div
          className={cn(
            'group flex items-center gap-1 px-2 py-1 text-sm cursor-pointer hover:bg-accent rounded-sm',
            isSelected && 'bg-accent',
            getGitStatusColor(node.gitStatus)
          )}
          style={{ paddingLeft: `${depth * 12 + 8}px` }}
          onClick={() => {
            if (node.type === 'directory') {
              toggleFolder(node.path);
            } else {
              onSelectFile?.(node.path);
            }
          }}
          onContextMenu={(e) => {
            e.preventDefault();
            const menu = document.createElement('div');
            menu.style.cssText = `
              position: fixed;
              top: ${e.clientY}px;
              left: ${e.clientX}px;
              background: white;
              border: 1px solid #ccc;
              border-radius: 4px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.1);
              padding: 4px 0;
              z-index: 1000;
              min-width: 160px;
            `;
            
            const menuItems = [
              ...(node.type === 'directory' ? [
                { label: 'New File', action: () => onCreateFile?.(node.path) },
                { label: 'New Folder', action: () => onCreateFolder?.(node.path) },
                { divider: true },
              ] : []),
              { label: 'Cut', action: () => onCut?.(node.path) },
              { label: 'Copy', action: () => onCopy?.(node.path) },
              { label: 'Paste', action: () => onPaste?.(node.path) },
              { divider: true },
              { label: 'Rename', action: () => setRenamingPath(node.path) },
              { label: 'Delete', action: () => onDelete?.(node.path) },
              { divider: true },
              { label: 'Copy Path', action: () => onCopyPath?.(node.path) },
              { label: 'Copy Relative Path', action: () => onCopyRelativePath?.(node.path) },
            ];
            
            menuItems.forEach(item => {
              if (item.divider) {
                const divider = document.createElement('hr');
                divider.style.cssText = 'margin: 4px 0; border: none; border-top: 1px solid #e5e5e5;';
                menu.appendChild(divider);
              } else {
                const menuItem = document.createElement('div');
                menuItem.textContent = item.label!;
                menuItem.style.cssText = `
                  padding: 6px 12px;
                  cursor: pointer;
                  font-size: 14px;
                  color: #333;
                `;
                menuItem.onmouseover = () => {
                  menuItem.style.backgroundColor = '#f0f0f0';
                };
                menuItem.onmouseout = () => {
                  menuItem.style.backgroundColor = 'transparent';
                };
                menuItem.onclick = () => {
                  item.action!();
                  document.body.removeChild(menu);
                };
                menu.appendChild(menuItem);
              }
            });
            
            document.body.appendChild(menu);
            
            const closeMenu = (e: MouseEvent) => {
              if (!menu.contains(e.target as Node)) {
                document.body.removeChild(menu);
                document.removeEventListener('click', closeMenu);
              }
            };
            
            setTimeout(() => {
              document.addEventListener('click', closeMenu);
            }, 0);
          }}
        >
          {node.type === 'directory' ? (
            <>
              {isExpanded ? (
                <ChevronDown className="h-4 w-4 shrink-0" />
              ) : (
                <ChevronRight className="h-4 w-4 shrink-0" />
              )}
              {isExpanded ? (
                <FolderOpen className="h-4 w-4 shrink-0" />
              ) : (
                <Folder className="h-4 w-4 shrink-0" />
              )}
            </>
          ) : (
            <>
              <span className="w-4" />
              {React.createElement(getFileIcon(node.name), {
                className: 'h-4 w-4 shrink-0'
              })}
            </>
          )}
          
          {isRenaming ? (
            <input
              type="text"
              defaultValue={node.name}
              className="flex-1 bg-transparent border-b border-input outline-none"
              onBlur={(e) => handleRename(node.path, e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  handleRename(node.path, e.currentTarget.value);
                } else if (e.key === 'Escape') {
                  setRenamingPath(null);
                }
              }}
              onClick={(e) => e.stopPropagation()}
              autoFocus
            />
          ) : (
            <span className="flex-1 truncate">{node.name}</span>
          )}
          
          {gitIndicator && (
            <span className="ml-auto text-xs font-bold">{gitIndicator}</span>
          )}
          
          <div className="hidden group-hover:flex items-center gap-1">
            {node.type === 'directory' && (
              <>
                <button
                  className="p-1 hover:bg-background rounded"
                  onClick={(e) => {
                    e.stopPropagation();
                    onCreateFile?.(node.path);
                  }}
                >
                  <Plus className="h-3 w-3" />
                </button>
                <button
                  className="p-1 hover:bg-background rounded"
                  onClick={(e) => {
                    e.stopPropagation();
                    onCreateFolder?.(node.path);
                  }}
                >
                  <Folder className="h-3 w-3" />
                </button>
              </>
            )}
            <button
              className="p-1 hover:bg-background rounded"
              onClick={(e) => {
                e.stopPropagation();
                setRenamingPath(node.path);
              }}
            >
              <Edit3 className="h-3 w-3" />
            </button>
            <button
              className="p-1 hover:bg-background rounded"
              onClick={(e) => {
                e.stopPropagation();
                onDelete?.(node.path);
              }}
            >
              <Trash2 className="h-3 w-3" />
            </button>
          </div>
        </div>
        
        {node.type === 'directory' && isExpanded && node.children && (
          <div>
            {node.children.map(child => renderNode(child, depth + 1))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="select-none">
      {nodes.map(node => renderNode(node))}
    </div>
  );
}