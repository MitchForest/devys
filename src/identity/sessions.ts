import { database, type Database } from "../data/database.ts";

export const sessionPerson = (db: Database, hash: string) =>
  database(db, (sql) =>
    sql.row<{ id: string; display_name: string }>(
      `SELECT o.id, o.display_name FROM people o JOIN web_sessions s ON o.id = s.person_id
       WHERE s.token_hash = $1 AND s.expires_at > now() AND o.revoked_at IS NULL`,
      [hash],
    ),
  );

export const deleteSession = (db: Database, hash: string) =>
  database(db, (sql) => sql.run("DELETE FROM web_sessions WHERE token_hash = $1", [hash]));

/** Claiming the token row first means concurrent attempts create only one session. */
export const redeemEnrollment = (
  db: Database,
  tokenHash: string,
  sessionHash: string,
  label: string,
) =>
  database(
    db,
    async (sql) => {
      const claimed = await sql.row<{ person_id: string }>(
        `UPDATE enrollment_tokens t SET consumed_at = now()
         FROM people o
         WHERE t.token_hash = $1 AND t.consumed_at IS NULL AND t.expires_at > now()
           AND o.id = t.person_id AND o.revoked_at IS NULL
         RETURNING t.person_id`,
        [tokenHash],
      );
      if (!claimed) return false;
      await sql.run(
        `INSERT INTO web_sessions (token_hash, person_id, expires_at, label)
         VALUES ($1, $2, now() + interval '7 days', $3)`,
        [sessionHash, claimed.person_id, label],
      );
      return true;
    },
    { transaction: true },
  );

/** A single-use code that signs another device in as this person, valid for ten minutes. */
export const issueDeviceCode = (db: Database, personId: string, tokenHash: string) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO enrollment_tokens (token_hash, person_id, expires_at)
       SELECT $1, id, now() + interval '10 minutes' FROM people WHERE id = $2 AND revoked_at IS NULL`,
      [tokenHash, personId],
    ),
  );

/** This person's signed-in devices; a device is named by the start of its session hash. */
export const devices = (db: Database, personId: string) =>
  database(db, (sql) =>
    sql.rows<{ id: string; label: string | null; created_at: string; expires_at: string }>(
      `SELECT left(token_hash, 16) AS id, label, created_at, expires_at FROM web_sessions
       WHERE person_id = $1 AND expires_at > now() ORDER BY created_at DESC`,
      [personId],
    ),
  );

/** Signs one of this person's devices out. Another person's device is never matched. */
export const revokeDevice = (db: Database, personId: string, id: string) =>
  database(db, (sql) =>
    sql.run("DELETE FROM web_sessions WHERE person_id = $1 AND left(token_hash, 16) = $2", [
      personId,
      id,
    ]),
  );
