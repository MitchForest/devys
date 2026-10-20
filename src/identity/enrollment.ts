import { database, type Database } from "../data/database.ts";

/** Creates the person if new and issues a one-hour code. A revoked person gets none. */
export const issueEnrollment = (
  db: Database,
  input: { personId: string; name: string; tokenHash: string },
) =>
  database(
    db,
    async (sql) => {
      await sql.run(
        "INSERT INTO people (id, display_name) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING",
        [input.personId, input.name],
      );
      await sql.run(
        `INSERT INTO enrollment_tokens (token_hash, person_id, expires_at)
         VALUES ($1, (SELECT id FROM people WHERE id = $2 AND revoked_at IS NULL),
           now() + interval '1 hour')`,
        [input.tokenHash, input.personId],
      );
    },
    { transaction: true },
  );
