-- conversations
-- C2: a person follows a conversation (a work item's thread) to be told at each milestone and
-- to see it in their sidebar; others hear only when the work is done or needs them.
CREATE TABLE follows (
  business_id text NOT NULL,
  conversation text NOT NULL,
  person_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, conversation, person_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);
