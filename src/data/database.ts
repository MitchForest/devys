import { Effect } from "effect";
import pg from "pg";
import { CapabilityError } from "../protocol/capability.ts";

/** Where Postgres is reached: a Hyperdrive binding, or any connection string in scripts. */
export interface Database {
  readonly connectionString: string;
}

/** Plain parameterized SQL (`$1`, `$2`, …) on one connection. */
export interface Sql {
  rows<T>(text: string, values?: readonly unknown[]): Promise<T[]>;
  row<T>(text: string, values?: readonly unknown[]): Promise<T | undefined>;
  /** Runs a statement and returns how many rows it changed. */
  run(text: string, values?: readonly unknown[]): Promise<number>;
}

// Timestamps cross the boundary as ISO strings, the same shape the API returns.
pg.types.setTypeParser(pg.types.builtins.TIMESTAMPTZ, (value) => new Date(value).toISOString());
pg.types.setTypeParser(pg.types.builtins.INT8, Number);

function sql(client: pg.Client): Sql {
  return {
    rows: async (text, values = []) => (await client.query(text, [...values])).rows,
    row: async (text, values = []) => (await client.query(text, [...values])).rows[0],
    run: async (text, values = []) => (await client.query(text, [...values])).rowCount ?? 0,
  };
}

/**
 * One connection per call: Hyperdrive pools connections, so Workers open and close
 * a client per operation. `transaction` commits everything `use` does, or nothing.
 */
async function connected<A>(db: Database, use: (client: pg.Client) => Promise<A>) {
  const client = new pg.Client({ connectionString: db.connectionString });
  let ending = false;
  // Failed queries reject on their own. On Workers the socket's read loop also
  // rejects once `end()` closes it; that teardown error is expected.
  client.on("error", (error) => {
    if (!ending) throw error;
  });
  await client.connect();
  try {
    return await use(client);
  } finally {
    ending = true;
    await client.end();
  }
}

export async function query<A>(db: Database, use: (sql: Sql) => Promise<A>) {
  return connected(db, (client) => use(sql(client)));
}

export async function transaction<A>(db: Database, use: (sql: Sql) => Promise<A>) {
  return connected(db, async (client) => {
    await client.query("BEGIN");
    try {
      const result = await use(sql(client));
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    }
  });
}

/** Keep database failures in the Effect capability error channel. */
export function database<A>(
  db: Database,
  use: (sql: Sql) => Promise<A>,
  options: { transaction?: boolean } = {},
): Effect.Effect<A, CapabilityError> {
  return Effect.tryPromise({
    try: () => (options.transaction ? transaction(db, use) : query(db, use)),
    catch: () => new CapabilityError({ code: "unavailable", message: "Database operation failed" }),
  });
}
