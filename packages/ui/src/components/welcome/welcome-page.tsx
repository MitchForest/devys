import React from 'react';
import { FolderOpen, Clock, Code } from 'lucide-react';

interface WelcomePageProps {
  onOpenFolder?: () => void;
  onOpenRecent?: (path: string) => void;
  recentFolders?: Array<{
    path: string;
    name: string;
    lastOpened: Date;
  }>;
}

export function WelcomePage({
  onOpenFolder,
  onOpenRecent,
  recentFolders = []
}: WelcomePageProps) {
  return (
    <div className="h-full w-full flex items-center justify-center bg-background">
      <div className="max-w-2xl w-full px-8">
        <div className="text-center mb-12">
          <div className="flex justify-center mb-6">
            <Code className="h-16 w-16 text-muted" />
          </div>
          <h1 className="text-2xl font-mono font-normal mb-2 text-foreground">&lt;devys/&gt;</h1>
          <p className="text-sm text-muted-foreground">
            Open a folder to start editing
          </p>
        </div>

        <div className="space-y-8">
          {/* Open Folder */}
          <div className="text-center">
            <button
              onClick={onOpenFolder}
              className="inline-flex items-center gap-2 px-4 py-2 bg-surface-3 text-foreground rounded-md hover:bg-hover transition-zed text-sm"
            >
              <FolderOpen className="h-4 w-4" />
              Open Folder
            </button>
          </div>

          {/* Recent Folders */}
          {recentFolders.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold uppercase text-muted mb-4 flex items-center gap-2">
                <Clock className="h-4 w-4" />
                Recent Folders
              </h2>
              <div className="space-y-2">
                {recentFolders.map((folder, index) => (
                  <button
                    key={index}
                    onClick={() => onOpenRecent?.(folder.path)}
                    className="w-full text-left px-4 py-3 bg-surface-2 rounded-md hover:bg-hover transition-zed group"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3 min-w-0">
                        <FolderOpen className="h-4 w-4 text-muted shrink-0" />
                        <div className="min-w-0">
                          <div className="font-medium truncate">{folder.name}</div>
                          <div className="text-xs text-muted truncate">{folder.path}</div>
                        </div>
                      </div>
                      <div className="text-xs text-muted ml-4 shrink-0">
                        {new Date(folder.lastOpened).toLocaleDateString()}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Keyboard Shortcuts */}
          <div className="text-center text-xs text-muted">
            <div className="space-y-1">
              <div>
                <kbd className="px-1.5 py-0.5 bg-surface-2 rounded-sm text-xs">⌘O</kbd> Open Folder
              </div>
              <div>
                <kbd className="px-1.5 py-0.5 bg-surface-2 rounded-sm text-xs">⌘T</kbd> New Terminal
              </div>
              <div>
                <kbd className="px-1.5 py-0.5 bg-surface-2 rounded-sm text-xs">⌘⇧C</kbd> Toggle Chat
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}