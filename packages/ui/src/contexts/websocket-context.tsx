import React, { createContext, useContext, ReactNode } from 'react';
import { useAppWebSocket, ReadyState } from '../hooks/use-app-websocket';

interface WebSocketContextType {
  send: (message: { type: string; payload?: unknown }) => void;
  isConnected: boolean;
  isConnecting: boolean;
  connectionState: keyof typeof ReadyState;
}

const WebSocketContext = createContext<WebSocketContextType | undefined>(undefined);

export function useWebSocket() {
  const context = useContext(WebSocketContext);
  if (!context) {
    throw new Error('useWebSocket must be used within a WebSocketProvider');
  }
  return context;
}

interface WebSocketProviderProps {
  children: ReactNode;
  url: string;
  onMessage?: (message: any) => void;
  onConnectionChange?: (isConnected: boolean) => void;
}

export function WebSocketProvider({ 
  children, 
  url, 
  onMessage,
  onConnectionChange 
}: WebSocketProviderProps) {
  const { send, isConnected, isConnecting, connectionState } = useAppWebSocket(url, {
    onMessage,
    onConnectionChange,
  });

  return (
    <WebSocketContext.Provider value={{ send, isConnected, isConnecting, connectionState }}>
      {children}
    </WebSocketContext.Provider>
  );
}