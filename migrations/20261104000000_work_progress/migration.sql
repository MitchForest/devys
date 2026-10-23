-- work
-- What an employee shows on a work item while it takes time (its steps) and what it achieved
-- (its results, checked from outside); each is replaced whole.
ALTER TABLE work_items
  ADD COLUMN steps jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_array_length(steps) <= 10),
  ADD COLUMN results jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_array_length(results) <= 12);

-- conversations
-- A card shows its record as it is now, updated in place: one per record and conversation.
ALTER TABLE messages DROP CONSTRAINT messages_kind_check;
ALTER TABLE messages ADD CONSTRAINT messages_kind_check CHECK (kind IN ('message', 'event', 'card'));
