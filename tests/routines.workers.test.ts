import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { channelFor } from "../src/app/channel.ts";
import { minuteTick } from "../src/app/dispatch.ts";
import { briefing } from "../src/app/home.ts";
import { apiRoute } from "../src/app/http.ts";
import { dispatchRoutines, routeEvent } from "../src/app/routines.ts";
import { answerDecision, grant, pendingDecisions } from "../src/authority/service.ts";
import { routineChat, routineRun } from "../src/channels/routine.ts";
import { messages } from "../src/conversations/service.ts";
import { createEmployee } from "../src/identity/service.ts";
import { sha256 } from "../src/protocol/bytes.ts";
import { CapabilityError, Invocation } from "../src/protocol/capability.ts";
import { ref } from "../src/protocol/ref.ts";
import type { Trigger } from "../src/work/contract.ts";
import { createProject } from "../src/work/projects.ts";
import {
  activateRoutine,
  proposeRoutine,
  quietRuns,
  routine,
  type Proposal,
} from "../src/work/routines.ts";
import { createWorkItem, workItem } from "../src/work/service.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);
const named = (name: string) => catalog.find((item) => item.name === name)!;
type Scope = { businessId: string; employeeId: string };

/** Acts as the employee through the real gate, as the runtime does: `ask` is approval_required. */
const as = (scope: Scope, context: { workItemId?: string; conversation?: string } = {}) =>
  Effect.provideService(Invocation, {
    ...scope,
    ...context,
    operationId: crypto.randomUUID(),
    authorize: (capability, input) =>
      Effect.promise(() => authorize(bindings, scope, capability, input, context)).pipe(
        Effect.flatMap((outcome) =>
          outcome.outcome === "allow"
            ? Effect.void
            : Effect.fail(
                new CapabilityError({
                  code: outcome.outcome === "ask" ? "approval_required" : "forbidden",
                  message: outcome.outcome,
                }),
              ),
        ),
      ),
    assertActive: () => Effect.void,
  });

/** The employee runtime as the dispatcher sees it: every input it is handed. */
function runtime() {
  const received: { messageId: string; chatId: string; text: string }[] = [];
  const agentEnv = {
    ...bindings,
    AGENT: {
      getByName: () => ({
        receive: async (_: unknown, input: { messageId: string; chatId: string; text: string }) => {
          received.push(input);
          return { accepted: true };
        },
      }),
    },
  } as unknown as Env;
  return { received, agentEnv };
}

const weekly: Trigger = { kind: "cron", expression: "0 9 * * 1", timezone: "Europe/London" };

/** An active routine of the employee, due a minute ago (or at `due`). */
async function activeRoutine(
  scope: Scope,
  proposal: Partial<Proposal> = {},
  due = new Date(Date.now() - 60_000).toISOString(),
) {
  const id = crypto.randomUUID();
  await Effect.runPromise(
    proposeRoutine(
      db,
      scope.businessId,
      id,
      {
        employeeId: scope.employeeId,
        projectId: null,
        title: "Weekly signups",
        instruction: "Report last week's signups.",
        trigger: weekly,
        notify: "always",
        ...proposal,
      },
      "employee:test",
    ),
  );
  const next = proposal.trigger?.kind === "event" ? null : due;
  return (await Effect.runPromise(activateRoutine(db, scope.businessId, id, 1, next)))!;
}

