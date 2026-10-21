import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { apiRoute } from "../src/app/http.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { Effect } from "effect";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { grant } from "../src/authority/service.ts";
import { markSeen, messages, postMessage } from "../src/conversations/service.ts";
import { createCommitment } from "../src/work/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

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

it("projects have a lead, members, a goal, deadline and budget, and work created in one belongs to it", async () => {
  const acme = await business("Projects");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  const growth = await json<Employee>(
    as(`${path}/employees`, { method: "POST", body: JSON.stringify({ template: "growth" }) }),
  );
  const project = await json<{
    id: string;
    lead_employee_id: string;
    goal: string | null;
    deadline: string | null;
    budget: { cents: number; currency: string } | null;
    member_ids: string[];
  }>(
    as(`${path}/projects`, {
      method: "POST",
      body: JSON.stringify({
        name: "Launch",
        goal: "Go live",
        deadline: "2026-12-01",
        budget: { cents: 50_000, currency: "USD" },
        members: [growth.id],
      }),
    }),
  );
  expect(project).toMatchObject({
    lead_employee_id: acme.operations.id,
    goal: "Go live",
    deadline: "2026-12-01",
    budget: { cents: 50_000, currency: "USD" },
    member_ids: [growth.id],
  });
  const put = (change: unknown) =>
    as(`${path}/projects/${project.id}`, { method: "PUT", body: JSON.stringify(change) });
  expect((await put({ lead: "nobody" })).status).toBe(400);
  expect((await put({ members: ["nobody"] })).status).toBe(400);
  expect((await put({ budget: { cents: 1.5, currency: "USD" } })).status).toBe(400);
  expect((await put({ deadline: "soon" })).status).toBe(400);
  expect(
    await json(put({ lead: growth.id, members: [], budget: null, goal: null, deadline: null })),
  ).toMatchObject({
    lead_employee_id: growth.id,
    member_ids: [],
    budget: null,
    goal: null,
    deadline: null,
  });
  expect((await as(`${path}/projects/nope`, { method: "PUT", body: "{}" })).status).toBe(404);
  const create = (projectId: string) =>
    as(`${path}/work`, {
      method: "POST",
      body: JSON.stringify({ title: "Buy the domain", owner: acme.operations.id, projectId }),
    });
  expect((await create("nope")).status).toBe(400);
  const task = await json<{ id: string; project_id: string }>(create(project.id));
  expect(task.project_id).toBe(project.id);
  const listed = await json<{ commitments: { id: string; project_id: string | null }[] }>(
    as(`${path}/work`),
  );
  expect(listed.commitments.find((item) => item.id === task.id)?.project_id).toBe(project.id);
  // A project references records; work belongs to it rather than being one of its items.
  expect(
    (
      await as(`${path}/projects/${project.id}/items`, {
        method: "POST",
        body: JSON.stringify({ ref: `devys:work/item/${task.id}` }),
      })
    ).status,
  ).toBe(400);
  // A conversation only exists for something of this business.
  expect((await as(`${path}/conversations/project:nope`)).status).toBe(404);
  expect((await as(`${path}/conversations/project:${project.id}`)).status).toBe(200);
  expect((await as(`${path}/conversations/space:${project.id}`)).status).toBe(404);
});

it("the app directory installs, uninstalls and pins apps; Documents stays and coming apps wait", async () => {
  const acme = await business("Apps");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  type App = { id: string; status: string; installed: boolean; pinned: boolean; visible: boolean };
  const apps = async () => (await json<{ apps: App[] }>(as(`${path}/apps`))).apps;
  const post = (url: string, value?: unknown) =>
    as(`${path}${url}`, { method: "POST", body: JSON.stringify(value ?? {}) });
  const byId = async (id: string) => (await apps()).find((app) => app.id === id)!;
  expect(await byId("documents")).toMatchObject({ installed: true, pinned: true, visible: true });
  // Code is installed but has no coding sessions yet, so it does not show.
  expect(await byId("code")).toMatchObject({ installed: true, visible: false });
  expect(await byId("mail")).toMatchObject({ status: "coming", installed: false });
  expect((await post("/apps/mail/install")).status).toBe(409);
  expect((await post("/apps/documents/uninstall")).status).toBe(409);
  expect((await post("/apps/nope/install")).status).toBe(404);
  expect((await post("/apps/code/uninstall")).status).toBe(200);
  expect(await byId("code")).toMatchObject({ installed: false, pinned: false });
  expect((await post("/apps/code/pin", { pinned: false })).status).toBe(409);
  expect((await post("/apps/code/install")).status).toBe(200);
  expect((await post("/apps/code/pin", { pinned: "no" })).status).toBe(400);
  // System apps come with every business: listed as installed, never installed, removed or pinned.
  expect(await byId("computer")).toMatchObject({ installed: true, pinned: false, visible: false });
  for (const action of ["install", "uninstall", "pin"])
    expect((await post(`/apps/work/${action}`, { pinned: true })).status).toBe(409);
  expect(await json(post("/apps/code/pin", { pinned: false }))).toMatchObject({
    app: { id: "code", installed: true, pinned: false },
  });
});

