-- Phase 2: Cache tables for context intelligence

-- Merkle trees by commit
CREATE TABLE IF NOT EXISTS merkle_cache (
  workspace TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  tree_data BLOB NOT NULL,
  root_hash TEXT NOT NULL,
  file_count INTEGER,
  created_at INTEGER,
  PRIMARY KEY (workspace, commit_sha)
);

CREATE INDEX IF NOT EXISTS idx_merkle_root_hash ON merkle_cache(root_hash);

-- Parsed files by content hash
CREATE TABLE IF NOT EXISTS file_cache (
  file_path TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  parsed_ast BLOB,
  symbols TEXT, -- JSON array
  language TEXT,
  parse_time_ms REAL,
  created_at INTEGER,
  PRIMARY KEY (file_path, content_hash)
);

CREATE INDEX IF NOT EXISTS idx_file_cache_language ON file_cache(language);

-- Code maps by workspace state
CREATE TABLE IF NOT EXISTS codemap_cache (
  workspace TEXT NOT NULL,
  state_hash TEXT NOT NULL, -- Hash of all file hashes
  code_map BLOB NOT NULL,
  file_count INTEGER,
  symbol_count INTEGER,
  created_at INTEGER,
  PRIMARY KEY (workspace, state_hash)
);

-- Performance metrics
CREATE TABLE IF NOT EXISTS cache_metrics (
  operation TEXT PRIMARY KEY,
  hit_count INTEGER DEFAULT 0,
  miss_count INTEGER DEFAULT 0,
  avg_time_ms REAL,
  last_updated INTEGER
);

-- Initialize metrics
INSERT OR IGNORE INTO cache_metrics (operation, last_updated) VALUES 
  ('merkle_memory', 0),
  ('merkle_disk', 0),
  ('file_cache', 0),
  ('codemap_cache', 0);