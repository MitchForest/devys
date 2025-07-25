import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from './terminal';
import { useTerminalWebSocketContext } from '../../contexts/terminal-websocket-context';

interface TerminalTabSimpleProps {
  sessionId: string;
  theme?: 'dark' | 'light';
  onTitleChange?: (title: string) => void;
}

export function TerminalTabSimple({ sessionId, theme = 'dark', onTitleChange }: TerminalTabSimpleProps) {
  const terminalRef = useRef<{
    write: (data: string) => void;
    writeln: (data: string) => void;
    clear: () => void;
    focus: () => void;
    fit: () => void;
    getTerminal: () => import('xterm').Terminal | null;
  }>(null);

  const { sendInput, resizeTerminal, createSession, subscribe, isConnected } = useTerminalWebSocketContext();

  // Subscribe to terminal output
  useEffect(() => {
    const unsubscribe = subscribe(sessionId, (data) => {
      if (terminalRef.current) {
        terminalRef.current.write(data);
      }
    });

    return unsubscribe;
  }, [sessionId, subscribe]);

  // Create session when connected
  useEffect(() => {
    if (isConnected) {
      createSession(sessionId);
    }
  }, [isConnected, sessionId, createSession]);

  // Handle terminal data input
  const handleData = useCallback((data: string) => {
    if (isConnected) {
      sendInput(sessionId, data);
    }
  }, [sessionId, sendInput, isConnected]);

  // Handle terminal resize
  const handleResize = useCallback((cols: number, rows: number) => {
    if (isConnected) {
      resizeTerminal(sessionId, cols, rows);
    }
  }, [sessionId, resizeTerminal, isConnected]);

  return (
    <Terminal
      ref={terminalRef}
      id={sessionId}
      theme={theme}
      onData={handleData}
      onResize={handleResize}
      onTitleChange={onTitleChange}
    />
  );
}