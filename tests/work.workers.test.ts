import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { dispatchReady } from "../src/app/dispatch.ts";
import { apiRoute } from "../src/app/http.ts";
import { answerDecision, grant, pendingDecisions } from "../src/authority/service.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { ref } from "../src/protocol/ref.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { createWorkItem, workItem } from "../src/work/service.ts";
import { createProject } from "../src/work/projects.ts";
import { messages } from "../src/conversations/service.ts";
import { createEmployee } from "../src/identity/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);
const named = (name: string) => catalog.find((item) => item.name === name)!;
const as = (scope: { businessId: string; employeeId: string }, workItemId?: string) =>
  Effect.provideService(Invocation, {
    ...scope,
    ...(workItemId ? { workItemId } : {}),
    operationId: crypto.randomUUID(),
    authorize: (capability, input) =>
      Effect.promise(() =>
        authorize(bindings, scope, capability, input, workItemId ? { workItemId } : {}),
      ).pipe(
        Effect.flatMap((outcome) =>
          outcome.outcome === "allow" ? Effect.void : Effect.fail(new Error(outcome.outcome)),
        ),
        Effect.orDie,
      ),
    assertActive: () => Effect.void,
  });

it("an ask opens one request per exact input; approval allows exactly one identical retry", async () => {
  const { person, scope } = await business();
  const create = named("driveCreate");
  const draft = { name: "inquiry.txt", content: "Ten units?" };
  const first = await Effect.runPromise(grant(db, scope, { capability: create, mode: "ask" }));
  const asked = await authorize(bindings, scope, create, draft);
  expect(asked.outcome).toBe("ask");
  const again = await authorize(bindings, scope, create, draft);
  expect(again).toEqual(asked);
  const other = await authorize(bindings, scope, create, { ...draft, content: "Twenty units?" });
  expect(other.outcome === "ask" && other.decisionId).not.toBe(
    asked.outcome === "ask" && asked.decisionId,
  );
  const pending = await Effect.runPromise(pendingDecisions(db, scope.businessId));
  expect(pending).toHaveLength(2);
  expect(
    pending.find((d) => d.id === (asked.outcome === "ask" && asked.decisionId))?.input,
  ).toEqual(draft);

  const id = asked.outcome === "ask" ? asked.decisionId! : "";
  expect(
    await Effect.runPromise(
      answerDecision(db, scope.businessId, id, { approve: true, by: person }),
    ),
  ).toMatchObject({ id, status: "approved" });
  expect(
    await Effect.runPromise(
      answerDecision(db, scope.businessId, id, { approve: false, by: person }),
    ),
  ).toBeUndefined();
  // A changed input does not ride on the approval.
  expect((await authorize(bindings, scope, create, { ...draft, name: "x.txt" })).outcome).toBe(
    "ask",
  );
  expect(await authorize(bindings, scope, create, draft)).toEqual({
    outcome: "allow",
    grantId: first.id,
  });
  // Used once: the same request asks again.
  expect((await authorize(bindings, scope, create, draft)).outcome).toBe("ask");
});

it("an approval is bound to the grant revision and expires to rejected", async () => {
  const { person, scope } = await business();
  const create = named("driveCreate");
  const draft = { name: "a.txt", content: "A" };
  await Effect.runPromise(grant(db, scope, { capability: create, mode: "ask" }));
  const asked = await authorize(bindings, scope, create, draft);
  const id = asked.outcome === "ask" ? asked.decisionId! : "";
  await Effect.runPromise(answerDecision(db, scope.businessId, id, { approve: true, by: person }));
  // The owner replaces the grant: the old approval no longer applies.
  await Effect.runPromise(grant(db, scope, { capability: create, mode: "ask" }));
  expect((await authorize(bindings, scope, create, draft)).outcome).toBe("ask");

  const late = await authorize(bindings, scope, create, { ...draft, name: "late.txt" });
  const lateId = late.outcome === "ask" ? late.decisionId! : "";
  await sql.run("UPDATE decisions SET expires_at = now() - interval '1 minute' WHERE id = $1", [
    lateId,
  ]);
  expect(
    await Effect.runPromise(
      answerDecision(db, scope.businessId, lateId, { approve: true, by: person }),
    ),
  ).toBeUndefined();
  expect(
    (await Effect.runPromise(pendingDecisions(db, scope.businessId))).map((d) => d.id),
  ).not.toContain(lateId);
  // The minute tick records the expiry; no one decided it, so the same request may ask again.
  const { expireDecisions } = await import("../src/authority/service.ts");
  await Effect.runPromise(expireDecisions(db));
  expect(
    (await sql.row<{ status: string }>("SELECT status FROM decisions WHERE id = $1", [lateId]))
      ?.status,
  ).toBe("rejected");
  expect((await authorize(bindings, scope, create, { ...draft, name: "late.txt" })).outcome).toBe(
    "ask",
  );
});

