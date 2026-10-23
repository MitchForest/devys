import { createHash, randomBytes } from "node:crypto";
import { parseArgs } from "node:util";
import { Effect } from "effect";
import { issueOwnerLink } from "../src/identity/sessions.ts";
import { databaseUrl } from "./db.ts";

// A one-time link that signs a browser in as the first person (created with --name if there is
// none yet), valid ten minutes, for a deployment without a Mac to sign in from (a cloud stage).
// Local mode needs none: `bun run local install` opens the Mac app, which signs itself in.

const { values } = parseArgs({
  options: {
    name: { type: "string" },
    // The deployment's address, which the link opens.
    url: { type: "string" },
    // A deployed stage's Postgres URL; defaults to the local development database.
    "database-url": { type: "string" },
  },
});
if (!values.name || !values.url) throw new Error("Pass --name and --url.");
const token = Buffer.from(randomBytes(32)).toString("hex");
await Effect.runPromise(
  issueOwnerLink(
    { connectionString: values["database-url"] ?? databaseUrl() },
    { tokenHash: createHash("sha256").update(token).digest("hex"), name: values.name },
  ),
);
console.log(`${new URL("/", values.url).href}#signin=${token}`);
