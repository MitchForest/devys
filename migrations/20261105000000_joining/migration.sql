-- identity
-- A device asking to join from the sign-in screen ("Connect to <Mac>"). It chose its own session
-- token and sends only its hash: allowing the request makes that hash a session of the person who
-- allowed it, so the token never exists on the server. A request lives two minutes.
CREATE TABLE join_requests (
  id text PRIMARY KEY,
  session_hash text NOT NULL UNIQUE CHECK (session_hash ~ '^[a-f0-9]{64}$'),
  -- What the device calls itself ("Mitch's iPhone", "Safari on Mac").
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  -- The app's signing key, enrolled for the device when it is allowed; browsers have none.
  public_key text CHECK (length(public_key) BETWEEN 80 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  answered_at timestamptz,
  -- Set when allowed; answered without it is denied.
  allowed_by text REFERENCES people(id)
);

-- One-time codes are gone; what remains is a one-time link that signs a browser in, valid ten
-- minutes (made by the Mac app, or by `bun run local install` before the Mac app is built).
ALTER TABLE enrollment_tokens RENAME TO sign_in_links;
