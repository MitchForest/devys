import { readdirSync } from "node:fs";
import pg from "pg";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createDatabase, databaseUrl, migrate, start } from "../scripts/db.ts";

const name = "devys_migration_test";

let client: pg.Client;
beforeAll(async () => {
  start();
  await createDatabase(name, true);
  client = new pg.Client({ connectionString: databaseUrl(name) });
  await client.connect();
}, 60_000);
afterAll(() => client?.end());

it("the migrations take an empty database to every component's tables, once", async () => {
  await migrate(name);
  await migrate(name);
  const tables = (
    await client.query<{ name: string }>(
      "SELECT tablename AS name FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename",
    )
  ).rows.map((row) => row.name);
  expect(tables).toEqual([
    "__alchemy_migrations",
    "app_installs",
    "app_reactions",
    "app_sign_ins",
    "artifacts",
    "businesses",
    "channel_bindings",
    "coding_sessions",
    "conversation_marks",
    "conversation_reads",
    "conversations",
    "decisions",
    "device_keys",
    "drive_files",
    "drive_operations",
    "employees",
    "follows",
    "google_connections",
    "google_oauth_states",
    "grants",
    "join_requests",
    "memberships",
    "memories",
    "memory_exclusions",
    "memory_links",
    "memory_operations",
    "memory_sources",
    "memory_state",
    "messages",
    "people",
    "project_items",
    "project_members",
    "projects",
    "remote_apps",
    "routines",
    "secrets",
    "sign_in_links",
    "suggested_replies",
    "web_sessions",
    "work_items",
  ]);
  // Alchemy records each migration by its directory name.
  expect(
    (await client.query("SELECT name FROM __alchemy_migrations ORDER BY id")).rows.map(
      (row) => row.name,
    ),
  ).toEqual(readdirSync("migrations").sort());
}, 60_000);
