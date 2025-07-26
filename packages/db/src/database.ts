import { Database } from 'bun:sqlite';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface Session {
  id: string;
  claude_session_id?: string;
  created_at: string;
  updated_at: string;
  status: 'active' | 'completed' | 'error';
  project_path: string;
  model: string;
  permission_mode: string;
}

export interface Message {
  id: string;
  session_id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  timestamp: string;
  parent_message_id?: string;
}

export interface ToolInvocation {
  id: string;
  message_id: string;
  tool_name: string;
  input_json?: string;
  output_json?: string;
  status: 'pending' | 'approved' | 'rejected' | 'completed' | 'error';
  created_at: string;
  completed_at?: string;
}

export class DatabaseService {
  private db: Database;

  constructor(dbPath?: string) {
    // Use path relative to packages/db if no path provided
    const defaultPath = join(__dirname, '..', '..', 'devys.db');
    this.db = new Database(dbPath || defaultPath);
    this.db.exec('PRAGMA journal_mode = WAL'); // Better concurrency
    this.initializeSchema();
  }

  private initializeSchema() {
    const schema = readFileSync(join(__dirname, 'schema.sql'), 'utf-8');
    this.db.exec(schema);
  }

  // Session methods
  createSession(id: string, projectPath: string, model: string = 'sonnet'): Session {
    const stmt = this.db.prepare(`
      INSERT INTO sessions (id, project_path, model)
      VALUES (?, ?, ?)
      RETURNING *
    `);
    
    return stmt.get(id, projectPath, model) as Session;
  }

  getSession(id: string): Session | null {
    const stmt = this.db.prepare('SELECT * FROM sessions WHERE id = ?');
    return stmt.get(id) as Session | null;
  }

  updateSession(id: string, updates: Partial<Session>): void {
    const fields = Object.keys(updates)
      .filter(key => key !== 'id')
      .map(key => `${key} = ?`);
    
    if (fields.length === 0) return;
    
    const values = Object.values(updates);
    values.push(id);
    
    const stmt = this.db.prepare(`
      UPDATE sessions 
      SET ${fields.join(', ')}, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);
    
    stmt.run(...values);
  }

  listSessions(limit: number = 20, offset: number = 0): Session[] {
    const stmt = this.db.prepare(`
      SELECT * FROM sessions 
      ORDER BY updated_at DESC 
      LIMIT ? OFFSET ?
    `);
    
    return stmt.all(limit, offset) as Session[];
  }

  // Message methods
  addMessage(message: Omit<Message, 'timestamp'>): Message {
    const stmt = this.db.prepare(`
      INSERT INTO messages (id, session_id, role, content, parent_message_id)
      VALUES (?, ?, ?, ?, ?)
      RETURNING *
    `);
    
    return stmt.get(
      message.id,
      message.session_id,
      message.role,
      message.content,
      message.parent_message_id || null
    ) as Message;
  }

  getSessionMessages(sessionId: string): Message[] {
    const stmt = this.db.prepare(`
      SELECT * FROM messages 
      WHERE session_id = ? 
      ORDER BY timestamp ASC
    `);
    
    return stmt.all(sessionId) as Message[];
  }

  // Tool invocation methods
  addToolInvocation(invocation: Omit<ToolInvocation, 'created_at'>): ToolInvocation {
    const stmt = this.db.prepare(`
      INSERT INTO tool_invocations (id, message_id, tool_name, input_json, status)
      VALUES (?, ?, ?, ?, ?)
      RETURNING *
    `);
    
    return stmt.get(
      invocation.id,
      invocation.message_id,
      invocation.tool_name,
      invocation.input_json || null,
      invocation.status
    ) as ToolInvocation;
  }

  updateToolInvocation(id: string, updates: Partial<ToolInvocation>): void {
    const fields = Object.keys(updates)
      .filter(key => key !== 'id')
      .map(key => `${key} = ?`);
    
    if (fields.length === 0) return;
    
    const values = Object.values(updates);
    values.push(id);
    
    const stmt = this.db.prepare(`
      UPDATE tool_invocations 
      SET ${fields.join(', ')}
      WHERE id = ?
    `);
    
    stmt.run(...values);
  }

  getMessageTools(messageId: string): ToolInvocation[] {
    const stmt = this.db.prepare(`
      SELECT * FROM tool_invocations 
      WHERE message_id = ? 
      ORDER BY created_at ASC
    `);
    
    return stmt.all(messageId) as ToolInvocation[];
  }

  // Session metadata methods
  updateSessionMetadata(sessionId: string, metadata: Record<string, unknown>): void {
    const stmt = this.db.prepare(`
      INSERT INTO session_metadata (session_id, metadata_json)
      VALUES (?, ?)
      ON CONFLICT(session_id) DO UPDATE SET metadata_json = ?
    `);
    
    const json = JSON.stringify(metadata);
    stmt.run(sessionId, json, json);
  }

  // Cleanup
  close() {
    this.db.close();
  }
}

// Export singleton instance
export const db = new DatabaseService();