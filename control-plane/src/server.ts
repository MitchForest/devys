// control-plane/src/server.ts
// Phase 1: Bun Control Plane Server Implementation

import { Database } from "bun:sqlite";
import { $ } from "bun";
import { z } from "zod";
import type { Server, ServerWebSocket } from "bun";

// Types and interfaces
interface RepoContext {
  codeMap: CodeMap;
  recentChanges: Change[];
  activeFiles: string[];
  failingTests: Test[];
  openPRs: PullRequest[];
}

interface CodeMap {
  functions: Symbol[];
  classes: Symbol[];
  interfaces: Symbol[];
  types: Symbol[];
  imports: Dependency[];
  workingSet: WorkingFile[];
}

interface Symbol {
  name: string;
  file: string;
  line: number;
  type: 'function' | 'class' | 'interface' | 'type';
  signature?: string;
  complexity?: number;
  references?: number;
}

interface Change {
  file: string;
  timestamp: number;
  type: 'add' | 'modify' | 'delete';
}

interface Test {
  name: string;
  file: string;
  error?: string;
}

interface PullRequest {
  id: number;
  title: string;
  author: string;
}

interface Dependency {
  name: string;
  path: string;
}

interface WorkingFile {
  path: string;
  lastModified: number;
}

interface Session {
  id: string;
  userId: string;
  workspace: string;
  context: RepoContext;
  createdAt: number;
  updatedAt: number;
  lastActivity?: number;
}

// Validation schemas
const CreateSessionSchema = z.object({
  userId: z.string().min(1),
  workspace: z.string().min(1),
});

const UpdateContextSchema = z.object({
  trigger: z.enum(['file_open', 'file_save', 'git_commit', 'test_run', 'manual']),
  data: z.any().optional(),
});

class ControlPlaneServer {
  private db: Database;
  private sessions: Map<string, Session>;
  private ptySidecarProcess?: any;
  public contextServer: ContextServer; // Made public for API access
  private claudeOrchestrator: ClaudeOrchestrator;
  private wsClients: Map<string, ServerWebSocket<any>>;
  
  constructor() {
    // Initialize database
    this.db = new Database("control.db");
    this.initDatabase();
    
    // Initialize in-memory caches
    this.sessions = new Map();
    this.wsClients = new Map();
    
    // Initialize services
    this.contextServer = new ContextServer(this.db);
    this.claudeOrchestrator = new ClaudeOrchestrator();
    
    // Start PTY sidecar
    this.startPtySidecar();
    
    // Load existing sessions from database
    this.loadSessions();
    
    // Start cleanup timer
    this.startCleanupTimer();
  }
  
  private async initDatabase() {
    try {
      // Read and execute schema
      const schema = await Bun.file("db/schema.sql").text();
      this.db.exec(schema);
    } catch (error: any) {
      // Ignore if tables/indexes already exist
      if (!error.message?.includes('already exists')) {
        throw error;
      }
    }
  }
  
  private async startPtySidecar() {
    try {
      // Check if sidecar binary exists
      const sidecarPath = "../pty-sidecar/target/release/pty-sidecar";
      const exists = await Bun.file(sidecarPath).exists();
      
      if (!exists) {
        console.warn("PTY sidecar not built. Building now...");
        await $`cd ../pty-sidecar && cargo build --release`.quiet();
      }
      
      // Launch PTY sidecar
      this.ptySidecarProcess = Bun.spawn([sidecarPath], {
        stdout: "pipe",
        stderr: "pipe",
        onExit(proc, exitCode, signalCode, error) {
          console.error(`PTY sidecar exited: code=${exitCode}, signal=${signalCode}`, error);
          // Auto-restart after 5 seconds
          setTimeout(() => this.startPtySidecar(), 5000);
        }
      });
      
      console.log("✅ PTY sidecar started on ws://localhost:8081");
      
      // Monitor sidecar output
      this.monitorSidecarOutput();
      
    } catch (error) {
      console.error("Failed to start PTY sidecar:", error);
      // Retry after 5 seconds
      setTimeout(() => this.startPtySidecar(), 5000);
    }
  }
  
