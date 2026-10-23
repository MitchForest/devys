import { database, type Database, type Sql } from "../data/database.ts";

/** How long a device stays signed in, in days. */
export const sessionDays = 7;

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

const insertSession = (sql: Sql, hash: string, personId: string, label: string | null) =>
  sql.run(
    `INSERT INTO web_sessions (token_hash, person_id, expires_at, label)
     VALUES ($1, $2, now() + interval '${sessionDays} days', $3)`,
    [hash, personId, label],
  );

/**
 * The Mac's owner in local mode: the earliest active person, created with `name` when there is
 * no one yet. Locked so two first sign-ins cannot create two owners.
 */
async function machineOwner(sql: Sql, name: string) {
  await sql.run("SELECT pg_advisory_xact_lock(hashtext('people:machine-owner'))");
  const first = await sql.row<{ id: string }>(
    "SELECT id FROM people WHERE revoked_at IS NULL ORDER BY created_at, id LIMIT 1",
  );
  if (first) return first.id;
  const id = crypto.randomUUID();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, $2)", [id, name]);
  return id;
}

/**
 * A session for the Mac's owner, asked for by the Mac app with the key only the owner's macOS
 * user can read (`POST /api/local/session`; .docs/AUTHORITY.md "Signing in").
 */
export const ownerSession = (
  db: Database,
  input: { sessionHash: string; name: string; label: string | null },
) =>
  database(
    db,
    async (sql) => {
      const owner = await machineOwner(sql, input.name);
      await insertSession(sql, input.sessionHash, owner, input.label);
      return owner;
    },
    { transaction: true },
  );

/** A one-time link that signs a browser in as the Mac's owner, from `bun run local install`. */
export const issueOwnerLink = (db: Database, input: { tokenHash: string; name: string }) =>
  database(
    db,
    async (sql) => {
      const owner = await machineOwner(sql, input.name);
      await sql.run(
        `INSERT INTO sign_in_links (token_hash, person_id, expires_at)
         VALUES ($1, $2, now() + interval '10 minutes')`,
        [input.tokenHash, owner],
      );
    },
    { transaction: true },
  );

/** A one-time link that signs a browser in as this person, valid for ten minutes. */
export const issueLink = (db: Database, personId: string, tokenHash: string) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO sign_in_links (token_hash, person_id, expires_at)
       SELECT $1, id, now() + interval '10 minutes' FROM people WHERE id = $2 AND revoked_at IS NULL`,
      [tokenHash, personId],
    ),
  );

/** Claiming the link first means concurrent attempts create only one session. */
export const redeemLink = (db: Database, tokenHash: string, sessionHash: string, label: string) =>
  database(
    db,
    async (sql) => {
      const claimed = await sql.row<{ person_id: string }>(
        `UPDATE sign_in_links t SET consumed_at = now()
         FROM people o
         WHERE t.token_hash = $1 AND t.consumed_at IS NULL AND t.expires_at > now()
           AND o.id = t.person_id AND o.revoked_at IS NULL
         RETURNING t.person_id`,
        [tokenHash],
      );
      if (!claimed) return false;
      await insertSession(sql, sessionHash, claimed.person_id, label);
      return true;
    },
    { transaction: true },
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

/** The device id of a session: the start of its hash, as `devices` lists it. */
export const deviceOf = (sessionHash: string) => sessionHash.slice(0, 16);

export { insertSession };
