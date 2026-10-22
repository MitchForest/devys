-- apps
-- A remote app a business added (LP6): an MCP server behind its own sign-in. `state` is where it
-- stands: `connecting` (added, not signed in), `review` (signed in, its tools listed, waiting for
-- the owner's Turn on), `on` (the owner's acceptance is its policy) or `lapsed` (its sign-in no
-- longer works; the owner reconnects). `tools` is what the server lists (descriptive only);
-- `policy` is the owner's: each tool's line (`own`, `ask` or `never`) and who may use it. Its
-- tokens are the vault's connection secret `app-<id>`. `logo` is the sha-256 of its logo's bytes
-- in R2 (`apps/<business>/<sha>`).
CREATE TABLE remote_apps (
  business_id text NOT NULL REFERENCES businesses(id),
  id text NOT NULL CHECK (id ~ '^[a-z][a-z0-9]{0,29}$'),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  summary text NOT NULL DEFAULT '' CHECK (length(summary) <= 500),
  url text NOT NULL CHECK (length(url) <= 2000),
  registry_name text CHECK (length(registry_name) <= 200),
  website text CHECK (length(website) <= 500),
  logo text CHECK (logo ~ '^[a-f0-9]{64}$'),
  state text NOT NULL DEFAULT 'connecting'
    CHECK (state IN ('connecting', 'review', 'on', 'lapsed')),
  tools jsonb NOT NULL DEFAULT '[]',
  policy jsonb,
  pinned boolean NOT NULL DEFAULT true,
  added_by text NOT NULL,
  added_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  PRIMARY KEY (business_id, id),
  UNIQUE (business_id, url)
);

-- A sign-in in progress: the state's hash, the PKCE verifier, the registered client and the
-- discovery, for ten minutes and one use. The verifier is useless without the code only the
-- callback receives.
CREATE TABLE app_sign_ins (
  state_hash text PRIMARY KEY,
  business_id text NOT NULL,
  app_id text NOT NULL,
  person_id text NOT NULL,
  pending jsonb NOT NULL,
  native boolean NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL,
  FOREIGN KEY (business_id, app_id) REFERENCES remote_apps(business_id, id) ON DELETE CASCADE
);

-- authority
-- `askOwner` gains the connect kind: answered when the owner turns the app on.
ALTER TABLE decisions DROP CONSTRAINT decisions_kind_check;
ALTER TABLE decisions ADD CONSTRAINT decisions_kind_check
  CHECK (kind IN ('decision', 'approve', 'take_over', 'secret', 'connect'));
-- The Team app's new core capability, held by every employee.
INSERT INTO grants (id, business_id, employee_id, capability, mode, constraints, responsibility)
SELECT gen_random_uuid()::text, business_id, employee_id, 'appSearch', 'auto', '{}', responsibility
FROM grants WHERE capability = 'askOwner' AND revoked_at IS NULL;
