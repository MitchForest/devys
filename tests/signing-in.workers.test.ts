/**
 * Signing in without codes (.docs/AUTHORITY.md "Signing in"): the Mac app as the Mac's owner with
 * the key only the owner's macOS user can read, a browser with a one-time link, and any other
 * device by asking to join and being allowed from a signed-in one.
 */
import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { beforeEach, expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { apiRoute } from "../src/app/http.ts";
import { endorsementPayload } from "../src/authority/signing.ts";
import { joinMatch, matchEmoji } from "../src/identity/joins.ts";
import { logout, requestPerson } from "../src/identity/http.ts";
import { isMachineOwner } from "../src/identity/service.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { db, sql } from "./fixtures/postgres.ts";
import { deviceKey } from "./fixtures/signing.ts";

const origin = "https://devys.test";
const ownerKey = "a".repeat(64);
const cloud = env as unknown as Env;
const local = {
  ...cloud,
  DEVYS_MODE: "local",
  DEVYS_OWNER_KEY: ownerKey,
  DEVYS_MACHINE_NAME: "Sam's Mac mini",
} as unknown as Env;

const hex = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");

const call = (
  path: string,
  init: { body?: unknown; bearer?: string; cookie?: string; method?: string } = {},
  bindings = local,
) =>
  apiRoute(
    new Request(`${origin}${path}`, {
      method: init.method ?? (init.body === undefined ? "GET" : "POST"),
      headers: {
        "content-type": "application/json",
        ...(init.bearer ? { authorization: `Bearer ${init.bearer}` } : {}),
        ...(init.cookie ? { cookie: `__Host-devys=${init.cookie}`, origin } : {}),
      },
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
    }),
    bindings,
  ).then((response) => response!);

async function person(name = "Member") {
  const id = crypto.randomUUID();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, $2)", [id, name]);
  return id;
}

/** A signed-in device of a person: its bearer token. */
async function signedIn(personId: string, label = "Mac") {
  const token = hex();
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', $3)",
    [await sha256(token), personId, label],
  );
  return token;
}

/** A device asking to join with a session token of its own choosing. */
async function ask(name: string, publicKey?: string) {
  const token = hex();
  const response = await call("/api/joins", {
    body: {
      name,
      session_hash: await sha256(token),
      ...(publicKey ? { public_key: publicKey } : {}),
    },
  });
  return { response, token };
}

const status = async (id: string, token: string) =>
  ((await (await call(`/api/joins/${id}`, { bearer: token })).json()) as { status: string }).status;

// Join requests are not scoped to a business; besides this file only the wire test makes one.
beforeEach(() => sql.run("DELETE FROM join_requests WHERE name NOT LIKE 'Wire %'"));

it("the Mac app signs in as the Mac's owner with the owner key, and only with it", async () => {
  expect(await (await call("/api/hello")).json()).toMatchObject({ name: "Sam's Mac mini" });
  const wrong = await call("/api/local/session", { body: { key: "b".repeat(64), name: "Sam" } });
  expect(wrong.status).toBe(404);
  // Cloud mode has no Mac and no owner key.
  expect(
    (await call("/api/local/session", { body: { key: ownerKey, name: "Sam" } }, cloud)).status,
  ).toBe(404);
  const response = await call("/api/local/session", {
    body: { key: ownerKey, name: "Sam", label: "Sam's Mac mini" },
  });
  expect(response.status).toBe(200);
  expect(response.headers.get("set-cookie")).toBeNull();
  const { session_token } = (await response.json()) as { session_token: string };
  const signedIn = await requestPerson(
    new Request(`${origin}/api/me`, { headers: { authorization: `Bearer ${session_token}` } }),
    local,
  );
  // The first person is the Mac's owner; a second sign-in is the same person, a new device.
  expect(await Effect.runPromise(isMachineOwner(db, signedIn!.person.id))).toBe(true);
  const again = (await (
    await call("/api/local/session", { body: { key: ownerKey, name: "Someone else" } })
  ).json()) as { session_token: string };
  const second = await requestPerson(
    new Request(`${origin}/api/me`, {
      headers: { authorization: `Bearer ${again.session_token}` },
    }),
    local,
  );
  expect(second!.person.id).toBe(signedIn!.person.id);
  expect(second!.device).not.toBe(signedIn!.device);
});

