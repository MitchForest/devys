-- conversations
-- Replies an employee offers with a message: the owner sees them under it while it is the latest
-- word, and tapping one sends it as their answer.
ALTER TABLE messages ADD COLUMN replies text[] NOT NULL DEFAULT '{}'
  CHECK (cardinality(replies) <= 4);

-- Replies an employee chose for its next message in a conversation (`suggestReplies`), taken by
-- that message and dropped when the owner speaks there first.
CREATE TABLE suggested_replies (
  business_id text NOT NULL,
  conversation text NOT NULL,
  employee_id text NOT NULL,
  replies text[] NOT NULL CHECK (cardinality(replies) BETWEEN 1 AND 4),
  PRIMARY KEY (business_id, conversation, employee_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);
