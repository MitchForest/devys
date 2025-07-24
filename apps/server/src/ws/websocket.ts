import { ServerWebSocket } from 'bun';
import { z } from 'zod';

// WebSocket message types
const WSMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('file:watch'),
    path: z.string()
  }),
  z.object({
    type: z.literal('file:unwatch'),
    path: z.string()
  }),
  z.object({
    type: z.literal('terminal:create'),
    id: z.string()
  }),
  z.object({
    type: z.literal('terminal:input'),
    id: z.string(),
    data: z.string()
  }),
  z.object({
    type: z.literal('terminal:resize'),
    id: z.string(),
    cols: z.number(),
    rows: z.number()
  }),
  z.object({
    type: z.literal('terminal:close'),
    id: z.string()
  }),
  z.object({
    type: z.literal('chat:message'),
    sessionId: z.string(),
    message: z.string()
  }),
  z.object({
    type: z.literal('ping')
  })
]);

export type WSMessage = z.infer<typeof WSMessageSchema>;

// WebSocket response types
export type WSResponse = 
  | { type: 'file:changed'; path: string; event: 'created' | 'modified' | 'deleted' }
  | { type: 'terminal:output'; id: string; data: string }
  | { type: 'terminal:exit'; id: string; code: number }
  | { type: 'chat:response'; sessionId: string; message: string; streaming: boolean }
  | { type: 'error'; message: string }
  | { type: 'pong' };

export interface WSData {
  connectionId: string;
}

export class WebSocketManager {
  private connections: Map<string, ServerWebSocket<WSData>> = new Map();
  private fileWatchers: Map<string, Set<string>> = new Map(); // path -> connectionIds
  private terminals: Map<string, any> = new Map(); // terminalId -> terminal process
  private connectionCounter = 0;

  addConnection(ws: ServerWebSocket<any>) {
    const connectionId = `ws-${++this.connectionCounter}`;
    ws.data = { connectionId };
    this.connections.set(connectionId, ws as ServerWebSocket<WSData>);
    console.log(`WebSocket connected: ${connectionId}`);
    return connectionId;
  }

  removeConnection(connectionId: string) {
    this.connections.delete(connectionId);
    console.log(`WebSocket disconnected: ${connectionId}`);
    
    // Clean up file watchers
    for (const [path, watchers] of this.fileWatchers.entries()) {
      watchers.delete(connectionId);
      if (watchers.size === 0) {
        this.fileWatchers.delete(path);
      }
    }
  }

  async handleMessage(ws: ServerWebSocket<any>, message: string | Buffer) {
    const connectionId = ws.data?.connectionId;
    if (!connectionId) return;
    
    try {
      const data = typeof message === 'string' ? JSON.parse(message) : JSON.parse(message.toString());
      const parsed = WSMessageSchema.parse(data);

      switch (parsed.type) {
        case 'file:watch':
          this.watchFile(connectionId, parsed.path);
          break;
          
        case 'file:unwatch':
          this.unwatchFile(connectionId, parsed.path);
          break;
          
        case 'terminal:create':
          // TODO: Implement terminal creation
          this.send(connectionId, { 
            type: 'error', 
            message: 'Terminal support not yet implemented' 
          });
          break;
          
        case 'chat:message':
          // TODO: Implement chat integration
          this.send(connectionId, {
            type: 'chat:response',
            sessionId: parsed.sessionId,
            message: 'Chat integration coming soon...',
            streaming: false
          });
          break;
          
        case 'ping':
          this.send(connectionId, { type: 'pong' });
          break;
      }
    } catch (error) {
      this.send(connectionId, {
        type: 'error',
        message: error instanceof Error ? error.message : 'Invalid message format'
      });
    }
  }

  private watchFile(connectionId: string, path: string) {
    if (!this.fileWatchers.has(path)) {
      this.fileWatchers.set(path, new Set());
      // TODO: Implement actual file watching with fs.watch
    }
    this.fileWatchers.get(path)?.add(connectionId);
  }

  private unwatchFile(connectionId: string, path: string) {
    const watchers = this.fileWatchers.get(path);
    if (watchers) {
      watchers.delete(connectionId);
      if (watchers.size === 0) {
        this.fileWatchers.delete(path);
        // TODO: Stop file watching
      }
    }
  }

  send(connectionId: string, response: WSResponse) {
    const ws = this.connections.get(connectionId);
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(response));
    }
  }

  broadcast(response: WSResponse) {
    const message = JSON.stringify(response);
    for (const ws of this.connections.values()) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      }
    }
  }

  notifyFileChange(path: string, event: 'created' | 'modified' | 'deleted') {
    const watchers = this.fileWatchers.get(path);
    if (watchers) {
      const response: WSResponse = {
        type: 'file:changed',
        path,
        event
      };
      
      for (const connectionId of watchers) {
        this.send(connectionId, response);
      }
    }
  }
}

export const wsManager = new WebSocketManager();