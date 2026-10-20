import { database, type Database } from "../data/database.ts";
import type { Space, SpaceItem } from "./contract.ts";

/** Every space in the business, with its items, oldest first. */
export const spaces = (db: Database, businessId: string) =>
  database(db, async (sql) => {
    const rows = await sql.rows<Omit<Space, "items">>(
      "SELECT id, name, purpose, lead_employee_id FROM spaces WHERE business_id = $1 ORDER BY created_at, id",
      [businessId],
    );
    const items = await sql.rows<SpaceItem & { space_id: string }>(
      `SELECT id, space_id, kind, ref FROM space_items
       WHERE business_id = $1 ORDER BY created_at, id`,
      [businessId],
    );
    return rows.map((space) => ({
      ...space,
      items: items
        .filter((item) => item.space_id === space.id)
        .map(({ id, kind, ref }) => ({ id, kind, ref })),
    }));
  });

export const createSpace = (
  db: Database,
  businessId: string,
  input: { name: string; purpose?: string; lead?: string },
) =>
  database(db, async (sql) => {
    const space = {
      id: crypto.randomUUID(),
      name: input.name,
      purpose: input.purpose ?? "",
      lead_employee_id: input.lead ?? null,
    };
    await sql.run(
      `INSERT INTO spaces (id, business_id, name, purpose, lead_employee_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [space.id, businessId, space.name, space.purpose, space.lead_employee_id],
    );
    return { ...space, items: [] } satisfies Space;
  });

/** Renames a space, rewrites its purpose or changes its lead. */
export const updateSpace = (
  db: Database,
  businessId: string,
  id: string,
  change: { name?: string; purpose?: string; lead?: string },
) =>
  database(db, (sql) =>
    sql.run(
      `UPDATE spaces SET name = coalesce($3, name), purpose = coalesce($4, purpose),
         lead_employee_id = coalesce($5, lead_employee_id)
       WHERE business_id = $1 AND id = $2`,
      [businessId, id, change.name ?? null, change.purpose ?? null, change.lead ?? null],
    ),
  );

/**
 * Places a record in a space. The caller has already checked the record belongs to
 * this business; a commitment is checked here because work owns it. Adding twice is a no-op.
 */
export const addToSpace = (
  db: Database,
  businessId: string,
  spaceId: string,
  item: { kind: SpaceItem["kind"]; ref: string },
) =>
  database(db, async (sql) => {
    const space = await sql.row("SELECT 1 FROM spaces WHERE business_id = $1 AND id = $2", [
      businessId,
      spaceId,
    ]);
    if (!space) return undefined;
    if (
      item.kind === "commitment" &&
      !(await sql.row("SELECT 1 FROM commitments WHERE business_id = $1 AND id = $2", [
        businessId,
        item.ref,
      ]))
    )
      return undefined;
    await sql.run(
      `INSERT INTO space_items (id, business_id, space_id, kind, ref) VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (space_id, kind, ref) DO NOTHING`,
      [crypto.randomUUID(), businessId, spaceId, item.kind, item.ref],
    );
    return (await sql.row<SpaceItem>(
      "SELECT id, kind, ref FROM space_items WHERE space_id = $1 AND kind = $2 AND ref = $3",
      [spaceId, item.kind, item.ref],
    ))!;
  });

/** Takes a record out of a space. The record itself is untouched. */
export const removeFromSpace = (db: Database, businessId: string, itemId: string) =>
  database(db, (sql) =>
    sql.run("DELETE FROM space_items WHERE business_id = $1 AND id = $2", [businessId, itemId]),
  );
