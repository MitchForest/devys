import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { agentDependencies } from "../src/app/agent.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { apiRoute } from "../src/app/http.ts";
import { grant } from "../src/authority/service.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);
const named = (name: string) => catalog.find((item) => item.name === name)!;

async function signedIn(person: string) {
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  return async (path: string, init: RequestInit = {}) =>
    (await apiRoute(
      new Request(`https://devys.test${path}`, {
        ...init,
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      }),
      bindings,
    )) ?? new Response(null, { status: 404 });
}

it("a new business's Head of Operations starts with the operations preset", async () => {
  const person = crypto.randomUUID();
  await sql.run("INSERT INTO people (id, display_name) VALUES ($1, 'Owner')", [person]);
  const as = await signedIn(person);
  const created = (await (
    await as("/api/businesses", { method: "POST", body: JSON.stringify({ name: "Acme" }) })
  ).json()) as { business: { id: string }; operations: { id: string } };
  const access = (await (
    await as(`/api/businesses/${created.business.id}/employees/${created.operations.id}/access`)
  ).json()) as {
    grants: { capability: string; mode: string; effect: string }[];
    available: unknown[];
  };
  expect(access.grants.map((g) => g.capability).sort()).toEqual(catalog.map((c) => c.name).sort());
  // Every capability runs on its own except hiring, production deploys and activating a
  // routine, which the owner approves each time.
  expect(
    access.grants
      .filter((g) => g.mode !== "auto")
      .map((g) => g.capability)
      .sort(),
  ).toEqual(["deployProduction", "hireEmployee", "routineActivate"]);
  expect(access.grants.find((g) => g.capability === "driveCreate")?.effect).toBe("external");
  expect(access.available).toEqual([]);
});

it("authorization re-reads grants: none denies, ask asks, revocation applies to the next call", async () => {
  const { scope } = await business();
  const { authorize } = agentDependencies(bindings);
  const remember = named("remember");
  expect((await authorize(scope, remember, {}, {})).outcome).toBe("deny");
  const granted = await Effect.runPromise(grant(db, scope, { capability: remember, mode: "ask" }));
  expect(await authorize(scope, remember, {}, {})).toMatchObject({
    outcome: "ask",
    grantId: granted.id,
    decisionId: expect.any(String),
  });
  const replaced = await Effect.runPromise(
    grant(db, scope, { capability: remember, mode: "auto" }),
  );
  expect(replaced.id).not.toBe(granted.id);
  expect(await authorize(scope, remember, {}, {})).toEqual({
    outcome: "allow",
    grantId: replaced.id,
  });
  await sql.run("UPDATE grants SET revoked_at = now() WHERE id = $1", [replaced.id]);
  expect((await authorize(scope, remember, {}, {})).outcome).toBe("deny");
  // Another business's identical employee scope shape gets nothing from this grant.
  const other = await business();
  expect((await authorize(other.scope, remember, {}, {})).outcome).toBe("deny");
});

it("the owner grants with limits, the limits narrow, and revocation removes access", async () => {
  const { person, scope } = await business();
  const as = await signedIn(person);
  const path = `/api/businesses/${scope.businessId}/employees/${scope.employeeId}/access`;
  expect(
    (await as(path, { method: "POST", body: JSON.stringify({ capability: "nope", mode: "auto" }) }))
      .status,
  ).toBe(400);
  expect(
    (
      await as(path, {
        method: "POST",
        body: JSON.stringify({
          capability: "remember",
          mode: "auto",
          constraints: { hosts: ["x"] },
        }),
      })
    ).status,
  ).toBe(400);
  const created = await as(path, {
    method: "POST",
    body: JSON.stringify({
      capability: "readPublicUrl",
      mode: "auto",
      constraints: { hosts: ["acme.example"] },
    }),
  });
  expect(created.status).toBe(201);
  const { id } = (await created.json()) as { id: string };
  const { authorize } = agentDependencies(bindings);
  const read = named("readPublicUrl");
  expect((await authorize(scope, read, { url: "https://acme.example/x" }, {})).outcome).toBe(
    "allow",
  );
  expect((await authorize(scope, read, { url: "https://example.com" }, {})).outcome).toBe("deny");
  expect((await as(`${path}/${id}/revoke`, { method: "POST" })).status).toBe(200);
  expect((await as(`${path}/${id}/revoke`, { method: "POST" })).status).toBe(404);
  expect((await authorize(scope, read, { url: "https://acme.example/x" }, {})).outcome).toBe(
    "deny",
  );
});

it("pausing marks the employee paused until resumed", async () => {
  const { person, scope } = await business();
  const as = await signedIn(person);
  const employee = `/api/businesses/${scope.businessId}/employees/${scope.employeeId}`;
  const { employee: lookup } = agentDependencies(bindings);
  expect((await lookup(scope))?.paused).toBe(false);
  // Pause stops running work through the agent; with no Durable Object binding here,
  // check the record directly instead of calling the route.
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [scope.employeeId]);
  expect((await lookup(scope))?.paused).toBe(true);
  const team = (await (await as(`/api/businesses/${scope.businessId}`)).json()) as {
    employees: { paused: boolean }[];
  };
  expect(team.employees[0]?.paused).toBe(true);
  const send = await as(
    `/api/businesses/${scope.businessId}/conversations/direct:${scope.employeeId}/messages`,
    {
      method: "POST",
      body: JSON.stringify({ id: "paused-message-1", text: "Are you there?" }),
    },
  );
  expect(send.status).toBe(409);
  expect((await as(`${employee}/resume`, { method: "POST" })).status).toBe(200);
  expect((await lookup(scope))?.paused).toBe(false);
});
