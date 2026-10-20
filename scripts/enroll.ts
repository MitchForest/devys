import { randomBytes, randomUUID, createHash } from "node:crypto";
import { rm, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { Effect } from "effect";
import { issueEnrollment } from "../src/identity/enrollment.ts";
import pg from "pg";
import { databaseUrl } from "./db.ts";

// Creates a person and a one-time sign-in code. Businesses are created from the apps
// or `POST /api/businesses`, which also grants the Head of Operations its preset.

const { values } = parseArgs({
  options: {
    name: { type: "string" },
    out: { type: "string" },
    person: { type: "string" },
    // Sign in as the earliest active person (the owner), creating them if there is none.
    owner: { type: "boolean" },
    // A deployed stage's Postgres URL; defaults to the local development database.
    "database-url": { type: "string" },
  },
});
if (!values.name || !values.out)
  throw new Error("Pass --name and --out (private access-code file).");
const db = { connectionString: values["database-url"] ?? databaseUrl() };
const owner = values.owner
  ? await (async () => {
      const client = new pg.Client(db);
      await client.connect();
      try {
        return (
          await client.query<{ id: string }>(
            "SELECT id FROM people WHERE revoked_at IS NULL ORDER BY created_at LIMIT 1",
          )
        ).rows[0]?.id;
      } finally {
        await client.end();
      }
    })()
  : undefined;
const personId = values.person ?? owner ?? randomUUID();
const token = Array.from(randomBytes(32), (byte) => byte.toString(16).padStart(2, "0")).join("");
await writeFile(values.out, `${token}\n`, { mode: 0o600, flag: "wx" });
try {
  await Effect.runPromise(
    issueEnrollment(db, {
      personId,
      name: values.name,
      tokenHash: createHash("sha256").update(token).digest("hex"),
    }),
  );
  console.log(
    `Person ${personId} enrolled. One-time access code written to ${values.out}; expires in one hour.`,
  );
} catch (error) {
  await rm(values.out, { force: true });
  throw error;
}