it("a routine runs once per slot in its conversation; missed slots run once, not as a backlog", async () => {
  const { scope } = await business();
  const { received, agentEnv } = runtime();
  const launch = await Effect.runPromise(
    createProject(db, scope.businessId, { id: crypto.randomUUID(), name: "Launch" }),
  );
  // Due three weeks ago: the dispatcher was down for two more slots.
  const missed = new Date(Date.now() - 21 * 24 * 3600_000).toISOString();
  const weeklyStatus = await activeRoutine(
    scope,
    { projectId: launch.id, title: "Weekly status" },
    missed,
  );
  await dispatchRoutines(agentEnv);
  await dispatchRoutines(agentEnv);
  const runs = received.filter((input) => input.messageId.includes(weeklyStatus.id));
  expect(runs.map((input) => input.messageId)).toEqual([
    routineRun(weeklyStatus.id, weeklyStatus.next_run_at!),
  ]);
  // It speaks in its project's channel, and names itself by its ref.
  expect(runs[0]!.chatId).toBe(routineChat(scope, `project:${launch.id}`));
  expect(runs[0]!.text).toContain(`(devys:work/routine/${weeklyStatus.id}, revision 1)`);
  expect(runs[0]!.text).not.toContain("NOTHING");
  const after = (await Effect.runPromise(routine(db, scope.businessId, weeklyStatus.id)))!;
  expect(Date.parse(after.next_run_at!)).toBeGreaterThan(Date.now());
  expect(after.last_run_at).not.toBeNull();

  // A lost record of the run (the slot not advanced) resubmits under the same operation id.
  await sql.run("UPDATE routines SET next_run_at = $2 WHERE id = $1", [weeklyStatus.id, missed]);
  await dispatchRoutines(agentEnv);
  expect(
    received.filter((input) => input.messageId.includes(weeklyStatus.id)).map((i) => i.messageId),
  ).toEqual([runs[0]!.messageId, runs[0]!.messageId]);
});

it("paused routines and paused employees' routines don't run", async () => {
  const { scope } = await business();
  const { received, agentEnv } = runtime();
  const paused = await activeRoutine(scope);
  await sql.run("UPDATE routines SET state = 'paused', next_run_at = NULL WHERE id = $1", [
    paused.id,
  ]);
  const waiting = await activeRoutine(scope);
  await sql.run("UPDATE employees SET paused_at = now() WHERE id = $1", [scope.employeeId]);
  await dispatchRoutines(agentEnv);
  expect(received).toEqual([]);
  // Its slot waits for the employee rather than being dropped.
  expect((await Effect.runPromise(routine(db, scope.businessId, waiting.id)))?.next_run_at).toBe(
    waiting.next_run_at,
  );
  await sql.run("UPDATE employees SET paused_at = NULL WHERE id = $1", [scope.employeeId]);
  await dispatchRoutines(agentEnv);
  expect(received.map((input) => input.messageId)).toEqual([
    routineRun(waiting.id, waiting.next_run_at!),
  ]);
});

