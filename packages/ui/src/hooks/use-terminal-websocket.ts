import { useCallback } from 'react';
import { useAppWebSocket } from './use-app-websocket';

interface TerminalMessage {
  type: 'terminal:input' | 'terminal:resize' | 'terminal:create' | 'terminal:close';
  payload: {
    sessionId: string;
    data?: string;
    cols?: number;
    rows?: number;
  };
}

interface UseTerminalWebSocketOptions {
  url: string;
  onOutput?: (sessionId: string, data: string) => void;
  onSessionCreated?: (sessionId: string) => void;
  onSessionClosed?: (sessionId: string) => void;
}

export function useTerminalWebSocket({ url, onOutput, onSessionCreated, onSessionClosed }: UseTerminalWebSocketOptions) {
  const handleMessage = useCallback((message: any) => {
    switch (message.type) {
      case 'terminal:output':
        if (message.sessionId && message.data) {
          onOutput?.(message.sessionId, message.data);
        }
        break;
      case 'terminal:created':
        if (message.sessionId) {
          onSessionCreated?.(message.sessionId);
        }
        break;
      case 'terminal:closed':
        if (message.sessionId) {
          onSessionClosed?.(message.sessionId);
        }
        break;
    }
  }, [onOutput, onSessionCreated, onSessionClosed]);

  const { send, isConnected, connectionState } = useAppWebSocket(url, {
    onMessage: handleMessage,
  });

  const sendInput = useCallback((sessionId: string, data: string) => {
    send({
      type: 'terminal:input',
      payload: {
        sessionId,
        data,
      },
    });
  }, [send]);

  const resizeTerminal = useCallback((sessionId: string, cols: number, rows: number) => {
    send({
      type: 'terminal:resize',
      payload: {
        sessionId,
        cols,
        rows,
      },
    });
  }, [send]);

  const createSession = useCallback((sessionId: string, cwd?: string) => {
    send({
      type: 'terminal:create',
      payload: {
        sessionId,
        cwd,
      },
    });
  }, [send]);

  const closeSession = useCallback((sessionId: string) => {
    send({
      type: 'terminal:close',
      payload: {
        sessionId,
      },
    });
  }, [send]);

  return {
    sendInput,
    resizeTerminal,
    createSession,
    closeSession,
    isConnected,
    connectionState,
  };
}