import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { business, db, sql } from "./fixtures/postgres.ts";
import type { Env } from "../infra/api.ts";
import {
  beginGoogle,
  finishGoogle,
  googleAccess,
  disconnectGoogle,
  protect,
  driveScope,
} from "../src/connections/google.ts";
import { listDrive, readDrive, selectDrive, writeDrive } from "../src/connections/drive.ts";
import { sha256 } from "../src/protocol/bytes.ts";
const config = {
  HYPERDRIVE: db,
  GOOGLE_CLIENT_ID: "test-client",
  GOOGLE_CLIENT_SECRET: "test-secret",
  CONNECTIONS_KEY: "12".repeat(32),
  PUBLIC_URL: "https://devys.example",
} as Env;
// `owner` is the business that holds the connection; `person` is the member who connected it.
let owner: string, person: string, grant: string;
const session = "ab".repeat(32);
const response = (body: unknown, headers = {}) => Response.json(body, { headers });
const tokens = () =>
  response({
    access_token: "private-access",
    token_type: "Bearer",
    expires_in: 3600,
    scope: driveScope,
    refresh_token: "private-refresh",
  });
beforeEach(async () => {
  const created = await business("Drive test");
  owner = created.business.id;
  person = created.person;
  grant = crypto.randomUUID();
  await sql.run(
    "INSERT INTO google_connections(business_id,id,refresh_token,connected_by) VALUES($1,$2,$3,$4)",
    [owner, grant, await protect(config, owner, grant, "private-refresh"), person],
  );
});
afterEach(() => vi.restoreAllMocks());
const member = async (businessId: string) => businessId === owner;
it("encrypted grants cannot be decrypted for another owner or connection", async () => {
  const encrypted = await protect(config, owner, grant, "secret");
  expect(encrypted).not.toContain("secret");
  expect(await protect(config, owner, grant, encrypted, true)).toBe("secret");
  await expect(protect(config, "other", grant, encrypted, true)).rejects.toThrow();
  await expect(protect(config, owner, "other", encrypted, true)).rejects.toThrow();
});
it("disconnect prevents an in-flight refresh from restoring access", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("/token")) {
      await sql.run("DELETE FROM google_connections WHERE business_id=$1", [owner]);
      return tokens();
    }
    throw new Error("Unexpected request");
  });
  await expect(googleAccess(config, owner)).rejects.toThrow("Connection changed");
  expect(
    await sql.row("SELECT id FROM google_connections WHERE business_id=$1", [owner]),
  ).toBeUndefined();
});
it("OAuth state binds the owner and session and disconnect invalidates a callback already exchanging tokens", async () => {
  const sessionHash = await sha256(session);
  await sql.run(
    "INSERT INTO web_sessions(token_hash,person_id,expires_at) VALUES($1,$2,'2999-01-01T00:00:00.000Z')",
    [sessionHash, person],
  );
  const headers = { cookie: `__Host-devys=${session}` };
  const start = await beginGoogle(
    new Request(config.PUBLIC_URL, { headers }),
    config,
    owner,
    person,
  );
  const { url } = (await start.json()) as { url: string };
  const auth = new URL(url);
  expect(auth.searchParams.get("scope")).toBe(driveScope);
  expect(auth.searchParams.get("code_challenge_method")).toBe("S256");
  const callback = `${config.PUBLIC_URL}/api/connections/google/callback?code=code&state=${auth.searchParams.get("state")}`;
  expect((await finishGoogle(new Request(callback), config, person, member)).status).toBe(400);
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("/token")) {
      await disconnectGoogle(config, owner);
      return tokens();
    }
    if (String(input).endsWith("/revoke")) return new Response(null, { status: 200 });
    throw new Error("Unexpected request");
  });
  expect(
    (await finishGoogle(new Request(callback, { headers }), config, person, member)).status,
  ).toBe(409);
  expect(
    (await finishGoogle(new Request(callback, { headers }), config, person, member)).status,
  ).toBe(400);
  expect(
    await sql.row("SELECT id FROM google_connections WHERE business_id=$1", [owner]),
  ).toBeUndefined();
});
it("selection checks provider permission, isolates businesses, and disconnect removes selected files", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = String(input);
    if (url.endsWith("/token")) return tokens();
    if (url.endsWith("/revoke")) return new Response(null);
    if (url.includes("/files/allowed?"))
      return response({ id: "allowed", name: "Chosen", mimeType: "text/plain" });
    return new Response(null, { status: 403 });
  });
  await expect(selectDrive(config, owner, ["denied"])).rejects.toThrow();
  await selectDrive(config, owner, ["allowed"]);
  expect(await listDrive(config, owner)).toHaveLength(1);
  expect(await listDrive(config, "other-owner")).toEqual([]);
  await expect(readDrive(config, owner, "unselected")).rejects.toThrow("Choose this file");
  expect(await disconnectGoogle(config, owner)).toEqual({ disconnected: true, revoked: true });
  expect(await listDrive(config, owner)).toEqual([]);
});
it("an uncertain create is inspected without uploading twice and changed inputs cannot reuse its receipt", async () => {
  let uploads = 0;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = String(input);
    if (url.endsWith("/token")) return tokens();
    if (url.includes("generateIds")) return response({ ids: ["created-file"] });
    if (url.includes("/upload/")) {
      uploads++;
      throw new Error("Connection lost after Google accepted the file");
    }
    if (url.includes("alt=media")) return new Response("saved text");
    if (url.includes("/files/created-file?"))
      return response(
        { id: "created-file", name: "Result", mimeType: "text/plain", version: "1" },
        { etag: '"v1"' },
      );
    throw new Error("Unexpected request");
  });
  const input = { name: "Result", content: "saved text" };
  expect((await writeDrive(config, owner, "create", input, async () => {})).status).toBe(
    "uncertain",
  );
  expect((await readDrive(config, owner, "created-file")).content).toBe("saved text");
  expect((await writeDrive(config, owner, "create", input, async () => {})).status).toBe(
    "completed",
  );
  expect(uploads).toBe(1);
  await expect(
    writeDrive(config, owner, "create", { ...input, content: "changed" }, async () => {}),
  ).rejects.toThrow("different inputs");
  expect(await listDrive(config, owner)).toHaveLength(1);
});
it("stale revisions and cancelled operations cannot issue an update", async () => {
  let writes = 0;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = String(input);
    if (url.endsWith("/token")) return tokens();
    if (url.includes("/upload/")) writes++;
    return response(
      { id: "selected", name: "Text", mimeType: "text/plain", version: "2" },
      { etag: '"v2"' },
    );
  });
  await selectDrive(config, owner, ["selected"]);
  await expect(
    writeDrive(
      config,
      owner,
      "stale",
      { id: "selected", content: "update", etag: '"v1"' },
      async () => {},
    ),
  ).rejects.toThrow("File changed");
  await expect(
    writeDrive(
      config,
      owner,
      "cancelled",
      { id: "selected", content: "update", etag: '"v2"' },
      async () => {
        throw new Error("Stopped");
      },
    ),
  ).rejects.toThrow("Stopped");
  expect(writes).toBe(0);
});

it("a second connected business cannot read another business's selected file", async () => {
  const other = crypto.randomUUID(),
    otherGrant = crypto.randomUUID();
  await sql.run(
    "INSERT INTO google_connections(business_id,id,refresh_token,connected_by) VALUES($1,$2,$3,$4)",
    [other, otherGrant, await protect(config, other, otherGrant, "other-refresh"), person],
  );
  let fileReads = 0;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("/token")) return tokens();
    fileReads++;
    return response({ id: "private", name: "Private text", mimeType: "text/plain" });
  });
  await selectDrive(config, owner, ["private"]);
  await expect(readDrive(config, other, "private")).rejects.toThrow("Choose this file");
  expect(fileReads).toBe(1);
});
