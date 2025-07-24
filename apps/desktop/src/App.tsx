import { useEffect } from 'react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';
import { 
  FileExplorer, 
  Tabs, 
  CodeEditor, 
  ThemeToggle, 
  ToastContainer, 
  useToast, 
  ChatInterface,
  useChatSession,
  type Tab 
} from '@claude-code-ide/ui';
import { FileCode, MessageSquare, Terminal as TerminalIcon } from 'lucide-react';
import { useAppStore } from './store';
import { useTheme } from './contexts/theme-context';
import type { FileAttachment } from '@claude-code-ide/types';

function App() {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const { toasts, showToast, closeToast } = useToast();
  
  const {
    // UI State
    showTerminal,
    showChat,
    
    // Project State
    fileTree,
    selectedFile,
    
    // Editor State
    openFiles,
    activeFileId,
    
    // Terminal State
    terminalSessions,
    activeTerminalId,
    
    // Chat State
    chatSessions,
    activeChatSessionId,
    
    // Actions
    selectFile,
    toggleTerminal,
    toggleChat,
    openFile,
    closeFile,
    setActiveFile,
    createTerminalSession,
    setActiveTerminal,
    closeTerminalSession,
    createChatSession,
    setChatSession,
    initializeServices,
    connectWebSocket,
    refreshFileTree,
    fileSystemService,
    updateFileContent,
    markFileDirty
  } = useAppStore();

  useEffect(() => {
    // Initialize services when component mounts
    const serverUrl = 'http://localhost:3001';
    initializeServices(serverUrl);
    connectWebSocket('ws://localhost:3001');
    
    // Load initial file tree
    refreshFileTree();
    
    // Create initial chat session if none exists
    if (chatSessions.length === 0) {
      createChatSession('Chat 1');
    }
    
    return () => {
      // Cleanup on unmount
      useAppStore.getState().disconnectWebSocket();
    };
  }, []);

  // Keyboard shortcuts handler
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      // Save file: Cmd+S (Mac) or Ctrl+S (Windows/Linux)
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        
        const activeFile = openFiles.find(f => f.id === activeFileId);
        if (activeFile && activeFile.isDirty && fileSystemService) {
          try {
            await fileSystemService.writeFile(activeFile.path, activeFile.content || '');
            markFileDirty(activeFile.id, false);
            showToast(`Saved ${activeFile.name}`, 'success', 2000);
          } catch (error) {
            console.error('Failed to save file:', error);
            showToast(`Failed to save ${activeFile.name}`, 'error', 3000);
          }
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [openFiles, activeFileId, fileSystemService, markFileDirty, showToast]);

  const handleFileSelect = async (path: string) => {
    selectFile(path);
    
    // Check if file is already open
    const existingFile = openFiles.find(f => f.path === path);
    if (existingFile) {
      setActiveFile(existingFile.id);
      return;
    }
    
    // Read file content from backend
    if (fileSystemService) {
      try {
        const content = await fileSystemService.readFile(path);
        const fileName = path.split('/').pop() || 'Untitled';
        const fileId = path;
        
        openFile({
          id: fileId,
          path,
          name: fileName,
          content,
          isDirty: false,
          language: getLanguageFromPath(path)
        });
      } catch (error) {
        console.error('Failed to read file:', error);
      }
    }
  };
  
  const getLanguageFromPath = (path: string): string => {
    const ext = path.split('.').pop()?.toLowerCase();
    switch (ext) {
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'py':
        return 'python';
      case 'json':
        return 'json';
      case 'html':
        return 'html';
      case 'css':
        return 'css';
      case 'md':
        return 'markdown';
      default:
        return 'text';
    }
  };

  const handleFileCreate = async (parentPath: string) => {
    if (!fileSystemService) return;
    
    const fileName = prompt('Enter file name:');
    if (!fileName) return;
    
    const fullPath = `${parentPath}/${fileName}`;
    try {
      await fileSystemService.createFile(fullPath, '');
      await refreshFileTree();
    } catch (error) {
      console.error('Failed to create file:', error);
    }
  };

  const handleFolderCreate = async (parentPath: string) => {
    if (!fileSystemService) return;
    
    const folderName = prompt('Enter folder name:');
    if (!folderName) return;
    
    const fullPath = `${parentPath}/${folderName}`;
    try {
      await fileSystemService.createFolder(fullPath);
      await refreshFileTree();
    } catch (error) {
      console.error('Failed to create folder:', error);
    }
  };

  const handleFileRename = async (path: string, newName: string) => {
    if (!fileSystemService) return;
    
    const dir = path.substring(0, path.lastIndexOf('/'));
    const newPath = `${dir}/${newName}`;
    
    try {
      await fileSystemService.renameFile(path, newPath);
      await refreshFileTree();
      
      // Update open files if renamed file is open
      const openFile = openFiles.find(f => f.path === path);
      if (openFile) {
        // TODO: Update file path in store
      }
    } catch (error) {
      console.error('Failed to rename file:', error);
    }
  };

  const handleFileDelete = async (path: string) => {
    if (!fileSystemService) return;
    
    const confirm = window.confirm(`Are you sure you want to delete ${path}?`);
    if (!confirm) return;
    
    try {
      await fileSystemService.deleteFile(path);
      await refreshFileTree();
      
      // Close file if it's open
      const openFile = openFiles.find(f => f.path === path);
      if (openFile) {
        closeFile(openFile.id);
      }
    } catch (error) {
      console.error('Failed to delete file:', error);
    }
  };

  // Convert editor files to tabs
  const editorTabs: Tab[] = openFiles.map(file => ({
    id: file.id,
    title: file.name,
    icon: <FileCode className="h-3 w-3" />,
    isDirty: file.isDirty,
    content: (
      <div className="h-full flex flex-col">
        <div className="px-4 py-2 border-b border-border bg-surface-2 flex items-center justify-between">
          <h2 className="text-xs text-muted">{file.path}</h2>
          {file.isDirty && (
            <span className="text-xs text-muted">
              Press {navigator.platform.includes('Mac') ? '⌘' : 'Ctrl'}+S to save
            </span>
          )}
        </div>
        <div className="flex-1 overflow-hidden">
          <CodeEditor
            value={file.content || ''}
            onChange={(value) => {
              updateFileContent(file.id, value);
              if (!file.isDirty) {
                markFileDirty(file.id, true);
              }
            }}
            language={file.language}
            theme={resolvedTheme}
            height="100%"
          />
        </div>
      </div>
    )
  }));
  
  // Convert terminal sessions to tabs
  const terminalTabs: Tab[] = terminalSessions.map(session => ({
    id: session.id,
    title: session.title,
    content: (
      <div className="p-4">
        <p className="text-sm text-muted-foreground">Terminal integration coming soon...</p>
      </div>
    )
  }));
  
  // Convert chat sessions to tabs
  const chatTabs: Tab[] = chatSessions.map(session => {
    const { 
      session: chatSession, 
      updateSession, 
      attachedFiles, 
      attachFile, 
      removeFile 
    } = useChatSession({
      id: session.id,
      title: session.title,
      messages: session.messages || [],
      createdAt: new Date(),
      updatedAt: new Date()
    });

    return {
      id: session.id,
      title: session.title,
      content: (
        <ChatInterface
          session={chatSession}
          onSessionUpdate={updateSession}
          attachedFiles={attachedFiles}
          onAttachFile={() => {
            // Open file dialog to attach files
            const selectedFile = openFiles.find(f => f.id === activeFileId);
            if (selectedFile) {
              attachFile({
                id: selectedFile.id,
                path: selectedFile.path,
                name: selectedFile.name,
                content: selectedFile.content,
                language: selectedFile.language
              });
              showToast(`Attached ${selectedFile.name}`, 'success', 2000);
            } else {
              showToast('Select a file in the editor to attach', 'info', 3000);
            }
          }}
          onRemoveFile={removeFile}
        />
      )
    };
  });

  return (
    <div className="h-screen w-screen bg-background text-foreground flex flex-col" style={{ fontSize: 'var(--font-size-base)', lineHeight: 'var(--line-height-base)' }}>
      {/* Main Content */}
      <div className="flex-1 flex overflow-hidden">
        <PanelGroup direction="horizontal">
          {/* File Explorer */}
          <Panel defaultSize={15} minSize={10} maxSize={30}>
            <div className="h-full bg-surface-3 border-r border-border">
              <FileExplorer
                nodes={fileTree}
                selectedPath={selectedFile || undefined}
                onSelectFile={handleFileSelect}
                onCreateFile={handleFileCreate}
                onCreateFolder={handleFolderCreate}
                onRename={handleFileRename}
                onDelete={handleFileDelete}
                onCopyPath={(path) => {
                  navigator.clipboard.writeText(path);
                }}
                onCopyRelativePath={(path) => {
                  navigator.clipboard.writeText(path.substring(1)); // Remove leading /
                }}
                onCut={(_path) => {
                  // TODO: Implement cut
                }}
                onCopy={(_path) => {
                  // TODO: Implement copy
                }}
                onPaste={(_path) => {
                  // TODO: Implement paste
                }}
                onRefresh={() => {
                  refreshFileTree();
                }}
              />
            </div>
          </Panel>
          
          <PanelResizeHandle className="w-px bg-border hover:bg-primary/20 transition-zed" />
          
          {/* Editor and Terminal */}
          <Panel defaultSize={showChat ? 60 : 85}>
            <PanelGroup direction="vertical">
              {/* Editor Area */}
              <Panel defaultSize={70} minSize={30}>
                <div className="h-full bg-surface-1">
                  {editorTabs.length > 0 ? (
                    <Tabs
                      tabs={editorTabs}
                      activeTabId={activeFileId || ''}
                      onTabSelect={setActiveFile}
                      onTabClose={closeFile}
                      contentClassName="h-full"
                    />
                  ) : (
                    <div className="h-full flex items-center justify-center">
                      <div className="text-center">
                        <h1 className="text-2xl font-bold">Welcome to Claude Code IDE</h1>
                        <p className="mt-2 text-muted-foreground">
                          Select a file from the explorer to begin editing
                        </p>
                      </div>
                    </div>
                  )}
                </div>
              </Panel>
              
              {showTerminal && (
                <>
                  <PanelResizeHandle className="h-px bg-border hover:bg-primary/20 transition-zed" />
                  
                  {/* Terminal Area */}
                  <Panel defaultSize={30} minSize={10} maxSize={50}>
                    <div className="h-full bg-surface-2">
                      <Tabs
                        tabs={terminalTabs}
                        activeTabId={activeTerminalId || ''}
                        onTabSelect={setActiveTerminal}
                        onTabClose={(tabId) => {
                          closeTerminalSession(tabId);
                        }}
                        onTabAdd={() => {
                          const count = terminalSessions.length + 1;
                          createTerminalSession(`Terminal ${count}`);
                        }}
                        onPanelClose={() => toggleTerminal()}
                        contentClassName="h-full"
                      />
                    </div>
                  </Panel>
                </>
              )}
            </PanelGroup>
          </Panel>
          
          {showChat && (
            <>
              <PanelResizeHandle className="w-px bg-border hover:bg-primary/20 transition-zed" />
              
              {/* Chat Sidebar */}
              <Panel defaultSize={25} minSize={15} maxSize={40}>
                <div className="h-full bg-surface-3">
                  <Tabs
                    tabs={chatTabs}
                    activeTabId={activeChatSessionId || ''}
                    onTabSelect={setChatSession}
                    onTabClose={(tabId) => {
                      // TODO: Implement chat session close
                      const newSessions = chatSessions.filter(s => s.id !== tabId);
                      if (newSessions.length === 0) {
                        toggleChat();
                      }
                    }}
                    onTabAdd={() => {
                      const count = chatSessions.length + 1;
                      createChatSession(`Chat ${count}`);
                    }}
                    onPanelClose={() => toggleChat()}
                    contentClassName="h-full"
                  />
                </div>
              </Panel>
            </>
          )}
        </PanelGroup>
      </div>

      {/* Status Bar */}
      <div className="h-6 bg-surface-2 border-t border-border flex items-center px-2 text-xs text-muted">
        <span>
          {activeFileId && openFiles.find(f => f.id === activeFileId)?.isDirty 
            ? `${openFiles.find(f => f.id === activeFileId)?.name} • Modified`
            : 'Ready'
          }
        </span>
        <div className="ml-auto flex items-center gap-4">
          {!showTerminal && (
            <button
              className="hover:text-foreground transition-colors"
              onClick={() => {
                toggleTerminal();
                if (terminalSessions.length === 0) {
                  createTerminalSession('Terminal 1');
                }
              }}
            >
              <TerminalIcon className="h-3 w-3 inline mr-1" />
              Terminal
            </button>
          )}
          {!showChat && (
            <button
              className="hover:text-foreground transition-colors"
              onClick={() => {
                toggleChat();
                if (chatSessions.length === 0) {
                  createChatSession('Chat 1');
                }
              }}
            >
              <MessageSquare className="h-3 w-3 inline mr-1" />
              Chat
            </button>
          )}
          <ThemeToggle theme={theme} onThemeChange={setTheme} className="h-4 px-2" />
          <span>Claude Code IDE v0.1.0</span>
        </div>
      </div>
      
      {/* Toast Notifications */}
      <ToastContainer toasts={toasts} onClose={closeToast} />
    </div>
  );
}

export default App;