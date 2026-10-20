-- conversations
-- The shared record of what was said: a DM with an employee, a space, or a work item's
-- thread. Pi keeps each employee's own reasoning; this is what everyone in it reads.
CREATE TABLE conversations (
  business_id text NOT NULL REFERENCES businesses(id),
  -- direct:<employee>, space:<space> or work:<commitment>
  key text NOT NULL CHECK (key ~ '^(direct|space|work):[A-Za-z0-9-]{1,64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, key)
);

CREATE TABLE messages (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  conversation text NOT NULL,
  -- person:<id>, employee:<id> or system
  author text NOT NULL CHECK (author ~ '^(person|employee):[A-Za-z0-9-]{1,64}$' OR author = 'system'),
  kind text NOT NULL DEFAULT 'message' CHECK (kind IN ('message', 'event')),
  text text NOT NULL CHECK (length(text) BETWEEN 1 AND 64000),
  reply_to text REFERENCES messages(id),
  -- Employee ids this message addresses.
  mentions text[] NOT NULL DEFAULT '{}',
  via_voice boolean NOT NULL DEFAULT false,
  -- What an event is about (a commitment id for hand-off cards).
  ref text,
  -- The sender's own id for this message, so a retried post is stored once.
  client_id text NOT NULL,
  -- Insertion order, which breaks ties between messages stored in the same millisecond.
  seq bigint GENERATED ALWAYS AS IDENTITY,
  -- Milliseconds, the precision clients see, so a read position can equal a message's time.
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (business_id, client_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);
CREATE INDEX messages_by_conversation ON messages (business_id, conversation, created_at, seq);

-- How far each participant has read (people) or been shown (employees).
CREATE TABLE conversation_reads (
  business_id text NOT NULL,
  conversation text NOT NULL,
  participant text NOT NULL,
  seen_at timestamptz NOT NULL,
  PRIMARY KEY (business_id, conversation, participant),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);
