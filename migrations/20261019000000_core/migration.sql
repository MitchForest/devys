-- Devys application records on Postgres. A clean start: nothing is migrated from D1.
-- Each component owns the tables under its heading; only it reads or writes them.

-- identity
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
  created_at timestamptz NOT NULL DEFAULT now()
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
  role text NOT NULL CHECK (length(role) BETWEEN 1 AND 200),
  -- How the employee appears in every client: null for its default Face.
  look jsonb,
  -- A paused employee takes no actions until resumed; its records stay.
  paused_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
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

CREATE TABLE web_sessions (
  token_hash text PRIMARY KEY,
  person_id text NOT NULL REFERENCES people(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

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
  revoked_at timestamptz
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
  commitment_id text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'used')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  decided_by text,
  decided_at timestamptz,
  used_at timestamptz
);
-- One open request per exact input under one grant.
CREATE UNIQUE INDEX decisions_open ON decisions (grant_id, input_hash)
  WHERE status IN ('pending', 'approved');
CREATE INDEX decisions_business ON decisions (business_id, status, requested_at DESC);

-- work
-- What is owed: an accountable employee, the next action, and evidence when done.
CREATE TABLE commitments (
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
  evidence jsonb NOT NULL DEFAULT '[]',
  revision integer NOT NULL DEFAULT 1,
  -- The revision last handed to the employee's runtime; due work has a newer one.
  submitted_revision integer,
  taken_over_by text,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX commitments_business ON commitments (business_id, updated_at DESC);
CREATE INDEX commitments_due ON commitments (state, due_at) WHERE state = 'ready';

-- A persistent place for an area of the business. It references records; it owns none.
CREATE TABLE spaces (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  purpose text NOT NULL DEFAULT '' CHECK (length(purpose) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_id, id)
);

-- A record shown in a space. The same record can appear in several spaces.
CREATE TABLE space_items (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  space_id text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('commitment', 'artifact')),
  ref text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (space_id, kind, ref),
  FOREIGN KEY (business_id, space_id) REFERENCES spaces(business_id, id) ON DELETE CASCADE
);

-- artifacts
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

-- connections
-- A Google connection belongs to a business; the member who connected it is recorded.
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

CREATE TABLE drive_files (
  business_id text NOT NULL,
  connection_id text NOT NULL REFERENCES google_connections(id) ON DELETE CASCADE,
  file_id text NOT NULL,
  name text NOT NULL,
  mime_type text NOT NULL,
  PRIMARY KEY (business_id, file_id)
);

CREATE TABLE drive_operations (
  business_id text NOT NULL,
  operation_id text NOT NULL,
  connection_id text NOT NULL,
  input_hash text NOT NULL,
  file_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('prepared', 'uncertain', 'completed')),
  PRIMARY KEY (business_id, operation_id)
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
