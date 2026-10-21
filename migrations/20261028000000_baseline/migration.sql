-- identity
-- Devys business records on Postgres. Each component, or app that keeps its own records,
-- owns the tables under its heading; only it reads or writes them.

CREATE TABLE people (
  id text PRIMARY KEY,
  display_name text NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- A business is the tenant and security boundary. Sharing a person shares nothing else.
CREATE TABLE businesses (
  id text PRIMARY KEY,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  -- How the business appears in every client: null for its initial on a tile.
  look jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- What the business does, in the owner's words.
  brief text NOT NULL DEFAULT '' CHECK (length(brief) <= 4000)
);

CREATE TABLE memberships (
  business_id text NOT NULL REFERENCES businesses(id),
  person_id text NOT NULL REFERENCES people(id),
  role text NOT NULL CHECK (role = 'owner'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, person_id)
);

-- Employees are agent principals. Each belongs to exactly one business.
CREATE TABLE employees (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  -- What the employee is accountable for.
  responsibilities text NOT NULL CHECK (length(responsibilities) BETWEEN 1 AND 2000),
  -- How the employee appears in every client: null for its default Face.
  look jsonb,
  -- A paused employee takes no actions until resumed; its records stay.
  paused_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- The model it runs on, chosen when it is set up (an id from config/models.ts).
  model text NOT NULL CONSTRAINT employees_model_length CHECK (length(model) BETWEEN 1 AND 120),
  -- Its role: the template it was hired from.
  template text NOT NULL DEFAULT 'custom'
    CHECK (template IN ('operations', 'engineering', 'growth', 'business-operations', 'custom')),
  UNIQUE (business_id, id)
);

-- A chat on a channel (iMessage today) reaches one employee of one business, for one member.
-- chat_id is the channel's own address, without the `<channel>:` prefix.
CREATE TABLE channel_bindings (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  employee_id text NOT NULL,
  person_id text NOT NULL,
  channel text NOT NULL CHECK (channel ~ '^[a-z][a-z0-9-]{0,31}$'),
  sender_id text NOT NULL,
  chat_id text NOT NULL,
  revoked_at timestamptz,
  UNIQUE (channel, sender_id, chat_id),
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id),
  FOREIGN KEY (business_id, person_id) REFERENCES memberships(business_id, person_id)
);

CREATE TABLE enrollment_tokens (
  token_hash text PRIMARY KEY,
  person_id text NOT NULL REFERENCES people(id),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);

-- A signed-in device, with a label the person can recognise.
CREATE TABLE web_sessions (
  token_hash text PRIMARY KEY,
  person_id text NOT NULL REFERENCES people(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  label text CHECK (length(label) <= 80)
);

-- work
-- A project is a bounded initiative with an optional goal, deadline and budget, a lead and
-- assigned employees.
CREATE TABLE projects (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  goal text CHECK (length(goal) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  lead_employee_id text,
  deadline date,
  budget_cents bigint CHECK (budget_cents >= 0),
  budget_currency text CHECK (budget_currency ~ '^[A-Z]{3}$'),
  UNIQUE (business_id, id),
  CONSTRAINT projects_budget_check CHECK ((budget_cents IS NULL) = (budget_currency IS NULL)),
  CONSTRAINT projects_lead_fkey
    FOREIGN KEY (business_id, lead_employee_id) REFERENCES employees(business_id, id)
);

-- The employees assigned to a project. The lead answers in its channel whether or not listed.
CREATE TABLE project_members (
  business_id text NOT NULL,
  project_id text NOT NULL,
  employee_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, project_id, employee_id),
  FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id) ON DELETE CASCADE,
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id)
);

-- An artifact or a file of the business folder a project shows, by its Ref, once. The project
-- references it without copying it.
CREATE TABLE project_items (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  project_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  ref text NOT NULL
    CHECK (ref ~ '^devys:documents/(artifact|file)/[^/]+$' AND length(ref) <= 2048),
  UNIQUE (project_id, ref),
  FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id) ON DELETE CASCADE
);

