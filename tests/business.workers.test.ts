import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { Effect } from "effect";
import { capabilities } from "../src/app/capabilities.ts";
import { apiRoute } from "../src/app/http.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { business, sql } from "./fixtures/postgres.ts";

const origin = "https://devys.test";

/** A signed-in device for this person. */
async function session(person: string) {
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  return (path: string, init: RequestInit = {}) =>
    apiRoute(
      new Request(`${origin}${path}`, {
        ...init,
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
          ...init.headers,
        },
      }),
      env as unknown as Env,
    ).then((response) => response ?? new Response(null, { status: 404 }));
}

it("a person sees only their businesses and can create one staffed with a Head of Operations", async () => {
  const acme = await business("Acme");
  await business("Someone else's");
  const as = await session(acme.person);
  const me = (await (await as("/api/me")).json()) as { businesses: { name: string }[] };
  expect(me.businesses.map((b) => b.name)).toEqual(["Acme"]);
  const created = await as("/api/businesses", {
    method: "POST",
    body: JSON.stringify({ name: "Globex" }),
  });
  expect(created.status).toBe(201);
  const { business: globex, operations } = (await created.json()) as {
    business: { id: string };
    operations: { name: string };
  };
  expect(operations.name).toBe("Head of Operations");
  const after = (await (await as("/api/me")).json()) as { businesses: { name: string }[] };
  expect(after.businesses.map((b) => b.name)).toEqual(["Acme", "Globex"]);
  const detail = (await (await as(`/api/businesses/${globex.id}`)).json()) as {
    employees: { name: string }[];
  };
  expect(detail.employees.map((e) => e.name)).toEqual(["Head of Operations"]);
});

it("a person changes the name they go by; a blank or long one is refused", async () => {
  const acme = await business("Named");
  const as = await session(acme.person);
  const rename = (display_name: unknown) =>
    as("/api/me", { method: "PUT", body: JSON.stringify({ display_name }) });
  const renamed = await rename("  Sam Rivera ");
  expect(renamed.status).toBe(200);
  expect(((await renamed.json()) as { person: { display_name: string } }).person.display_name).toBe(
    "Sam Rivera",
  );
  const me = (await (await as("/api/me")).json()) as { person: { display_name: string } };
  expect(me.person.display_name).toBe("Sam Rivera");
  expect((await rename("   ")).status).toBe(400);
  expect((await rename("x".repeat(81))).status).toBe(400);
  expect((await rename(7)).status).toBe(400);
});

it("another business's routes, employees, memory, files and connections do not exist for a non-member", async () => {
  const acme = await business("Acme");
  const globex = await business("Globex");
  await sql.run(
    `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
     VALUES ('00000000-0000-4000-a000-000000000001', $1, 'op', $1 || '/a', 'a.txt', 'text/plain', 1)`,
    [globex.business.id],
  );
  const as = await session(acme.person);
  const other = `/api/businesses/${globex.business.id}`;
  for (const path of [
    other,
    `${other}/memory`,
    `${other}/export`,
    `${other}/connections/google`,
    `${other}/artifacts/00000000-0000-4000-a000-000000000001`,
    `${other}/employees/${globex.operations.id}/status`,
    `${other}/conversations/direct:${globex.operations.id}`,
  ])
    expect((await as(path)).status, path).toBe(404);
  for (const path of [
    `${other}/employees`,
    `${other}/conversations/direct:${globex.operations.id}/messages`,
    `${other}/employees/${globex.operations.id}/stop`,
  ])
    expect((await as(path, { method: "POST", body: "{}" })).status, path).toBe(404);
  // Inside its own business, a member still cannot reach an employee of another business.
  const mine = `/api/businesses/${acme.business.id}/employees/${globex.operations.id}`;
  expect((await as(`${mine}/status`)).status).toBe(404);
  expect(
    (await as(`/api/businesses/${acme.business.id}/artifacts/00000000-0000-4000-a000-000000000001`))
      .status,
  ).toBe(404);
});

it("a member adds employees to their own business and the list shows them", async () => {
  const acme = await business("Acme");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  expect(
    (
      await as(`${path}/employees`, {
        method: "POST",
        body: JSON.stringify({ template: "custom", name: "Growth" }),
      })
    ).status,
  ).toBe(400);
  const created = await as(`${path}/employees`, {
    method: "POST",
    body: JSON.stringify({
      template: "custom",
      name: "Growth",
      responsibilities: "Runs acquisition and the launch PR.",
    }),
  });
  expect(created.status).toBe(201);
  const detail = (await (await as(path)).json()) as { employees: { name: string }[] };
  expect(detail.employees.map((e) => e.name)).toEqual(["Head of Operations", "Growth"]);
});

it("employees run on a configured model chosen at hire time and changeable by members", async () => {
  const acme = await business("Acme");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  const catalog = (await (await as("/api/models")).json()) as {
    defaults: { employee: string };
    models: { id: string }[];
  };
  expect(catalog.models.map((m) => m.id)).toContain(catalog.defaults.employee);
  const hired = async (model?: string) =>
    as(`${path}/employees`, {
      method: "POST",
      body: JSON.stringify({ template: "growth", model }),
    });
  expect((await hired("not-a-model")).status).toBe(400);
  const growth = (await (await hired("gpt-6.1-sol")).json()) as { id: string; model: string };
  expect(growth.model).toBe("gpt-6.1-sol");
  const model = (employee: string, body: unknown) =>
    as(`${path}/employees/${employee}/model`, { method: "PUT", body: JSON.stringify(body) });
  expect((await model(growth.id, { model: "gpt-4o" })).status).toBe(400);
  expect((await model(growth.id, { model: "gemini-4-argon" })).status).toBe(200);
  const detail = (await (await as(path)).json()) as {
    employees: { name: string; model: string }[];
  };
  expect(detail.employees.map((e) => [e.name, e.model])).toEqual([
    ["Head of Operations", catalog.defaults.employee],
    ["Growth", "gemini-4-argon"],
  ]);
  // Someone outside the business cannot change its employees' models.
  const stranger = await session((await business("Elsewhere")).person);
  expect(
    (
      await stranger(`${path}/employees/${growth.id}/model`, {
        method: "PUT",
        body: JSON.stringify({ model: "gpt-6-luna" }),
      })
    ).status,
  ).toBe(404);
});

it("a published artifact's link opens it for a member and for nobody else", async () => {
  const acme = await business("Acme");
  const runtime = {
    ...env,
    PUBLIC_URL: origin,
    WORKSPACE: {
      getByName: () => ({
        exportFile: async (_path: string, key: string) => {
          await (env as unknown as Env).FILES.put(key, "quarterly numbers");
          return { size: 17 };
        },
      }),
    },
  } as unknown as Env;
  const published = (await Effect.runPromise(
    capabilities(runtime)
      .find((item) => item.name === "publishArtifact")!
      .execute({ path: "/workspace/q3.txt", filename: "q3.txt", contentType: "text/plain" })
      .pipe(
        Effect.provideService(Invocation, {
          ...acme.scope,
          operationId: crypto.randomUUID(),
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      ),
  )) as { url: string };
  expect(published.url.startsWith(`${origin}/api/businesses/${acme.business.id}/artifacts/`)).toBe(
    true,
  );
  const path = published.url.slice(origin.length);
  const opened = await (await session(acme.person))(path);
  expect(opened.status).toBe(200);
  expect(await opened.text()).toBe("quarterly numbers");
  const stranger = await business("Globex");
  expect((await (await session(stranger.person))(path)).status).toBe(404);
});