it("activation is the owner's decision on one exact revision; a later revision needs a new one", async () => {
  const { person, scope } = await business();
  await Effect.runPromise(grant(db, scope, { capability: named("routinePropose"), mode: "auto" }));
  await Effect.runPromise(grant(db, scope, { capability: named("routineActivate"), mode: "ask" }));
  const proposed = (await Effect.runPromise(
    named("routinePropose")
      .execute({
        title: "Inbox sweep",
        instruction: "Look for supplier replies that need an answer.",
        trigger: {
          kind: "cron",
          expression: "*/30 * * * *",
          timezone: "America/New_York",
          hours: { start: "09:00", end: "18:00", days: ["mon", "tue", "wed", "thu", "fri"] },
        },
        notify: "when_found",
      })
      .pipe(as(scope)),
  )) as { ref: string; state: string; revision: number; schedule: string };
  expect(proposed).toMatchObject({ state: "proposed", revision: 1 });
  expect(proposed.schedule).toBe(
    "Every 30 minutes, between 09:00 and 18:00 on Mon, Tue, Wed, Thu, Fri (America/New_York)",
  );
  const id = proposed.ref.slice("devys:work/routine/".length);
  const activate = (revision: number) =>
    Effect.runPromise(
      named("routineActivate").execute({ routine: proposed.ref, revision }).pipe(as(scope)),
    );
  // Proposing activated nothing; activating asks the owner.
  await expect(activate(1)).rejects.toMatchObject({ code: "approval_required" });
  const [asked] = await Effect.runPromise(pendingDecisions(db, scope.businessId));
  expect(asked).toMatchObject({
    capability: "routineActivate",
    input: { routine: id, revision: 1 },
  });
  await Effect.runPromise(
    answerDecision(db, scope.businessId, asked!.id, { approve: true, by: person }),
  );
  const active = (await activate(1)) as { state: string; nextRunAt: string };
  expect(active.state).toBe("active");
  expect(Date.parse(active.nextRunAt)).toBeGreaterThan(Date.now());

  // A new revision stops it and needs a new decision; the old approval was used.
  const revised = (await Effect.runPromise(
    named("routinePropose")
      .execute({
        routine: proposed.ref,
        expectedRevision: 1,
        title: "Inbox sweep",
        instruction: "Look for supplier and customer replies that need an answer.",
        trigger: { kind: "cron", expression: "0 * * * *", timezone: "America/New_York" },
        notify: "when_found",
      })
      .pipe(as(scope)),
  )) as { state: string; revision: number; nextRunAt: string | null };
  expect(revised).toMatchObject({ state: "proposed", revision: 2, nextRunAt: null });
  await expect(activate(2)).rejects.toMatchObject({ code: "approval_required" });
  await expect(activate(1)).rejects.toMatchObject({ code: "approval_required" });

  // Home shows the request with the proposal it decides, readable as a whole.
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  const home = (await (await apiRoute(
    new Request(`https://devys.test/api/businesses/${scope.businessId}/home`, {
      headers: { authorization: `Bearer ${token}` },
    }),
    bindings,
  ))!.json()) as {
    needs_you: {
      capability?: string;
      input?: { revision: number };
      title: string;
      routine: { revision: number; schedule: string } | null;
    }[];
  };
  const requests = home.needs_you.filter((item) => item.capability === "routineActivate");
  expect(requests.find((item) => item.input?.revision === 2)?.routine).toMatchObject({
    revision: 2,
    schedule: "Every hour (America/New_York)",
  });
  // The request for the old revision no longer has a proposal to show.
  expect(requests.find((item) => item.input?.revision === 1)?.routine).toBeNull();
  expect(requests.map((item) => item.title)).toEqual(["Inbox sweep", "Inbox sweep"]);
});

it("a routine grants nothing: its runs act with the employee's own grants", async () => {
  const { scope } = await business();
  const item = await activeRoutine(scope, {
    instruction: "Create the weekly report in Drive.",
  });
  const channel = channelFor(bindings);
  const input = {
    messageId: routineRun(item.id, item.next_run_at!),
    senderId: "dispatcher",
    chatId: routineChat(scope),
    text: "Run",
  };
  // Bound to the employee itself, as any dispatcher input: no principal of its own.
  expect(await channel.binding(input)).toEqual({ personId: "dispatcher", ...scope });
  expect(
    (
      await authorize(
        bindings,
        scope,
        named("driveCreate"),
        { name: "report.txt", content: "Signups: 12" },
        { conversation: `direct:${scope.employeeId}` },
      )
    ).outcome,
  ).toBe("deny");
  // Another conversation, or a paused routine, is not bound at all.
  expect(
    await channel.binding({ ...input, chatId: routineChat(scope, "project:elsewhere") }),
  ).toBeUndefined();
  await sql.run("UPDATE routines SET state = 'paused', next_run_at = NULL WHERE id = $1", [
    item.id,
  ]);
  expect(await channel.binding(input)).toBeUndefined();
});

