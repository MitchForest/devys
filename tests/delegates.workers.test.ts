import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import {
  codingIncomplete,
  delegateDependencies,
  delegateEventsRoute,
} from "../src/app/delegates.ts";
import { grant } from "../src/authority/service.ts";
import type { Inbound } from "../src/channels/contract.ts";
import { messages } from "../src/conversations/service.ts";
import { delegateCapabilities } from "../src/delegates/capabilities.ts";
import type { Delegates, StartRequest } from "../src/delegates/contract.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { commitment, createCommitment, setTakeover } from "../src/work/service.ts";
import { codingRoute, handBack } from "../src/app/coding.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const hostToken = "host-token";

const harnessDelegates = (state: { delegates: Delegates }) => () => state.delegates;
const ownerOf = async (businessId: string) =>
  (
    await sql.row<{ person_id: string }>(
      "SELECT person_id FROM memberships WHERE business_id = $1",
      [businessId],
    )
  )?.person_id;

/** Records what each employee runtime receives, and what the fake host was asked. */
function harness() {
  const received: { employee: string; input: Inbound }[] = [];
  const bindings = {
    ...env,
    DEVYS_HOST_TOKEN: hostToken,
    AGENT: {
      getByName: (name: string) => ({
        receive: async (_scope: unknown, input: Inbound) => {
          received.push({ employee: (JSON.parse(name) as string[])[1]!, input });
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  const starts: StartRequest[] = [];
  const sent: string[] = [];
  const published: { id: string; repository: string; title: string }[] = [];
  const deploys: { id: string; stage: string; commit?: string }[] = [];
  const delegates: Delegates = {
    start: async (request) => {
      starts.push(request);
      return {
        sessionId: "thread-1",
        repository: "/Users/owner/acme",
        baseCommit: "a".repeat(40),
        branch: `devys/${request.id.slice(0, 12)}`,
        worktree: `/Users/owner/Devys/b/worktrees/${request.id}`,
      };
    },
    inspect: async () => ({ state: "idle", reply: "Done.", diffStat: " a.ts | 2 +-", error: null }),
    diff: async () => ({ files: [], patch: "" }),
    transcript: async () => ({ entries: [{ kind: "command", text: "bun test" }] }),
    send: async (_id, text) => {
      sent.push(text);
      return { steered: false };
    },
    interrupt: async () => {},
    accept: async () => ({ commit: "b".repeat(40), diffStat: " 1 file changed", patch: "+x" }),
    deploy: async (id, request) => {
      deploys.push({
        id,
        stage: request.stage,
        ...(request.commit ? { commit: request.commit } : {}),
      });
      return { commit: request.commit ?? "b".repeat(40) };
    },
    publish: async (id, request) => {
      published.push({ id, ...request });
      return {
        repository: request.repository,
        repositoryId: "R_kgDOtest",
        branch: `devys/${id.slice(0, 12)}`,
        base: "main",
        commit: "b".repeat(40),
        pullRequest: `https://github.com/${request.repository}/pull/7`,
      };
    },
  };
  const catalog = delegateCapabilities({
    ...delegateDependencies(bindings),
    delegates: () => delegates,
  });
  const named = (name: string) => catalog.find((item) => item.name === name)!;
  return { received, bindings, starts, sent, published, deploys, named, delegates };
}

const as = (
  bindings: Env,
  scope: { businessId: string; employeeId: string },
  commitmentId?: string,
  operationId = crypto.randomUUID(),
) =>
  Effect.provideService(Invocation, {
    ...scope,
    ...(commitmentId ? { commitmentId } : {}),
    operationId,
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

async function setup() {
  const state = harness();
  const { scope } = await business("Delegates");
  for (const name of [
    "codingStart",
    "codingStatus",
    "codingSend",
    "codingAccept",
    "codingPublish",
    "deployPreview",
  ])
    await Effect.runPromise(grant(db, scope, { capability: state.named(name), mode: "auto" }));
  await Effect.runPromise(
    grant(db, scope, { capability: state.named("deployProduction"), mode: "ask" }),
  );
  const work = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Add a waitlist page",
      createdBy: "person:test",
    }),
  );
  return { ...state, scope, work };
}

const event = (bindings: Env, events: unknown[], token = hostToken) =>
  delegateEventsRoute(
    new Request("http://127.0.0.1:8787/internal/delegates/events", {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
      body: JSON.stringify({ events }),
    }),
    bindings,
  );

it("coding starts only from a work item, once per call, within the grant's repositories", async () => {
  const { bindings, scope, work, starts, named } = await setup();
  const start = named("codingStart");
  const input = {
    provider: "codex",
    objective: "Build the waitlist page",
    repository: "/Users/owner/acme",
  };
  const outside = await Effect.runPromise(
    start.execute(input).pipe(as(bindings, scope), Effect.flip),
  );
  expect(outside).toMatchObject({ code: "invalid_input" });
  const operationId = crypto.randomUUID();
  const first = (await Effect.runPromise(
    start.execute(input).pipe(as(bindings, scope, work.id, operationId)),
  )) as { assignment: string; branch: string };
  // The same call replayed is the same assignment; the host makes it idempotent.
  const again = (await Effect.runPromise(
    start.execute(input).pipe(as(bindings, scope, work.id, operationId)),
  )) as { assignment: string };
  expect(again.assignment).toBe(first.assignment);
  expect(starts.map((request) => request.id)).toEqual([first.assignment, first.assignment]);
  expect(starts[0]).toMatchObject({
    provider: "codex",
    purpose: "build",
    repository: { path: "/Users/owner/acme" },
  });

  // A grant limited to other repositories refuses this one.
  await Effect.runPromise(
    grant(db, scope, {
      capability: start,
      mode: "auto",
      constraints: { repositories: ["/Users/owner/globex"] },
    }),
  );
  const refused = await Effect.runPromise(
    start.execute(input).pipe(as(bindings, scope, work.id), Effect.exit),
  );
  expect(refused._tag).toBe("Failure");
});

it("coding clones the business's GitHub repository and publishes accepted work as a pull request", async () => {
  const { bindings, scope, work, starts, published, named } = await setup();
  const { assignment } = (await Effect.runPromise(
    named("codingStart")
      .execute({ provider: "codex", objective: "Fix the footer", cloneRepository: "acme/site" })
      .pipe(as(bindings, scope, work.id)),
  )) as { assignment: string };
  expect(starts.at(-1)!.repository).toEqual({ clone: "acme/site" });
  const two = await Effect.runPromise(
    named("codingStart")
      .execute({
        provider: "codex",
        objective: "x",
        cloneRepository: "acme/site",
        newRepository: "site",
      })
      .pipe(as(bindings, scope, work.id), Effect.flip),
  );
  expect(two).toMatchObject({ code: "invalid_input" });

  const publish = named("codingPublish");
  const result = await Effect.runPromise(
    publish
      .execute({ assignment, repository: "acme/site", title: "Fix the footer", body: "Checked." })
      .pipe(as(bindings, scope, work.id)),
  );
  expect(result).toMatchObject({ pullRequest: "https://github.com/acme/site/pull/7" });
  expect(published).toEqual([
    { id: assignment, repository: "acme/site", title: "Fix the footer", body: "Checked." },
  ]);
  const evidence = (await Effect.runPromise(commitment(db, scope.businessId, work.id)))!.evidence;
  expect(evidence.at(-1)!.note).toContain(
    "to devys/" + assignment.slice(0, 12) + " on github.com/acme/site (repository R_kgDOtest)",
  );
  // A grant limited to other repositories refuses this one.
  await Effect.runPromise(
    grant(db, scope, {
      capability: publish,
      mode: "auto",
      constraints: { repositories: ["acme/docs"] },
    }),
  );
  const refused = await Effect.runPromise(
    publish
      .execute({ assignment, repository: "acme/site", title: "Again", body: "x" })
      .pipe(as(bindings, scope, work.id), Effect.exit),
  );
  expect(refused._tag).toBe("Failure");
  expect(published).toHaveLength(1);
});

it("host events become thread cards, wake the employee under a stable id, and record checks as evidence", async () => {
  const { bindings, scope, work, received, sent, named } = await setup();
  const { assignment } = (await Effect.runPromise(
    named("codingStart")
      .execute({
        provider: "codex",
        objective: "Build the waitlist page",
        newRepository: "waitlist",
      })
      .pipe(as(bindings, scope, work.id)),
  )) as { assignment: string };
  expect((await event(bindings, [], "wrong")).status).toBe(401);
  const finished = {
    id: `${assignment}:turn-1:finished`,
    assignmentId: assignment,
    kind: "finished",
    text: "Built the page and its tests.",
    diffStat: " app.ts | 40 ++++\n 1 file changed, 40 insertions(+)",
  };
  expect(
    (
      await event(bindings, [
        { id: `${assignment}:started`, assignmentId: assignment, kind: "started", text: "x" },
        finished,
      ])
    ).status,
  ).toBe(200);
  // Delivered twice: the runtime admits a message id once, so both carry the same id.
  await event(bindings, [finished]);
  expect(received).toHaveLength(2);
  expect(received[1]!.input.messageId).toBe(received[0]!.input.messageId);
  expect(received[0]).toMatchObject({
    employee: scope.employeeId,
    input: {
      senderId: "delegate",
      chatId: `work:${scope.businessId}:${scope.employeeId}:${work.id}`,
    },
  });
  expect(received[0]!.input.text).toContain("Built the page and its tests.");

  await Effect.runPromise(
    named("codingSend")
      .execute({ assignment, text: "Add an empty state" })
      .pipe(as(bindings, scope, work.id)),
  );
  expect(sent).toEqual(["Add an empty state"]);
  await Effect.runPromise(
    named("codingAccept")
      .execute({ assignment, message: "Add the waitlist page", check: "bun test" })
      .pipe(as(bindings, scope, work.id)),
  );
  const current = async () => (await Effect.runPromise(commitment(db, scope.businessId, work.id)))!;
  // Not complete until the accepted commit's check passes.
  expect(await codingIncomplete(bindings, scope.businessId, await current())).toMatch(
    /codingAccept/,
  );
  const checked = {
    id: `${assignment}:checked:c1`,
    assignmentId: assignment,
    kind: "checked",
    text: "`bun test` passed.",
    // A huge diff stat is cut to fit rather than failing the event forever.
    diffStat: " x.ts | 1 +\n".repeat(20_000),
    check: { commit: "b".repeat(40), command: "bun test", exitCode: 0, output: "ok" },
  };
  expect(await (await event(bindings, [checked])).json()).toEqual({ delivered: [checked.id] });
  // Redelivered: the check is recorded once.
  await event(bindings, [checked]);
  expect(await codingIncomplete(bindings, scope.businessId, await current())).toBeUndefined();
  const thread = await Effect.runPromise(
    messages(db, scope.businessId, `work:${work.id}`, { limit: 50 }),
  );
  expect(thread.map((message) => message.text)).toEqual([
    expect.stringMatching(/started Codex · devys\/.*: Build the waitlist page/),
    "Codex finished · 1 file changed, 40 insertions(+): Built the page and its tests.",
    "→ Codex: Add an empty state",
    "`bun test` passed.",
  ]);
  const evidence = (await Effect.runPromise(commitment(db, scope.businessId, work.id)))!.evidence;
  expect(
    evidence.map((entry) => [entry.commit?.slice(0, 1), entry.check?.exitCode ?? null]),
  ).toEqual([
    ["b", null],
    ["b", 0],
  ]);
  expect(received).toHaveLength(4);
});

it("the owner steers a session only after taking the work over; handing back wakes its employee", async () => {
  const state = await setup();
  const { bindings, scope, work, received, sent, named } = state;
  const { assignment } = (await Effect.runPromise(
    named("codingStart")
      .execute({ provider: "claude", objective: "Build it", newRepository: "site" })
      .pipe(as(bindings, scope, work.id)),
  )) as { assignment: string };
  const person = { id: (await ownerOf(scope.businessId))!, display_name: "Owner" };
  const access = (path: string) => ({
    person,
    business: { id: scope.businessId } as never,
    trusted: true,
    path,
  });
  const fake = harnessDelegates(state);
  const call = (path: string, init: RequestInit = {}) =>
    codingRoute(new Request(`http://devys.test${path}`, init), bindings, access(path), fake);

  const listed = (await (await call(`/work/${work.id}/sessions`))!.json()) as {
    sessions: { id: string; state: string; provider: string }[];
  };
  expect(listed.sessions).toMatchObject([{ id: assignment, state: "idle", provider: "claude" }]);
  // What the session did is read from the provider on request.
  expect(await (await call(`/work/${work.id}/sessions/${assignment}/transcript`))!.json()).toEqual({
    entries: [{ kind: "command", text: "bun test" }],
  });
  const steer = (text: string) =>
    call(`/work/${work.id}/sessions/${assignment}/send`, {
      method: "POST",
      body: JSON.stringify({ text }),
    });
  expect((await steer("Use a grid"))!.status).toBe(409);
  await Effect.runPromise(setTakeover(db, scope.businessId, work.id, person.id));
  expect((await steer("Use a grid"))!.status).toBe(200);
  expect(sent).toContain("Use a grid");
  const thread = await Effect.runPromise(
    messages(db, scope.businessId, `work:${work.id}`, { limit: 50 }),
  );
  expect(thread.at(-1)?.text).toBe("Owner → Claude Code: Use a grid");
  // While the owner holds the work, the session's turns post cards but wake no one.
  const woken = received.length;
  await event(bindings, [
    {
      id: `${assignment}:owner-turn:finished`,
      assignmentId: assignment,
      kind: "finished",
      text: "Used a grid.",
      diffStat: "",
    },
  ]);
  expect(received.length).toBe(woken);
  expect(
    (await Effect.runPromise(messages(db, scope.businessId, `work:${work.id}`, { limit: 50 }))).at(
      -1,
    )?.text,
  ).toContain("Used a grid.");

  const before = received.length;
  await Effect.runPromise(setTakeover(db, scope.businessId, work.id, null));
  await handBack(bindings, scope.businessId, work.id, fake);
  expect(received.length).toBe(before + 1);
  expect(received.at(-1)!.input.text).toContain("The owner handed this work item back");
  expect(received.at(-1)!.input.chatId).toBe(
    `work:${scope.businessId}:${scope.employeeId}:${work.id}`,
  );
});

it("a new coding session is a work item already taken over by the owner", async () => {
  const state = await setup();
  const { bindings, scope, starts } = state;
  const person = (await ownerOf(scope.businessId))!;
  const path = "/coding";
  const start = () =>
    codingRoute(
      new Request(`http://devys.test${path}`, {
        method: "POST",
        body: JSON.stringify({
          clientId: "new-session-0001",
          employee: scope.employeeId,
          provider: "codex",
          objective: "Prototype the landing page\nWith a waitlist form.",
          newRepository: "landing",
        }),
      }),
      bindings,
      {
        person: { id: person, display_name: "Owner" } as never,
        business: { id: scope.businessId } as never,
        trusted: true,
        path,
      },
      harnessDelegates(state),
    );
  const first = (await (await start())!.json()) as { work: string; assignment: string };
  const again = (await (await start())!.json()) as { work: string; assignment: string };
  expect(again).toMatchObject({ work: first.work, assignment: first.assignment });
  const item = (await Effect.runPromise(commitment(db, scope.businessId, first.work)))!;
  expect(item).toMatchObject({
    title: "Prototype the landing page",
    taken_over_by: person,
    state: "in_progress",
  });
  expect(starts.at(-1)).toMatchObject({ provider: "codex", repository: { create: "landing" } });
  // The owner follows what they drive; following can be turned off.
  const { conversationSummaries, setFollowing } = await import("../src/conversations/service.ts");
  const following = async () =>
    (await Effect.runPromise(conversationSummaries(db, scope.businessId, person))).find(
      (summary) => summary.key === `work:${first.work}`,
    )?.following;
  expect(await following()).toBe(true);
  await Effect.runPromise(setFollowing(db, scope.businessId, `work:${first.work}`, person, false));
  expect(await following()).toBe(false);
});

it("comments on a file reach the chosen employee's DM as one message with their anchors", async () => {
  const { bindings, scope, received } = await setup();
  const { filesRoute } = await import("../src/app/files.ts");
  const person = (await ownerOf(scope.businessId))!;
  const local = {
    ...bindings,
    DEVYS_MODE: "local",
    DEVYS_HOST_HOME: "/Users/owner",
  } as unknown as Env;
  const response = await filesRoute(
    new Request("http://devys.test/files/comments", {
      method: "POST",
      body: JSON.stringify({
        id: "file-comments-0001",
        path: `/Users/owner/Devys/${scope.businessId}/docs/plan.md`,
        employee: scope.employeeId,
        comments: [
          {
            anchor: { kind: "text", start: 2, end: 6, quote: "Plan" },
            text: "Call it the launch plan",
          },
          {
            anchor: { kind: "pdf", page: 2, rects: [{ x: 10, y: 20, width: 100, height: 40 }] },
            text: "Wrong figure",
          },
        ],
      }),
    }),
    local,
    {
      person: { id: person, display_name: "Owner" } as never,
      business: { id: scope.businessId } as never,
      trusted: true,
      path: "/files/comments",
    },
  );
  expect(response?.status).toBe(201);
  const dm = await Effect.runPromise(
    messages(db, scope.businessId, `direct:${scope.employeeId}`, { limit: 5 }),
  );
  expect(dm.at(-1)?.text).toContain('"Plan" (characters 2–6): Call it the launch plan');
  expect(dm.at(-1)?.text).toContain("page 2, region 10,20 100×40: Wrong figure");
  expect(received.at(-1)).toMatchObject({ employee: scope.employeeId });
  // Or to a work item's thread, addressed to its owner.
  const own = await Effect.runPromise(
    createCommitment(db, scope.businessId, {
      owner: scope.employeeId,
      title: "Fix the plan",
      createdBy: "person:test",
    }),
  );
  const toWork = await filesRoute(
    new Request("http://devys.test/files/comments", {
      method: "POST",
      body: JSON.stringify({
        id: "file-comments-0002",
        path: `/Users/owner/Devys/${scope.businessId}/docs/plan.md`,
        work: own.id,
        comments: [{ anchor: { kind: "lines", start: 3, end: 4 }, text: "Shorter" }],
      }),
    }),
    local,
    {
      person: { id: person, display_name: "Owner" } as never,
      business: { id: scope.businessId } as never,
      trusted: true,
      path: "/files/comments",
    },
  );
  expect(toWork?.status).toBe(201);
  const thread = await Effect.runPromise(
    messages(db, scope.businessId, `work:${own.id}`, { limit: 5 }),
  );
  expect(thread.at(-1)?.text).toContain("Shorter");
});

it("previews deploy on their own, production asks, rollbacks name a known commit, and results become evidence", async () => {
  const { bindings, scope, work, received, deploys, named } = await setup();
  const { assignment } = (await Effect.runPromise(
    named("codingStart")
      .execute({ provider: "codex", objective: "Build it", newRepository: "site" })
      .pipe(as(bindings, scope, work.id)),
  )) as { assignment: string };
  const command = "bunx wrangler deploy --env preview";
  expect(
    await Effect.runPromise(
      named("deployPreview")
        .execute({ assignment, command })
        .pipe(as(bindings, scope, work.id)),
    ),
  ).toEqual({ deploying: "b".repeat(40) });
  expect(deploys).toEqual([{ id: assignment, stage: "preview" }]);
  // Production waits for the owner: a decision, and nothing deployed.
  const asked = await Effect.runPromiseExit(
    named("deployProduction")
      .execute({ assignment, command: "bunx wrangler deploy" })
      .pipe(as(bindings, scope, work.id)),
  );
  expect(asked._tag).toBe("Failure");
  expect(deploys).toHaveLength(1);
  // Rolling back only to a commit this work item knows.
  const rollback = await Effect.runPromise(
    named("deployPreview")
      .execute({ assignment, command, commit: "c".repeat(12) })
      .pipe(as(bindings, scope, work.id), Effect.flip),
  );
  expect(rollback).toMatchObject({ code: "invalid_input" });
  const deployed = {
    id: `${assignment}:deployed:preview:1`,
    assignmentId: assignment,
    kind: "deployed",
    text: "Deployed bbbbbbb to preview: https://site.example.workers.dev answers (200).",
    deploy: {
      stage: "preview",
      commit: "b".repeat(40),
      command,
      exitCode: 0,
      url: "https://site.example.workers.dev",
      status: 200,
      live: true,
      output: "Deployed",
    },
  };
  await event(bindings, [deployed]);
  await event(bindings, [deployed]);
  const evidence = (await Effect.runPromise(commitment(db, scope.businessId, work.id)))!.evidence;
  expect(evidence.filter((entry) => entry.deploy)).toEqual([
    expect.objectContaining({
      commit: "b".repeat(40),
      deploy: { stage: "preview", url: "https://site.example.workers.dev", live: true },
    }),
  ]);
  expect(received.at(-1)!.input.text).toContain("It is live");
  // Now that commit is a rollback target.
  expect(
    await Effect.runPromise(
      named("deployPreview")
        .execute({ assignment, command, commit: "bbbbbbbbbbbb" })
        .pipe(as(bindings, scope, work.id)),
    ),
  ).toEqual({ deploying: "bbbbbbbbbbbb" });
});
