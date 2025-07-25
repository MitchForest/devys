import useWebSocket, { ReadyState } from 'react-use-websocket';
import { useCallback, useEffect, useRef } from 'react';

interface WebSocketMessage {
  type: string;
  payload?: unknown;
}

interface UseAppWebSocketOptions {
  onMessage?: (message: WebSocketMessage) => void;
  onConnectionChange?: (isConnected: boolean) => void;
  shouldReconnect?: boolean;
}

export function useAppWebSocket(url: string, options: UseAppWebSocketOptions = {}) {
  const { onMessage, onConnectionChange, shouldReconnect = true } = options;
  const messageQueue = useRef<WebSocketMessage[]>([]);
  const previousReadyState = useRef<ReadyState | null>(null);

  const { sendMessage, lastMessage, readyState } = useWebSocket(url, {
    shouldReconnect: () => shouldReconnect,
    reconnectAttempts: 10,
    reconnectInterval: (attemptNumber) => 
      Math.min(Math.pow(2, attemptNumber) * 1000, 10000), // exponential backoff up to 10s
    share: true, // share socket across components
    heartbeat: {
      message: JSON.stringify({ type: 'ping' }),
      returnMessage: JSON.stringify({ type: 'pong' }),
      timeout: 60000, // 1 minute
      interval: 30000, // 30 seconds
    },
  });

  // Handle connection state changes
  useEffect(() => {
    if (previousReadyState.current !== readyState) {
      const isConnected = readyState === ReadyState.OPEN;
      onConnectionChange?.(isConnected);

      // Send queued messages when connected
      if (isConnected && messageQueue.current.length > 0) {
        messageQueue.current.forEach(msg => {
          sendMessage(JSON.stringify(msg));
        });
        messageQueue.current = [];
      }

      previousReadyState.current = readyState;
    }
  }, [readyState, sendMessage, onConnectionChange]);

  // Handle incoming messages
  useEffect(() => {
    if (lastMessage !== null) {
      try {
        const message = JSON.parse(lastMessage.data) as WebSocketMessage;
        onMessage?.(message);
      } catch (error) {
        console.error('Failed to parse WebSocket message:', error);
      }
    }
  }, [lastMessage, onMessage]);

  // Enhanced send function with queueing
  const send = useCallback((message: WebSocketMessage) => {
    if (readyState === ReadyState.OPEN) {
      sendMessage(JSON.stringify(message));
    } else {
      // Queue message for when connection is restored
      messageQueue.current.push(message);
    }
  }, [readyState, sendMessage]);

  return {
    send,
    readyState,
    isConnected: readyState === ReadyState.OPEN,
    isConnecting: readyState === ReadyState.CONNECTING,
    connectionState: ReadyState[readyState] as keyof typeof ReadyState,
  };
}

// Export ReadyState enum for convenience
export { ReadyState };