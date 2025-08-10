-- control-plane/db/schema.sql
-- Phase 1: Database schema for session management

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    workspace TEXT NOT NULL,
    context TEXT NOT NULL, -- JSON
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_activity INTEGER
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_workspace ON sessions(workspace);

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    type TEXT NOT NULL,
    data TEXT, -- JSON
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX idx_events_session_id ON events(session_id);
CREATE INDEX idx_events_timestamp ON events(timestamp);

CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    metric TEXT NOT NULL,
    value REAL NOT NULL,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX idx_metrics_session_id ON metrics(session_id);
CREATE INDEX idx_metrics_metric ON metrics(metric);

CREATE TABLE IF NOT EXISTS context_cache (
    workspace TEXT PRIMARY KEY,
    code_map TEXT NOT NULL, -- JSON
    generated_at INTEGER NOT NULL,
    file_count INTEGER NOT NULL,
    symbol_count INTEGER NOT NULL
);