-- A work item is what is owed: an accountable employee, the next action, and evidence when
-- done. It belongs to at most one project.
CREATE TABLE work_items (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  owner_employee_id text NOT NULL,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  objective text NOT NULL DEFAULT '' CHECK (length(objective) <= 4000),
  next_action text NOT NULL DEFAULT '' CHECK (length(next_action) <= 1000),
  wait_condition text CHECK (length(wait_condition) <= 1000),
  due_at timestamptz,
  state text NOT NULL DEFAULT 'ready'
    CHECK (state IN ('proposed', 'ready', 'in_progress', 'waiting', 'needs_decision', 'completed', 'cancelled')),
  -- Values for capabilities' own constraint fields, by capability name. They only narrow.
  conditions jsonb NOT NULL DEFAULT '{}',
  -- Read by clients as stored: snake_case fields, `at` in the API's timestamp form.
  evidence jsonb NOT NULL DEFAULT '[]',
  revision integer NOT NULL DEFAULT 1,
  -- The revision last handed to the employee's runtime; due work has a newer one.
  submitted_revision integer,
  taken_over_by text,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  project_id text,
  UNIQUE (business_id, id),
  CONSTRAINT work_items_owner_fkey
    FOREIGN KEY (business_id, owner_employee_id) REFERENCES employees(business_id, id),
  CONSTRAINT work_items_project_fkey
    FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id)
);
CREATE INDEX work_items_business ON work_items (business_id, updated_at DESC);
CREATE INDEX work_items_due ON work_items (state, due_at) WHERE state = 'ready';
CREATE INDEX work_items_by_project ON work_items (business_id, project_id)
  WHERE project_id IS NOT NULL;

-- authority
-- An employee's standing permission for one capability. Immutable: a change revokes
-- the active row and inserts a new one, so a grant id is a revision decisions can bind.
CREATE TABLE grants (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  employee_id text NOT NULL,
  capability text NOT NULL CHECK (length(capability) BETWEEN 1 AND 100),
  mode text NOT NULL CHECK (mode IN ('auto', 'ask')),
  constraints jsonb NOT NULL DEFAULT '{}',
  responsibility text,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CONSTRAINT grants_employee_fkey
    FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id)
);
CREATE UNIQUE INDEX grants_active ON grants (business_id, employee_id, capability)
  WHERE revoked_at IS NULL;

-- A one-off approval of one exact request. It binds the grant (its revision), the
-- capability and a hash of the exact input; it is used once and expires to rejected.
CREATE TABLE decisions (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  employee_id text NOT NULL,
  grant_id text NOT NULL REFERENCES grants(id),
  capability text NOT NULL,
  input jsonb NOT NULL,
  input_hash text NOT NULL,
  work_item_id text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'used')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  decided_by text,
  decided_at timestamptz,
  used_at timestamptz,
  -- The conversation the asking turn was answering, so the owner's answer is posted there and
  -- wakes the employee instead of waiting for something else to retry.
  conversation text
    CHECK (conversation IS NULL OR conversation ~ '^(direct|project|work):[A-Za-z0-9-]{1,64}$'),
  CONSTRAINT decisions_employee_fkey
    FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id),
  CONSTRAINT decisions_work_item_fkey
    FOREIGN KEY (business_id, work_item_id) REFERENCES work_items(business_id, id)
);
-- One open request per exact input under one grant.
CREATE UNIQUE INDEX decisions_open ON decisions (grant_id, input_hash)
  WHERE status IN ('pending', 'approved');
CREATE INDEX decisions_business ON decisions (business_id, status, requested_at DESC);