it("a one-time link signs a browser in once, and a signed-in app makes one for itself", async () => {
  const owner = await person("Sam");
  const app = await signedIn(owner);
  // Only from the app itself (bearer) or the same origin.
  const issued = await call("/api/devices/link", { body: {}, bearer: app });
  expect(issued.status).toBe(201);
  const { token } = (await issued.json()) as { token: string };
  const redeem = () =>
    apiRoute(
      new Request(`${origin}/api/link`, {
        method: "POST",
        headers: { origin, "content-type": "application/json" },
        body: JSON.stringify({ token }),
      }),
      local,
    ).then((response) => response!);
  const first = await redeem();
  expect(first.status).toBe(200);
  const session = /__Host-devys=([a-f0-9]{64})/.exec(first.headers.get("set-cookie") ?? "")![1]!;
  expect(
    (await requestPerson(
      new Request(`${origin}/api/me`, { headers: { cookie: `__Host-devys=${session}` } }),
      local,
    ))!.person.id,
  ).toBe(owner);
  expect((await redeem()).status).toBe(401);
  // Cross-site, refused before anything is read.
  const crossSite = await apiRoute(
    new Request(`${origin}/api/link`, {
      method: "POST",
      headers: { origin: "https://evil.test" },
      body: JSON.stringify({ token }),
    }),
    local,
  );
  expect(crossSite!.status).toBe(403);
});

it("both screens show the same two emoji, derived from the request", async () => {
  expect(new Set(matchEmoji).size).toBe(64);
  const hash = await sha256("session");
  const pair = await joinMatch("4b7c1d0e-0000-4000-8000-000000000000", hash);
  expect(pair).toEqual(await joinMatch("4b7c1d0e-0000-4000-8000-000000000000", hash));
  expect(pair[0]).not.toBe(pair[1]);
  expect(pair).not.toEqual(await joinMatch("4b7c1d0e-0000-4000-8000-000000000001", hash));

  const owner = await person("Sam");
  const mac = await signedIn(owner);
  const { response } = await ask("Sam's iPhone");
  expect(response.status).toBe(201);
  const asked = (await response.json()) as { id: string; match: string[]; name: string };
  const waiting = (await (await call("/api/joins", { bearer: mac })).json()) as {
    joins: { id: string; match: string[]; name: string }[];
  };
  expect(waiting.joins).toEqual([expect.objectContaining({ id: asked.id, name: "Sam's iPhone" })]);
  expect(waiting.joins[0]!.match).toEqual(asked.match);
});

it("allowed from a signed-in device, the asking device's own token becomes its session", async () => {
  const owner = await person("Sam");
  const mac = await signedIn(owner);
  const { response, token } = await ask("Sam's iPhone");
  const { id } = (await response.json()) as { id: string };
  expect(await status(id, token)).toBe("pending");
  // Its status is for it alone: another token learns nothing.
  expect((await call(`/api/joins/${id}`, { bearer: hex() })).status).toBe(404);
  // Nobody signed in cannot answer, nor can the asking device itself.
  expect((await call(`/api/joins/${id}/allow`, { body: {} })).status).toBe(401);
  expect((await call(`/api/joins/${id}/allow`, { body: {}, bearer: token })).status).toBe(401);
  expect((await call("/api/me", { bearer: token })).status).toBe(401);
  const allowed = await call(`/api/joins/${id}/allow`, { body: {}, bearer: mac });
  expect(allowed.status).toBe(200);
  expect(await allowed.json()).toEqual({ key: null });
  expect(await status(id, token)).toBe("allowed");
  const me = (await (await call("/api/me", { bearer: token })).json()) as {
    person: { id: string };
  };
  expect(me.person.id).toBe(owner);
  const devices = (await (await call("/api/devices", { bearer: mac })).json()) as {
    devices: { label: string | null }[];
  };
  expect(devices.devices.map((device) => device.label)).toContain("Sam's iPhone");
  // Answered once: a second answer changes nothing.
  expect((await call(`/api/joins/${id}/deny`, { body: {}, bearer: mac })).status).toBe(409);
  expect((await call(`/api/joins`, { bearer: mac }).then((r) => r.json())) as unknown).toEqual({
    joins: [],
  });
  // Signing the device out ends the session it chose.
  await logout(
    new Request(`${origin}/api/logout`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
    }),
    local,
  );
  expect((await call("/api/me", { bearer: token })).status).toBe(401);
});

