-- work
-- A woken follow-up is said so when its work is handed back: the time it came due, kept
-- until the work next changes.
ALTER TABLE work_items ADD COLUMN woken_at timestamptz;
