import { ServerWebSocket } from 'bun';
import { z } from 'zod';
import { spawn, type ChildProcess } from 'child_process';
import * as path from 'path';

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
    id: z.string(),
    cwd: z.string().optional()
  }),
  z.object({
    type: z.literal('terminal:execute'),
    id: z.string(),
    command: z.string(),
    cwd: z.string().optional()
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
  }),
  z.object({
    type: z.literal('workflow:subscribe'),
    executionId: z.string()
  }),
  z.object({
    type: z.literal('workflow:unsubscribe'),
    executionId: z.string()
  })
]);

export type WSMessage = z.infer<typeof WSMessageSchema>;

// WebSocket response types
export type WSResponse = 
  | { type: 'file:changed'; path: string; event: 'created' | 'modified' | 'deleted' }
  | { type: 'terminal:output'; id: string; data: string }
  | { type: 'terminal:exit'; id: string; code: number }
  | { type: 'chat:response'; sessionId: string; message: string; streaming: boolean }
  | { type: 'workflow:progress'; event: unknown }
  | { type: 'workflow:subscribed'; executionId: string }
  | { type: 'workflow:unsubscribed'; executionId: string }
  | { type: 'error'; message: string }
  | { type: 'pong' };

export interface WSData {
  connectionId: string;
}

interface TerminalProcess {
  process: ChildProcess | null;
  cwd: string;
  connectionId: string;
}

export class WebSocketManager {
  private connections: Map<string, ServerWebSocket<WSData>> = new Map();
  private fileWatchers: Map<string, Set<string>> = new Map(); // path -> connectionIds
  private terminals: Map<string, TerminalProcess> = new Map(); // terminalId -> terminal process
  private connectionCounter = 0;

  addConnection(ws: ServerWebSocket<unknown>) {
    const connectionId = `ws-${++this.connectionCounter}`;
    ws.data = { connectionId };
    this.connections.set(connectionId, ws as ServerWebSocket<WSData>);
    // WebSocket connected: ${connectionId}
    return connectionId;
  }

  removeConnection(connectionId: string) {
    this.connections.delete(connectionId);
    // WebSocket disconnected: ${connectionId}
    
    // Clean up file watchers
    for (const [path, watchers] of this.fileWatchers.entries()) {
      watchers.delete(connectionId);
      if (watchers.size === 0) {
        this.fileWatchers.delete(path);
      }
    }
  }

  async handleMessage(ws: ServerWebSocket<unknown>, message: string | Buffer) {
    const connectionId = (ws.data as WSData | undefined)?.connectionId;
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
          this.createTerminal(connectionId, parsed.id, parsed.cwd);
          break;
          
        case 'terminal:execute':
          this.executeCommand(connectionId, parsed.id, parsed.command, parsed.cwd);
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
          
        case 'workflow:subscribe':
          // For Phase 1, we just acknowledge the subscription
          // The workflow engine will broadcast to all connections
          this.send(connectionId, { 
            type: 'workflow:subscribed', 
            executionId: parsed.executionId 
          });
          break;
          
        case 'workflow:unsubscribe':
          this.send(connectionId, { 
            type: 'workflow:unsubscribed', 
            executionId: parsed.executionId 
          });
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

  private createTerminal(connectionId: string, terminalId: string, cwd?: string) {
    if (this.terminals.has(terminalId)) {
      this.send(connectionId, {
        type: 'error',
        message: `Terminal ${terminalId} already exists`
      });
      return;
    }

    this.terminals.set(terminalId, {
      process: null,
      cwd: cwd || process.cwd(),
      connectionId
    });

    // Send initial output
    this.send(connectionId, {
      type: 'terminal:output',
      id: terminalId,
      data: `Terminal ${terminalId} created\r\n$ `
    });
  }

  private executeCommand(connectionId: string, terminalId: string, command: string, cwd?: string) {
    const terminal = this.terminals.get(terminalId);
    if (!terminal) {
      this.send(connectionId, {
        type: 'error',
        message: `Terminal ${terminalId} not found`
      });
      return;
    }

    // Kill any existing process
    if (terminal.process && !terminal.process.killed) {
      terminal.process.kill();
    }

    // Update cwd if provided
    if (cwd) {
      terminal.cwd = cwd;
    }

    // Handle cd command specially
    if (command.startsWith('cd ')) {
      const newDir = command.substring(3).trim();
      try {
        terminal.cwd = path.resolve(terminal.cwd, newDir);
        this.send(connectionId, {
          type: 'terminal:output',
          id: terminalId,
          data: `$ ${command}\r\n$ `
        });
        return;
      } catch (error) {
        this.send(connectionId, {
          type: 'terminal:output',
          id: terminalId,
          data: `$ ${command}\r\ncd: ${error instanceof Error ? error.message : 'Invalid path'}\r\n$ `
        });
        return;
      }
    }

    // Execute command
    const proc = spawn(command, [], {
      cwd: terminal.cwd,
      shell: true,
      env: process.env
    });

    terminal.process = proc;

    // Send command echo
    this.send(connectionId, {
      type: 'terminal:output',
      id: terminalId,
      data: `$ ${command}\r\n`
    });

    // Handle stdout
    proc.stdout.on('data', (data: Buffer) => {
      this.send(connectionId, {
        type: 'terminal:output',
        id: terminalId,
        data: data.toString().replace(/\n/g, '\r\n')
      });
    });

    // Handle stderr
    proc.stderr.on('data', (data: Buffer) => {
      this.send(connectionId, {
        type: 'terminal:output',
        id: terminalId,
        data: data.toString().replace(/\n/g, '\r\n')
      });
    });

    // Handle exit
    proc.on('exit', (code) => {
      terminal.process = null;
      this.send(connectionId, {
        type: 'terminal:exit',
        id: terminalId,
        code: code || 0
      });
      // Send new prompt
      this.send(connectionId, {
        type: 'terminal:output',
        id: terminalId,
        data: '$ '
      });
    });

    // Handle error
    proc.on('error', (error) => {
      this.send(connectionId, {
        type: 'terminal:output',
        id: terminalId,
        data: `Error: ${error.message}\r\n$ `
      });
      terminal.process = null;
    });
  }

  // Method to send output from Claude Code's Bash tool to terminal
  sendTerminalOutput(terminalId: string, output: string) {
    const terminal = this.terminals.get(terminalId);
    if (terminal) {
      this.send(terminal.connectionId, {
        type: 'terminal:output',
        id: terminalId,
        data: output.replace(/\n/g, '\r\n')
      });
    }
  }
}

export const wsManager = new WebSocketManager();