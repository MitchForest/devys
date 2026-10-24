import type { Ref } from "../protocol/ref.ts";
import { database, isoText, type Database } from "../data/database.ts";
import { employeeOf, type ConversationKey, type Message, type Worked } from "./contract.ts";

const columns =
  "id, conversation, author, kind, text, reply_to, mentions, via_voice, ref, replies, question, pick_many, worked, created_at";

/**
 * Adds a message, creating the conversation on first use. A retried post with the same
 * client id returns the stored message and `created: false`. An employee's message takes the
 * replies it chose with `suggestReplies`; a person's drops every pending choice there. An event
 * carries the replies it is posted with (Devys's notice offers "Ask again").
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
    kind?: Message["kind"];
    ref?: Ref | null;
    /** An event's replies to tap. */
    replies?: readonly string[];
    /** An employee's reply: how its turn was worked out. */
    worked?: Worked;
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
      const employee =
        (input.kind ?? "message") === "message" ? employeeOf(input.author) : undefined;
      const card = employee
        ? ((await sql.row<{ replies: string[]; question: string | null; pick_many: boolean }>(
            `SELECT replies, question, pick_many FROM suggested_replies
             WHERE business_id = $1 AND conversation = $2 AND employee_id = $3`,
            [businessId, key, employee],
          )) ?? { replies: [], question: null, pick_many: false })
        : {
            replies: input.kind === "event" ? [...(input.replies ?? [])] : [],
            question: null,
            pick_many: false,
          };
      const inserted = await sql.row<Message>(
        `INSERT INTO messages
           (id, business_id, conversation, author, kind, text, reply_to, mentions, via_voice, ref,
            client_id, replies, question, pick_many, worked)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         ON CONFLICT (business_id, conversation, client_id) DO NOTHING
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
          card.replies,
          card.question,
          card.pick_many,
          input.worked ?? null,
        ],
      );
      if (inserted) {
        if (employee || input.author.startsWith("person:"))
          await sql.run(
            `DELETE FROM suggested_replies WHERE business_id = $1 AND conversation = $2
               AND ($3::text IS NULL OR employee_id = $3)`,
            [businessId, key, employee ?? null],
          );
        return { message: inserted, created: true };
      }
      const existing = await sql.row<Message>(
        `SELECT ${columns} FROM messages
         WHERE business_id = $1 AND conversation = $2 AND client_id = $3`,
        [businessId, key, input.clientId],
      );
      return { message: existing!, created: false };
    },
    { transaction: true },
  );

/**
 * Sets the replies an employee offers with its next message in a conversation, replacing any it
 * chose before.
 */
export const suggestReplies = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  employeeId: string,
  card: { replies: readonly string[]; question?: string; pickMany?: boolean },
) =>
  database(db, async (sql) => {
    await sql.run(
      "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
      [businessId, key],
    );
    await sql.run(
      `INSERT INTO suggested_replies (business_id, conversation, employee_id, replies, question,
         pick_many)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (business_id, conversation, employee_id) DO UPDATE SET replies = excluded.replies,
         question = excluded.question, pick_many = excluded.pick_many`,
      [businessId, key, employeeId, card.replies, card.question ?? null, card.pickMany ?? false],
    );
  });

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

/** One message of a conversation by id, if it is there. */
export const messageIn = (db: Database, businessId: string, key: ConversationKey, id: string) =>
  database(db, (sql) =>
    sql.row<Message>(
      `SELECT ${columns} FROM messages WHERE business_id = $1 AND conversation = $2 AND id = $3`,
      [businessId, key, id],
    ),
  );

/**
 * What a participant had not seen before a message: the latest `limit` messages after its read
 * position and before that message, oldest first. Undefined when its read position is already
 * at or after the message, so the message reached it before.
 */
export const unseenBefore = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  participant: string,
  messageId: string,
  limit: number,
) =>
  database(db, async (sql) => {
    const position = await sql.row<{ seq: string; seen: string }>(
      `SELECT m.seq::text AS seq, coalesce(r.seen_seq, 0)::text AS seen FROM messages m
       LEFT JOIN conversation_reads r ON r.business_id = m.business_id
         AND r.conversation = m.conversation AND r.participant = $3
       WHERE m.business_id = $1 AND m.conversation = $2 AND m.id = $4`,
      [businessId, key, participant, messageId],
    );
    if (!position || BigInt(position.seen) >= BigInt(position.seq)) return undefined;
    return (
      await sql.rows<Message>(
        `SELECT ${columns} FROM messages
         WHERE business_id = $1 AND conversation = $2 AND seq > $3::bigint AND seq < $4::bigint
         ORDER BY seq DESC LIMIT $5`,
        [businessId, key, position.seen, position.seq, limit],
      )
    ).reverse();
  });

/**
 * Moves a participant's read position forward to a message (by id), or to the last message
 * stored at or before a time (`{ at }`, what clients report). It never moves back.
 */
export const markSeen = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  participant: string,
  upTo: { message: string } | { at: string },
) =>
  database(db, async (sql) => {
    await sql.run(
      "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
      [businessId, key],
    );
    const position =
      "message" in upTo
        ? "(SELECT seq FROM messages WHERE business_id = $1 AND conversation = $2 AND id = $4)"
        : `(SELECT max(seq) FROM messages
            WHERE business_id = $1 AND conversation = $2 AND created_at <= $4::timestamptz)`;
    await sql.run(
      `INSERT INTO conversation_reads (business_id, conversation, participant, seen_seq)
       SELECT $1, $2, $3, seq FROM (SELECT ${position} AS seq) found WHERE seq IS NOT NULL
       ON CONFLICT (business_id, conversation, participant)
       DO UPDATE SET seen_seq = greatest(conversation_reads.seen_seq, excluded.seen_seq)`,
      [businessId, key, participant, "message" in upTo ? upTo.message : upTo.at],
    );
    // Reading it clears a person's "mark as unread".
    if (participant.startsWith("person:"))
      await sql.run(
        `UPDATE conversation_marks SET marked_unread = false
         WHERE business_id = $1 AND conversation = $2 AND person_id = $3 AND marked_unread`,
        [businessId, key, participant.slice("person:".length)],
      );
  });

/** When the last message a participant has read was stored; undefined if they have read none. */
export const readAt = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  participant: string,
) =>
  database(
    db,
    async (sql) =>
      (
        await sql.row<{ created_at: string }>(
          `SELECT m.created_at FROM conversation_reads r
         JOIN messages m ON m.business_id = r.business_id AND m.conversation = r.conversation
           AND m.seq = r.seen_seq
         WHERE r.business_id = $1 AND r.conversation = $2 AND r.participant = $3`,
          [businessId, key, participant],
        )
      )?.created_at,
  );

/** Starts or stops a person following a conversation. */
export const setFollowing = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  personId: string,
  on: boolean,
) =>
  database(db, async (sql) => {
    await sql.run(
      "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
      [businessId, key],
    );
    await sql.run(
      on
        ? "INSERT INTO follows (business_id, conversation, person_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
        : "DELETE FROM follows WHERE business_id = $1 AND conversation = $2 AND person_id = $3",
      [businessId, key, personId],
    );
  });

/**
 * How a person keeps a conversation in their sidebar: pinned or not; hidden (until something
 * new is said); marked unread (until they next read it).
 */
export const markConversation = (
  db: Database,
  businessId: string,
  key: ConversationKey,
  personId: string,
  mark: { pinned?: boolean; hidden?: boolean; unread?: boolean },
) =>
  database(db, async (sql) => {
    await sql.run(
      "INSERT INTO conversations (business_id, key) VALUES ($1, $2) ON CONFLICT DO NOTHING",
      [businessId, key],
    );
    await sql.run(
      `INSERT INTO conversation_marks (business_id, conversation, person_id, pinned_at, hidden_at,
         marked_unread)
       VALUES ($1, $2, $3, CASE WHEN $4::boolean THEN now() END, CASE WHEN $5::boolean THEN now() END,
         coalesce($6::boolean, false))
       ON CONFLICT (business_id, conversation, person_id) DO UPDATE SET
         pinned_at = CASE WHEN $4::boolean IS NULL THEN conversation_marks.pinned_at
           WHEN $4 THEN coalesce(conversation_marks.pinned_at, now()) END,
         hidden_at = CASE WHEN $5::boolean IS NULL THEN conversation_marks.hidden_at
           WHEN $5 THEN now() END,
         marked_unread = coalesce($6::boolean, conversation_marks.marked_unread)`,
      [businessId, key, personId, mark.pinned ?? null, mark.hidden ?? null, mark.unread ?? null],
    );
  });

/**
 * Every conversation of the business with its latest message, this person's unread count,
 * whether they follow it, and how they keep it in their sidebar.
 */
export const conversationSummaries = (db: Database, businessId: string, personId: string) =>
  database(db, (sql) =>
    sql.rows<{
      key: ConversationKey;
      last: Message | null;
      unread: number;
      following: boolean;
      pinned: boolean;
      hidden: boolean;
    }>(
      `SELECT c.key,
         EXISTS (SELECT 1 FROM follows f WHERE f.business_id = c.business_id
           AND f.conversation = c.key AND f.person_id = $2) AS following,
         coalesce(k.pinned_at IS NOT NULL, false) AS pinned,
         coalesce(k.hidden_at > coalesce((SELECT max(m.created_at) FROM messages m
           WHERE m.business_id = c.business_id AND m.conversation = c.key), '-infinity'), false)
           AS hidden,
         (SELECT (to_jsonb(m) - 'business_id' - 'client_id' - 'seq')
            || jsonb_build_object('created_at', ${isoText("m.created_at")}) FROM messages m
          WHERE m.business_id = c.business_id AND m.conversation = c.key
          ORDER BY m.created_at DESC, m.seq DESC LIMIT 1) AS last,
         greatest((SELECT count(*)::int FROM messages m
          WHERE m.business_id = c.business_id AND m.conversation = c.key
            AND m.author <> 'person:' || $2
            AND m.seq > coalesce((SELECT r.seen_seq FROM conversation_reads r
              WHERE r.business_id = c.business_id AND r.conversation = c.key
                AND r.participant = 'person:' || $2), 0)),
           CASE WHEN k.marked_unread THEN 1 ELSE 0 END) AS unread
       FROM conversations c
       LEFT JOIN conversation_marks k ON k.business_id = c.business_id AND k.conversation = c.key
         AND k.person_id = $2
       WHERE c.business_id = $1`,
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

/**
 * The employee turn behind a reply in a conversation: its author and the Pi operation it
 * answered (posted as `reply:<operation>`); undefined for any other message.
 */
export const replyTurnOf = (db: Database, businessId: string, key: ConversationKey, id: string) =>
  database(db, async (sql) => {
    const row = await sql.row<{ author: string; client_id: string }>(
      `SELECT author, client_id FROM messages
       WHERE business_id = $1 AND conversation = $2 AND id = $3 AND client_id LIKE 'reply:%'`,
      [businessId, key, id],
    );
    const employeeId = row && employeeOf(row.author);
    return employeeId
      ? { employeeId, operationId: row.client_id.slice("reply:".length) }
      : undefined;
  });

/**
 * Whether answers wait on the owner in a conversation: an employee's question card is its latest
 * word (or one is set for its next message), so the owner has buttons to tap.
 */
export const offersAnswers = (db: Database, businessId: string, key: ConversationKey) =>
  database(db, async (sql) => {
    const set = await sql.row<{ n: number }>(
      "SELECT count(*)::int AS n FROM suggested_replies WHERE business_id = $1 AND conversation = $2",
      [businessId, key],
    );
    if (set!.n > 0) return true;
    const latest = await sql.row<{ author: string; replies: string[] }>(
      `SELECT author, replies FROM messages WHERE business_id = $1 AND conversation = $2
       ORDER BY created_at DESC, seq DESC LIMIT 1`,
      [businessId, key],
    );
    return Boolean(latest && employeeOf(latest.author) && latest.replies.length > 0);
  });
