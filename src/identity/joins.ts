import { database, type Database } from "../data/database.ts";
import { sha256Bytes } from "../protocol/bytes.ts";
import { deviceOf, insertSession } from "./sessions.ts";

/** How long a device's request to join waits for an answer. */
export const joinSeconds = 120;
/** At most this many requests wait at once; more are refused until one is answered or expires. */
const waitingLimit = 5;

/**
 * Sixty-four emoji that read the same at a glance on every platform (single code points, no
 * skin tones or joiners). Two of them, shown on both screens, tell the owner which request is
 * the device in their hand.
 */
export const matchEmoji = [
  "🐶",
  "🐱",
  "🐭",
  "🐹",
  "🐰",
  "🦊",
  "🐻",
  "🐼",
  "🐨",
  "🐯",
  "🦁",
  "🐮",
  "🐷",
  "🐸",
  "🐵",
  "🐔",
  "🐧",
  "🐦",
  "🦆",
  "🦉",
  "🐴",
  "🦄",
  "🐝",
  "🦋",
  "🐌",
  "🐞",
  "🐢",
  "🐙",
  "🦀",
  "🐠",
  "🐬",
  "🐳",
  "🦒",
  "🦓",
  "🐘",
  "🦔",
  "🌵",
  "🌲",
  "🌻",
  "🍀",
  "🍁",
  "🍄",
  "🌙",
  "🌈",
  "🔥",
  "🍎",
  "🍊",
  "🍋",
  "🍉",
  "🍇",
  "🍓",
  "🍒",
  "🍑",
  "🍍",
  "🥝",
  "🥕",
  "🌽",
  "🍩",
  "🍪",
  "🎈",
  "🎁",
  "🚀",
  "⚓",
  "🔔",
] as const;

/** The two emoji for a request: from its id and the session it asks for, so both sides agree. */
export async function joinMatch(id: string, sessionHash: string): Promise<[string, string]> {
  const digest = await sha256Bytes(new TextEncoder().encode(`${id}:${sessionHash}`));
  const byte = (index: number) => Number.parseInt(digest.slice(index * 2, index * 2 + 2), 16);
  const first = byte(0) % matchEmoji.length;
  // Never the same emoji twice, so the pair reads as two things.
  const second = (first + 1 + (byte(1) % (matchEmoji.length - 1))) % matchEmoji.length;
  return [matchEmoji[first]!, matchEmoji[second]!];
}

export type JoinStatus = "pending" | "allowed" | "denied" | "expired";

interface JoinRow {
  id: string;
  session_hash: string;
  name: string;
  public_key: string | null;
  expires_at: string;
}

/** A device asks to join; undefined while too many requests are already waiting. */
export const askToJoin = (
  db: Database,
  input: { sessionHash: string; name: string; publicKey: string | null },
) =>
  database(
    db,
    async (sql) => {
      await sql.run("SELECT pg_advisory_xact_lock(hashtext('join_requests'))");
      await sql.run("DELETE FROM join_requests WHERE expires_at < now() - interval '1 day'");
      const waiting = await sql.row<{ n: number }>(
        "SELECT count(*)::int AS n FROM join_requests WHERE answered_at IS NULL AND expires_at > now()",
      );
      if ((waiting?.n ?? 0) >= waitingLimit) return undefined;
      return (await sql.row<JoinRow>(
        `INSERT INTO join_requests (id, session_hash, name, public_key, expires_at)
         VALUES ($1, $2, $3, $4, now() + interval '${joinSeconds} seconds')
         RETURNING id, session_hash, name, public_key, expires_at`,
        [crypto.randomUUID(), input.sessionHash, input.name, input.publicKey],
      ))!;
    },
    { transaction: true },
  );

/** Where a request stands, for the device that made it (it proves itself with its session hash). */
export const joinStatus = (db: Database, id: string, sessionHash: string) =>
  database(db, async (sql) => {
    const row = await sql.row<{ status: JoinStatus }>(
      `SELECT CASE WHEN allowed_by IS NOT NULL THEN 'allowed'
                   WHEN answered_at IS NOT NULL THEN 'denied'
                   WHEN expires_at <= now() THEN 'expired'
                   ELSE 'pending' END AS status
       FROM join_requests WHERE id = $1 AND session_hash = $2`,
      [id, sessionHash],
    );
    return row?.status;
  });

/** Requests still waiting for an answer, oldest first. */
export const waitingJoins = (db: Database) =>
  database(db, (sql) =>
    sql.rows<JoinRow>(
      `SELECT id, session_hash, name, public_key, expires_at FROM join_requests
       WHERE answered_at IS NULL AND expires_at > now() ORDER BY created_at`,
    ),
  );

/**
 * Answers a waiting request once. Allowing makes the device's chosen session one of this
 * person's; the device id is the session's, so its key can be enrolled for it at once.
 * Undefined when the request was already answered, has expired or does not exist.
 */
export const answerJoin = (db: Database, id: string, personId: string, allow: boolean) =>
  database(
    db,
    async (sql) => {
      const claimed = await sql.row<JoinRow>(
        `UPDATE join_requests SET answered_at = now(), allowed_by = $2
         WHERE id = $1 AND answered_at IS NULL AND expires_at > now()
         RETURNING id, session_hash, name, public_key, expires_at`,
        [id, allow ? personId : null],
      );
      if (!claimed) return undefined;
      if (allow) await insertSession(sql, claimed.session_hash, personId, claimed.name);
      return { ...claimed, device: deviceOf(claimed.session_hash) };
    },
    { transaction: true },
  );