it("a quiet run that finds nothing posts nothing and is counted in the briefing; others post", async () => {
  const { scope } = await business();
  const channel = channelFor(bindings);
  const quiet = await activeRoutine(scope, { title: "Inbox sweep", notify: "when_found" });
  const loud = await activeRoutine(scope, { title: "Weekly signups", notify: "always" });
  const since = new Date(Date.now() - 1000).toISOString();
  const reply = (item: { id: string; next_run_at: string | null }, text: string) =>
    channel.send(
      scope,
      routineChat(scope),
      text,
      crypto.randomUUID(),
      routineRun(item.id, item.next_run_at!),
    );
  await reply(quiet, "NOTHING");
  await reply(quiet, " NOTHING\n");
  await reply(loud, "NOTHING");
  const said = await Effect.runPromise(
    messages(db, scope.businessId, `direct:${scope.employeeId}`),
  );
  // Only the routine that always speaks posted (even its "NOTHING").
  expect(said.map((message) => message.text)).toEqual(["NOTHING"]);
  expect((await Effect.runPromise(routine(db, scope.businessId, quiet.id)))?.last_result).toBe(
    "nothing to report",
  );
  await reply(loud, "12 signups last week, up from 9.\n\nDetails follow.");
  expect((await Effect.runPromise(routine(db, scope.businessId, loud.id)))?.last_result).toBe(
    "12 signups last week, up from 9. Details follow.",
  );
  const counted = await Effect.runPromise(quietRuns(db, scope.businessId, since));
  expect(counted).toEqual([{ id: quiet.id, title: "Inbox sweep", runs: 2 }]);
  expect(briefing([], since, Date.now(), counted)).toBe(
    'While you were away:\nChecked, nothing to report: "Inbox sweep" 2 times.',
  );
  expect(
    await Effect.runPromise(quietRuns(db, scope.businessId, new Date().toISOString())),
  ).toEqual([]);
});

it("an event starts each matching routine once per event id", async () => {
  const { scope } = await business();
  const { received, agentEnv } = runtime();
  const supplier = await activeRoutine(scope, {
    title: "Supplier replies",
    trigger: { kind: "event", source: "test", type: "reply", filters: { from: "parts@acme.test" } },
  });
  const any = await activeRoutine(scope, {
    title: "Any reply",
    trigger: { kind: "event", source: "test", type: "reply", filters: {} },
  });
  await activeRoutine(scope, {
    title: "Other source",
    trigger: { kind: "event", source: "other", type: "reply", filters: {} },
  });
  const event = {
    source: "test",
    type: "reply",
    id: "msg-1",
    fields: { from: "parts@acme.test", subject: "Price" },
  };
  expect((await routeEvent(agentEnv, scope.businessId, event)).sort()).toEqual(
    [supplier.id, any.id].sort(),
  );
  await routeEvent(agentEnv, scope.businessId, event);
  expect(received.map((input) => input.messageId).sort()).toEqual(
    [
      routineRun(supplier.id, "event:msg-1"),
      routineRun(supplier.id, "event:msg-1"),
      routineRun(any.id, "event:msg-1"),
      routineRun(any.id, "event:msg-1"),
    ].sort(),
  );
  expect(received[0]!.text).toContain('"subject":"Price"');
  // A filter that differs starts nothing there.
  expect(
    await routeEvent(agentEnv, scope.businessId, {
      ...event,
      id: "msg-2",
      fields: { from: "someone@else.test" },
    }),
  ).toEqual([any.id]);
  // Another business's routines never hear it.
  const other = await business();
  expect(await routeEvent(agentEnv, other.scope.businessId, event)).toEqual([]);
});

