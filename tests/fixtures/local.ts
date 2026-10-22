import { createHash, randomBytes, randomUUID } from "node:crypto";
import pg from "pg";
import { getPlatformProxy } from "wrangler";
import { databaseUrl } from "../../scripts/db.ts";

/** The local development Postgres and R2 that `bun run dev:local` serves from. */
export async function localStores(channel = false) {
  const base = channel ? "http://127.0.0.1:5180" : "http://127.0.0.1:5173";
  const client = new pg.Client({ connectionString: databaseUrl() });
  await client.connect();
  const proxy = await getPlatformProxy<{ FILES: R2Bucket }>({
    configPath: channel ? "wrangler.channel.jsonc" : "wrangler.local.jsonc",
    persist: { path: channel ? ".wrangler/channel-state/v3" : ".wrangler/state/v3" },
    envFiles: [],
    remoteBindings: false,
  });
  const run = async (text: string, values: unknown[] = []) =>
    (await client.query(text, values)).rowCount ?? 0;
  return {
    files: proxy.env.FILES,
    /**
     * A person who owns a new business, created through the API so its Head of
     * Operations gets the real operations preset of grants.
     */
    async owner(name: string, businessName = `${name}'s business`) {
      const person = randomUUID();
      await run("INSERT INTO people (id, display_name) VALUES ($1, $2)", [person, name]);
      const token = Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join(
        "",
      );
      await run(
        "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '10 minutes')",
        [createHash("sha256").update(token).digest("hex"), person],
      );
      const response = await fetch(`${base}/api/businesses`, {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ name: businessName }),
      });
      if (!response.ok) throw new Error(`Creating a business failed: ${response.status}`);
      const created = (await response.json()) as {
        business: { id: string };
        operations: { id: string };
      };
      return { person, business: created.business.id, operations: created.operations.id };
    },
    /** Removes fixtures and everything they own, children first. */
    async remove(owners: { person: string; business: string }[]) {
      const people = owners.map((o) => o.person);
      const businesses = owners.map((o) => o.business);
      for (const table of [
        "memories",
        "memory_state",
        "memory_sources",
        "memory_links",
        "memory_operations",
        "memory_exclusions",
      ])
        await run(`DELETE FROM ${table} WHERE scope_id = ANY($1)`, [businesses]);
      for (const table of [
        "follows",
        "conversation_reads",
        "messages",
        "conversations",
        "decisions",
        "coding_sessions",
        "routines",
        "work_items",
        "project_items",
        "project_members",
        "projects",
        "app_installs",
        "artifacts",
        "app_reactions",
        "channel_bindings",
        "secrets",
        "grants",
        "employees",
        "memberships",
      ])
        await run(`DELETE FROM ${table} WHERE business_id = ANY($1)`, [businesses]);
      await run("DELETE FROM businesses WHERE id = ANY($1)", [businesses]);
      for (const table of ["device_keys", "web_sessions", "enrollment_tokens"])
        await run(`DELETE FROM ${table} WHERE person_id = ANY($1)`, [people]);
      await run("DELETE FROM people WHERE id = ANY($1)", [people]);
    },
    sql: {
      run: async (text: string, values: unknown[] = []) =>
        (await client.query(text, values)).rowCount ?? 0,
      row: async <T>(text: string, values: unknown[] = []) =>
        (await client.query(text, values)).rows[0] as T | undefined,
    },
    async dispose() {
      await client.end();
      await proxy.dispose();
    },
  };
}