it("a browser trades its allowed token for its cookie, only on the same origin", async () => {
  const owner = await person("Sam");
  const mac = await signedIn(owner);
  const { response, token } = await ask("Safari on iPad");
  const { id } = (await response.json()) as { id: string };
  const cookie = (from = origin) =>
    apiRoute(
      new Request(`${origin}/api/joins/${id}/cookie`, {
        method: "POST",
        headers: { origin: from, "content-type": "application/json" },
        body: JSON.stringify({ token }),
      }),
      local,
    ).then((r) => r!);
  expect((await cookie()).status).toBe(403);
  await call(`/api/joins/${id}/allow`, { body: {}, bearer: mac });
  expect((await cookie("https://evil.test")).status).toBe(403);
  const signed = await cookie();
  expect(signed.status).toBe(200);
  expect(signed.headers.get("set-cookie")).toContain(`__Host-devys=${token}`);
});

it("denied or expired, the device is not signed in and no one is asked again", async () => {
  const owner = await person("Sam");
  const mac = await signedIn(owner);
  const denied = await ask("Stranger's phone");
  const deniedId = ((await denied.response.json()) as { id: string }).id;
  expect((await call(`/api/joins/${deniedId}/deny`, { body: {}, bearer: mac })).status).toBe(200);
  expect(await status(deniedId, denied.token)).toBe("denied");
  expect((await call("/api/me", { bearer: denied.token })).status).toBe(401);

  const late = await ask("Late phone");
  const lateId = ((await late.response.json()) as { id: string }).id;
  await sql.run("UPDATE join_requests SET expires_at = now() - interval '1 second' WHERE id = $1", [
    lateId,
  ]);
  expect(await status(lateId, late.token)).toBe("expired");
  expect((await call(`/api/joins/${lateId}/allow`, { body: {}, bearer: mac })).status).toBe(409);
  expect((await call("/api/me", { bearer: late.token })).status).toBe(401);
  expect(
    ((await (await call("/api/joins", { bearer: mac })).json()) as { joins: unknown[] }).joins,
  ).toEqual([]);
});

it("a stranger cannot flood the screens: at most five requests wait at once", async () => {
  for (let index = 0; index < 5; index++)
    expect((await ask(`Phone ${index}`)).response.status).toBe(201);
  expect((await ask("One more")).response.status).toBe(429);
  expect((await call("/api/joins", { body: { name: "No hash" } })).status).toBe(400);
});

it("allowed by an app that approves spending, the new app's key is enrolled for it to endorse", async () => {
  const owner = await person("Sam");
  const mac = await signedIn(owner);
  const [macKey, phoneKey] = [await deviceKey(), await deviceKey()];
  const first = (await (
    await call("/api/device-keys", { body: { public_key: macKey.publicKey }, bearer: mac })
  ).json()) as { id: string; status: string };
  expect(first.status).toBe("active");
  const { response, token } = await ask("Sam's iPhone", phoneKey.publicKey);
  const { id } = (await response.json()) as { id: string };
  const answered = (await (
    await call(`/api/joins/${id}/allow`, { body: {}, bearer: mac })
  ).json()) as { key: { id: string; status: string; device: string; label: string } };
  const phoneDevice = (await sha256(token)).slice(0, 16);
  expect(answered.key).toMatchObject({
    status: "pending",
    device: phoneDevice,
    label: "Sam's iPhone",
  });
  // The Mac signs it at once (Touch ID there), and the iPhone's key approves spending.
  const endorsed = await call(`/api/device-keys/${answered.key.id}/endorse`, {
    body: {
      key_id: first.id,
      signature: await macKey.sign(
        endorsementPayload({
          person: owner,
          key: answered.key.id,
          device: phoneDevice,
          publicKey: phoneKey.publicKey,
        }),
      ),
    },
    bearer: mac,
  });
  expect(endorsed.status).toBe(200);
  const mine = (await (await call("/api/device-keys", { bearer: token })).json()) as {
    keys: { status: string; current: boolean }[];
  };
  expect(mine.keys.find((key) => key.current)).toMatchObject({ status: "active" });
});
