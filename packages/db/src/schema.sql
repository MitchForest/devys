-- devys Database Schema
-- SQLite database for session persistence and chat history

-- Sessions table - stores Claude Code session information
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  claude_session_id TEXT, -- Claude Code's internal session ID
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT DEFAULT 'active', -- active, completed, error
  project_path TEXT,
  model TEXT DEFAULT 'sonnet',
  permission_mode TEXT DEFAULT 'default'
);

-- Messages table - stores chat messages
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL, -- user, assistant, system, tool
  content TEXT,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  parent_message_id TEXT,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- Tool invocations table - stores tool calls and results
CREATE TABLE IF NOT EXISTS tool_invocations (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  input_json TEXT, -- JSON string of tool input
  output_json TEXT, -- JSON string of tool output
  status TEXT DEFAULT 'pending', -- pending, approved, rejected, completed, error
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- Session metadata - stores additional context
CREATE TABLE IF NOT EXISTS session_metadata (
  session_id TEXT PRIMARY KEY,
  files_modified INTEGER DEFAULT 0,
  tools_used INTEGER DEFAULT 0,
  total_tokens_used INTEGER DEFAULT 0,
  total_cost_usd REAL DEFAULT 0,
  metadata_json TEXT, -- Additional metadata as JSON
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_tool_invocations_message_id ON tool_invocations(message_id);
CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at);

-- Trigger to update session updated_at timestamp
CREATE TRIGGER IF NOT EXISTS update_session_timestamp 
AFTER INSERT ON messages
BEGIN
  UPDATE sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.session_id;
END;