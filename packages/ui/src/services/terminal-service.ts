import { EventEmitter } from '../lib/event-emitter';
import type { TerminalSession } from '@devys/types';

// Re-export for convenience
export type { TerminalSession } from '@devys/types';

export interface TerminalCommand {
  sessionId: string;
  command: string;
  cwd?: string;
}

export interface TerminalOutput {
  sessionId: string;
  type: 'stdout' | 'stderr' | 'exit';
  data: string;
  timestamp: Date;
}

export class TerminalService extends EventEmitter {
  private sessions: Map<string, TerminalSession> = new Map();
  private ws: WebSocket | null = null;
  private apiEndpoint: string;

  constructor(apiEndpoint = 'http://localhost:3001/api/terminal') {
    super();
    this.apiEndpoint = apiEndpoint;
  }

  connect(wsUrl: string) {
    if (this.ws) {
      this.ws.close();
    }

    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      this.emit('connected');
    };

    this.ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        this.handleMessage(message);
      } catch (error) {
        console.error('Failed to parse terminal message:', error);
      }
    };

    this.ws.onerror = (error) => {
      console.error('Terminal WebSocket error:', error);
      this.emit('error', error);
    };

    this.ws.onclose = () => {
      this.emit('disconnected');
      this.ws = null;
    };
  }

  disconnect() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private handleMessage(message: { 
    type: string; 
    sessionId?: string;
    id?: string; 
    data?: string;
    outputType?: string;
    timestamp?: string | number;
    code?: number;
    error?: string;
  }) {
    switch (message.type) {
      case 'terminal:output':
        this.handleOutput({
          sessionId: message.id || '',
          type: 'stdout',
          data: message.data || '',
          timestamp: new Date()
        });
        break;
      
      case 'terminal:exit':
        if (message.id && message.code !== undefined) {
          this.handleExit(message.id, message.code);
        }
        break;
      
      case 'error':
        this.emit('terminal-error', {
          sessionId: message.id || message.sessionId,
          error: message.error
        });
        break;
    }
  }

  private handleOutput(output: TerminalOutput) {
    const session = this.sessions.get(output.sessionId);
    if (session) {
      session.output.push(output.data);
      this.emit('output', output);
    }
  }

  private handleExit(sessionId: string, code: number) {
    const session = this.sessions.get(sessionId);
    if (session) {
      if ('isActive' in session) session.isActive = false;
      if ('active' in session) session.active = false;
      this.emit('exit', { sessionId, code });
    }
  }

  createSession(id: string, title: string, cwd?: string): TerminalSession {
    const session: TerminalSession = {
      id,
      title,
      cwd: cwd || '/',
      isActive: true,
      output: []
    };

    this.sessions.set(id, session);
    this.emit('session-created', session);

    // Send create session message to server
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'terminal:create',
        id: id,
        cwd: session.cwd
      }));
    }

    return session;
  }

  getSession(id: string): TerminalSession | undefined {
    return this.sessions.get(id);
  }

  getAllSessions(): TerminalSession[] {
    return Array.from(this.sessions.values());
  }

  async executeCommand(command: TerminalCommand): Promise<void> {
    const session = this.sessions.get(command.sessionId);
    if (!session) {
      throw new Error(`Session ${command.sessionId} not found`);
    }

    if (session.command !== undefined) {
      session.command = command.command;
    }
    session.output.push(`$ ${command.command}\n`);

    // Send command to server via WebSocket
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'terminal:execute',
        id: command.sessionId,
        command: command.command,
        cwd: command.cwd || session.cwd
      }));
    } else {
      // Fallback to HTTP API
      const response = await fetch(`${this.apiEndpoint}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command)
      });

      if (!response.ok) {
        throw new Error(`Failed to execute command: ${response.statusText}`);
      }

      const result = await response.json();
      if (result.output) {
        this.handleOutput({
          sessionId: command.sessionId,
          type: 'stdout',
          data: result.output,
          timestamp: new Date()
        });
      }
      if (result.error) {
        this.handleOutput({
          sessionId: command.sessionId,
          type: 'stderr',
          data: result.error,
          timestamp: new Date()
        });
      }
    }
  }

  killSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    if ('isActive' in session) session.isActive = false;
    if ('active' in session) session.active = false;

    // Send kill message to server
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'terminal:close',
        id: sessionId
      }));
    }

    this.sessions.delete(sessionId);
    this.emit('session-killed', sessionId);
  }

  clearSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.output = [];
      this.emit('session-cleared', sessionId);
    }
  }

  // Method to write output from Claude Code's Bash tool
  writeToolOutput(sessionId: string, output: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      this.handleOutput({
        sessionId,
        type: 'stdout',
        data: output,
        timestamp: new Date()
      });
    }
  }
}

// Export singleton instance
export const terminalService = new TerminalService();