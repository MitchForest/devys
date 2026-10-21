-- authority
-- A request's kind: `decision` answers a modelled capability held in `ask` mode; `approve` and
-- `take_over` are an employee's `askOwner`, whose exact request is `input`. An approve with an
-- amount is a spend approval: it is approved only with a signature by one of the owner's device
-- keys over its canonical payload, kept here with the key that made it. A take-over request is
-- approved when the owner takes the work over and used when they hand it back.
ALTER TABLE decisions ADD COLUMN kind text NOT NULL DEFAULT 'decision'
  CHECK (kind IN ('decision', 'approve', 'take_over'));
ALTER TABLE decisions ADD COLUMN signature text;
ALTER TABLE decisions ADD COLUMN signed_by text;
ALTER TABLE decisions ADD CONSTRAINT decisions_spend_signed CHECK (
  kind <> 'approve' OR input -> 'amount' IS NULL OR status NOT IN ('approved', 'used')
    OR (signature IS NOT NULL AND signed_by IS NOT NULL)
);
ALTER TABLE decisions ADD CONSTRAINT decisions_asked_in_thread CHECK (
  kind = 'decision' OR work_item_id IS NOT NULL
);

-- A person's device signing key: a Secure Enclave P-256 public key (X9.63, base64) of one of
-- their signed-in Mac or iPhone apps (`device`, the session's id). The first key a person
-- enrolls is active at once; a later one is pending until an active key signs it. A device that
-- signs in again with its key keeps it. Revoked keys stay for the approvals they signed.
CREATE TABLE device_keys (
  id text PRIMARY KEY,
  person_id text NOT NULL REFERENCES people(id),
  device text NOT NULL CHECK (device ~ '^[a-f0-9]{16}$'),
  label text CHECK (length(label) <= 80),
  public_key text NOT NULL CHECK (length(public_key) BETWEEN 80 AND 100),
  status text NOT NULL CHECK (status IN ('pending', 'active')),
  endorsed_by text REFERENCES device_keys(id),
  endorsement text,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE INDEX device_keys_person ON device_keys (person_id) WHERE revoked_at IS NULL;
-- A key belongs to one device at a time; a revoked one may be enrolled again, as a new key.
CREATE UNIQUE INDEX device_keys_current ON device_keys (public_key) WHERE revoked_at IS NULL;
ALTER TABLE decisions ADD CONSTRAINT decisions_signed_by_fkey
  FOREIGN KEY (signed_by) REFERENCES device_keys(id);
