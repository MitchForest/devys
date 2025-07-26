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
    payload: z.object({
      sessionId: z.string(),
      cwd: z.string().optional()
    })
  }),
  z.object({
    type: z.literal('terminal:execute'),
    payload: z.object({
      sessionId: z.string(),
      command: z.string(),
      cwd: z.string().optional()
    })
  }),
  z.object({
    type: z.literal('terminal:input'),
    payload: z.object({
      sessionId: z.string(),
      data: z.string()
    })
  }),
  z.object({
    type: z.literal('terminal:resize'),
    payload: z.object({
      sessionId: z.string(),
      cols: z.number(),
      rows: z.number()
    })
  }),
  z.object({
    type: z.literal('terminal:close'),
    payload: z.object({
      sessionId: z.string()
    })
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
  | { type: 'terminal:output'; sessionId: string; data: string }
  | { type: 'terminal:exit'; sessionId: string; code: number }
  | { type: 'terminal:created'; sessionId: string }
  | { type: 'terminal:closed'; sessionId: string }
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
  buffer?: string;
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
          this.createTerminal(connectionId, parsed.payload.sessionId, parsed.payload.cwd);
          break;
          
        case 'terminal:execute':
          this.executeCommand(connectionId, parsed.payload.sessionId, parsed.payload.command, parsed.payload.cwd);
          break;
          
        case 'terminal:input':
          this.handleTerminalInput(connectionId, parsed.payload.sessionId, parsed.payload.data);
          break;
          
        case 'terminal:resize':
          // TODO: Implement terminal resize
          break;
          
        case 'terminal:close':
          this.closeTerminal(parsed.payload.sessionId);
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
      type: 'terminal:created',
      sessionId: terminalId
    });
    
    const terminal = this.terminals.get(terminalId)!;
    const prompt = this.getPrompt(terminal.cwd);
    this.send(connectionId, {
      type: 'terminal:output',
      sessionId: terminalId,
      data: `Terminal ${terminalId} created\r\n${prompt}`
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

    // Don't intercept claude command - let it execute normally
    // The system will handle whether it's installed or not

    // Handle cd command specially
    if (command.startsWith('cd ')) {
      const newDir = command.substring(3).trim();
      try {
        const oldPrompt = this.getPrompt(terminal.cwd);
        terminal.cwd = path.resolve(terminal.cwd, newDir);
        const newPrompt = this.getPrompt(terminal.cwd);
        this.send(connectionId, {
          type: 'terminal:output',
          sessionId: terminalId,
          data: `${oldPrompt}${command}\r\n${newPrompt}`
        });
        return;
      } catch (error) {
        const prompt = this.getPrompt(terminal.cwd);
        this.send(connectionId, {
          type: 'terminal:output',
          sessionId: terminalId,
          data: `${prompt}${command}\r\ncd: ${error instanceof Error ? error.message : 'Invalid path'}\r\n${prompt}`
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

    // Send command echo with prompt
    const prompt = this.getPrompt(terminal.cwd);
    this.send(connectionId, {
      type: 'terminal:output',
      sessionId: terminalId,
      data: `${prompt}${command}\r\n`
    });

    // Handle stdout
    proc.stdout.on('data', (data: Buffer) => {
      this.send(connectionId, {
        type: 'terminal:output',
        sessionId: terminalId,
        data: data.toString().replace(/\n/g, '\r\n')
      });
    });

    // Handle stderr
    proc.stderr.on('data', (data: Buffer) => {
      this.send(connectionId, {
        type: 'terminal:output',
        sessionId: terminalId,
        data: data.toString().replace(/\n/g, '\r\n')
      });
    });

    // Handle exit
    proc.on('exit', (code) => {
      terminal.process = null;
      this.send(connectionId, {
        type: 'terminal:exit',
        sessionId: terminalId,
        code: code || 0
      });
      // Send new prompt with path
      const prompt = this.getPrompt(terminal.cwd);
      this.send(connectionId, {
        type: 'terminal:output',
        sessionId: terminalId,
        data: prompt
      });
    });

    // Handle error
    proc.on('error', (error) => {
      const prompt = this.getPrompt(terminal.cwd);
      this.send(connectionId, {
        type: 'terminal:output',
        sessionId: terminalId,
        data: `Error: ${error.message}\r\n${prompt}`
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
        sessionId: terminalId,
        data: output.replace(/\n/g, '\r\n')
      });
    }
  }

  private handleTerminalInput(connectionId: string, terminalId: string, data: string) {
    const terminal = this.terminals.get(terminalId);
    if (!terminal) {
      this.send(connectionId, {
        type: 'error',
        message: `Terminal ${terminalId} not found`
      });
      return;
    }

    // If there's a running process, send input to it
    if (terminal.process && terminal.process.stdin) {
      terminal.process.stdin.write(data);
    } else {
      // No running process, accumulate input and echo it back
      // Initialize buffer if not exists
      if (!terminal.buffer) {
        terminal.buffer = '';
      }
      
      // Handle special characters
      if (data === '\r' || data === '\n') {
        // Enter key pressed - execute the buffered command
        const command = terminal.buffer.trim();
        terminal.buffer = '';
        if (command) {
          this.executeCommand(connectionId, terminalId, command);
        } else {
          // Just send a new prompt with path
          const prompt = this.getPrompt(terminal.cwd);
          this.send(connectionId, {
            type: 'terminal:output',
            sessionId: terminalId,
            data: `\r\n${prompt}`
          });
        }
      } else if (data === '\x7f' || data === '\b') {
        // Backspace
        if (terminal.buffer.length > 0) {
          terminal.buffer = terminal.buffer.slice(0, -1);
          // Send backspace sequence to update the display
          this.send(connectionId, {
            type: 'terminal:output',
            sessionId: terminalId,
            data: '\b \b'
          });
        }
      } else if (data === '\x03') {
        // Ctrl+C - clear buffer and send new prompt
        terminal.buffer = '';
        const prompt = this.getPrompt(terminal.cwd);
        this.send(connectionId, {
          type: 'terminal:output',
          sessionId: terminalId,
          data: `^C\r\n${prompt}`
        });
      } else {
        // Regular character - add to buffer and echo
        terminal.buffer += data;
        this.send(connectionId, {
          type: 'terminal:output',
          sessionId: terminalId,
          data: data
        });
      }
    }
  }

  private closeTerminal(terminalId: string) {
    const terminal = this.terminals.get(terminalId);
    if (terminal) {
      // Kill the process if running
      if (terminal.process && !terminal.process.killed) {
        terminal.process.kill();
      }
      this.terminals.delete(terminalId);
    }
  }

  private getPrompt(cwd: string): string {
    // Get just the last part of the path for display
    const cwdName = cwd.split(path.sep).pop() || cwd;
    const username = process.env.USER || 'user';
    const hostname = process.env.HOSTNAME || 'localhost';
    
    // Format: username@hostname cwdName % 
    return `${username}@${hostname} ${cwdName} % `;
  }
}

export const wsManager = new WebSocketManager();