  private async monitorSidecarOutput() {
    if (!this.ptySidecarProcess) return;
    
    const reader = this.ptySidecarProcess.stdout.getReader();
    const decoder = new TextDecoder();
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      const text = decoder.decode(value);
      console.log("[PTY Sidecar]", text.trim());
    }
  }
  
  private loadSessions() {
    const rows = this.db.query("SELECT * FROM sessions").all() as any[];
    
    for (const row of rows) {
      const session: Session = {
        id: row.id,
        userId: row.user_id,
        workspace: row.workspace,
        context: JSON.parse(row.context),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        lastActivity: row.last_activity,
      };
      
      this.sessions.set(session.id, session);
    }
    
    console.log(`Loaded ${this.sessions.size} sessions from database`);
  }
  
  private startCleanupTimer() {
    // Clean up stale sessions every 5 minutes
    setInterval(() => {
      const now = Date.now();
      const staleTimeout = 3600000; // 1 hour
      
      for (const [id, session] of this.sessions) {
        const lastActivity = session.lastActivity || session.updatedAt;
        if (now - lastActivity > staleTimeout) {
          console.log(`Removing stale session: ${id}`);
          this.deleteSession(id);
        }
      }
    }, 300000); // 5 minutes
  }
  
  async createSession(userId: string, workspace: string): Promise<Session> {
    const sessionId = crypto.randomUUID();
    const now = Date.now();
    
    // Generate initial context
    const context = await this.contextServer.generateContext(workspace);
    
    const session: Session = {
      id: sessionId,
      userId,
      workspace,
      context,
      createdAt: now,
      updatedAt: now,
    };
    
    // Store in memory
    this.sessions.set(sessionId, session);
    
    // Persist to database
    this.db.run(
      `INSERT INTO sessions (id, user_id, workspace, context, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [sessionId, userId, workspace, JSON.stringify(context), now, now]
    );
    
    // Log event
    this.logEvent(sessionId, 'session_created', { userId, workspace });
    
    return session;
  }
  
  async getSession(sessionId: string): Promise<Session | null> {
    // Try memory first
    let session = this.sessions.get(sessionId);
    
    if (!session) {
      // Try database
      const row = this.db.query(
        "SELECT * FROM sessions WHERE id = ?"
      ).get(sessionId) as any;
      
      if (row) {
        session = {
          id: row.id,
          userId: row.user_id,
          workspace: row.workspace,
          context: JSON.parse(row.context),
          createdAt: row.created_at,
          updatedAt: row.updated_at,
          lastActivity: row.last_activity,
        };
        
        // Cache in memory
        this.sessions.set(sessionId, session);
      }
    }
    
    return session || null;
  }
  
  async deleteSession(sessionId: string): Promise<boolean> {
    // Remove from memory
    const deleted = this.sessions.delete(sessionId);
    
    // Remove from database
    this.db.run("DELETE FROM sessions WHERE id = ?", [sessionId]);
    
    // Close WebSocket if exists
    const ws = this.wsClients.get(sessionId);
    if (ws) {
      ws.close();
      this.wsClients.delete(sessionId);
    }
    
    return deleted;
  }
  
  async updateContext(sessionId: string, trigger: string, data?: any) {
    const session = await this.getSession(sessionId);
    if (!session) throw new Error("Session not found");
    
    // Update context based on trigger
    session.context = await this.contextServer.updateContext(
      session.workspace,
      session.context,
      trigger,
      data
    );
    
    session.updatedAt = Date.now();
    session.lastActivity = Date.now();
    
    // Update in database
    this.db.run(
      `UPDATE sessions 
       SET context = ?, updated_at = ?, last_activity = ?
       WHERE id = ?`,
      [JSON.stringify(session.context), session.updatedAt, session.lastActivity, sessionId]
    );
    
    // Log event
    this.logEvent(sessionId, 'context_updated', { trigger, data });
    
    // Notify WebSocket clients
    this.broadcastToSession(sessionId, {
      type: 'context_updated',
      context: session.context,
    });
    
    return session.context;
  }
  
  async runClaudeCommand(sessionId: string, command: string, context?: any) {
    const session = await this.getSession(sessionId);
    if (!session) throw new Error("Session not found");
    
    // Use session context if no specific context provided
    const executionContext = context || session.context;
    
    // Log command
    this.logEvent(sessionId, 'claude_command', { command });
    
    // Execute through orchestrator
    const result = await this.claudeOrchestrator.execute(
      command,
      executionContext,
      sessionId
    );
    
    // Update activity
    session.lastActivity = Date.now();
    this.db.run(
      "UPDATE sessions SET last_activity = ? WHERE id = ?",
      [session.lastActivity, sessionId]
    );
    
    return result;
  }
  
  private logEvent(sessionId: string, type: string, data?: any) {
    this.db.run(
      "INSERT INTO events (session_id, type, data, timestamp) VALUES (?, ?, ?, ?)",
      [sessionId, type, data ? JSON.stringify(data) : null, Date.now()]
    );
  }
  
  private logMetric(sessionId: string, metric: string, value: number) {
    this.db.run(
      "INSERT INTO metrics (session_id, metric, value, timestamp) VALUES (?, ?, ?, ?)",
      [sessionId, metric, value, Date.now()]
    );
  }
  
  private broadcastToSession(sessionId: string, message: any) {
    const ws = this.wsClients.get(sessionId);
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify(message));
    }
  }
  
  // API Handlers
  async handleApiRequest(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace('/api/', '');
    const method = req.method;
    
    try {
      // Session endpoints
      if (path === 'sessions' && method === 'POST') {
        const body = await req.json();
        const validated = CreateSessionSchema.parse(body);
        const session = await this.createSession(validated.userId, validated.workspace);
        return Response.json(session);
      }
      
      if (path.startsWith('sessions/')) {
        const parts = path.split('/');
        const sessionId = parts[1];
        
        if (parts.length === 2) {
          if (method === 'GET') {
            const session = await this.getSession(sessionId);
            if (!session) {
              return new Response('Session not found', { status: 404 });
            }
            return Response.json(session);
          }
          
          if (method === 'DELETE') {
            const deleted = await this.deleteSession(sessionId);
            return Response.json({ deleted });
          }
        }
        
        if (parts[2] === 'context' && method === 'POST') {
          const body = await req.json();
          const validated = UpdateContextSchema.parse(body);
          const context = await this.updateContext(
            sessionId,
            validated.trigger,
            validated.data
          );
          return Response.json(context);
        }
        
        if (parts[2] === 'claude' && method === 'POST') {
          const body = await req.json();
          const result = await this.runClaudeCommand(
            sessionId,
            body.command,
            body.context
          );
          return Response.json(result);
        }
      }
      
      // Health check
      if (path === 'health') {
        const health = {
          status: 'healthy',
          sessions: this.sessions.size,
          ptySidecar: this.ptySidecarProcess ? 'running' : 'stopped',
          database: 'connected',
          uptime: process.uptime(),
        };
        return Response.json(health);
      }
      
      return new Response('Not Found', { status: 404 });
      
    } catch (error: any) {
      console.error('API error:', error);
      
      if (error instanceof z.ZodError) {
        return Response.json(
          { error: 'Validation error', details: error.errors },
          { status: 400 }
        );
      }
      
      return Response.json(
        { error: error.message },
        { status: 500 }
      );
    }
  }
}

// Phase 2: Real Context Server Implementation
import { ContextGenerator } from './services/context/context-generator';

class ContextServer {
  private contextGenerators: Map<string, ContextGenerator> = new Map();
  
  constructor(private db: Database) {}
  
  private getGenerator(workspace: string): ContextGenerator {
    if (!this.contextGenerators.has(workspace)) {
      this.contextGenerators.set(workspace, new ContextGenerator(workspace, this.db));
    }
    return this.contextGenerators.get(workspace)!;
  }
  
  async generateContext(workspace: string): Promise<RepoContext> {
    const generator = this.getGenerator(workspace);
    const context = await generator.generateContext();
    
    // Transform to legacy RepoContext format for compatibility
    return {
      codeMap: {
        functions: context.codeMap?.functions.map(f => ({
          name: f.name,
          file: f.file,
          line: f.line,
          type: 'function' as const,
          signature: f.signature,
          complexity: f.complexity,
          references: 0
        })) || [],
        classes: context.codeMap?.classes.map(c => ({
          name: c.name,
          file: c.file,
          line: c.line,
          type: 'class' as const,
          signature: c.name,
          complexity: 1,
          references: 0
        })) || [],
        interfaces: context.codeMap?.interfaces.map(i => ({
          name: i.name,
          file: i.file,
          line: i.line,
          type: 'interface' as const,
          signature: i.name,
          complexity: 1,
          references: 0
        })) || [],
        types: context.codeMap?.types.map(t => ({
          name: t.name,
          file: t.file,
          line: t.line,
          type: 'type' as const,
          signature: t.definition,
          complexity: 1,
          references: 0
        })) || [],
        imports: [],
        workingSet: context.selectedFiles?.map(f => ({
          path: f.path,
          lastModified: Date.now()
        })) || [],
      },
      recentChanges: [],
      activeFiles: context.selectedFiles?.map(f => f.path) || [],
      failingTests: [],
      openPRs: [],
    };
  }
  
  async updateContext(
    workspace: string,
    currentContext: RepoContext,
    trigger: string,
    data?: any
  ): Promise<RepoContext> {
    const generator = this.getGenerator(workspace);
    const context = await generator.updateContext(trigger, data);
    
    // Transform to legacy format
    return this.generateContext(workspace);
  }
  
  async getMetrics(workspace: string) {
    const generator = this.getGenerator(workspace);
    return generator.getMetrics();
  }
  
  clearCache(workspace: string) {
    const generator = this.getGenerator(workspace);
    generator.clearCache();
  }
}

class ClaudeOrchestrator {
  async execute(command: string, context: any, sessionId: string): Promise<any> {
    // Placeholder - will be implemented in Phase 5
    return {
      command,
      result: 'Command execution will be implemented in Phase 5',
      sessionId,
    };
  }
}

// Import context API
import { ContextAPI } from './api/context-api';

// Start the server
const controlPlane = new ControlPlaneServer();
const contextAPI = new ContextAPI(controlPlane.contextServer);

const server = Bun.serve({
  port: 3000,
  
  async fetch(req, server) {
    const url = new URL(req.url);
    
    // WebSocket upgrade
    if (req.headers.get('upgrade') === 'websocket') {
      const sessionId = url.searchParams.get('session');
      if (!sessionId) {
        return new Response('Session ID required', { status: 400 });
      }
      
      const success = server.upgrade(req, {
        data: { sessionId },
      });
      
      return success
        ? undefined
        : new Response('WebSocket upgrade failed', { status: 500 });
    }
    
    // Context API routes (Phase 2)
    if (url.pathname.startsWith('/api/context/')) {
      return contextAPI.handleRequest(req);
    }
    
    // API routes
    if (url.pathname.startsWith('/api/')) {
      return controlPlane.handleApiRequest(req);
    }
    
    // Static files
    if (url.pathname === '/') {
      const indexFile = Bun.file('public/index.html');
      if (await indexFile.exists()) {
        return new Response(indexFile);
      }
      return new Response('Welcome to Devys Control Plane', {
        headers: { 'Content-Type': 'text/plain' },
      });
    }
    
    return new Response('Not Found', { status: 404 });
  },
  
  websocket: {
    open(ws) {
      const { sessionId } = ws.data;
      controlPlane.wsClients.set(sessionId, ws);
      console.log(`WebSocket connected for session: ${sessionId}`);
    },
    
    message(ws, message) {
      const { sessionId } = ws.data;
      // Handle WebSocket messages
      try {
        const data = JSON.parse(message.toString());
        console.log(`WebSocket message from ${sessionId}:`, data);
        // Process based on message type
      } catch (error) {
        console.error('Invalid WebSocket message:', error);
      }
    },
    
    close(ws) {
      const { sessionId } = ws.data;
      controlPlane.wsClients.delete(sessionId);
      console.log(`WebSocket disconnected for session: ${sessionId}`);
    },
  },
});

console.log(`🚀 Control plane running on http://localhost:${server.port}`);
console.log(`📊 API available at http://localhost:${server.port}/api/`);
console.log(`🔌 WebSocket endpoint: ws://localhost:${server.port}/?session=SESSION_ID`);