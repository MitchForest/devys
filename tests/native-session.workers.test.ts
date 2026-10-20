import { env } from "cloudflare:workers";
import { sql } from "./fixtures/postgres.ts";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { enrollDevice, logout, requestPerson } from "../src/identity/http.ts";
import { sha256 } from "../src/protocol/bytes.ts";

const bindings = env as unknown as Env;
const origin = "https://devys.test";
const hex = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");

async function enrollment() {
  const owner = crypto.randomUUID();
  const code = hex();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, 'Native')", [owner]);
  await sql.run(
    "INSERT INTO enrollment_tokens (token_hash, person_id, expires_at) VALUES ($1, $2, '2999-01-01T00:00:00.000Z')",
    [await sha256(code), owner],
  );
  return { owner, code };
}

const exchange = (code: string) =>
  enrollDevice(
    new Request(`${origin}/api/native/session`, {
      method: "POST",
      body: JSON.stringify({ token: code }),
    }),
    bindings,
  );

const bearer = (token: string, headers: Record<string, string> = {}) =>
  new Request(`${origin}/api/status`, {
    headers: { authorization: `Bearer ${token}`, ...headers },
  });

it("exchanges a one-time code for a bearer session that authorizes without a browser origin", async () => {
  const { owner, code } = await enrollment();
  const response = await exchange(code);
  expect(response.headers.get("set-cookie")).toBeNull();
  const { sessionToken } = (await response.json()) as { sessionToken: string };
  expect(await requestPerson(bearer(sessionToken), bindings)).toMatchObject({
    person: { id: owner },
    bearer: true,
  });
  expect((await exchange(code)).status).toBe(401);
});

it("judges an Authorization header alone, never falling back to the cookie", async () => {
  const { code } = await enrollment();
  const { sessionToken } = (await (await exchange(code)).json()) as { sessionToken: string };
  const forged = bearer("0".repeat(64), { cookie: `__Host-devys=${sessionToken}` });
  expect(await requestPerson(forged, bindings)).toBeUndefined();
  const malformed = new Request(`${origin}/api/status`, {
    headers: { authorization: "Basic abc", cookie: `__Host-devys=${sessionToken}` },
  });
  expect(await requestPerson(malformed, bindings)).toBeUndefined();
  const browser = new Request(`${origin}/api/status`, {
    headers: { cookie: `__Host-devys=${sessionToken}` },
  });
  expect(await requestPerson(browser, bindings)).toMatchObject({ bearer: false });
});

it("signs a device out by revoking only its bearer session", async () => {
  const { code } = await enrollment();
  const { sessionToken } = (await (await exchange(code)).json()) as { sessionToken: string };
  const signedOut = await logout(
    new Request(`${origin}/api/logout`, {
      method: "POST",
      headers: { authorization: `Bearer ${sessionToken}` },
    }),
    bindings,
  );
  expect(signedOut.status).toBe(200);
  expect(signedOut.headers.get("set-cookie")).toBeNull();
  expect(await requestPerson(bearer(sessionToken), bindings)).toBeUndefined();
});