it("an owner's rejection stands, and an approval covers only the work item it was asked for", async () => {
  const { person, scope } = await business();
  const create = named("driveCreate");
  const draft = { name: "b.txt", content: "B" };
  await Effect.runPromise(grant(db, scope, { capability: create, mode: "ask" }));
  const asked = await authorize(bindings, scope, create, draft);
  const id = asked.outcome === "ask" ? asked.decisionId! : "";
  await Effect.runPromise(answerDecision(db, scope.businessId, id, { approve: false, by: person }));
  expect((await authorize(bindings, scope, create, draft)).outcome).toBe("deny");

  const [one, two] = await Promise.all(
    ["One", "Two"].map((title) =>
      Effect.runPromise(
        createWorkItem(db, scope.businessId, {
          id: crypto.randomUUID(),
          owner: scope.employeeId,
          title,
          createdBy: "person:test",
        }),
      ),
    ),
  );
  const other = { name: "c.txt", content: "C" };
  const forOne = await authorize(bindings, scope, create, other, { workItemId: one!.id });
  const oneId = forOne.outcome === "ask" ? forOne.decisionId! : "";
  await Effect.runPromise(
    answerDecision(db, scope.businessId, oneId, { approve: true, by: person }),
  );
  expect((await authorize(bindings, scope, create, other, { workItemId: two!.id })).outcome).toBe(
    "ask",
  );
  expect((await authorize(bindings, scope, create, other, { workItemId: one!.id })).outcome).toBe(
    "allow",
  );
});

it("work's conditions only narrow, and taking it over stops the employee acting on it", async () => {
  const { scope } = await business();
  const read = named("readPublicUrl");
  await Effect.runPromise(grant(db, scope, { capability: read, mode: "auto" }));
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Research Search Intelligence",
      conditions: { readPublicUrl: { hosts: ["searchintelligence.com"] } },
      createdBy: "person:test",
    }),
  );
  expect(
    (
      await authorize(
        bindings,
        scope,
        read,
        { url: "https://searchintelligence.com/x" },
        { workItemId: work.id },
      )
    ).outcome,
  ).toBe("allow");
  expect(
    (
      await authorize(
        bindings,
        scope,
        read,
        { url: "https://example.com" },
        { workItemId: work.id },
      )
    ).outcome,
  ).toBe("deny");
  // Outside that work item the grant alone applies.
  expect((await authorize(bindings, scope, read, { url: "https://example.com" })).outcome).toBe(
    "allow",
  );
  await sql.run("UPDATE work_items SET taken_over_by = 'someone' WHERE id = $1", [work.id]);
  expect(
    (
      await authorize(
        bindings,
        scope,
        read,
        { url: "https://searchintelligence.com/x" },
        { workItemId: work.id },
      )
    ).outcome,
  ).toBe("deny");
  // The employee cannot change work a person has taken over.
  const update = named("workUpdate");
  await Effect.runPromise(grant(db, scope, { capability: update, mode: "auto" }));
  const result = await Effect.runPromise(
    update
      .execute({
        ref: ref("work", "item", work.id),
        revision: work.revision,
        nextAction: "Mine now",
      })
      .pipe(as(scope), Effect.flip),
  );
  expect(result).toMatchObject({ code: "conflict" });
});

