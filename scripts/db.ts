/**
 * Project-local Postgres 17 for development and tests, following Closekit. The cluster lives in
 * `.pgdata/` (gitignored) and listens only on 127.0.0.1. Migrations use Alchemy's SQL migration
 * format (`migrations/<timestamp>_<name>/migration.sql`) and its `__alchemy_migrations` table, so
 * deploys apply the same directory through Alchemy's PlanetScale resource.
 *
 *   bun scripts/db.ts start | stop | status | migrate [db] | reset [db] | ensure | url [db] | drill [db]
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import pg from "pg";

const root = resolve(import.meta.dirname, "..");
// Local mode keeps its own cluster outside the checkout (scripts/local.ts sets this).
const dataDir = process.env.DEVYS_PG_DATA ?? join(root, ".pgdata");
export const port = Number(process.env.DEVYS_PG_PORT ?? 54331);
export const devDatabase = "devys";
export const testDatabase = "devys_test";
export const databaseUrl = (database = devDatabase) =>
  `postgres://devys:devys@127.0.0.1:${port}/${database}`;

export function bin(name: string) {
  const which = spawnSync("which", ["pg_ctl"], { encoding: "utf8" }).stdout.trim();
  const dir = [
    process.env.PG_BIN,
    "/opt/homebrew/opt/postgresql@17/bin",
    "/usr/local/opt/postgresql@17/bin",
    "/usr/lib/postgresql/17/bin",
    which && dirname(realpathSync(which)),
  ].find((candidate) => candidate && existsSync(join(candidate, "initdb")));
  if (!dir) throw new Error("Install PostgreSQL 17 (`brew install postgresql@17`) or set PG_BIN.");
  return join(dir, name);
}

function run(command: string, args: string[]) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    process.stderr.write(result.stdout + result.stderr);
    throw new Error(`${command} ${args[0] ?? ""} failed`);
  }
}

const running = () =>
  existsSync(join(dataDir, "PG_VERSION")) &&
  spawnSync(bin("pg_ctl"), ["status", "-D", dataDir]).status === 0;

export function start() {
  if (!existsSync(join(dataDir, "PG_VERSION"))) {
    mkdirSync(dataDir, { recursive: true });
    // Trust auth ignores the password; Hyperdrive's local connection string requires one.
    run(bin("initdb"), ["-D", dataDir, "-U", "devys", "--auth=trust", "-E", "UTF8", "--no-locale"]);
  }
  if (running()) return false;
  run(bin("pg_ctl"), [
    "start",
    "-D",
    dataDir,
    "-w",
    "-l",
    join(dataDir, "server.log"),
    "-o",
    `-p ${port} -c listen_addresses=127.0.0.1 -c unix_socket_directories='' -c max_connections=200`,
  ]);
  return true;
}

async function withClient<T>(database: string, use: (client: pg.Client) => Promise<T>) {
  const client = new pg.Client({ connectionString: databaseUrl(database) });
  await client.connect();
  try {
    return await use(client);
  } finally {
    await client.end();
  }
}

export async function createDatabase(name: string, recreate = false) {
  await withClient("postgres", async (client) => {
    if (recreate) await client.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
    const exists = await client.query("SELECT 1 FROM pg_database WHERE datname = $1", [name]);
    if (!exists.rowCount) await client.query(`CREATE DATABASE "${name}"`);
  });
}

export async function dropDatabase(name: string) {
  await withClient("postgres", (client) =>
    client.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`),
  );
}

type AlchemyMigrations = {
  applyMigrations: (options: {
    resolved: { dir: string; table: string };
    executor: unknown;
  }) => import("effect").Effect.Effect<void, unknown, never>;
  makePgMigrationExecutor: (client: pg.Client) => unknown;
};

/**
 * Applies pending migrations with Alchemy's own registry so local bookkeeping matches deploys.
 * Alchemy does not export it through package `exports`, so it is loaded by path, as in Closekit.
 */
export async function migrate(database = devDatabase) {
  const [migrations, platform, { Effect }] = await Promise.all([
    import(
      join(root, "node_modules/alchemy/src/SQL/Migrations/index.ts")
    ) as Promise<AlchemyMigrations>,
    import("@effect/platform-bun/BunServices"),
    import("effect"),
  ]);
  await withClient(database, (client) =>
    Effect.runPromise(
      migrations
        .applyMigrations({
          resolved: { dir: join(root, "migrations"), table: "__alchemy_migrations" },
          executor: migrations.makePgMigrationExecutor(client),
        })
        .pipe(Effect.provide(platform.layer)),
    ),
  );
}

/**
 * Restore drill: dumps a database with pg_dump, restores it into an empty one, and
 * compares every table's row count. Returns the tables that differ (none means it passed).
 */
export async function drill(source = devDatabase) {
  const target = `${source}_restore`;
  const dump = spawnSync(bin("pg_dump"), ["--no-owner", "--no-privileges", databaseUrl(source)], {
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
  });
  if (dump.status !== 0) throw new Error(`pg_dump failed: ${dump.stderr}`);
  await createDatabase(target, true);
  const restore = spawnSync(
    bin("psql"),
    ["--quiet", "--set", "ON_ERROR_STOP=1", databaseUrl(target)],
    {
      input: dump.stdout,
      encoding: "utf8",
      maxBuffer: 512 * 1024 * 1024,
    },
  );
  if (restore.status !== 0) throw new Error(`Restore failed: ${restore.stderr}`);
  const counts = (database: string) =>
    withClient(database, async (client) => {
      const tables = (
        await client.query<{ name: string }>(
          "SELECT tablename AS name FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename",
        )
      ).rows.map((row) => row.name);
      const result: Record<string, number> = {};
      for (const table of tables)
        result[table] = Number(
          (await client.query(`SELECT count(*) FROM "${table}"`)).rows[0].count,
        );
      return result;
    });
  const [before, after] = await Promise.all([counts(source), counts(target)]);
  const tables = Object.keys(before);
  return {
    tables: tables.map((table) => ({ table, source: before[table]!, restored: after[table] ?? 0 })),
    differing: tables.filter((table) => before[table] !== after[table]),
  };
}

/** Starts the cluster if needed, creates the development and test databases and migrates both. */
export async function ensure() {
  start();
  for (const name of [devDatabase, testDatabase]) {
    await createDatabase(name);
    await migrate(name);
  }
}

if (import.meta.main) {
  const [command = "status", name] = process.argv.slice(2);
  switch (command) {
    case "start":
      console.log(start() ? `started on ${port}` : `already running on ${port}`);
      break;
    case "stop":
      if (running()) run(bin("pg_ctl"), ["stop", "-D", dataDir, "-m", "fast", "-w"]);
      break;
    case "status":
      console.log(running() ? `running on 127.0.0.1:${port}` : "not running");
      break;
    case "url":
      console.log(databaseUrl(name));
      break;
    case "migrate":
      start();
      await createDatabase(name ?? devDatabase);
      await migrate(name);
      break;
    case "reset":
      start();
      await createDatabase(name ?? devDatabase, true);
      await migrate(name);
      break;
    case "ensure":
      await ensure();
      break;
    case "drill": {
      start();
      const result = await drill(name);
      for (const row of result.tables)
        console.log(`${row.table.padEnd(24)} ${String(row.source).padStart(6)} → ${row.restored}`);
      if (result.differing.length)
        throw new Error(`Restore differs: ${result.differing.join(", ")}`);
      console.log(`Restore drill passed: ${result.tables.length} tables match.`);
      break;
    }
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}
