import React from 'react';
import { X, Plus, MoreHorizontal, History } from 'lucide-react';
import { cn } from '../../lib/utils';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from './dropdown-menu';

export interface Tab {
  id: string;
  title: string;
  content?: React.ReactNode;
  isDirty?: boolean;
  icon?: React.ReactNode;
}

interface TabsProps {
  tabs: Tab[];
  activeTabId?: string;
  onTabSelect?: (tabId: string) => void;
  onTabClose?: (tabId: string) => void;
  onTabAdd?: () => void;
  onTabsAction?: () => void;
  onPanelClose?: () => void;
  onHistorySelect?: (tabId: string) => void;
  historySessions?: Tab[];
  className?: string;
  tabClassName?: string;
  contentClassName?: string;
}

export function Tabs({
  tabs,
  activeTabId,
  onTabSelect,
  onTabClose,
  onTabAdd,
  onTabsAction,
  onPanelClose,
  onHistorySelect,
  historySessions = [],
  className,
  tabClassName,
  contentClassName,
}: TabsProps) {
  const activeTab = tabs.find(tab => tab.id === activeTabId) || tabs[0];

  return (
    <div className={cn('flex flex-col h-full', className)}>
      {/* Tab Header */}
      <div className="flex items-center border-b border-panel bg-tab-bar">
        <div className="flex-1 flex items-center min-w-0">
          <div className="flex-1 flex items-center overflow-x-auto scrollbar-zed">
            {tabs.map((tab) => (
              <div
                key={tab.id}
                className={cn(
                  'group flex items-center gap-1.5 px-3 py-1 border-r border-border cursor-pointer transition-zed min-w-0',
                  activeTab?.id === tab.id ? 'bg-tab-active' : 'bg-tab-inactive hover:bg-tab-hover',
                  tabClassName
                )}
                onClick={() => onTabSelect?.(tab.id)}
              >
                {tab.icon && <span className="shrink-0">{tab.icon}</span>}
                <span className="text-sm truncate">{tab.title}</span>
                {tab.isDirty && <span className="text-xs">•</span>}
                {onTabClose && (
                  <button
                    className="ml-1 p-0.5 opacity-0 group-hover:opacity-100 hover:bg-active rounded transition-opacity"
                    onClick={(e) => {
                      e.stopPropagation();
                      onTabClose(tab.id);
                    }}
                  >
                    <X className="h-3 w-3" />
                  </button>
                )}
              </div>
            ))}
          </div>
          
          {/* Tab Actions */}
          <div className="flex items-center border-l border-border">
            {onTabAdd && (
              <button
                className="p-1.5 hover:bg-hover transition-zed"
                onClick={onTabAdd}
                title="New Tab"
              >
                <Plus className="h-4 w-4" />
              </button>
            )}
            {(onHistorySelect || historySessions.length > 0) && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    className="p-1.5 hover:bg-hover transition-zed"
                    title="Chat History"
                  >
                    <History className="h-4 w-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-56">
                  <DropdownMenuLabel>Chat History</DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  {historySessions.length === 0 ? (
                    <DropdownMenuItem disabled>
                      <span className="text-xs text-muted">No previous chats</span>
                    </DropdownMenuItem>
                  ) : (
                    historySessions.map((session) => (
                      <DropdownMenuItem
                        key={session.id}
                        onClick={() => onHistorySelect?.(session.id)}
                        className="text-xs"
                      >
                        <span className="truncate">{session.title}</span>
                      </DropdownMenuItem>
                    ))
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            )}
            {onPanelClose && (
              <button
                className="p-1.5 hover:bg-hover transition-zed border-l border-border"
                onClick={onPanelClose}
                title="Close Panel"
              >
                <X className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Tab Content */}
      {activeTab && (
        <div className={cn('flex-1 overflow-hidden', contentClassName)}>
          {activeTab.content}
        </div>
      )}
    </div>
  );
}