it("ready work reaches its employee once per revision, and a lost hand-off is resubmitted under the same id", async () => {
  const { scope } = await business();
  const received: { scope: unknown; messageId: string; chatId: string; text: string }[] = [];
  let failMark = true;
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (
          target: unknown,
          input: { messageId: string; chatId: string; text: string },
        ) => {
          received.push({ scope: target, ...input });
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Draft the PR inquiry",
      createdBy: "person:test",
    }),
  );
  // Simulate the hand-off landing but its record failing: the work item stays ready.
  const revert = async () => {
    if (failMark)
      await sql.run(
        "UPDATE work_items SET state = 'ready', submitted_revision = NULL WHERE id = $1",
        [work.id],
      );
    failMark = false;
  };
  await dispatchReady(agentEnv);
  await revert();
  await dispatchReady(agentEnv);
  await dispatchReady(agentEnv);
  const mine = received.filter((item) => item.chatId.endsWith(work.id));
  expect(mine.map((item) => item.messageId)).toEqual([`${work.id}:1`, `${work.id}:1`]);
  // The hand-off names the work item by its ref.
  expect(mine[0]!.text).toContain(
    `Work on this work item (devys:work/item/${work.id}, revision 1)`,
  );
  expect((await Effect.runPromise(workItem(db, scope.businessId, work.id)))?.state).toBe(
    "in_progress",
  );
  // A paused employee's work waits.
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [scope.employeeId]);
  const later = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Later",
      createdBy: "person:test",
    }),
  );
  await dispatchReady(agentEnv);
  expect(received.some((item) => item.chatId.endsWith(later.id))).toBe(false);
});

it("a due date is a deadline: ready work due next month is handed over now", async () => {
  const { scope } = await business();
  const received: string[] = [];
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (_: unknown, input: { chatId: string }) => {
          received.push(input.chatId);
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Quarterly filing",
      dueAt: new Date(Date.now() + 30 * 24 * 3600_000).toISOString(),
      createdBy: "person:test",
    }),
  );
  await dispatchReady(agentEnv);
  expect(received.some((chat) => chat.endsWith(work.id))).toBe(true);
  expect((await Effect.runPromise(workItem(db, scope.businessId, work.id)))?.state).toBe(
    "in_progress",
  );
});

it("work in a project is handed over with a card in its thread and in the project's channel", async () => {
  const { scope } = await business();
  const agentEnv = {
    ...bindings,
    AGENT: { getByName: () => ({ receive: async () => ({ accepted: true }) }) },
  } as unknown as Env;
  const launch = await Effect.runPromise(
    createProject(db, scope.businessId, { id: crypto.randomUUID(), name: "Launch" }),
  );
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Started from a message",
      projectId: launch.id,
      createdBy: "person:test",
    }),
  );
  await dispatchReady(agentEnv);
  await dispatchReady(agentEnv);
  for (const key of [`work:${work.id}`, `project:${launch.id}`] as const)
    expect(
      (await Effect.runPromise(messages(db, scope.businessId, key))).map((m) => [m.kind, m.ref]),
    ).toEqual([["event", `devys:work/item/${work.id}`]]);
});

it("paused employees' work and a failing hand-off never hold up other work", async () => {
  const paused = await business();
  for (let index = 0; index < 21; index++)
    await Effect.runPromise(
      createWorkItem(db, paused.scope.businessId, {
        id: crypto.randomUUID(),
        owner: paused.scope.employeeId,
        title: `Waiting ${index}`,
        createdBy: "person:test",
      }),
    );
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [paused.scope.employeeId]);
  const { scope } = await business();
  const broken = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Fails",
      createdBy: "person:test",
    }),
  );
  const fine = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Works",
      createdBy: "person:test",
    }),
  );
  const received: string[] = [];
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (_: unknown, input: { chatId: string }) => {
          if (input.chatId.endsWith(broken.id)) throw new Error("runtime unavailable");
          received.push(input.chatId);
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  await dispatchReady(agentEnv);
  expect(received.some((chat) => chat.endsWith(fine.id))).toBe(true);
  expect((await Effect.runPromise(workItem(db, scope.businessId, broken.id)))?.state).toBe("ready");
});

