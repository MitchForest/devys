import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { apiRoute } from "../src/app/http.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { business, sql } from "./fixtures/postgres.ts";

const origin = "https://devys.test";
// Retiring stops the employee's runtime; record the stops instead of running one.
const stopped: string[] = [];
const bindings = {
  ...env,
  AGENT: { getByName: (name: string) => ({ stop: async () => stopped.push(name) }) },
} as unknown as Env;

/** A signed-in device for this person, and the raw token behind it. */
async function session(person: string) {
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 hour', 'Test')",
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
      bindings,
    ).then((response) => response ?? new Response(null, { status: 404 }));
}

type Employee = { id: string; name: string; role: string; template: string; model: string };
const json = async <T>(response: Response | Promise<Response>) =>
  (await (await response).json()) as T;
const grantsOf = async (employee: string) =>
  (
    await sql.rows<{ capability: string; mode: string }>(
      "SELECT capability, mode FROM grants WHERE employee_id = $1 AND revoked_at IS NULL",
      [employee],
    )
  ).reduce<Record<string, string>>((all, row) => ({ ...all, [row.capability]: row.mode }), {});

it("a new business starts with its brief and the chosen team, each with its template's access", async () => {
  const { person } = await business("Owner's first");
  const as = await session(person);
  const roles = await json<{ roles: { id: string; capabilities: string[] }[] }>(as("/api/roles"));
  expect(roles.roles.map((role) => role.id)).toEqual([
    "engineering",
    "growth",
    "business-operations",
    "custom",
  ]);
  expect(
    (
      await as("/api/businesses", {
        method: "POST",
        body: JSON.stringify({ name: "Bad", team: ["operations"] }),
      })
    ).status,
  ).toBe(400);
  const created = await json<{
    business: { id: string; brief: string };
    operations: Employee;
    team: Employee[];
  }>(
    as("/api/businesses", {
      method: "POST",
      body: JSON.stringify({
        name: "Globex",
        brief: "Handwriting practice for children.",
        team: ["engineering", "growth"],
      }),
    }),
  );
  expect(created.business.brief).toBe("Handwriting practice for children.");
  expect(created.team.map((employee) => [employee.name, employee.template])).toEqual([
    ["Engineering", "engineering"],
    ["Growth", "growth"],
  ]);
  const operations = await grantsOf(created.operations.id);
  expect(operations.hireEmployee).toBe("ask");
  expect(operations.run).toBe("auto");
  const engineering = await grantsOf(created.team[0]!.id);
  expect(engineering.run).toBe("auto");
  expect(engineering.hireEmployee).toBeUndefined();
  expect((await grantsOf(created.team[1]!.id)).run).toBeUndefined();
});

