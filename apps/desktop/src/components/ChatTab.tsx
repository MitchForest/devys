import React from 'react';
import { ChatInterface } from '@claude-code-ide/ui';
import { useChatSession } from '@claude-code-ide/ui';
import type { ChatSession, FileTab } from '@claude-code-ide/types';

interface ChatTabProps {
  session: ChatSession;
  openFiles: FileTab[];
  activeFileId: string | null;
  showToast: (message: string, type: 'success' | 'error' | 'info', duration?: number) => void;
}

export function ChatTab({ session, openFiles, activeFileId, showToast }: ChatTabProps) {
  const { 
    chatSession, 
    updateSession, 
    attachedFiles, 
    attachFile, 
    removeFile 
  } = useChatSession({
    id: session.id,
    title: session.title,
    messages: session.messages || []
  });

  return (
    <ChatInterface
      session={chatSession || undefined}
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
  );
}