it("members manage work and answer requests over HTTP; stale revisions conflict", async () => {
  const { person, scope } = await business();
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  const call = async (path: string, body?: unknown) =>
    (await apiRoute(
      new Request(`https://devys.test/api/businesses/${scope.businessId}${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      bindings,
    ))!;
  expect((await call("/work", { title: "x", owner: "not-an-employee" })).status).toBe(400);
  expect(
    (
      await call("/work", {
        title: "x",
        owner: scope.employeeId,
        conditions: { remember: { hosts: [] } },
      })
    ).status,
  ).toBe(400);
  const created = (await (
    await call("/work", { title: "Launch Acme", owner: scope.employeeId })
  ).json()) as {
    id: string;
    revision: number;
  };
  // Routes decode with the work contract's schemas, as capabilities do, and say what is wrong.
  const unknownState = await call(`/work/${created.id}`, {
    expected_revision: created.revision,
    state: "done",
  });
  expect(unknownState.status).toBe(400);
  expect(await unknownState.text()).toContain('["state"]');
  expect((await call("/work", { title: "  ", owner: scope.employeeId })).status).toBe(400);
  expect((await call(`/work/${created.id}`, { state: "waiting" })).status).toBe(400);
  // Work is read-only to the owner until they take it over (owner decision 2026-10-21).
  const asked = await call(`/work/${created.id}`, {
    expected_revision: created.revision,
    state: "waiting",
  });
  expect(asked.status).toBe(409);
  expect(await asked.text()).toContain("Take over");
  const taken = (await (await call(`/work/${created.id}/takeover`, {})).json()) as {
    taken_over_by: string;
    revision: number;
  };
  expect(taken.taken_over_by).toBe(person);
  const moved = await call(`/work/${created.id}`, {
    expected_revision: taken.revision,
    state: "waiting",
  });
  expect(moved.status).toBe(200);
  expect(
    (await call(`/work/${created.id}`, { expected_revision: taken.revision, state: "ready" }))
      .status,
  ).toBe(409);
  const listed = (await (await call("/work")).json()) as { work_items: { id: string }[] };
  expect(listed.work_items.map((c) => c.id)).toContain(created.id);

  await Effect.runPromise(grant(db, scope, { capability: named("driveCreate"), mode: "ask" }));
  // Asked for a work item the employee still holds (a taken-over one fences it).
  const asking = (await (
    await call("/work", { title: "Draft the note", owner: scope.employeeId })
  ).json()) as { id: string };
  await authorize(
    bindings,
    scope,
    named("driveCreate"),
    { name: "n.txt", content: "c" },
    { workItemId: asking.id },
  );
  const { decisions } = (await (await call("/decisions")).json()) as {
    decisions: { id: string }[];
  };
  expect(decisions).toHaveLength(1);
  expect((await call(`/decisions/${decisions[0]!.id}/approve`, {})).status).toBe(200);
  expect((await call(`/decisions/${decisions[0]!.id}/reject`, {})).status).toBe(409);
  // The work item still lists the request once answered; the business names its members.
  const forItem = (await (await call(`/decisions?work_item=${asking.id}`)).json()) as {
    decisions: { id: string; status: string }[];
  };
  expect(forItem.decisions).toEqual([
    expect.objectContaining({ id: decisions[0]!.id, status: "approved" }),
  ]);
  const detail = (await (await call("")).json()) as { members: { id: string }[] };
  expect(detail.members.map((member) => member.id)).toEqual([person]);
});

it("projects reference records without copying them, refuse other businesses' records, and grant nothing", async () => {
  const acme = await business("Acme");
  const globex = await business("Globex");
  const signIn = async (person: string, use: Env = bindings) => {
    const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
      b.toString(16).padStart(2, "0"),
    ).join("");
    await sql.run(
      "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
      [await sha256(token), person],
    );
    return async (businessId: string, path: string, body?: unknown) =>
      (await apiRoute(
        new Request(`https://devys.test/api/businesses/${businessId}${path}`, {
          method: body === undefined ? "GET" : "POST",
          headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        }),
        use,
      ))!;
  };
  const owner = await signIn(acme.person);
  const launch = (await (
    await owner(acme.business.id, "/projects", { name: "Launch", goal: "Ship it" })
  ).json()) as { id: string };
  // The same limits as projectCreate: a long goal is refused, not cut.
  const long = await owner(acme.business.id, "/projects", { name: "Long", goal: "x".repeat(501) });
  expect(long.status).toBe(400);
  expect(await long.text()).toContain('["goal"]');
  expect(
    (await owner(acme.business.id, "/projects", { name: "Late", deadline: "next week" })).status,
  ).toBe(400);
  const growth = (await (
    await owner(acme.business.id, "/projects", { name: "Growth" })
  ).json()) as {
    id: string;
  };
  const artifact = async (businessId: string) => {
    const id = crypto.randomUUID();
    await sql.run(
      `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
       VALUES ($1, $2, $1, $1, 'plan.html', 'text/html', 1)`,
      [id, businessId],
    );
    return id;
  };
  const page = await artifact(acme.business.id);
  const theirs = await artifact(globex.business.id);
  const pageRef = (id: string) => `devys:documents/artifact/${id}`;
  const fileRef = (path: string) => `devys:documents/file/${encodeURIComponent(path)}`;
  const add = (project: string, ref: string) =>
    owner(acme.business.id, `/projects/${project}/items`, { ref });
  const item = (await (await add(launch.id, pageRef(page))).json()) as { id: string; ref: string };
  expect(item.ref).toBe(pageRef(page));
  expect((await add(growth.id, pageRef(page))).status).toBe(201);
  // Adding the same ref again keeps one item.
  expect(((await (await add(launch.id, pageRef(page))).json()) as { id: string }).id).toBe(item.id);
  expect((await add(launch.id, pageRef(theirs))).status).toBe(400);
  expect((await add(launch.id, pageRef(crypto.randomUUID()))).status).toBe(400);
  // Only refs: not a bare id, not the old card form, not a work item or a project.
  expect((await add(launch.id, page)).status).toBe(400);
  expect((await add(launch.id, `artifact:${page}`)).status).toBe(400);
  expect((await add(launch.id, `devys:work/project/${growth.id}`)).status).toBe(400);
  const listed = (await (await owner(acme.business.id, "/projects")).json()) as {
    projects: { name: string; items: { ref: string }[] }[];
  };
  expect(listed.projects.map((p) => [p.name, p.items.map((i) => i.ref)])).toEqual([
    ["Launch", [pageRef(page)]],
    ["Growth", [pageRef(page)]],
  ]);
  // Removing goes through the project it is in.
  expect(
    (await owner(acme.business.id, `/projects/${growth.id}/items/${item.id}/remove`, {})).status,
  ).toBe(404);
  expect(
    (await owner(acme.business.id, `/projects/${launch.id}/items/${item.id}/remove`, {})).status,
  ).toBe(200);
  // A file is a path in the business's folder on the Mac, so only in local mode.
  const folder = `/Users/owner/Devys/${acme.business.id}`;
  expect((await add(launch.id, fileRef(`${folder}/plan.xlsx`))).status).toBe(400);
  const local = await signIn(acme.person, {
    ...bindings,
    DEVYS_MODE: "local",
    DEVYS_HOST_HOME: "/Users/owner",
  } as unknown as Env);
  const addFile = (path: string) =>
    local(acme.business.id, `/projects/${growth.id}/items`, { ref: fileRef(path) });
  expect((await addFile(`${folder}/plan.xlsx`)).status).toBe(201);
  expect((await addFile(`${folder}/../other/plan.xlsx`)).status).toBe(400);
  expect((await addFile(`/Users/owner/Devys/${globex.business.id}/x.md`)).status).toBe(400);
  const withFile = (await (await local(acme.business.id, "/projects")).json()) as {
    projects: { name: string; items: { ref: string }[] }[];
  };
  expect(withFile.projects.find((p) => p.name === "Growth")?.items).toContainEqual(
    expect.objectContaining({ ref: fileRef(`${folder}/plan.xlsx`) }),
  );
  // Globex's owner can't see Acme's projects, and can't add into them through Globex.
  const other = await signIn(globex.person);
  expect((await other(acme.business.id, "/projects")).status).toBe(404);
  expect(
    (await other(globex.business.id, `/projects/${launch.id}/items`, { ref: pageRef(theirs) }))
      .status,
  ).toBe(404);
});

