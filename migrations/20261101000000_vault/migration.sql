-- vault
-- A business's secret by name: its value encrypted under its own data key, the data key wrapped
-- by the master key only the Mac host holds (both base64, bound to business, name and kind). The
-- Worker keeps ciphertext only. `spend` is a card, filled only against a signed spend approval;
-- `connection` is an app connection's credential, named in lowercase apart from the owner's.
CREATE TABLE secrets (
  business_id text NOT NULL REFERENCES businesses(id),
  name text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('secret', 'spend', 'connection')),
  data_key text NOT NULL,
  ciphertext text NOT NULL CHECK (length(ciphertext) <= 32000),
  added_by text NOT NULL,
  added_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  PRIMARY KEY (business_id, name),
  CONSTRAINT secrets_name_check CHECK (
    (kind = 'connection' AND name ~ '^[a-z][a-z0-9_-]{0,63}$')
    OR (kind <> 'connection' AND name ~ '^[A-Z][A-Z0-9_]{0,63}$')
  )
);

-- connections
-- Google's refresh token moves to the vault (the secret named `google`), and the connection key
-- in `.env` is gone: tokens sealed under it can't be opened, so connections made before are
-- removed and the owner connects Google again. The PKCE verifier lives ten minutes and is
-- useless without the authorization code, so it is kept as is.
DELETE FROM google_oauth_states;
DELETE FROM google_connections;
ALTER TABLE google_connections DROP COLUMN refresh_token;

-- authority
-- `askOwner` gains the secret kind: answered when the owner adds the named secret.
ALTER TABLE decisions DROP CONSTRAINT decisions_kind_check;
ALTER TABLE decisions ADD CONSTRAINT decisions_kind_check
  CHECK (kind IN ('decision', 'approve', 'take_over', 'secret'));
-- The Browser app's new capability, granted wherever the browser is.
INSERT INTO grants (id, business_id, employee_id, capability, mode, constraints, responsibility)
SELECT gen_random_uuid()::text, business_id, employee_id, 'browserFill', 'auto', '{}', responsibility
FROM grants WHERE capability = 'browserScript' AND revoked_at IS NULL;
