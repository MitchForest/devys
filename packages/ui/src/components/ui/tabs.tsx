import React from 'react';
import { X, Plus, MoreHorizontal } from 'lucide-react';
import { cn } from '../../lib/utils';

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
  className,
  tabClassName,
  contentClassName,
}: TabsProps) {
  const activeTab = tabs.find(tab => tab.id === activeTabId) || tabs[0];

  return (
    <div className={cn('flex flex-col h-full', className)}>
      {/* Tab Header */}
      <div className="flex items-center border-b border-border bg-background">
        <div className="flex-1 flex items-center min-w-0">
          <div className="flex-1 flex items-center overflow-x-auto scrollbar-thin">
            {tabs.map((tab) => (
              <div
                key={tab.id}
                className={cn(
                  'group flex items-center gap-2 px-3 py-1.5 border-r border-border cursor-pointer hover:bg-accent/50 transition-colors min-w-0',
                  activeTab?.id === tab.id && 'bg-accent',
                  tabClassName
                )}
                onClick={() => onTabSelect?.(tab.id)}
              >
                {tab.icon && <span className="shrink-0">{tab.icon}</span>}
                <span className="text-sm truncate">{tab.title}</span>
                {tab.isDirty && <span className="text-xs">•</span>}
                {onTabClose && (
                  <button
                    className="ml-1 p-0.5 opacity-0 group-hover:opacity-100 hover:bg-background rounded transition-opacity"
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
                className="p-1.5 hover:bg-accent transition-colors"
                onClick={onTabAdd}
                title="New Tab"
              >
                <Plus className="h-4 w-4" />
              </button>
            )}
            {onTabsAction && (
              <button
                className="p-1.5 hover:bg-accent transition-colors"
                onClick={onTabsAction}
                title="More Actions"
              >
                <MoreHorizontal className="h-4 w-4" />
              </button>
            )}
            {onPanelClose && (
              <button
                className="p-1.5 hover:bg-accent transition-colors border-l border-border"
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