-- conversations
-- The shared record of what was said: a direct chat with an employee, a project's channel, or
-- a work item's thread. Pi keeps each employee's own reasoning; this is what everyone in it reads.
CREATE TABLE conversations (
  business_id text NOT NULL REFERENCES businesses(id),
  -- direct:<employee>, project:<project> or work:<work item>
  key text NOT NULL CHECK (key ~ '^(direct|project|work):[A-Za-z0-9-]{1,64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, key)
);

CREATE TABLE messages (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  conversation text NOT NULL,
  -- person:<id>, employee:<id> or system
  author text NOT NULL CHECK (author ~ '^(person|employee):[A-Za-z0-9-]{1,64}$' OR author = 'system'),
  kind text NOT NULL DEFAULT 'message' CHECK (kind IN ('message', 'event')),
  text text NOT NULL CHECK (length(text) BETWEEN 1 AND 64000),
  reply_to text REFERENCES messages(id),
  -- Employee ids this message addresses.
  mentions text[] NOT NULL DEFAULT '{}',
  via_voice boolean NOT NULL DEFAULT false,
  -- What an event is about, as a Ref: devys:<app>/<kind>/<id>.
  ref text CHECK (ref ~ '^devys:[a-z]+/[a-z]+/[^/]+$' AND length(ref) <= 2048),
  -- The sender's own id for this message, so a retried post is stored once.
  client_id text NOT NULL,
  -- Insertion order, which breaks ties between messages stored in the same millisecond.
  seq bigint GENERATED ALWAYS AS IDENTITY,
  -- Milliseconds, the precision clients see.
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  CONSTRAINT messages_client_id_key UNIQUE (business_id, conversation, client_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);
CREATE INDEX messages_by_conversation ON messages (business_id, conversation, created_at, seq);

-- How far each participant has read (people) or been shown (employees): the last message's
-- insertion order, so two messages stored in the same millisecond are never skipped.
CREATE TABLE conversation_reads (
  business_id text NOT NULL,
  conversation text NOT NULL,
  participant text NOT NULL,
  seen_seq bigint NOT NULL,
  PRIMARY KEY (business_id, conversation, participant),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);

-- A person follows a conversation (a work item's thread) to be told at each milestone and to
-- see it in their sidebar; others hear only when the work is done or needs them.
CREATE TABLE follows (
  business_id text NOT NULL,
  conversation text NOT NULL,
  person_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, conversation, person_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);

-- connections
-- A Google connection belongs to a business; the member who connected it is recorded. The
-- connection keeps only the Google grant.
CREATE TABLE google_oauth_states (
  state_hash text PRIMARY KEY,
  business_id text NOT NULL UNIQUE,
  person_id text NOT NULL,
  session_hash text NOT NULL,
  verifier text NOT NULL,
  expires_at bigint NOT NULL,
  claimed boolean NOT NULL DEFAULT false
);

CREATE TABLE google_connections (
  business_id text PRIMARY KEY,
  id text NOT NULL UNIQUE,
  refresh_token text NOT NULL,
  connected_by text NOT NULL,
  connected_at timestamptz NOT NULL DEFAULT now()
);

-- documents
-- A file an employee produced; its bytes are in R2 under object_key.
CREATE TABLE artifacts (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  operation_id text NOT NULL,
  object_key text NOT NULL UNIQUE,
  filename text NOT NULL,
  content_type text NOT NULL,
  byte_length integer NOT NULL CHECK (byte_length >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_id, operation_id)
);
CREATE INDEX artifacts_business_created ON artifacts (business_id, created_at DESC);

-- A file the owner chose in the Drive picker, or one Devys wrote. Disconnecting removes it.
CREATE TABLE drive_files (
  business_id text NOT NULL,
  connection_id text NOT NULL,
  file_id text NOT NULL,
  name text NOT NULL,
  mime_type text NOT NULL,
  PRIMARY KEY (business_id, file_id),
  CONSTRAINT drive_files_connection_id_fkey1
    FOREIGN KEY (connection_id) REFERENCES google_connections(id) ON DELETE CASCADE
);

-- A Drive write's receipt: its input, the file it targets and whether it is known to have landed.
CREATE TABLE drive_operations (
  business_id text NOT NULL,
  operation_id text NOT NULL,
  connection_id text NOT NULL,
  input_hash text NOT NULL,
  file_id text NOT NULL,
  status text NOT NULL
    CONSTRAINT drive_operations_status_check1 CHECK (status IN ('prepared', 'uncertain', 'completed')),
  PRIMARY KEY (business_id, operation_id)
);

-- code
-- A coding session is a native Codex or Claude Code session in its own worktree, serving
-- one work item. The provider owns the session and its transcript; this is the reference to
-- it. The row is written before the host starts the session, then completed with where it runs.
CREATE TABLE coding_sessions (
  id text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9-]{1,64}$'),
  business_id text NOT NULL REFERENCES businesses(id),
  work_item_id text NOT NULL,
  employee_id text NOT NULL,
  provider text NOT NULL CHECK (provider IN ('codex', 'claude')),
  purpose text NOT NULL CHECK (purpose IN ('build', 'review')),
  objective text NOT NULL CHECK (length(objective) BETWEEN 1 AND 8000),
  reviews text REFERENCES coding_sessions(id),
  repository text CHECK (length(repository) <= 1024),
  base_commit text CHECK (base_commit ~ '^[0-9a-f]{40}$'),
  branch text CHECK (length(branch) <= 200),
  worktree text CHECK (length(worktree) <= 1024),
  -- The provider's own session (Codex thread, Claude Code session).
  provider_session_id text CHECK (length(provider_session_id) <= 200),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT coding_sessions_work_item_fkey
    FOREIGN KEY (business_id, work_item_id) REFERENCES work_items(business_id, id),
  CONSTRAINT coding_sessions_employee_fkey
    FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id)
);
CREATE INDEX coding_sessions_by_work_item ON coding_sessions (business_id, work_item_id, created_at);

-- apps
-- The apps each business has installed from the directory, and whether the owner keeps them
-- in the sidebar.
CREATE TABLE app_installs (
  business_id text NOT NULL REFERENCES businesses(id),
  app_id text NOT NULL CHECK (app_id ~ '^[a-z][a-z0-9-]{0,39}$'),
  pinned boolean NOT NULL DEFAULT true,
  installed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, app_id)
);