it("Home lists what needs the owner and the work at a glance, and briefs them once on return", async () => {
  const acme = await business("Home");
  const as = await session(acme.person);
  const path = `/api/businesses/${acme.business.id}`;
  const ops = acme.operations.id;
  const scope = acme.scope;
  const work = async (title: string, state: string, extra = "") => {
    const created = await Effect.runPromise(
      createCommitment(db, scope.businessId, { owner: ops, title, createdBy: "person:t" }),
    );
    await sql.run(`UPDATE commitments SET state = $2${extra} WHERE id = $1`, [created.id, state]);
    return created.id;
  };
  const asked = await work("Order the domain", "in_progress");
  const decide = await work("Pick a name", "needs_decision");
  const moving = await work("Draft the site", "in_progress");
  const late = await work("Supplier quote", "waiting", ", due_at = now() - interval '1 day'");
  await work("Shipped", "completed");
  // A request for approval, asked in the work item's thread.
  const list = capabilities(bindings).find((item) => item.name === "commitmentList")!;
  await Effect.runPromise(grant(db, scope, { capability: list, mode: "ask" }));
  await authorize(
    bindings,
    scope,
    list,
    {},
    { commitmentId: asked, conversation: `work:${asked}` },
  );
  type Home = {
    needsYou: { kind: string; id: string; title: string; conversation: string | null }[];
    glance: { moving: { id: string }[]; stuck: { id: string }[]; spentCents: number | null };
    since: string | null;
    briefing: { id: string; author: string; text: string } | null;
  };
  const home = await json<Home>(as(`${path}/home`));
  expect(home.needsYou.map((need) => [need.kind, need.title, need.conversation])).toEqual([
    ["decision", "Order the domain", `work:${asked}`],
    ["work", "Pick a name", `work:${decide}`],
  ]);
  expect(home.glance.moving.map((item) => item.id).sort()).toEqual([asked, moving].sort());
  expect(home.glance.stuck.map((item) => item.id)).toEqual([late]);
  expect(home.glance.spentCents).toBeNull();
  // The owner has never read the chat with Operations: nothing to brief against.
  expect(home).toMatchObject({ since: null, briefing: null });

  // The owner last read Operations' chat ten hours ago; the work above changed since.
  const key = `direct:${ops}` as const;
  const { message } = await Effect.runPromise(
    postMessage(db, scope.businessId, key, {
      author: `employee:${ops}`,
      text: "Hi",
      clientId: "hi",
    }),
  );
  await sql.run("UPDATE messages SET created_at = now() - interval '10 hours' WHERE id = $1", [
    message.id,
  ]);
  await Effect.runPromise(
    markSeen(db, scope.businessId, key, `person:${acme.person}`, { message: message.id }),
  );
  // Posting the briefing must wake nobody: these bindings' runtime has no `receive`.
  const first = await json<Home>(as(`${path}/home`));
  expect(first.briefing).toMatchObject({ author: `employee:${ops}` });
  expect(first.briefing!.text).toContain('Done: "Shipped".');
  expect(first.briefing!.text).toContain('"Draft the site"');
  expect(first.briefing!.text).toContain('Stuck: "Supplier quote".');
  const again = await json<Home>(as(`${path}/home`));
  expect(again.briefing?.id).toBe(first.briefing!.id);
  const said = await Effect.runPromise(messages(db, scope.businessId, key));
  expect(said.map((m) => m.text)).toEqual(["Hi", first.briefing!.text]);
});

it("Home posts no briefing when nothing happened while the owner was away", async () => {
  const quiet = await business("Quiet");
  const as = await session(quiet.person);
  const key = `direct:${quiet.operations.id}` as const;
  const { message } = await Effect.runPromise(
    postMessage(db, quiet.business.id, key, { author: "system", text: "Hello", clientId: "hello" }),
  );
  await sql.run("UPDATE messages SET created_at = now() - interval '2 days' WHERE id = $1", [
    message.id,
  ]);
  await Effect.runPromise(
    markSeen(db, quiet.business.id, key, `person:${quiet.person}`, { message: message.id }),
  );
  const home = await json<{ briefing: unknown; since: string }>(
    as(`/api/businesses/${quiet.business.id}/home`),
  );
  expect(home.briefing).toBeNull();
  expect(Date.parse(home.since)).toBeLessThan(Date.now() - 24 * 3_600_000);
  expect(await Effect.runPromise(messages(db, quiet.business.id, key))).toHaveLength(1);
});
