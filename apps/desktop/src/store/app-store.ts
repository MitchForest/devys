import { create } from 'zustand';
import { devtools, subscribeWithSelector } from 'zustand/middleware';
import type { FileNode, FileTab, ChatSession, TerminalSession, Workflow } from '@claude-code-ide/types';
import { FileSystemService } from '@claude-code-ide/core';

interface UIState {
  activePanel: 'explorer' | 'chat' | 'terminal';
  showTerminal: boolean;
  showChat: boolean;
  theme: 'light' | 'dark' | 'system';
}

interface ProjectState {
  projectPath: string | null;
  fileTree: FileNode[];
  selectedFile: string | null;
  gitStatus: Record<string, 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked'>;
}

interface EditorState {
  openFiles: FileTab[];
  activeFileId: string | null;
}

interface SessionState {
  chatSessions: ChatSession[];
  activeChatSessionId: string | null;
  terminalSessions: TerminalSession[];
  activeTerminalId: string | null;
}

interface WorkflowState {
  activeWorkflow: Workflow | null;
  workflowProgress: number;
  workflowStatus: 'idle' | 'running' | 'completed' | 'failed';
}

interface AppState extends UIState, ProjectState, EditorState, SessionState, WorkflowState {
  // File System Service
  fileSystemService: FileSystemService | null;
  
  // WebSocket connection
  ws: WebSocket | null;
  wsConnected: boolean;
  
  // Actions - UI
  setActivePanel: (panel: 'explorer' | 'chat' | 'terminal') => void;
  toggleTerminal: () => void;
  toggleChat: () => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
  
