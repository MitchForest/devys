-- conversations
-- R0: read positions are the last message's insertion order, not its time, so two messages
-- stored in the same millisecond are never skipped. Client ids are unique per conversation.
ALTER TABLE conversation_reads ADD COLUMN seen_seq bigint;
UPDATE conversation_reads r SET seen_seq = coalesce(
  (SELECT max(m.seq) FROM messages m
   WHERE m.business_id = r.business_id AND m.conversation = r.conversation AND m.created_at <= r.seen_at),
  0);
ALTER TABLE conversation_reads ALTER COLUMN seen_seq SET NOT NULL;
ALTER TABLE conversation_reads DROP COLUMN seen_at;
ALTER TABLE messages DROP CONSTRAINT messages_business_id_client_id_key;
ALTER TABLE messages ADD CONSTRAINT messages_client_id_key UNIQUE (business_id, conversation, client_id);