it("a follow-up wakes waiting work once, and any other state clears it", async () => {
  const { scope } = await business();
  const { received, agentEnv } = runtime();
  await Effect.runPromise(grant(db, scope, { capability: named("workUpdate"), mode: "auto" }));
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: scope.employeeId,
      title: "Chase the supplier",
      createdBy: "person:test",
    }),
  );
  const update = (input: Record<string, unknown>) =>
    Effect.runPromise(
      named("workUpdate")
        .execute({ item: ref("work", "item", work.id), ...input })
        .pipe(as(scope, { workItemId: work.id }), Effect.flip),
    ).catch(() => undefined);
  const thursday = new Date(Date.now() + 3 * 24 * 3600_000).toISOString();
  // A follow-up goes with waiting, in the future.
  expect(await update({ expectedRevision: 1, wakeAt: thursday })).toMatchObject({
    code: "invalid_input",
  });
  expect(
    await update({ expectedRevision: 1, state: "waiting", wakeAt: "2020-01-01T00:00:00Z" }),
  ).toMatchObject({ code: "invalid_input" });
  const waiting = await Effect.runPromise(
    named("workUpdate")
      .execute({
        item: ref("work", "item", work.id),
        expectedRevision: 1,
        state: "waiting",
        waitCondition: "The supplier's price",
        wakeAt: thursday,
      })
      .pipe(as(scope, { workItemId: work.id })),
  );
  expect(waiting).toMatchObject({ state: "waiting", wakeAt: thursday });
  // Not yet: nothing wakes.
  await minuteTick(agentEnv);
  expect(received.filter((input) => input.chatId.endsWith(work.id))).toEqual([]);
  await sql.run("UPDATE work_items SET wake_at = now() - interval '1 minute' WHERE id = $1", [
    work.id,
  ]);
  await minuteTick(agentEnv);
  await minuteTick(agentEnv);
  const handed = received.filter((input) => input.chatId.endsWith(work.id));
  expect(handed.map((input) => input.messageId)).toEqual([`${work.id}:3`]);
  expect(handed[0]!.text).toContain("It was waiting on: The supplier's price");
  expect(handed[0]!.text).toContain("This is the follow-up you set; it came due");
  const woken = (await Effect.runPromise(workItem(db, scope.businessId, work.id)))!;
  expect(woken).toMatchObject({ state: "in_progress", wake_at: null });

  // Waiting again with a follow-up, then moving on: the follow-up is cleared.
  const again = await Effect.runPromise(
    named("workUpdate")
      .execute({
        item: ref("work", "item", work.id),
        expectedRevision: woken.revision,
        state: "waiting",
        wakeAt: thursday,
      })
      .pipe(as(scope, { workItemId: work.id })),
  );
  const moved = await Effect.runPromise(
    named("workUpdate")
      .execute({
        item: ref("work", "item", work.id),
        expectedRevision: (again as { revision: number }).revision,
        state: "in_progress",
      })
      .pipe(as(scope, { workItemId: work.id })),
  );
  expect(moved).toMatchObject({ state: "in_progress", wakeAt: null });
});

