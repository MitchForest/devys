import { useState, useEffect, useCallback } from 'react';
import type { ChatSession, FileAttachment, ChatMessage } from '@devys/types';

interface UseChatSessionOptions {
  id?: string;
  title?: string;
  messages?: ChatMessage[];
  apiEndpoint?: string;
  autoLoad?: boolean;
}

interface UseChatSessionReturn {
  chatSession: ChatSession | null;
  sessions: ChatSession[];
  updateSession: (updatedSession: ChatSession) => void;
  loadSession: (sessionId: string) => Promise<void>;
  createSession: () => ChatSession;
  loadSessions: () => Promise<void>;
  attachedFiles: FileAttachment[];
  attachFile: (file: FileAttachment) => void;
  removeFile: (fileId: string) => void;
  isLoading: boolean;
  error: Error | null;
}

export function useChatSession(options: UseChatSessionOptions = {}): UseChatSessionReturn {
  const { 
    id: initialId, 
    title: initialTitle = 'New Conversation', 
    messages: initialMessages = [],
    apiEndpoint = 'http://localhost:3001/api/chat',
    autoLoad = true
  } = options;

  const [session, setSession] = useState<ChatSession | null>(
    initialId ? {
      id: initialId,
      title: initialTitle,
      messages: initialMessages,
      createdAt: new Date(),
      updatedAt: new Date()
    } : null
  );

  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [attachedFiles, setAttachedFiles] = useState<FileAttachment[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Load a specific session from the server
  const loadSession = useCallback(async (sessionId: string) => {
    setIsLoading(true);
    setError(null);
    
    try {
      const response = await fetch(`${apiEndpoint}/sessions/${sessionId}`);
      if (!response.ok) {
        throw new Error(`Failed to load session: ${response.statusText}`);
      }
      
      const data = await response.json();
      const loadedSession: ChatSession = {
        id: data.session.id,
        title: data.session.title || 'New Conversation',
        messages: data.messages || [],
        createdAt: new Date(data.session.created_at),
        updatedAt: new Date(data.session.updated_at),
        status: data.session.status,
        model: data.session.model,
        projectPath: data.session.project_path
      };
      
      setSession(loadedSession);
    } catch (err) {
      setError(err as Error);
      console.error('Failed to load session:', err);
    } finally {
      setIsLoading(false);
    }
  }, [apiEndpoint]);

  // Load all sessions
  const loadSessions = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const response = await fetch(`${apiEndpoint}/sessions`);
      if (!response.ok) {
        throw new Error(`Failed to load sessions: ${response.statusText}`);
      }
      
      const data = await response.json();
      const loadedSessions: ChatSession[] = data.sessions.map((s: {
        id: string;
        title?: string;
        messages: Array<{ role: string; content: string; timestamp?: string }>;
        created_at?: string;
        updated_at?: string;
        status?: string;
        model?: string;
        project_path?: string;
      }) => ({
        id: s.id,
        title: s.title || 'New Conversation',
        messages: [],
        createdAt: s.created_at ? new Date(s.created_at) : new Date(),
        updatedAt: s.updated_at ? new Date(s.updated_at) : new Date(),
        status: s.status as 'active' | 'completed' | 'error' | undefined,
        model: s.model,
        projectPath: s.project_path
      }));
      
      setSessions(loadedSessions);
    } catch (err) {
      setError(err as Error);
      console.error('Failed to load sessions:', err);
    } finally {
      setIsLoading(false);
    }
  }, [apiEndpoint]);

  // Create a new session
  const createSession = useCallback(() => {
    const newSession: ChatSession = {
      id: crypto.randomUUID(),
      title: 'New Conversation',
      messages: [],
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    setSession(newSession);
    return newSession;
  }, []);

  const updateSession = useCallback((updatedSession: ChatSession) => {
    setSession(updatedSession);
    
    // Update in sessions list
    setSessions(prev => 
      prev.map(s => s.id === updatedSession.id ? updatedSession : s)
    );
  }, []);

  const attachFile = useCallback((file: FileAttachment) => {
    setAttachedFiles(prev => [...prev, file]);
  }, []);

  const removeFile = useCallback((fileId: string) => {
    setAttachedFiles(prev => prev.filter(f => (f.id || f.path) !== fileId));
  }, []);

  // Load initial session if provided and autoLoad is true
  useEffect(() => {
    if (initialId && autoLoad) {
      loadSession(initialId);
    }
  }, [initialId, autoLoad, loadSession]);

  return {
    chatSession: session,
    sessions,
    updateSession,
    loadSession,
    createSession,
    loadSessions,
    attachedFiles,
    attachFile,
    removeFile,
    isLoading,
    error
  };
}