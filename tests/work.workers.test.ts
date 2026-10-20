import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { dispatchDue } from "../src/app/dispatch.ts";
import { apiRoute } from "../src/app/http.ts";
import { answerDecision, grant, pendingDecisions } from "../src/authority/service.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { createCommitment, commitment } from "../src/work/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);
const named = (name: string) => catalog.find((item) => item.name === name)!;
const as = (scope: { businessId: string; employeeId: string }, commitmentId?: string) =>
  Effect.provideService(Invocation, {
    ...scope,
    ...(commitmentId ? { commitmentId } : {}),
    operationId: crypto.randomUUID(),
    authorize: (capability, input) =>
      Effect.promise(() =>
        authorize(bindings, scope, capability, input, commitmentId ? { commitmentId } : {}),
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
        createCommitment(db, scope.businessId, {
          owner: scope.employeeId,
          title,
          createdBy: "person:test",
        }),
      ),
    ),
  );
  const other = { name: "c.txt", content: "C" };
  const forOne = await authorize(bindings, scope, create, other, { commitmentId: one!.id });
  const oneId = forOne.outcome === "ask" ? forOne.decisionId! : "";
  await Effect.runPromise(
    answerDecision(db, scope.businessId, oneId, { approve: true, by: person }),
  );
  expect((await authorize(bindings, scope, create, other, { commitmentId: two!.id })).outcome).toBe(
    "ask",
  );
  expect((await authorize(bindings, scope, create, other, { commitmentId: one!.id })).outcome).toBe(
    "allow",
  );
});

it("work's conditions only narrow, and taking it over stops the employee acting on it", async () => {
  const { scope } = await business();
  const read = named("readPublicUrl");
  await Effect.runPromise(grant(db, scope, { capability: read, mode: "auto" }));
  const work = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
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
        { commitmentId: work.id },
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
        { commitmentId: work.id },
      )
    ).outcome,
  ).toBe("deny");
  // Outside that commitment the grant alone applies.
  expect((await authorize(bindings, scope, read, { url: "https://example.com" })).outcome).toBe(
    "allow",
  );
  await sql.run("UPDATE commitments SET taken_over_by = 'someone' WHERE id = $1", [work.id]);
  expect(
    (
      await authorize(
        bindings,
        scope,
        read,
        { url: "https://searchintelligence.com/x" },
        { commitmentId: work.id },
      )
    ).outcome,
  ).toBe("deny");
  // The employee cannot change work a person has taken over.
  const update = named("commitmentUpdate");
  await Effect.runPromise(grant(db, scope, { capability: update, mode: "auto" }));
  const result = await Effect.runPromise(
    update
      .execute({ id: work.id, expectedRevision: work.revision, nextAction: "Mine now" })
      .pipe(as(scope), Effect.flip),
  );
  expect(result).toMatchObject({ code: "conflict" });
});

it("due work reaches its employee once per revision, and a lost hand-off is resubmitted under the same id", async () => {
  const { scope } = await business();
  const received: { scope: unknown; messageId: string; chatId: string }[] = [];
  let failMark = true;
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (target: unknown, input: { messageId: string; chatId: string }) => {
          received.push({ scope: target, messageId: input.messageId, chatId: input.chatId });
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  const work = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Draft the PR inquiry",
      createdBy: "person:test",
    }),
  );
  // Simulate the hand-off landing but its record failing: the commitment stays due.
  const revert = async () => {
    if (failMark)
      await sql.run(
        "UPDATE commitments SET state = 'ready', submitted_revision = NULL WHERE id = $1",
        [work.id],
      );
    failMark = false;
  };
  await dispatchDue(agentEnv);
  await revert();
  await dispatchDue(agentEnv);
  await dispatchDue(agentEnv);
  const mine = received.filter((item) => item.chatId.endsWith(work.id));
  expect(mine.map((item) => item.messageId)).toEqual([`${work.id}:1`, `${work.id}:1`]);
  expect((await Effect.runPromise(commitment(db, scope.businessId, work.id)))?.state).toBe(
    "in_progress",
  );
  // A paused employee's work waits.
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [scope.employeeId]);
  const later = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Later",
      createdBy: "person:test",
    }),
  );
  await dispatchDue(agentEnv);
  expect(received.some((item) => item.chatId.endsWith(later.id))).toBe(false);
});

