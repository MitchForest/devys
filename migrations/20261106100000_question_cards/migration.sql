-- conversations
-- Replies become a question card (G4, 2026-10-23): up to six lettered answers of a few words,
-- the question as its title, and whether the owner may pick several (then Done sends them).
ALTER TABLE messages DROP CONSTRAINT messages_replies_check;
ALTER TABLE messages ADD CONSTRAINT messages_replies_check CHECK (cardinality(replies) <= 6);
ALTER TABLE messages ADD COLUMN question text CHECK (length(question) BETWEEN 1 AND 120);
ALTER TABLE messages ADD COLUMN pick_many boolean NOT NULL DEFAULT false;
ALTER TABLE suggested_replies DROP CONSTRAINT suggested_replies_replies_check;
ALTER TABLE suggested_replies ADD CONSTRAINT suggested_replies_replies_check
  CHECK (cardinality(replies) BETWEEN 1 AND 6);
ALTER TABLE suggested_replies ADD COLUMN question text CHECK (length(question) BETWEEN 1 AND 120);
ALTER TABLE suggested_replies ADD COLUMN pick_many boolean NOT NULL DEFAULT false;
