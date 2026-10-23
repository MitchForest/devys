-- conversations
-- How each person keeps a conversation in their sidebar (G1, 2026-10-23): pinned to the top,
-- hidden until something new is said, or marked unread until they next read it.
CREATE TABLE conversation_marks (
  business_id text NOT NULL,
  conversation text NOT NULL,
  person_id text NOT NULL,
  pinned_at timestamptz,
  hidden_at timestamptz,
  marked_unread boolean NOT NULL DEFAULT false,
  PRIMARY KEY (business_id, conversation, person_id),
  FOREIGN KEY (business_id, conversation) REFERENCES conversations(business_id, key)
);

-- Every member starts with the Chief of Staff pinned.
INSERT INTO conversations (business_id, key)
SELECT e.business_id, 'direct:' || e.id FROM employees e
WHERE e.template = 'chief-of-staff' AND e.revoked_at IS NULL
ON CONFLICT DO NOTHING;
INSERT INTO conversation_marks (business_id, conversation, person_id, pinned_at)
SELECT e.business_id, 'direct:' || e.id, m.person_id, now()
FROM employees e JOIN memberships m ON m.business_id = e.business_id
WHERE e.template = 'chief-of-staff' AND e.revoked_at IS NULL
ON CONFLICT DO NOTHING;