-- memory
-- A scope is a business today; memory private to one principal can add scopes later.
CREATE TABLE memories (
  scope_id text NOT NULL,
  key text NOT NULL,
  content text NOT NULL,
  source_operation_id text NOT NULL,
  source_kind text NOT NULL CHECK (source_kind IN ('user', 'inference')),
  revision integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- A claim's validity (valid_from, valid_until) and its evidence (each with observed_at).
  details jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (scope_id, key)
);

CREATE TABLE memory_state (
  scope_id text PRIMARY KEY,
  revision integer NOT NULL DEFAULT 0,
  cursor bigint NOT NULL DEFAULT 0,
  excluded_before timestamptz
);

CREATE TABLE memory_sources (
  scope_id text NOT NULL,
  id text NOT NULL,
  observed_at timestamptz NOT NULL,
  kind text NOT NULL CHECK (kind IN ('owner', 'external')),
  content text,
  processed boolean NOT NULL DEFAULT false,
  excluded boolean NOT NULL DEFAULT false,
  PRIMARY KEY (scope_id, id)
);
CREATE INDEX memory_pending ON memory_sources (scope_id, processed, excluded);

CREATE TABLE memory_exclusions (
  scope_id text NOT NULL,
  key text NOT NULL,
  PRIMARY KEY (scope_id, key)
);

CREATE TABLE memory_operations (
  scope_id text NOT NULL,
  id text NOT NULL,
  fingerprint text NOT NULL,
  PRIMARY KEY (scope_id, id)
);

-- Supporting source links survive a claim's correction.
CREATE TABLE memory_links (
  scope_id text NOT NULL,
  key text NOT NULL,
  source_id text NOT NULL,
  evidence jsonb NOT NULL,
  PRIMARY KEY (scope_id, key, source_id)
);
CREATE INDEX memory_links_source ON memory_links (scope_id, source_id);

-- channels
-- Tapbacks on an employee's messages, read as context on the owner's next message.
CREATE TABLE app_reactions (
  business_id text NOT NULL,
  employee_id text NOT NULL,
  target_id text NOT NULL,
  emoji text NOT NULL,
  target_text text NOT NULL,
  consumed_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, employee_id, target_id, emoji)
);
