import { useState, useCallback } from 'react';
import type { ChatSession, FileAttachment } from '@claude-code-ide/types';

interface UseChatSessionOptions {
  id: string;
  title: string;
  messages?: any[];
}

export function useChatSession(options: UseChatSessionOptions) {
  const [session, setSession] = useState<ChatSession>({
    id: options.id,
    title: options.title,
    messages: options.messages || [],
    createdAt: new Date(),
    updatedAt: new Date()
  });

  const [attachedFiles, setAttachedFiles] = useState<FileAttachment[]>([]);

  const updateSession = useCallback((updatedSession: ChatSession) => {
    setSession(updatedSession);
  }, []);

  const attachFile = useCallback((file: FileAttachment) => {
    setAttachedFiles(prev => [...prev, file]);
  }, []);

  const removeFile = useCallback((fileId: string) => {
    setAttachedFiles(prev => prev.filter(f => (f.id || f.path) !== fileId));
  }, []);

  return {
    chatSession: session,
    updateSession,
    attachedFiles,
    attachFile,
    removeFile
  };
}