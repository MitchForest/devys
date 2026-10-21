import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { query, type Database } from "../../src/data/database.ts";
import { createBusiness } from "../../src/identity/service.ts";
import { defaultApps } from "../../src/app/apps.ts";
import { install } from "../../src/apps/service.ts";
/** The test database behind the Workers pool's Hyperdrive binding. */
export const db = (env as unknown as { HYPERDRIVE: Database }).HYPERDRIVE;
export const sql = {
  run: (text: string, values: unknown[] = []) => query(db, (s) => s.run(text, values)),
  row: <T>(text: string, values: unknown[] = []) => query(db, (s) => s.row<T>(text, values)),
  rows: <T>(text: string, values: unknown[] = []) => query(db, (s) => s.rows<T>(text, values)),
};

/** A person who owns a fresh business staffed with a Head of Operations, with its default apps. */
export async function business(name = "Test business") {
  const person = crypto.randomUUID();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, 'Owner')", [person]);
  const created = await Effect.runPromise(
    createBusiness(db, person, {
      name,
      brief: "",
      model: "claude-opus-5-5",
      operations: { name: "Head of Operations", responsibilities: "Runs the business day to day." },
    }),
  );
  await Effect.runPromise(install(db, created.business.id, defaultApps));
  return {
    person,
    business: created.business,
    operations: created.operations,
    scope: { businessId: created.business.id, employeeId: created.operations.id },
  };
}