  // Actions - Project
  setProjectPath: (path: string) => void;
  refreshFileTree: () => Promise<void>;
  selectFile: (path: string | null) => void;
  updateGitStatus: (status: Record<string, 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked'>) => void;
  
  // Actions - Editor
  openFile: (file: FileTab) => void;
  closeFile: (fileId: string) => void;
  setActiveFile: (fileId: string) => void;
  updateFileContent: (fileId: string, content: string) => void;
  markFileDirty: (fileId: string, isDirty: boolean) => void;
  
  // Actions - Sessions
  createChatSession: (title: string) => void;
  setChatSession: (sessionId: string) => void;
  addChatMessage: (sessionId: string, message: any) => void;
  createTerminalSession: (title: string) => void;
  setActiveTerminal: (terminalId: string) => void;
  closeTerminalSession: (terminalId: string) => void;
  
  // Actions - Workflow
  startWorkflow: (workflow: Workflow) => void;
  updateWorkflowProgress: (progress: number) => void;
  completeWorkflow: (status: 'completed' | 'failed') => void;
  
  // Actions - Services
  initializeServices: (serverUrl: string) => void;
  connectWebSocket: (wsUrl: string) => void;
  disconnectWebSocket: () => void;
}

export const useAppStore = create<AppState>()(
  devtools(
    subscribeWithSelector((set, get) => ({
      // Initial UI State
      activePanel: 'explorer',
      showTerminal: true,
      showChat: true,
      theme: 'dark',
      
      // Initial Project State
      projectPath: null,
      fileTree: [],
      selectedFile: null,
      gitStatus: {},
      
      // Initial Editor State
      openFiles: [],
      activeFileId: null,
      
      // Initial Session State
      chatSessions: [],
      activeChatSessionId: null,
      terminalSessions: [{
        id: 'terminal-1',
        title: 'Terminal 1',
        isActive: true,
        output: []
      }],
      activeTerminalId: 'terminal-1',
      
      // Initial Workflow State
      activeWorkflow: null,
      workflowProgress: 0,
      workflowStatus: 'idle',
      
      // Services
      fileSystemService: null,
      ws: null,
      wsConnected: false,
      
      // UI Actions
      setActivePanel: (panel) => set({ activePanel: panel }),
      toggleTerminal: () => set((state) => ({ showTerminal: !state.showTerminal })),
      toggleChat: () => set((state) => ({ showChat: !state.showChat })),
      setTheme: (theme) => set({ theme }),
      
      // Project Actions
      setProjectPath: (path) => set({ projectPath: path }),
      
      refreshFileTree: async () => {
        const { fileSystemService, projectPath } = get();
        if (!fileSystemService || !projectPath) return;
        
        try {
          const nodes = await fileSystemService.listFiles(projectPath);
          set({ fileTree: nodes });
        } catch (error) {
          console.error('Failed to refresh file tree:', error);
        }
      },
      
      selectFile: (path) => set({ selectedFile: path }),
      
      updateGitStatus: (status) => set({ gitStatus: status }),
      
      // Editor Actions
      openFile: (file) => set((state) => {
        const exists = state.openFiles.find(f => f.id === file.id);
        if (exists) {
          return { activeFileId: file.id };
        }
        return {
          openFiles: [...state.openFiles, file],
          activeFileId: file.id
        };
      }),
      
      closeFile: (fileId) => set((state) => {
        const newFiles = state.openFiles.filter(f => f.id !== fileId);
        const newActiveId = state.activeFileId === fileId && newFiles.length > 0
          ? newFiles[newFiles.length - 1].id
          : state.activeFileId;
        
        return {
          openFiles: newFiles,
          activeFileId: newActiveId
        };
      }),
      
      setActiveFile: (fileId) => set({ activeFileId: fileId }),
      
      updateFileContent: (fileId, content) => set((state) => ({
        openFiles: state.openFiles.map(f =>
          f.id === fileId ? { ...f, content } : f
        )
      })),
      
      markFileDirty: (fileId, isDirty) => set((state) => ({
        openFiles: state.openFiles.map(f =>
          f.id === fileId ? { ...f, isDirty } : f
        )
      })),
      
      // Session Actions
      createChatSession: (title) => set((state) => {
        const newSession: ChatSession = {
          id: `chat-${Date.now()}`,
          title,
          messages: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        return {
          chatSessions: [...state.chatSessions, newSession],
          activeChatSessionId: newSession.id
        };
      }),
      
      setChatSession: (sessionId) => set({ activeChatSessionId: sessionId }),
      
      addChatMessage: (sessionId, message) => set((state) => ({
        chatSessions: state.chatSessions.map(session =>
          session.id === sessionId
            ? {
                ...session,
                messages: [...session.messages, message],
                updatedAt: new Date()
              }
            : session
        )
      })),
      
      createTerminalSession: (title) => set((state) => {
        const newSession: TerminalSession = {
          id: `terminal-${Date.now()}`,
          title,
          isActive: true,
          output: []
        };
        
        return {
          terminalSessions: [...state.terminalSessions, newSession],
          activeTerminalId: newSession.id
        };
      }),
      
      setActiveTerminal: (terminalId) => set({ activeTerminalId: terminalId }),
      
      closeTerminalSession: (terminalId) => set((state) => {
        const newSessions = state.terminalSessions.filter(t => t.id !== terminalId);
        const newActiveId = state.activeTerminalId === terminalId && newSessions.length > 0
          ? newSessions[0].id
          : state.activeTerminalId;
        
        return {
          terminalSessions: newSessions,
          activeTerminalId: newActiveId,
          showTerminal: newSessions.length > 0
        };
      }),
      
      // Workflow Actions
      startWorkflow: (workflow) => set({
        activeWorkflow: workflow,
        workflowProgress: 0,
        workflowStatus: 'running'
      }),
      
      updateWorkflowProgress: (progress) => set({ workflowProgress: progress }),
      
      completeWorkflow: (status) => set({
        workflowStatus: status,
        workflowProgress: 100
      }),
      
      // Service Actions
      initializeServices: (serverUrl) => {
        const fileSystemService = new FileSystemService({ baseUrl: serverUrl });
        set({ fileSystemService });
      },
      
      connectWebSocket: (wsUrl) => {
        const { ws } = get();
        if (ws) {
          ws.close();
        }
        
        const websocket = new WebSocket(wsUrl);
        
        websocket.onopen = () => {
          set({ wsConnected: true });
        };
        
        websocket.onclose = () => {
          set({ wsConnected: false });
        };
        
        websocket.onerror = (error) => {
          console.error('WebSocket error:', error);
          set({ wsConnected: false });
        };
        
        websocket.onmessage = (event) => {
          try {
            const message = JSON.parse(event.data);
            // Handle WebSocket messages here
            console.log('WebSocket message:', message);
          } catch (error) {
            console.error('Failed to parse WebSocket message:', error);
          }
        };
        
        set({ ws: websocket });
      },
      
      disconnectWebSocket: () => {
        const { ws } = get();
        if (ws) {
          ws.close();
          set({ ws: null, wsConnected: false });
        }
      }
    }))
  )
);