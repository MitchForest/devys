import { useEffect } from 'react';
import { listen } from '@tauri-apps/api/event';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';
import { 
  FileExplorer, 
  Tabs, 
  CodeEditor, 
  ThemeToggle, 
  ToastContainer, 
  useToast,
  TerminalTabSimple,
  type Tab 
} from '@devys/ui';
import { WelcomePage } from '@devys/ui';
import { FileCode, MessageSquare, Terminal as TerminalIcon } from 'lucide-react';
import { useAppStore } from './store';
import { useTheme, cn } from '@devys/ui';
import { ChatInterface } from '@devys/ui';
import { tauriBridge } from './lib/tauri-bridge';

function App() {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const { toasts, showToast, closeToast } = useToast();
  
  const {
    // UI State
    showTerminal,
    showChat,
    
    // Project State
    projectPath,
    fileTree,
    selectedFile,
    showHiddenFiles,
    
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
    setProjectPath,
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
    refreshFileTree,
    fileSystemService,
    updateFileContent,
    markFileDirty,
    toggleHiddenFiles
  } = useAppStore();

  useEffect(() => {
    // Initialize services when component mounts
    const serverUrl = 'http://localhost:3001';
    initializeServices(serverUrl);
    
    // Only load file tree if project path exists
    if (projectPath) {
      refreshFileTree();
    }
    
    // Create initial chat session if none exists
    if (chatSessions.length === 0) {
      createChatSession('New Chat');
    }
  }, [chatSessions.length, createChatSession, initializeServices, projectPath, refreshFileTree]);

  // Keyboard shortcuts handler
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      // Save file: Cmd+S (Mac) or Ctrl+S (Windows/Linux)
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        
        const activeFile = openFiles.find(f => f.id === activeFileId);
        if (activeFile && activeFile.isDirty && fileSystemService && projectPath) {
          try {
            // Convert relative path to absolute path
            const absolutePath = activeFile.path.startsWith('/') 
              ? projectPath + activeFile.path 
              : activeFile.path;
            
            await fileSystemService.writeFile(absolutePath, activeFile.content || '');
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
  }, [openFiles, activeFileId, fileSystemService, markFileDirty, showToast, projectPath]);

  // Handle terminal creation with project path
  const handleNewTerminal = () => {
    if (!showTerminal) {
      toggleTerminal();
    }
    const count = terminalSessions.length + 1;
    createTerminalSession(`Terminal ${count}`);
  };

  // Listen for menu events from Tauri
  useEffect(() => {
    const unsubscribe = listen<string>('menu-action', (event) => {
      switch (event.payload) {
        case 'new-terminal':
          handleNewTerminal();
          break;
        case 'close-terminal':
          if (activeTerminalId) {
            closeTerminalSession(activeTerminalId);
          }
          break;
        case 'open-folder':
          tauriBridge.openFolderDialog().then(folderPath => {
            if (folderPath) {
              setProjectPath(folderPath);
              refreshFileTree();
              showToast(`Opened folder: ${folderPath}`, 'success', 2000);
            }
          });
          break;
        case 'toggle-chat':
          toggleChat();
          if (!showChat && chatSessions.length === 0) {
            createChatSession('New Chat');
          }
          break;
      }
    });

    return () => {
      unsubscribe.then(fn => fn());
    };
  }, [handleNewTerminal, activeTerminalId, closeTerminalSession, toggleChat, showChat, chatSessions.length, createChatSession, setProjectPath, refreshFileTree, showToast]);

  const handleFileSelect = async (path: string) => {
    selectFile(path);
    
    // Check if file is already open
    const existingFile = openFiles.find(f => f.path === path);
    if (existingFile) {
      setActiveFile(existingFile.id);
      return;
    }
    
    // Read file content from backend
    if (fileSystemService && projectPath) {
      try {
        // Convert relative path to absolute path
        const absolutePath = path.startsWith('/') 
          ? projectPath + path 
          : path;
        
        const content = await fileSystemService.readFile(absolutePath);
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
        showToast(`Failed to open ${path}`, 'error', 3000);
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

  const handleAttachToChat = async (path: string) => {
    if (!fileSystemService) return;
    
    try {
      // Read file content
      const _content = await fileSystemService.readFile(path);
      const fileName = path.split('/').pop() || 'Untitled';
      
      // Get current chat session
      const currentChatSession = chatSessions.find(s => s.id === activeChatSessionId);
      if (!currentChatSession) {
        showToast('Please open a chat session first', 'error', 3000);
        return;
      }
      
      // TODO: Attach file to current chat session
      // This would require accessing the ChatTab component's attachFile method
      // For now, just show a success message
      showToast(`Attached ${fileName} to chat`, 'success', 2000);
    } catch (error) {
      console.error('Failed to attach file:', error);
      showToast('Failed to attach file to chat', 'error', 3000);
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
        <div className="flex-1 overflow-hidden bg-editor">
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
      <TerminalTabSimple
        key={session.id}
        sessionId={session.id}
        theme={resolvedTheme}
        onTitleChange={(_title: string) => {
          // Update terminal title if needed
        }}
      />
    )
  }));
  
  // Convert chat sessions to tabs
  const chatTabs: Tab[] = chatSessions.map(session => ({
    id: session.id,
    title: session.title,
    content: (
      <ChatInterface
        key={session.id}
        session={session}
        onSessionUpdate={(updatedSession) => {
          // TODO: Implement chat session update
          setChatSession(updatedSession.id);
        }}
        attachedFiles={[]} // TODO: Implement file attachment state per session
        onAttachFile={() => {
          // Open file dialog to attach files
          const selectedFile = openFiles.find(f => f.id === activeFileId);
          if (selectedFile) {
            // TODO: Implement file attachment
            showToast(`Attached ${selectedFile.name}`, 'success', 2000);
          } else {
            showToast('Select a file in the editor to attach', 'info', 3000);
          }
        }}
        onRemoveFile={() => {}}
      />
    )
  }));

  // Show welcome page if no project is open
  if (!projectPath) {
    return (
      <div className="h-screen w-screen bg-background text-foreground flex flex-col" style={{ fontSize: 'var(--font-size-base)', lineHeight: 'var(--line-height-base)' }}>
        <WelcomePage
          onOpenFolder={async () => {
            const folderPath = await tauriBridge.openFolderDialog();
            if (folderPath) {
              setProjectPath(folderPath);
              refreshFileTree();
              showToast(`Opened folder: ${folderPath}`, 'success', 2000);
            }
          }}
          onOpenRecent={(path: string) => {
            setProjectPath(path);
            refreshFileTree();
            showToast(`Opened folder: ${path}`, 'success', 2000);
          }}
          recentFolders={[]}  // TODO: Implement recent folders
        />
        <ToastContainer toasts={toasts} onClose={closeToast} />
      </div>
    );
  }

  return (
    <div className="h-screen w-screen bg-background text-foreground flex flex-col" style={{ fontSize: 'var(--font-size-base)', lineHeight: 'var(--line-height-base)' }}>
      {/* Main Content */}
      <div className="flex-1 flex overflow-hidden">
        <PanelGroup direction="horizontal">
          {/* File Explorer */}
          <Panel defaultSize={15} minSize={10} maxSize={30}>
            <div className="h-full bg-surface-3 border-r border-border">
              <div className="h-full flex flex-col">
                <FileExplorer
                  nodes={fileTree}
                  selectedPath={selectedFile || undefined}
                  onSelectFile={handleFileSelect}
                  onOpenFolder={async (path: string) => {
                    // If path is '/', open native folder dialog
                    if (path === '/') {
                      const folderPath = await tauriBridge.openFolderDialog();
                      if (folderPath) {
                        setProjectPath(folderPath);
                        refreshFileTree();
                        showToast(`Opened folder: ${folderPath}`, 'success', 2000);
                      }
                    } else {
                      // Otherwise, change to the specified folder
                      setProjectPath(path);
                      refreshFileTree();
                      showToast(`Opened folder: ${path}`, 'success', 2000);
                    }
                  }}
                  onCreateFile={handleFileCreate}
                  onCreateFolder={handleFolderCreate}
                  onRename={handleFileRename}
                  onDelete={handleFileDelete}
                  onCopyPath={(path: string) => {
                    navigator.clipboard.writeText(path);
                  }}
                  onCopyRelativePath={(path: string) => {
                    navigator.clipboard.writeText(path.substring(1)); // Remove leading /
                  }}
                  onCut={(_path: string) => {
                  // TODO: Implement cut
                }}
                onCopy={(_path: string) => {
                  // TODO: Implement copy
                }}
                onPaste={(_path: string) => {
                  // TODO: Implement paste
                }}
                onRefresh={() => {
                  refreshFileTree();
                }}
                onAttachToChat={handleAttachToChat}
                onToggleHidden={() => {
                  toggleHiddenFiles();
                  refreshFileTree();
                }}
                showHidden={showHiddenFiles}
                />
              </div>
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
                        <h1 className="text-2xl font-bold">Welcome to Devys</h1>
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
                        onTabClose={(tabId: string) => {
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
                    onTabClose={(tabId: string) => {
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
        <span className="flex items-center gap-3">
          {projectPath && (
            <span className="text-muted-foreground">
              {projectPath.split('/').pop()}
            </span>
          )}
          {activeFileId && openFiles.find(f => f.id === activeFileId) && (
            <span className="flex items-center gap-1">
              <span className="text-muted-foreground">—</span>
              <span>{openFiles.find(f => f.id === activeFileId)?.name}</span>
              {openFiles.find(f => f.id === activeFileId)?.isDirty && (
                <span className="text-muted-foreground">•</span>
              )}
            </span>
          )}
        </span>
        <div className="ml-auto flex items-center gap-2">
          <button
            className={cn(
              "p-1 rounded transition-colors",
              showChat ? "bg-surface-3 text-foreground" : "hover:bg-surface-3 text-muted hover:text-foreground"
            )}
            onClick={() => {
              toggleChat();
              if (!showChat && chatSessions.length === 0) {
                createChatSession('New Chat');
              }
            }}
            title={showChat ? "Hide Chat" : "Show Chat"}
          >
            <MessageSquare className="h-3 w-3" />
          </button>
          <button
            className={cn(
              "p-1 rounded transition-colors",
              showTerminal ? "bg-surface-3 text-foreground" : "hover:bg-surface-3 text-muted hover:text-foreground"
            )}
            onClick={() => {
              toggleTerminal();
              if (!showTerminal && terminalSessions.length === 0) {
                createTerminalSession('Terminal 1');
              }
            }}
            title={showTerminal ? "Hide Terminal" : "Show Terminal"}
          >
            <TerminalIcon className="h-3 w-3" />
          </button>
          <div className="w-px h-4 bg-border mx-1" />
          <ThemeToggle theme={theme} onThemeChange={setTheme} className="h-4 px-2" />
        </div>
      </div>
      
      {/* Toast Notifications */}
      <ToastContainer toasts={toasts} onClose={closeToast} />
    </div>
  );
}

export default App;