it("handing back work with no coding sessions puts it back in the dispatcher's hands", async () => {
  const { handBack } = await import("../src/app/coding.ts");
  const { markSubmitted } = await import("../src/work/service.ts");
  const { scope } = await business();
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Taken and returned",
      createdBy: "person:test",
    }),
  );
  await Effect.runPromise(markSubmitted(db, work.id, work.revision));
  await handBack(bindings, scope.businessId, work.id);
  const after = (await Effect.runPromise(workItem(db, scope.businessId, work.id)))!;
  expect(after.state).toBe("ready");
  expect(after.revision).toBeGreaterThan(work.revision);
});

it("a create rerun under the same operation id makes one work item and one project", async () => {
  const { scope } = await business();
  const rerun = <A, E>(effect: Effect.Effect<A, E, Invocation>) =>
    Effect.runPromise(
      effect.pipe(
        Effect.provideService(Invocation, {
          ...scope,
          operationId: "recovered-call",
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      ),
    );
  const work = named("workCreate").execute({ title: "Draft the inquiry" });
  const first = (await rerun(work)) as { ref: string };
  expect(first.ref).toMatch(/^devys:work\/item\//);
  expect(((await rerun(work)) as { ref: string }).ref).toBe(first.ref);
  const project = named("projectCreate").execute({ name: "Launch" });
  const made = (await rerun(project)) as { ref: string };
  expect(made.ref).toMatch(/^devys:work\/project\//);
  expect(((await rerun(project)) as { ref: string }).ref).toBe(made.ref);
  const counted = await sql.row<{ items: number; projects: number }>(
    `SELECT (SELECT count(*)::int FROM work_items WHERE business_id = $1) AS items,
            (SELECT count(*)::int FROM projects WHERE business_id = $1) AS projects`,
    [scope.businessId],
  );
  expect(counted).toEqual({ items: 1, projects: 1 });
});

it("an employee changes only its own work items; the Chief of Staff changes anyone's", async () => {
  const { scope } = await business();
  const engineer = await Effect.runPromise(
    createEmployee(db, scope.businessId, {
      name: "Engineering",
      responsibilities: "Builds the product.",
      model: "claude-opus-5-5",
      template: "engineering",
    }),
  );
  const acting = (employeeId: string) =>
    Effect.provideService(Invocation, {
      businessId: scope.businessId,
      employeeId,
      operationId: crypto.randomUUID(),
      authorize: () => Effect.void,
      assertActive: () => Effect.void,
    });
  const mine = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Plan the launch",
      createdBy: "person:t",
    }),
  );
  const update = (id: string, revision: number) =>
    named("workUpdate").execute({
      ref: ref("work", "item", id),
      revision,
      nextAction: "Draft",
    });
  const refused = await Effect.runPromise(
    Effect.flip(update(mine.id, mine.revision).pipe(acting(engineer.id))),
  );
  expect(refused).toMatchObject({ code: "forbidden" });
  const theirs = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: engineer.id,
      title: "Build the page",
      createdBy: "person:t",
    }),
  );
  expect(
    await Effect.runPromise(update(theirs.id, theirs.revision).pipe(acting(scope.employeeId))),
  ).toMatchObject({ nextAction: "Draft" });
});

