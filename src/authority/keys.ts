import { database, type Database } from "../data/database.ts";
import type { DeviceKey } from "./contract.ts";

const columns = "id, device, label, public_key, status, created_at";

/** A person's signing keys that are not revoked, newest first. */
export const deviceKeys = (db: Database, personId: string) =>
  database(db, (sql) =>
    sql.rows<DeviceKey>(
      `SELECT ${columns} FROM device_keys WHERE person_id = $1 AND revoked_at IS NULL
       ORDER BY created_at DESC`,
      [personId],
    ),
  );

/** One of the person's keys, if it is not revoked. */
export const deviceKey = (db: Database, personId: string, id: string) =>
  database(db, (sql) =>
    sql.row<DeviceKey>(
      `SELECT ${columns} FROM device_keys WHERE id = $1 AND person_id = $2 AND revoked_at IS NULL`,
      [id, personId],
    ),
  );

/**
 * Enrolls a device's key, replacing any other key the device had. The person's first key is
 * active at once; a later one waits for an active key's signature (`endorseKey`). A key already
 * enrolled by this person moves to this device with its status.
 */
export const enrollKey = (
  db: Database,
  key: { personId: string; device: string; label: string | null; publicKey: string },
) =>
  database(
    db,
    async (sql) => {
      // One enrollment per person at a time, so two first keys cannot both be active.
      await sql.run("SELECT pg_advisory_xact_lock(hashtext($1))", [`device_keys:${key.personId}`]);
      // The same key, signed in again (a new session of the same device): it moves with it.
      const kept = await sql.row<DeviceKey>(
        `UPDATE device_keys SET device = $3, label = $4
         WHERE person_id = $1 AND public_key = $2 AND revoked_at IS NULL RETURNING ${columns}`,
        [key.personId, key.publicKey, key.device, key.label],
      );
      if (kept) return kept;
      await sql.run(
        `UPDATE device_keys SET revoked_at = now()
         WHERE person_id = $1 AND device = $2 AND revoked_at IS NULL`,
        [key.personId, key.device],
      );
      const active = await sql.row<{ id: string }>(
        `SELECT id FROM device_keys
         WHERE person_id = $1 AND status = 'active' AND revoked_at IS NULL LIMIT 1`,
        [key.personId],
      );
      return (await sql.row<DeviceKey>(
        `INSERT INTO device_keys (id, person_id, device, label, public_key, status)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${columns}`,
        [
          crypto.randomUUID(),
          key.personId,
          key.device,
          key.label,
          key.publicKey,
          active ? "pending" : "active",
        ],
      ))!;
    },
    { transaction: true },
  );

/** Activates a pending key with the signature of the person's active key that allowed it. */
export const endorseKey = (
  db: Database,
  personId: string,
  id: string,
  endorsement: { by: string; signature: string },
) =>
  database(db, (sql) =>
    sql.row<DeviceKey>(
      `UPDATE device_keys SET status = 'active', endorsed_by = $3, endorsement = $4
       WHERE id = $1 AND person_id = $2 AND status = 'pending' AND revoked_at IS NULL
       RETURNING ${columns}`,
      [id, personId, endorsement.by, endorsement.signature],
    ),
  );

/** Revokes one key, or every key of one device (signed out). Signed approvals keep their key. */
export const revokeKeys = (
  db: Database,
  personId: string,
  which: { id: string } | { device: string },
) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE device_keys SET revoked_at = now()
       WHERE person_id = $1 AND ${"id" in which ? "id" : "device"} = $2 AND revoked_at IS NULL`,
      [personId, "id" in which ? which.id : which.device],
    ),
  );

/** Revokes every key of the install (the Mac's owner clearing them); returns how many. */
export const revokeAllKeys = (db: Database) =>
  database(db, (sql) =>
    sql.run("UPDATE device_keys SET revoked_at = now() WHERE revoked_at IS NULL"),
  );
