-- code
-- C1: a coding assignment is a native Codex or Claude Code session in its own worktree,
-- serving one work item. The provider owns the session and its transcript; this is the
-- reference to it. The row is written before the host starts the session, then completed
-- with where it runs.
CREATE TABLE assignments (
  id text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9-]{1,64}$'),
  business_id text NOT NULL REFERENCES businesses(id),
  commitment_id text NOT NULL REFERENCES commitments(id),
  employee_id text NOT NULL REFERENCES employees(id),
  provider text NOT NULL CHECK (provider IN ('codex', 'claude')),
  purpose text NOT NULL CHECK (purpose IN ('build', 'review')),
  objective text NOT NULL CHECK (length(objective) BETWEEN 1 AND 8000),
  reviews text REFERENCES assignments(id),
  repository text CHECK (length(repository) <= 1024),
  base_commit text CHECK (base_commit ~ '^[0-9a-f]{40}$'),
  branch text CHECK (length(branch) <= 200),
  worktree text CHECK (length(worktree) <= 1024),
  session_id text CHECK (length(session_id) <= 200),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX assignments_by_commitment ON assignments (business_id, commitment_id, created_at);