it("steps and results are replaced whole, bounded, and shown as one card in the thread updated in place", async () => {
  const { scope } = await business();
  for (const name of ["workCreate", "workUpdate", "workComplete"])
    await Effect.runPromise(grant(db, scope, { capability: named(name), mode: "auto" }));
  const created = (await Effect.runPromise(
    named("workCreate").execute({ title: "Set up acme-widgets.com" }).pipe(as(scope)),
  )) as { ref: string; revision: number; steps: unknown[]; results: unknown[] };
  expect(created).toMatchObject({ steps: [], results: [] });
  const id = created.ref.split("/").at(-1)!;
  const thread = `work:${id}` as const;
  const cards = async () =>
    (await Effect.runPromise(messages(db, scope.businessId, thread))).filter(
      (m) => m.kind === "card",
    );
  type Shown = { ref: string; revision: number; steps: unknown[]; results: unknown[] };
  // What workCreate returns is what workUpdate takes, as is: one naming rule.
  const update = (from: Shown, change: Record<string, unknown>) =>
    Effect.runPromise(
      named("workUpdate")
        .execute({ ref: from.ref, revision: from.revision, ...change })
        .pipe(as(scope, id)),
    ) as Promise<Shown>;
  const refused = (from: Shown, change: Record<string, unknown>) =>
    Effect.runPromise(
      Effect.flip(
        named("workUpdate")
          .execute({ ref: from.ref, revision: from.revision, ...change })
          .pipe(as(scope, id)),
      ),
    );
  expect(await cards()).toEqual([]);
  const planned = await update(created, {
    steps: [
      { title: "Register the domain", state: "doing" },
      { title: "Set up email", state: "todo" },
    ],
  });
  expect(planned.steps).toHaveLength(2);
  const [card] = await cards();
  expect(card).toMatchObject({ kind: "card", ref: created.ref, author: "system" });

  // Each change replaces the whole list; the same one card stands for it.
  const moved = await update(planned, {
    steps: [
      { title: "Register the domain", state: "done" },
      { title: "Set up email", state: "doing" },
    ],
    results: [
      { label: "Registered acme-widgets.com", value: "expires 2027-10-22", ok: true },
      { label: "Live at", url: "https://acme-widgets.com" },
      { label: "Payment", value: "uncertain", ok: null },
    ],
  });
  expect(moved.steps).toEqual([
    { title: "Register the domain", state: "done" },
    { title: "Set up email", state: "doing" },
  ]);
  expect(moved.results).toHaveLength(3);
  const fewer = await update(moved, { results: [{ label: "MX records", ok: true }] });
  expect(fewer.results).toEqual([{ label: "MX records", ok: true }]);
  expect(fewer.steps).toHaveLength(2);
  expect((await cards()).map((m) => m.id)).toEqual([card!.id]);

  // Bounded: at most 10 steps and 12 results, short words, https links only.
  const step = { title: "A step", state: "todo" };
  for (const change of [
    { steps: Array.from({ length: 11 }, () => step) },
    { steps: [{ title: "A step", state: "started" }] },
    { steps: [{ title: "x".repeat(121), state: "todo" }] },
    { results: Array.from({ length: 13 }, () => ({ label: "ok" })) },
    { results: [{ label: "x".repeat(81) }] },
    { results: [{ label: " " }] },
    { results: [{ label: "Live at", url: "http://acme-widgets.com" }] },
    { results: [{ label: "Live at", url: "javascript:alert(1)" }] },
  ])
    expect(await refused(fewer, change)).toMatchObject({ code: "invalid_input" });

  // Completing records its results too; the card still stands alone.
  const done = (await Effect.runPromise(
    named("workComplete")
      .execute({
        ref: fewer.ref,
        revision: fewer.revision,
        evidence: "The domain is registered and mail is set up.",
        results: [{ label: "Test email delivered", ok: true }],
      })
      .pipe(as(scope, id)),
  )) as Shown & { state: string };
  expect(done).toMatchObject({
    state: "completed",
    results: [{ label: "Test email delivered", ok: true }],
  });
  expect(await cards()).toHaveLength(1);
  expect(await Effect.runPromise(workItem(db, scope.businessId, id))).toMatchObject({
    results: [{ label: "Test email delivered", ok: true }],
  });
});