it("members hire from templates, edit employees and the brief, and retire with a handover", async () => {
  const acme = await business("Acme");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  expect(
    (
      await as(`${path}/employees`, {
        method: "POST",
        body: JSON.stringify({ template: "operations" }),
      })
    ).status,
  ).toBe(400);
  expect(
    (
      await as(`${path}/employees`, {
        method: "POST",
        body: JSON.stringify({ template: "custom" }),
      })
    ).status,
  ).toBe(400);
  const growth = await json<Employee>(
    as(`${path}/employees`, {
      method: "POST",
      body: JSON.stringify({ template: "growth", model: "gpt-6.1-sol" }),
    }),
  );
  expect([growth.name, growth.template, growth.model]).toEqual(["Growth", "growth", "gpt-6.1-sol"]);
  expect(growth.role.length).toBeGreaterThan(50);

  await as(`${path}/employees/${growth.id}/profile`, {
    method: "PUT",
    body: JSON.stringify({ name: "Growth lead", responsibilities: "Run the launch PR." }),
  });
  await as(path, { method: "PUT", body: JSON.stringify({ brief: "Scholarships for families." }) });
  const detail = await json<{ business: { brief: string }; employees: Employee[] }>(as(path));
  expect(detail.business.brief).toBe("Scholarships for families.");
  expect(detail.employees.find((e) => e.id === growth.id)).toMatchObject({
    name: "Growth lead",
    role: "Run the launch PR.",
  });

  const work = await json<{ id: string }>(
    as(`${path}/work`, {
      method: "POST",
      body: JSON.stringify({ title: "Pitch editors", owner: growth.id }),
    }),
  );
  expect(
    (
      await as(`${path}/employees/${acme.operations.id}/retire`, {
        method: "POST",
        body: JSON.stringify({ reassignTo: growth.id }),
      })
    ).status,
  ).toBe(409);
  expect(
    (
      await as(`${path}/employees/${growth.id}/retire`, {
        method: "POST",
        body: JSON.stringify({ reassignTo: growth.id }),
      })
    ).status,
  ).toBe(400);
  const retired = await as(`${path}/employees/${growth.id}/retire`, {
    method: "POST",
    body: JSON.stringify({ reassignTo: acme.operations.id }),
  });
  expect(retired.status).toBe(200);
  const after = await json<{ employees: Employee[] }>(as(path));
  expect(after.employees.map((e) => e.id)).toEqual([acme.operations.id]);
  const moved = await sql.row<{ owner_employee_id: string }>(
    "SELECT owner_employee_id FROM commitments WHERE id = $1",
    [work.id],
  );
  expect(moved?.owner_employee_id).toBe(acme.operations.id);
  expect(stopped.some((name) => name.includes(growth.id))).toBe(true);
});

it("a signed-in person adds a device with a code, sees their devices and signs one out", async () => {
  const { person } = await business("Devices");
  const as = await session(person);
  const issued = await json<{ code: string }>(as("/api/devices/codes", { method: "POST" }));
  const exchanged = await apiRoute(
    new Request(`${origin}/api/native/session`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: issued.code, name: "Mitch's iPad" }),
    }),
    env as unknown as Env,
  );
  expect(exchanged?.status).toBe(200);
  const list = await json<{ devices: { id: string; label: string; current: boolean }[] }>(
    as("/api/devices"),
  );
  expect(list.devices.map((device) => [device.label, device.current]).sort()).toEqual([
    ["Mitch's iPad", false],
    ["Test", true],
  ]);
  const ipad = list.devices.find((device) => !device.current)!;
  const stranger = await session((await business("Elsewhere")).person);
  expect((await stranger(`/api/devices/${ipad.id}/revoke`, { method: "POST" })).status).toBe(404);
  expect((await as(`/api/devices/${ipad.id}/revoke`, { method: "POST" })).status).toBe(200);
  expect((await json<{ devices: unknown[] }>(as("/api/devices"))).devices).toHaveLength(1);
});

it("spaces have a lead, and a task created in a space is shown there", async () => {
  const acme = await business("Spaces");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  const space = await json<{ id: string; lead_employee_id: string }>(
    as(`${path}/spaces`, {
      method: "POST",
      body: JSON.stringify({ name: "Launch", purpose: "Go live" }),
    }),
  );
  expect(space.lead_employee_id).toBe(acme.operations.id);
  expect(
    (
      await as(`${path}/spaces/${space.id}`, {
        method: "PUT",
        body: JSON.stringify({ lead: "nobody" }),
      })
    ).status,
  ).toBe(400);
  const task = await json<{ id: string }>(
    as(`${path}/work`, {
      method: "POST",
      body: JSON.stringify({
        title: "Buy the domain",
        owner: acme.operations.id,
        spaceId: space.id,
      }),
    }),
  );
  const listed = await json<{ spaces: { id: string; items: { kind: string; ref: string }[] }[] }>(
    as(`${path}/spaces`),
  );
  expect(listed.spaces.find((s) => s.id === space.id)?.items).toEqual([
    expect.objectContaining({ kind: "commitment", ref: task.id }),
  ]);
  // A conversation only exists for something of this business.
  expect((await as(`${path}/conversations/space:nope`)).status).toBe(404);
  expect((await as(`${path}/conversations/space:${space.id}`)).status).toBe(200);
});
