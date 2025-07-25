import React, { createContext, useContext, ReactNode, useCallback, useRef } from 'react';
import { useTerminalWebSocket } from '../hooks/use-terminal-websocket';

interface TerminalWebSocketContextType {
  sendInput: (sessionId: string, data: string) => void;
  resizeTerminal: (sessionId: string, cols: number, rows: number) => void;
  createSession: (sessionId: string) => void;
  closeSession: (sessionId: string) => void;
  isConnected: boolean;
  connectionState: string;
  subscribe: (sessionId: string, handler: (data: string) => void) => () => void;
}

const TerminalWebSocketContext = createContext<TerminalWebSocketContextType | undefined>(undefined);

export function useTerminalWebSocketContext() {
  const context = useContext(TerminalWebSocketContext);
  if (!context) {
    throw new Error('useTerminalWebSocketContext must be used within a TerminalWebSocketProvider');
  }
  return context;
}

interface TerminalWebSocketProviderProps {
  children: ReactNode;
  url: string;
}

export function TerminalWebSocketProvider({ children, url }: TerminalWebSocketProviderProps) {
  const outputHandlers = useRef<Map<string, Set<(data: string) => void>>>(new Map());

  const handleOutput = useCallback((sessionId: string, data: string) => {
    const handlers = outputHandlers.current.get(sessionId);
    if (handlers) {
      handlers.forEach(handler => handler(data));
    }
  }, []);

  const { sendInput, resizeTerminal, createSession, closeSession, isConnected, connectionState } = useTerminalWebSocket({
    url,
    onOutput: handleOutput,
  });

  const subscribe = useCallback((sessionId: string, handler: (data: string) => void) => {
    if (!outputHandlers.current.has(sessionId)) {
      outputHandlers.current.set(sessionId, new Set());
    }
    outputHandlers.current.get(sessionId)!.add(handler);

    // Return unsubscribe function
    return () => {
      const handlers = outputHandlers.current.get(sessionId);
      if (handlers) {
        handlers.delete(handler);
        if (handlers.size === 0) {
          outputHandlers.current.delete(sessionId);
        }
      }
    };
  }, []);

  return (
    <TerminalWebSocketContext.Provider value={{
      sendInput,
      resizeTerminal,
      createSession,
      closeSession,
      isConnected,
      connectionState,
      subscribe,
    }}>
      {children}
    </TerminalWebSocketContext.Provider>
  );
}