-- authority
-- The conversation an asking turn was answering, so the owner's answer is posted there and
-- wakes the employee instead of waiting for something else to retry.
ALTER TABLE decisions ADD COLUMN conversation text
  CHECK (conversation IS NULL OR conversation ~ '^(direct|space|work):[A-Za-z0-9-]{1,64}$');