it("work is updated from any conversation but completed only in its thread; Operations anywhere", async () => {
  const { scope } = await business();
  const engineer = await Effect.runPromise(
    createEmployee(db, scope.businessId, {
      name: "Engineering",
      responsibilities: "Builds the product.",
      model: "claude-opus-5-5",
      template: "engineering",
    }),
  );
  const mine = { businessId: scope.businessId, employeeId: engineer.id };
  for (const capability of ["workUpdate", "workComplete", "workCreate"])
    await Effect.runPromise(grant(db, mine, { capability: named(capability), mode: "auto" }));
  const work = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: engineer.id,
      title: "Build the page",
      createdBy: "person:t",
    }),
  );
  const elsewhere = { conversation: `direct:${engineer.id}` };
  const thread = { workItemId: work.id, conversation: `work:${work.id}` };
  const update = named("workUpdate").execute({
    item: ref("work", "item", work.id),
    expectedRevision: 1,
    nextAction: "Draft",
  });
  // What the owner asks for in a chat is recorded there: its plan changes from anywhere.
  expect(await Effect.runPromise(update.pipe(as(mine, elsewhere)))).toMatchObject({
    nextAction: "Draft",
  });
  // It is completed only in its own thread, where it is worked; another item's thread is
  // elsewhere too.
  const complete = named("workComplete").execute({
    item: ref("work", "item", work.id),
    expectedRevision: 2,
    evidence: "Shipped",
  });
  const refused = await Effect.runPromise(Effect.flip(complete.pipe(as(mine, elsewhere))));
  expect(refused).toMatchObject({ code: "conflict" });
  expect(refused.message).toContain(`devys:work/item/${work.id}`);
  const other = await Effect.runPromise(
    createWorkItem(db, scope.businessId, {
      id: crypto.randomUUID(),
      owner: engineer.id,
      title: "Other",
      createdBy: "person:t",
    }),
  );
  expect(
    await Effect.runPromise(
      Effect.flip(
        complete.pipe(as(mine, { workItemId: other.id, conversation: `work:${other.id}` })),
      ),
    ),
  ).toMatchObject({ code: "conflict" });
  expect(await Effect.runPromise(complete.pipe(as(mine, thread)))).toMatchObject({
    state: "completed",
  });
  // Creating work is allowed anywhere.
  expect(
    await Effect.runPromise(
      named("workCreate").execute({ title: "Follow-on" }).pipe(as(mine, elsewhere)),
    ),
  ).toMatchObject({ title: "Follow-on" });
  // Operations coordinates from its own direct chat.
  await Effect.runPromise(grant(db, scope, { capability: named("workUpdate"), mode: "auto" }));
  expect(
    await Effect.runPromise(
      named("workUpdate")
        .execute({ item: ref("work", "item", other.id), expectedRevision: 1, nextAction: "Ship" })
        .pipe(as(scope, { conversation: `direct:${scope.employeeId}` })),
    ),
  ).toMatchObject({ nextAction: "Ship" });
});

it("the owner lists routines by employee and project, and pauses and resumes them", async () => {
  const { person, scope } = await business();
  const launch = await Effect.runPromise(
    createProject(db, scope.businessId, { id: crypto.randomUUID(), name: "Launch" }),
  );
  const status = await activeRoutine(scope, { projectId: launch.id, title: "Weekly status" });
  await activeRoutine(scope, { title: "Signups" });
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  await sql.run(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [await sha256(token), person],
  );
  const call = async (path: string, method = "GET") =>
    (await apiRoute(
      new Request(`https://devys.test/api/businesses/${scope.businessId}${path}`, {
        method,
        headers: { authorization: `Bearer ${token}` },
      }),
      bindings,
    ))!;
  const listed = async (query: string) =>
    ((await (await call(`/routines${query}`)).json()) as { routines: { title: string }[] }).routines
      .map((item) => item.title)
      .sort();
  expect(await listed("")).toEqual(["Signups", "Weekly status"]);
  expect(await listed(`?project=${launch.id}`)).toEqual(["Weekly status"]);
  expect(await listed(`?employee=${scope.employeeId}`)).toEqual(["Signups", "Weekly status"]);
  const paused = await call(`/routines/${status.id}/pause`, "POST");
  expect(await paused.json()).toMatchObject({ state: "paused", next_run_at: null });
  const resumed = await call(`/routines/${status.id}/resume`, "POST");
  const body = (await resumed.json()) as { state: string; next_run_at: string };
  expect(body.state).toBe("active");
  expect(Date.parse(body.next_run_at)).toBeGreaterThan(Date.now());
  expect((await call(`/routines/${status.id}/resume`, "POST")).status).toBe(409);
  // A proposed routine is activated by the owner's decision, not resumed.
  const proposed = crypto.randomUUID();
  await Effect.runPromise(
    proposeRoutine(
      db,
      scope.businessId,
      proposed,
      {
        employeeId: scope.employeeId,
        projectId: null,
        title: "Proposed",
        instruction: "Do it.",
        trigger: weekly,
        notify: "always",
      },
      "employee:test",
    ),
  );
  expect((await call(`/routines/${proposed}/resume`, "POST")).status).toBe(409);
  expect((await call(`/routines/${crypto.randomUUID()}/pause`, "POST")).status).toBe(404);
});