it("paused employees' work and a failing hand-off never hold up other work", async () => {
  const paused = await business();
  for (let index = 0; index < 21; index++)
    await Effect.runPromise(
      createCommitment(db, paused.scope.businessId, {
        owner: paused.scope.employeeId,
        title: `Waiting ${index}`,
        createdBy: "person:test",
      }),
    );
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [paused.scope.employeeId]);
  const { scope } = await business();
  const broken = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Fails",
      createdBy: "person:test",
    }),
  );
  const fine = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
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
  await dispatchDue(agentEnv);
  expect(received.some((chat) => chat.endsWith(fine.id))).toBe(true);
  expect((await Effect.runPromise(commitment(db, scope.businessId, broken.id)))?.state).toBe(
    "ready",
  );
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
  const moved = await call(`/work/${created.id}`, {
    expectedRevision: created.revision,
    state: "waiting",
  });
  expect(moved.status).toBe(200);
  expect(
    (await call(`/work/${created.id}`, { expectedRevision: created.revision, state: "ready" }))
      .status,
  ).toBe(409);
  const taken = (await (await call(`/work/${created.id}/takeover`, {})).json()) as {
    taken_over_by: string;
  };
  expect(taken.taken_over_by).toBe(person);
  const listed = (await (await call("/work")).json()) as { commitments: { id: string }[] };
  expect(listed.commitments.map((c) => c.id)).toContain(created.id);

  await Effect.runPromise(grant(db, scope, { capability: named("driveCreate"), mode: "ask" }));
  await authorize(bindings, scope, named("driveCreate"), { name: "n.txt", content: "c" });
  const { decisions } = (await (await call("/decisions")).json()) as {
    decisions: { id: string }[];
  };
  expect(decisions).toHaveLength(1);
  expect((await call(`/decisions/${decisions[0]!.id}/approve`, {})).status).toBe(200);
  expect((await call(`/decisions/${decisions[0]!.id}/reject`, {})).status).toBe(409);
});

it("spaces reference records without copying them, refuse other businesses' records, and grant nothing", async () => {
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
    await owner(acme.business.id, "/spaces", { name: "Launch", purpose: "Ship it" })
  ).json()) as { id: string };
  const growth = (await (await owner(acme.business.id, "/spaces", { name: "Growth" })).json()) as {
    id: string;
  };
  const work = await Effect.runPromise(
    createCommitment(db, acme.business.id, {
      owner: acme.scope.employeeId,
      title: "PR inquiry",
      createdBy: "person:t",
    }),
  );
  const theirs = await Effect.runPromise(
    createCommitment(db, globex.business.id, {
      owner: globex.scope.employeeId,
      title: "Theirs",
      createdBy: "person:t",
    }),
  );
  const add = (space: string, ref: string, kind = "commitment") =>
    owner(acme.business.id, `/spaces/${space}/items`, { kind, ref });
  const item = (await (await add(launch.id, work.id)).json()) as { id: string };
  expect((await add(growth.id, work.id)).status).toBe(201);
  expect((await add(launch.id, theirs.id)).status).toBe(400);
  expect((await add(launch.id, crypto.randomUUID(), "artifact")).status).toBe(400);
  const listed = (await (await owner(acme.business.id, "/spaces")).json()) as {
    spaces: { name: string; items: { ref: string }[] }[];
  };
  expect(listed.spaces.map((s) => [s.name, s.items.map((i) => i.ref)])).toEqual([
    ["Launch", [work.id]],
    ["Growth", [work.id]],
  ]);
  expect(
    (await owner(acme.business.id, `/spaces/${launch.id}/items/${item.id}/remove`, {})).status,
  ).toBe(200);
  expect(await Effect.runPromise(commitment(db, acme.business.id, work.id))).toBeDefined();
  // A file is a path in the business's folder on the Mac, so only in local mode.
  const folder = `/Users/owner/Devys/${acme.business.id}`;
  expect((await add(launch.id, `${folder}/plan.xlsx`, "file")).status).toBe(400);
  const local = await signIn(acme.person, {
    ...bindings,
    DEVYS_MODE: "local",
    DEVYS_HOST_HOME: "/Users/owner",
  } as unknown as Env);
  const addFile = (ref: string) =>
    local(acme.business.id, `/spaces/${growth.id}/items`, { kind: "file", ref });
  expect((await addFile(`${folder}/plan.xlsx`)).status).toBe(201);
  expect((await addFile(`${folder}/../other/plan.xlsx`)).status).toBe(400);
  expect((await addFile(`/Users/owner/Devys/${globex.business.id}/x.md`)).status).toBe(400);
  const withFile = (await (await local(acme.business.id, "/spaces")).json()) as {
    spaces: { name: string; items: { kind: string; ref: string }[] }[];
  };
  expect(withFile.spaces.find((s) => s.name === "Growth")?.items).toContainEqual(
    expect.objectContaining({ kind: "file", ref: `${folder}/plan.xlsx` }),
  );
  // Globex's owner can't see Acme's spaces, and can't add into them through Globex.
  const other = await signIn(globex.person);
  expect((await other(acme.business.id, "/spaces")).status).toBe(404);
  expect(
    (
      await other(globex.business.id, `/spaces/${launch.id}/items`, {
        kind: "commitment",
        ref: theirs.id,
      })
    ).status,
  ).toBe(400);
});

it("handing back work with no coding sessions puts it back in the dispatcher's hands", async () => {
  const { handBack } = await import("../src/app/coding.ts");
  const { markSubmitted } = await import("../src/work/service.ts");
  const { scope } = await business();
  const work = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Taken and returned",
      createdBy: "person:test",
    }),
  );
  await Effect.runPromise(markSubmitted(db, work.id, work.revision));
  await handBack(bindings, scope.businessId, work.id);
  const after = (await Effect.runPromise(commitment(db, scope.businessId, work.id)))!;
  expect(after.state).toBe("ready");
  expect(after.revision).toBeGreaterThan(work.revision);
});
