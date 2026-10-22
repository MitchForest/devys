import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { business, db, sql } from "./fixtures/postgres.ts";
import type { Env } from "../infra/api.ts";
import {
  beginGoogle,
  finishGoogle,
  googleAccess,
  disconnectGoogle,
  driveScope,
  googleConnection,
} from "../src/connections/google.ts";
import { listDrive, readDrive, selectDrive, writeDrive } from "../src/apps/documents/drive.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import type { SendWithSecret } from "../src/vault/contract.ts";
import { envelopeKeyring } from "../src/vault/envelope.ts";
import { vaultHost } from "../src/vault/host/server.ts";
import { postgresSecrets } from "../src/vault/store.ts";
const config = {
  HYPERDRIVE: db,
  GOOGLE_CLIENT_ID: "test-client",
  GOOGLE_CLIENT_SECRET: "test-secret",
  PUBLIC_URL: "https://devys.example",
} as unknown as Env;
// The refresh token lives in the vault; the host (here, its route in process) sends Google's
// token and revoke requests with it, so what the Worker sees never holds it.
const keyring = await envelopeKeyring(crypto.getRandomValues(new Uint8Array(32)));
const secrets = postgresSecrets(db, keyring);
const sentToGoogle: string[] = [];
const send: SendWithSecret = async (secret, request, placeholder) =>
  (await vaultHost(keyring).handle("/vault/request", {
    secret,
    request,
    placeholder,
  })) as Awaited<ReturnType<SendWithSecret>>;
const vault = { secrets, send };
const drive = { db, connection: googleConnection(config, vault) };
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
  await sql.run("INSERT INTO google_connections(business_id,id,connected_by) VALUES($1,$2,$3)", [
    owner,
    grant,
    person,
  ]);
  await secrets.put(owner, "google", "connection", "private-refresh", person);
  sentToGoogle.length = 0;
});
afterEach(() => vi.restoreAllMocks());
const member = async (businessId: string) => businessId === owner;
/** Google's side: records each token or revoke request's body, as the host sent it. */
const google = (answer: (url: string) => Promise<Response> | Response) =>
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (/\/(token|revoke)$/.test(url)) sentToGoogle.push(String(init?.body ?? ""));
    return answer(url);
  });
