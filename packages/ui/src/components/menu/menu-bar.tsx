import React from 'react';
import { Terminal, Split, X } from 'lucide-react';

interface MenuBarProps {
  onNewTerminal?: () => void;
  onSplitTerminal?: () => void;
  onCloseTerminal?: () => void;
  onOpenFolder?: () => void;
  onOpenRecent?: (path: string) => void;
  recentFolders?: string[];
}

export function MenuBar({
  onNewTerminal,
  onSplitTerminal,
  onCloseTerminal,
  onOpenFolder,
  onOpenRecent,
  recentFolders = []
}: MenuBarProps) {
  const [activeMenu, setActiveMenu] = React.useState<string | null>(null);

  const handleMenuClick = (menu: string) => {
    setActiveMenu(activeMenu === menu ? null : menu);
  };

  const handleClickOutside = React.useCallback(() => {
    setActiveMenu(null);
  }, []);

  React.useEffect(() => {
    if (activeMenu) {
      document.addEventListener('click', handleClickOutside);
      return () => document.removeEventListener('click', handleClickOutside);
    }
  }, [activeMenu, handleClickOutside]);

  return (
    <div className="h-8 bg-surface-3 border-b border-border flex items-center px-2 text-xs">
      {/* File Menu */}
      <div className="relative">
        <button
          className="px-3 py-1 hover:bg-hover rounded transition-colors"
          onClick={(e) => {
            e.stopPropagation();
            handleMenuClick('file');
          }}
        >
          File
        </button>
        {activeMenu === 'file' && (
          <div className="absolute top-full left-0 mt-1 bg-surface-2 border border-border rounded-md shadow-md min-w-[200px] py-1 z-50">
            <button
              className="w-full px-3 py-1.5 text-left hover:bg-hover transition-colors"
              onClick={() => {
                onOpenFolder?.();
                setActiveMenu(null);
              }}
            >
              Open Folder...
            </button>
            {recentFolders.length > 0 && (
              <>
                <div className="h-px bg-border my-1" />
                <div className="px-3 py-1 text-muted text-xs">Recent Folders</div>
                {recentFolders.map((folder, index) => (
                  <button
                    key={index}
                    className="w-full px-3 py-1.5 text-left hover:bg-hover transition-colors truncate"
                    onClick={() => {
                      onOpenRecent?.(folder);
                      setActiveMenu(null);
                    }}
                  >
                    {folder.split('/').pop() || folder}
                  </button>
                ))}
              </>
            )}
          </div>
        )}
      </div>

      {/* Terminal Menu */}
      <div className="relative">
        <button
          className="px-3 py-1 hover:bg-hover rounded transition-colors"
          onClick={(e) => {
            e.stopPropagation();
            handleMenuClick('terminal');
          }}
        >
          Terminal
        </button>
        {activeMenu === 'terminal' && (
          <div className="absolute top-full left-0 mt-1 bg-surface-2 border border-border rounded-md shadow-md min-w-[200px] py-1 z-50">
            <button
              className="w-full px-3 py-1.5 text-left hover:bg-hover transition-colors flex items-center gap-2"
              onClick={() => {
                onNewTerminal?.();
                setActiveMenu(null);
              }}
            >
              <Terminal className="h-3 w-3" />
              New Terminal
            </button>
            <button
              className="w-full px-3 py-1.5 text-left hover:bg-hover transition-colors flex items-center gap-2"
              onClick={() => {
                onSplitTerminal?.();
                setActiveMenu(null);
              }}
            >
              <Split className="h-3 w-3" />
              Split Terminal
            </button>
            <div className="h-px bg-border my-1" />
            <button
              className="w-full px-3 py-1.5 text-left hover:bg-hover transition-colors flex items-center gap-2"
              onClick={() => {
                onCloseTerminal?.();
                setActiveMenu(null);
              }}
            >
              <X className="h-3 w-3" />
              Close Terminal
            </button>
          </div>
        )}
      </div>
    </div>
  );
}