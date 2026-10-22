/**
 * Remote apps a business added (LP6): MCP servers behind their own sign-in, with what each lists
 * and the owner's acceptance, which is its policy. Their tokens are the vault's; this keeps the
 * manifest.
 */
import { database, type Database } from "../data/database.ts";
import type { RemotePolicy, RemoteServer, RemoteState, RemoteTool } from "./contract.ts";

export interface RemoteApp {
  id: string;
  name: string;
  summary: string;
  url: string;
  registry_name: string | null;
  website: string | null;
  /** The sha-256 of its logo's bytes in R2. */
  logo: string | null;
  state: RemoteState;
  tools: RemoteTool[];
  policy: RemotePolicy | null;
  pinned: boolean;
  added_by: string;
  added_at: string;
  accepted_at: string | null;
}

const columns =
  "id, name, summary, url, registry_name, website, logo, state, tools, policy, pinned, added_by, added_at, accepted_at";

/** The vault connection secret a remote app's tokens are kept in. */
export const connectionName = (appId: string) => `app-${appId}`;

/** A remote app's id from its name: lowercase letters and digits ("Acme Books" → "acmebooks"). */
const slug = (name: string) => {
  const base = name.toLowerCase().replace(/[^a-z0-9]/g, "");
  return /^[a-z]/.test(base) ? base.slice(0, 24) : `app${base}`.slice(0, 24);
};

export const remoteApps = (db: Database, businessId: string) =>
  database(db, (sql) =>
    sql.rows<RemoteApp>(
      `SELECT ${columns} FROM remote_apps WHERE business_id = $1 ORDER BY added_at, id`,
      [businessId],
    ),
  );

export const remoteApp = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<RemoteApp>(`SELECT ${columns} FROM remote_apps WHERE business_id = $1 AND id = $2`, [
      businessId,
      id,
    ]),
  );

/** The business's remote app at this address or registry name, if it added one. */
export const remoteAppFor = (db: Database, businessId: string, address: string) =>
  database(db, (sql) =>
    sql.row<RemoteApp>(
      `SELECT ${columns} FROM remote_apps
       WHERE business_id = $1 AND (url = $2 OR registry_name = $2 OR id = $2)`,
      [businessId, address],
    ),
  );

/**
 * Adds a remote app (`connecting`) under an id made from its name, never one a built-in app or
 * another of the business's apps has; adding an address already added returns that app.
 */
export const addRemoteApp = (
  db: Database,
  businessId: string,
  app: {
    name: string;
    summary: string;
    url: string;
    registryName: string | null;
    website: string | null;
    logo: string | null;
    addedBy: string;
  },
  taken: readonly string[],
) =>
  database(
    db,
    async (sql) => {
      const existing = await sql.row<RemoteApp>(
        `SELECT ${columns} FROM remote_apps WHERE business_id = $1 AND url = $2`,
        [businessId, app.url],
      );
      if (existing) return existing;
      const used = new Set([
        ...taken,
        ...(
          await sql.rows<{ id: string }>("SELECT id FROM remote_apps WHERE business_id = $1", [
            businessId,
          ])
        ).map((row) => row.id),
      ]);
      const base = slug(app.name);
      let id = base;
      for (let n = 2; used.has(id); n++) id = `${base}${n}`;
      return (await sql.row<RemoteApp>(
        `INSERT INTO remote_apps (business_id, id, name, summary, url, registry_name, website, logo,
           added_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING ${columns}`,
        [
          businessId,
          id,
          app.name.slice(0, 80),
          app.summary.slice(0, 500),
          app.url,
          app.registryName,
          app.website,
          app.logo,
          app.addedBy,
        ],
      ))!;
    },
    { transaction: true },
  );

/**
 * The app signed in (or reconnected): what its server says it is and lists. A newly connected app
 * waits for review; a reconnected one that was on is on again (its policy stands; tools it did
 * not list before have no line, so no one has them until the owner reviews).
 */
export const connectedRemoteApp = (
  db: Database,
  businessId: string,
  id: string,
  found: { server: RemoteServer; tools: RemoteTool[]; logo: string | null },
) =>
  database(db, (sql) =>
    sql.row<RemoteApp>(
      `UPDATE remote_apps SET
         state = CASE WHEN policy IS NULL THEN 'review' ELSE 'on' END,
         name = $3, summary = CASE WHEN $4 = '' THEN summary ELSE $4 END,
         website = coalesce($5, website), logo = coalesce($6, logo), tools = $7
       WHERE business_id = $1 AND id = $2 RETURNING ${columns}`,
      [
        businessId,
        id,
        (found.server.title ?? found.server.name).slice(0, 80),
        (found.server.description ?? "").slice(0, 500),
        found.server.website ?? null,
        found.logo,
        JSON.stringify(found.tools),
      ],
    ),
  );

/** Its sign-in stopped working: it lapses until the owner reconnects. */
export const lapseRemoteApp = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.run(
      "UPDATE remote_apps SET state = 'lapsed' WHERE business_id = $1 AND id = $2 AND state = 'on'",
      [businessId, id],
    ),
  );

/** The owner turned it on: their acceptance is its policy. */
export const acceptRemoteApp = (
  db: Database,
  businessId: string,
  id: string,
  policy: RemotePolicy,
) =>
  database(db, (sql) =>
    sql.row<RemoteApp>(
      `UPDATE remote_apps SET policy = $3, state = 'on', accepted_at = now()
       WHERE business_id = $1 AND id = $2 AND state IN ('review', 'on') RETURNING ${columns}`,
      [businessId, id, JSON.stringify(policy)],
    ),
  );

export const pinRemoteApp = (db: Database, businessId: string, id: string, pinned: boolean) =>
  database(
    db,
    async (sql) =>
      (await sql.run("UPDATE remote_apps SET pinned = $3 WHERE business_id = $1 AND id = $2", [
        businessId,
        id,
        pinned,
      ])) > 0,
  );

export const removeRemoteApp = (db: Database, businessId: string, id: string) =>
  database(db, (sql) =>
    sql.row<RemoteApp>(
      `DELETE FROM remote_apps WHERE business_id = $1 AND id = $2 RETURNING ${columns}`,
      [businessId, id],
    ),
  );

/** A sign-in started: ten minutes, one use, bound to its business, app and person. */
export const startSignIn = (
  db: Database,
  input: {
    stateHash: string;
    businessId: string;
    appId: string;
    personId: string;
    pending: unknown;
    native: boolean;
  },
) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO app_sign_ins (state_hash, business_id, app_id, person_id, pending, native,
         expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, now() + interval '10 minutes')`,
      [
        input.stateHash,
        input.businessId,
        input.appId,
        input.personId,
        JSON.stringify(input.pending),
        input.native,
      ],
    ),
  );

/** The sign-in a callback finishes, once; expired or used ones are gone. */
export const claimSignIn = (db: Database, stateHash: string) =>
  database(db, (sql) =>
    sql.row<{
      business_id: string;
      app_id: string;
      person_id: string;
      pending: unknown;
      native: boolean;
    }>(
      `DELETE FROM app_sign_ins WHERE state_hash = $1 AND expires_at > now()
       RETURNING business_id, app_id, person_id, pending, native`,
      [stateHash],
    ),
  );