it("work, project and routine capabilities name the record they change ref and its revision revision, as their outputs do", () => {
  for (const name of [
    "workUpdate",
    "workComplete",
    "projectUpdate",
    "projectAdd",
    "routinePropose",
    "routineActivate",
    "routinePause",
  ]) {
    const fields = Object.keys(
      (named(name).input as unknown as { fields: Record<string, unknown> }).fields,
    );
    expect(fields, name).toContain("ref");
    for (const old of ["item", "expectedRevision", "routine"])
      expect(fields, name).not.toContain(old);
  }
});

it("work created while talking to the owner shows its card in that conversation, not twice", async () => {
  const { scope } = await business();
  await Effect.runPromise(grant(db, scope, { capability: named("workCreate"), mode: "auto" }));
  const direct = `direct:${scope.employeeId}` as const;
  const inChat = (title: string, conversation: string) =>
    Effect.runPromise(
      named("workCreate")
        .execute({ title })
        .pipe(
          Effect.provideService(Invocation, {
            ...scope,
            conversation,
            operationId: crypto.randomUUID(),
            authorize: () => Effect.void,
            assertActive: () => Effect.void,
          }),
        ),
    ) as Promise<{ ref: string }>;
  const created = await inChat("Buy the domain", direct);
  const cards = async (key: `${string}:${string}`) =>
    (await Effect.runPromise(messages(db, scope.businessId, key as typeof direct))).filter(
      (m) => m.kind === "card",
    );
  expect((await cards(direct)).map((m) => [m.ref, m.text])).toEqual([
    [created.ref, "Buy the domain"],
  ]);
  // Work made in a thread is already in that thread; nothing else shows it.
  const nested = await inChat("Check the DNS", `work:${created.ref.split("/").at(-1)}`);
  expect(await cards(`work:${nested.ref.split("/").at(-1)}`)).toEqual([]);
  expect(await cards(direct)).toHaveLength(1);
});

