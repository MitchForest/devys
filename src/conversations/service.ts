import { database, type Database } from "../data/database.ts";
import type { ConversationKey, Message } from "./contract.ts";

const columns =
  "id, conversation, author, kind, text, reply_to, mentions, via_voice, ref, created_at";

/**
 * Adds a message, creating the conversation on first use. A retried post with the same
 * client id returns the stored message and `created: false`.
 */
export const postMessage = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  input: {
    author: string;
    text: string;
    clientId: string;
    replyTo?: string | null;
    mentions?: string[];
    viaVoice?: boolean;
    kind?: "message" | "event";
    ref?: string | null;
  },
) =>
  database(
    db,
    async (sql) => {
      await sql.run(
        "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        [businessId, key],
      );
      // A reply must point at a message of the same conversation.
      const replyTo = input.replyTo
        ? ((
            await sql.row<{ id: string }>(
              "SELECT id FROM messages WHERE business_id = $1 AND conversation = $2 AND id = $3",
              [businessId, key, input.replyTo],
            )
          )?.id ?? null)
        : null;
      const inserted = await sql.row<Message>(
        `INSERT INTO messages
           (id, business_id, conversation, author, kind, text, reply_to, mentions, via_voice, ref, client_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (business_id, client_id) DO NOTHING
         RETURNING ${columns}`,
        [
          crypto.randomUUID(),
          businessId,
          key,
          input.author,
          input.kind ?? "message",
          input.text,
          replyTo,
          input.mentions ?? [],
          input.viaVoice ?? false,
          input.ref ?? null,
          input.clientId,
        ],
      );
      if (inserted) return { message: inserted, created: true };
      const existing = await sql.row<Message>(
        `SELECT ${columns} FROM messages WHERE business_id = $1 AND client_id = $2`,
        [businessId, input.clientId],
      );
      return { message: existing!, created: false };
    },
    { transaction: true },
  );

/** A page of a conversation, oldest first, ending before `before` (a message id). */
export const messages = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  page: { before?: string; limit?: number } = {},
) =>
  database(db, async (sql) =>
    (
      await sql.rows<Message>(
        `SELECT ${columns} FROM messages
         WHERE business_id = $1 AND conversation = $2
           AND ($3::text IS NULL OR (created_at, seq) < (SELECT created_at, seq FROM messages WHERE id = $3))
         ORDER BY created_at DESC, seq DESC LIMIT $4`,
        [businessId, key, page.before ?? null, page.limit ?? 50],
      )
    ).reverse(),
  );

/** Messages after a moment (exclusive), oldest first, at most `limit`, the newest kept. */
export const messagesSince = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  since: string | null,
  limit: number,
) =>
  database(db, async (sql) =>
    (
      await sql.rows<Message>(
        `SELECT ${columns} FROM messages
         WHERE business_id = $1 AND conversation = $2 AND ($3::timestamptz IS NULL OR created_at > $3)
         ORDER BY created_at DESC, seq DESC LIMIT $4`,
        [businessId, key, since, limit],
      )
    ).reverse(),
  );

/** When a participant (`person:<id>` or `employee:<id>`) last read or was shown this. */
export const seenAt = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  participant: string,
) =>
  database(
    db,
    async (sql) =>
      (
        await sql.row<{ seen_at: string }>(
          `SELECT seen_at FROM conversation_reads
           WHERE business_id = $1 AND conversation = $2 AND participant = $3`,
          [businessId, key, participant],
        )
      )?.seen_at ?? null,
  );

/** Moves a participant's read position forward; it never moves back. */
export const markSeen = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  participant: string,
  at: string,
) =>
  database(db, async (sql) => {
    await sql.run(
      "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
      [businessId, key],
    );
    await sql.run(
      `INSERT INTO conversation_reads (business_id, conversation, participant, seen_at)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (business_id, conversation, participant)
       DO UPDATE SET seen_at = greatest(conversation_reads.seen_at, excluded.seen_at)`,
      [businessId, key, participant, at],
    );
  });

/** Every conversation of the business with its latest message and this person's unread count. */
export const conversationSummaries = (db: Database, businessId: string, personId: string) =>
  database(db, (sql) =>
    sql.rows<{ key: ConversationKey; last: Message | null; unread: number }>(
      `SELECT c.key,
         (SELECT to_jsonb(m) - 'business_id' - 'client_id' - 'seq' FROM messages m
          WHERE m.business_id = c.business_id AND m.conversation = c.key
          ORDER BY m.created_at DESC, m.seq DESC LIMIT 1) AS last,
         (SELECT count(*)::int FROM messages m
          WHERE m.business_id = c.business_id AND m.conversation = c.key
            AND m.author <> 'person:' || $2
            AND m.created_at > coalesce((SELECT r.seen_at FROM conversation_reads r
              WHERE r.business_id = c.business_id AND r.conversation = c.key
                AND r.participant = 'person:' || $2), '-infinity')) AS unread
       FROM conversations c WHERE c.business_id = $1`,
      [businessId, personId],
    ),
  );

/** Every message of the business in the order it was stored, 100 at a time, after `afterSeq`. */
export const exportMessages = (db: Database, businessId: string, afterSeq: string) =>
  database(db, (sql) =>
    sql.rows<Message & { seq: string }>(
      `SELECT ${columns}, seq::text AS seq FROM messages
       WHERE business_id = $1 AND seq > $2::bigint ORDER BY seq LIMIT 100`,
      [businessId, afterSeq],
    ),
  );
