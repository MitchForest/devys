-- conversations
-- An employee's reply says how it was worked out (2026-10-23): how long its turn took and how
-- many steps it shows. The steps themselves stay in the employee's Pi record.
ALTER TABLE messages ADD COLUMN worked jsonb CHECK (
  worked IS NULL OR (
    jsonb_typeof(worked -> 'ms') = 'number' AND jsonb_typeof(worked -> 'steps') = 'number'
    AND worked - 'ms' - 'steps' = '{}'::jsonb
  )
);