it("a plan with a step for the owner waits for Start; Start hands it out at once, once", async () => {
  const { person, scope } = await business();
  await Effect.runPromise(grant(db, scope, { capability: named("workCreate"), mode: "auto" }));
  const create = (input: Record<string, unknown>) =>
    Effect.runPromise(named("workCreate").execute(input).pipe(as(scope))) as Promise<{
      ref: string;
      state: string;
      steps: { title: string; by?: string }[];
    }>;
  // A plan without the owner, money or anything public starts at once.
  expect((await create({ title: "Tidy the notes", steps: [step("Sort them")] })).state).toBe(
    "ready",
  );
  const planned = await create({
    title: "Buy acme-widgets.com",
    steps: [
      step("Connect the card", "owner"),
      step("Check out"),
      step("Approve the total", "owner"),
    ],
  });
  expect(planned.state).toBe("proposed");
  expect(planned.steps.map((s) => s.by ?? "employee")).toEqual(["owner", "employee", "owner"]);
  // A payment or anything public waits too, when the employee says so.
  expect((await create({ title: "Post the launch", waitForStart: true })).state).toBe("proposed");

  const received: string[] = [];
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (_: unknown, input: { text: string }) => {
          received.push(input.text);
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  // Nothing proposed is handed out by the minute tick.
  await dispatchReady(agentEnv);
  expect(received.some((text) => text.includes("Buy acme-widgets.com"))).toBe(false);

  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  const id = planned.ref.split("/").at(-1)!;
  const start = () =>
    apiRoute(
      new Request(`https://devys.test/api/businesses/${scope.businessId}/work/${id}/start`, {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: "{}",
      }),
      agentEnv,
    );
  expect((await start())!.status).toBe(200);
  // Handed out now, with its plan and whose steps are the owner's.
  const handOff = received.find((text) => text.includes("Buy acme-widgets.com"))!;
  expect(handOff).toContain("1. Owner: Connect the card (todo)");
  expect(handOff).toContain("2. Check out (todo)");
  expect((await Effect.runPromise(workItem(db, scope.businessId, id)))!.state).toBe("in_progress");
  expect((await start())!.status).toBe(409);
});

const step = (title: string, by?: "owner") => ({ title, state: "todo", ...(by ? { by } : {}) });