it("the refresh token is in the vault: only the host's request carries it, and only for its business", async () => {
  const row = await sql.row<{ ciphertext: string; kind: string }>(
    "SELECT ciphertext, kind FROM secrets WHERE business_id=$1 AND name='google'",
    [owner],
  );
  expect(row).toMatchObject({ kind: "connection" });
  expect(row!.ciphertext).not.toContain("private-refresh");
  // Connection credentials are not the owner's secrets: not listed, and not runnable.
  expect(await secrets.list(owner)).toEqual([]);
  await expect(secrets.sealed(owner, ["google"], ["secret", "spend"])).rejects.toThrow(/No secret/);
  google((url) => (url.endsWith("/token") ? tokens() : new Response(null, { status: 404 })));
  const access = await googleAccess(config, vault, owner);
  expect(access).toEqual({ id: grant, token: "private-access" });
  expect(sentToGoogle[0]).toContain("refresh_token=private-refresh");
  // Another business's token never opens in this business's name.
  const [sealed] = await secrets.sealed(owner, ["google"], ["connection"]);
  await expect(
    send(
      { ...sealed!, business: "other-business" },
      { url: "https://oauth2.googleapis.com/token", method: "POST", headers: {}, body: "" },
      "devys-google-placeholder-0000",
    ),
  ).rejects.toThrow(/could not be opened/);
  // An answer that echoes the token comes back without it.
  google(() => new Response("you sent private-refresh", { status: 400 }));
  const echoed = await send(
    sealed!,
    {
      url: "https://oauth2.googleapis.com/token",
      method: "POST",
      headers: {},
      body: "t=devys-google-placeholder-0000",
    },
    "devys-google-placeholder-0000",
  );
  expect(echoed.body).toBe("you sent [redacted]");
});
it("disconnect prevents an in-flight refresh from restoring access", async () => {
  google(async (input) => {
    if (String(input).endsWith("/token")) {
      await sql.run("DELETE FROM google_connections WHERE business_id=$1", [owner]);
      return tokens();
    }
    throw new Error("Unexpected request");
  });
  await expect(googleAccess(config, vault, owner)).rejects.toThrow("Connection changed");
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
  expect((await finishGoogle(new Request(callback), config, vault, person, member)).status).toBe(
    400,
  );
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("/token")) {
      await disconnectGoogle(config, vault, owner);
      return tokens();
    }
    if (String(input).endsWith("/revoke")) return new Response(null, { status: 200 });
    throw new Error("Unexpected request");
  });
  expect(
    (await finishGoogle(new Request(callback, { headers }), config, vault, person, member)).status,
  ).toBe(409);
  expect(
    (await finishGoogle(new Request(callback, { headers }), config, vault, person, member)).status,
  ).toBe(400);
  expect(
    await sql.row("SELECT id FROM google_connections WHERE business_id=$1", [owner]),
  ).toBeUndefined();
});
it("selection checks provider permission, isolates businesses, and disconnect removes selected files", async () => {
  google(async (input) => {
    const url = String(input);
    if (url.endsWith("/token")) return tokens();
    if (url.endsWith("/revoke")) return new Response(null);
    if (url.includes("/files/allowed?"))
      return response({ id: "allowed", name: "Chosen", mimeType: "text/plain" });
    return new Response(null, { status: 403 });
  });
  await expect(selectDrive(drive, owner, ["denied"])).rejects.toThrow();
  await selectDrive(drive, owner, ["allowed"]);
  expect(await listDrive(db, owner)).toHaveLength(1);
  expect(await listDrive(db, "other-owner")).toEqual([]);
  await expect(readDrive(drive, owner, "unselected")).rejects.toThrow("Choose this file");
  expect(await disconnectGoogle(config, vault, owner)).toEqual({
    disconnected: true,
    revoked: true,
  });
  // The revoke carried the token; the vault no longer holds it.
  expect(sentToGoogle.at(-1)).toBe("token=private-refresh");
  expect(
    await sql.row("SELECT 1 FROM secrets WHERE business_id=$1 AND name='google'", [owner]),
  ).toBeUndefined();
  expect(await listDrive(db, owner)).toEqual([]);
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
  expect((await writeDrive(drive, owner, "create", input, async () => {})).status).toBe(
    "uncertain",
  );
  expect((await readDrive(drive, owner, "created-file")).content).toBe("saved text");
  expect((await writeDrive(drive, owner, "create", input, async () => {})).status).toBe(
    "completed",
  );
  expect(uploads).toBe(1);
  await expect(
    writeDrive(drive, owner, "create", { ...input, content: "changed" }, async () => {}),
  ).rejects.toThrow("different inputs");
  expect(await listDrive(db, owner)).toHaveLength(1);
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
  await selectDrive(drive, owner, ["selected"]);
  await expect(
    writeDrive(
      drive,
      owner,
      "stale",
      { id: "selected", content: "update", etag: '"v1"' },
      async () => {},
    ),
  ).rejects.toThrow("File changed");
  await expect(
    writeDrive(
      drive,
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
  const other = (await business("Other drive")).business.id,
    otherGrant = crypto.randomUUID();
  await sql.run("INSERT INTO google_connections(business_id,id,connected_by) VALUES($1,$2,$3)", [
    other,
    otherGrant,
    person,
  ]);
  await secrets.put(other, "google", "connection", "other-refresh", person);
  let fileReads = 0;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("/token")) return tokens();
    fileReads++;
    return response({ id: "private", name: "Private text", mimeType: "text/plain" });
  });
  await selectDrive(drive, owner, ["private"]);
  await expect(readDrive(drive, other, "private")).rejects.toThrow("Choose this file");
  expect(fileReads).toBe(1);
});
