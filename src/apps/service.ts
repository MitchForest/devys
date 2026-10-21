import { database, type Database } from "../data/database.ts";

/** The business's installed apps and whether each is pinned to the sidebar. */
export const installs = (db: Database, businessId: string) =>
  database(db, (sql) =>
    sql.rows<{ app_id: string; pinned: boolean }>(
      "SELECT app_id, pinned FROM app_installs WHERE business_id = $1 ORDER BY installed_at, app_id",
      [businessId],
    ),
  );

/** Installs apps; installing one already installed changes nothing. */
export const install = (db: Database, businessId: string, appIds: readonly string[]) =>
  database(db, (sql) =>
    sql.run(
      `INSERT INTO app_installs (business_id, app_id) SELECT $1, unnest($2::text[])
       ON CONFLICT DO NOTHING`,
      [businessId, [...appIds]],
    ),
  );

export const uninstall = (db: Database, businessId: string, appId: string) =>
  database(db, (sql) =>
    sql.run("DELETE FROM app_installs WHERE business_id = $1 AND app_id = $2", [businessId, appId]),
  );

/** Pins or unpins an installed app; false when it is not installed. */
export const setPinned = (db: Database, businessId: string, appId: string, pinned: boolean) =>
  database(
    db,
    async (sql) =>
      (await sql.run("UPDATE app_installs SET pinned = $3 WHERE business_id = $1 AND app_id = $2", [
        businessId,
        appId,
        pinned,
      ])) > 0,
  );
