/**
 * The envelope vault's store (the default `SecretStore` adapter): sealed secrets in Postgres. The
 * Worker writes and reads ciphertext only; the keyring (the Mac host) seals, and only the host
 * opens.
 */
import { query, type Database } from "../data/database.ts";
import { HostRefusal } from "../protocol/host.ts";
import type { Keyring, Sealed, SecretEntry, SecretKind, SecretStore } from "./contract.ts";

/** Names by kind: the owner's in capitals, connection credentials in lowercase. */
const named = (name: string, kind: SecretKind) =>
  kind === "connection"
    ? /^[a-z][a-z0-9_-]{0,63}$/.test(name)
    : /^[A-Z][A-Z0-9_]{0,63}$/.test(name);

export function postgresSecrets(db: Database, keyring: Keyring): SecretStore {
  return {
    async put(business, name, kind, value, addedBy) {
      if (!named(name, kind)) throw new Error(`Invalid ${kind} name`);
      const sealed = await keyring.seal(business, name, kind, value);
      await query(db, (sql) =>
        sql.run(
          `INSERT INTO secrets (business_id, name, kind, data_key, ciphertext, added_by)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (business_id, name) DO UPDATE SET kind = excluded.kind,
             data_key = excluded.data_key, ciphertext = excluded.ciphertext,
             added_by = excluded.added_by, added_at = now(), last_used_at = NULL`,
          [business, name, kind, sealed.key, sealed.data, addedBy],
        ),
      );
    },
    async putSealed(sealed, addedBy) {
      if (sealed.kind !== "connection" || !named(sealed.name, sealed.kind))
        throw new Error("Only a connection's credential is stored sealed");
      await query(db, (sql) =>
        sql.run(
          `INSERT INTO secrets (business_id, name, kind, data_key, ciphertext, added_by)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (business_id, name) DO UPDATE SET kind = excluded.kind,
             data_key = excluded.data_key, ciphertext = excluded.ciphertext`,
          [sealed.business, sealed.name, sealed.kind, sealed.key, sealed.data, addedBy],
        ),
      );
    },
    list: (business) =>
      query(db, (sql) =>
        sql.rows<SecretEntry>(
          `SELECT name, kind, added_by, added_at, last_used_at FROM secrets
           WHERE business_id = $1 AND kind <> 'connection' ORDER BY name`,
          [business],
        ),
      ),
    remove: async (business, name) =>
      (await query(db, (sql) =>
        sql.run("DELETE FROM secrets WHERE business_id = $1 AND name = $2", [business, name]),
      )) === 1,
    async sealed(business, names, kinds) {
      if (!names.length) return [];
      const rows = await query(db, (sql) =>
        sql.rows<{ name: string; kind: SecretKind; data_key: string; ciphertext: string }>(
          `UPDATE secrets SET last_used_at = now()
           WHERE business_id = $1 AND name = ANY($2::text[]) AND kind = ANY($3::text[])
           RETURNING name, kind, data_key, ciphertext`,
          [business, [...names], [...kinds]],
        ),
      );
      const missing = names.filter((name) => !rows.some((row) => row.name === name));
      if (missing.length)
        throw new HostRefusal(
          404,
          `No ${kinds.includes("spend") ? "secret or card" : "secret"} named ${missing.join(", ")} in this business: ask the owner to add it (askOwner, kind secret).`,
        );
      return names.map((name): Sealed => {
        const row = rows.find((each) => each.name === name)!;
        return { business, name, kind: row.kind, key: row.data_key, data: row.ciphertext };
      });
    },
  };
}
