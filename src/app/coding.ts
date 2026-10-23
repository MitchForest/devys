import { Effect } from "effect";
import type { Env } from "./env.ts";
import { ref } from "../protocol/ref.ts";
import { workChat } from "../channels/work.ts";
import {
  codingInstructions,
  providerName,
  type CodingDependencies,
} from "../apps/code/capabilities.ts";
import {
  providers,
  type CodingEvent,
  type CodingHost,
  type CodingSession,
  type Deployed,
  type Provider,
} from "../apps/code/contract.ts";
import {
  codedWork,
  codingSession,
  codingSessionById,
  codingSessionsFor,
  employeeCodingSessions,
  recordCodingSession,
  recordStarted,
  startedSessions,
} from "../apps/code/service.ts";
import { scopeName, type Business, type Person, type Scope } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { stableId } from "../protocol/bytes.ts";
import { setFollowing } from "../conversations/service.ts";
import type { WorkItem } from "../work/contract.ts";
import { addEvidence, createWorkItem, requeue, workItem } from "../work/service.ts";
import { modeOf } from "./mode.ts";
import { postEvent } from "./conversations.ts";
import { body } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { Transcript, WorkingDiff } from "../apps/code/contract.ts";
import { CodedWork, CodingSessions, CodingStarted, Interrupted, Steered } from "./wire.ts";
import { coordinates } from "../identity/team.ts";

type Access = { person: Person; business: Business; trusted: boolean; path: string };

/**
 * The owner's side of coding sessions (.docs/PRODUCT_EXPERIENCE.md#first-class-coding-workspace):
 * a work item's sessions with their live state and diff, steering one directly while the work
 * item is taken over, stopping one, and starting a session with no employee driving. Session
 * state is read from the provider each time; nothing here stores it.
 */
export async function codingRoute(
  request: Request,
  env: Env,
  access: Access,
  coding: (scope: Scope) => CodingHost = modeOf(env).coding,
) {
  const { person, business, trusted, path } = access;
  if (path === "/coding" && request.method === "GET")
    return respond(CodedWork, {
      work: await Effect.runPromise(codedWork(env.HYPERDRIVE, business.id)),
      sessions: await Effect.runPromise(startedSessions(env.HYPERDRIVE, business.id)),
    });
  if (path === "/coding" && request.method === "POST")
    return trusted ? startOwned(request, env, access, coding) : forbidden();
  const match =
    /^\/work\/([A-Za-z0-9-]{1,64})\/sessions(?:\/([A-Za-z0-9-]{1,64})(?:\/(diff|transcript|send|interrupt))?)?$/.exec(
      path,
    );
  if (!match) return undefined;
  const [, workId, codingSessionId, action] = match;
  const work = await Effect.runPromise(workItem(env.HYPERDRIVE, business.id, workId!));
  if (!work) return notFound();
  if (!codingSessionId && request.method === "GET") {
    const items = (
      await Effect.runPromise(codingSessionsFor(env.HYPERDRIVE, business.id, work.id))
    ).filter((item) => item.provider_session_id);
    return respond(CodingSessions, {
      sessions: await Promise.all(items.map((item) => sessionOf(coding, business.id, item))),
    });
  }
  const item = codingSessionId
    ? await Effect.runPromise(codingSession(env.HYPERDRIVE, business.id, codingSessionId))
    : undefined;
  if (!item || item.work_item_id !== work.id || !item.provider_session_id) return notFound();
  const host = coding({ businessId: business.id, employeeId: item.employee_id });
  if (action === "diff" && request.method === "GET")
    return respond(WorkingDiff, await host.diff(item.id));
  if (action === "transcript" && request.method === "GET")
    return respond(Transcript, await host.transcript(item.id));
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (action === "interrupt") {
    await host.interrupt(item.id);
    return respond(Interrupted, { interrupted: true });
  }
  if (action === "send") {
    // Steering a session yourself is taking the work over, so its employee stops steering it.
    if (work.taken_over_by !== person.id)
      return new Response("Take over the work item to steer its session yourself.", {
        status: 409,
      });
    const { text } = await body<{ text: string }>(request, 64_000);
    if (typeof text !== "string" || !text.trim() || text.length > 8000)
      return new Response("Say what the session should do.", { status: 400 });
    const sent = await host.send(item.id, text);
    await postEvent(env, business.id, `work:${work.id}`, {
      clientId: `owner-send:${crypto.randomUUID()}`,
      text: `${person.display_name} → ${providerName(item.provider)}: ${text}`,
      ref: ref("code", "session", item.id),
    });
    return respond(Steered, sent);
  }
  return notFound();
}

/** A session as the owner sees it: the reference, plus live state from the provider. */
async function sessionOf(
  coding: (scope: Scope) => CodingHost,
  businessId: string,
  item: CodingSession,
) {
  try {
    const { diffStat, ...status } = await coding({
      businessId,
      employeeId: item.employee_id,
    }).inspect(item.id);
    return { ...item, ...status, diff_stat: diffStat };
  } catch (error) {
    return {
      ...item,
      state: "unavailable" as const,
      reply: null,
      diff_stat: "",
      error: error instanceof Error ? error.message : "The Mac host is unavailable",
    };
  }
}

/**
 * "New coding session": a work item owned by the chosen employee but already taken over by
 * the owner, so the owner drives; handing it back lets the employee verify and ship.
 */
async function startOwned(
  request: Request,
  env: Env,
  access: Access,
  coding: (scope: Scope) => CodingHost,
) {
  const { person, business } = access;
  const input = await body<{
    client_id: string;
    employee: string;
    provider: Provider;
    objective: string;
    repository: string;
    new_repository: string;
  }>(request, 16_000);
  if (
    typeof input.client_id !== "string" ||
    !/^[A-Za-z0-9-]{8,64}$/.test(input.client_id) ||
    !providers.includes(input.provider as Provider) ||
    typeof input.objective !== "string" ||
    !input.objective.trim() ||
    input.objective.length > 8000 ||
    !input.repository === !input.new_repository
  )
    return new Response(
      "Send a client id, a provider, an objective, and a repository path or a new repository name.",
      { status: 400 },
    );
  const scope = { businessId: business.id, employeeId: String(input.employee) };
  if (!(await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope))))
    return new Response("Choose an employee of this business to hand it to later.", {
      status: 400,
    });
  const id = await stableId(`${business.id}:owned:${input.client_id}`);
  const existing = await Effect.runPromise(codingSession(env.HYPERDRIVE, business.id, id));
  const workId =
    existing?.work_item_id ??
    (
      await Effect.runPromise(
        createWorkItem(env.HYPERDRIVE, business.id, {
          id: await stableId(`${business.id}:owned-work:${input.client_id}`),
          owner: scope.employeeId,
          title: input.objective.split("\n")[0]!.slice(0, 200),
          objective: input.objective.slice(0, 4000),
          createdBy: `person:${person.id}`,
          // Created taken over, so the dispatcher never hands it to the employee meanwhile.
          takenOverBy: person.id,
        }),
      )
    ).id;
  await Effect.runPromise(
    recordCodingSession(env.HYPERDRIVE, business.id, {
      id,
      workItemId: workId,
      employeeId: scope.employeeId,
      provider: input.provider as Provider,
      purpose: "build",
      objective: input.objective,
    }),
  );
  const started = await coding(scope).start({
    id,
    scope,
    provider: input.provider as Provider,
    purpose: "build",
    repository: input.repository ? { path: input.repository } : { create: input.new_repository! },
    objective: input.objective,
    instructions: codingInstructions("build"),
  });
  await Effect.runPromise(recordStarted(env.HYPERDRIVE, business.id, id, started));
  // The owner drives this one, so they follow each milestone of it.
  await Effect.runPromise(
    setFollowing(env.HYPERDRIVE, business.id, `work:${workId}`, person.id, true),
  );
  return respond(
    CodingStarted,
    {
      work: workId,
      coding_session: id,
      provider_session_id: started.providerSessionId,
      repository: started.repository,
      base_commit: started.baseCommit,
      branch: started.branch,
      worktree: started.worktree,
    },
    { status: 201 },
  );
}

/**
 * Handing a work item back: when it has coding sessions, its employee is woken in its work
 * session to read what changed while the owner drove, then carries on.
 */
export async function handBack(
  env: Env,
  businessId: string,
  workId: string,
  coding: (scope: Scope) => CodingHost = modeOf(env).coding,
) {
  const work = await Effect.runPromise(workItem(env.HYPERDRIVE, businessId, workId));
  if (!work) return;
  const items = (
    await Effect.runPromise(codingSessionsFor(env.HYPERDRIVE, businessId, workId))
  ).filter((item) => item.provider_session_id);
  // Without coding sessions there is nothing to brief: the dispatcher hands the work over again.
  if (!items.length)
    return void (await Effect.runPromise(requeue(env.HYPERDRIVE, businessId, workId)));
  const scope = { businessId, employeeId: work.owner_employee_id };
  const sessions = await Promise.all(items.map((item) => sessionOf(coding, businessId, item)));
  const text = [
    "The owner handed this work item back to you after driving its coding sessions. Read what changed, then carry on: review, iterate with codingSend, accept with codingAccept and the repository's check.",
    ...sessions.map(
      (session) =>
        `${providerName(session.provider)} session ${ref("code", "session", session.id)} (${session.purpose}, ${session.state}) in ${session.worktree}:\n${session.diff_stat || "no changes"}${session.reply ? `\nIts latest reply: ${session.reply.slice(0, 2000)}` : ""}`,
    ),
  ].join("\n\n");
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `handback:${workId}:${work.revision}`,
    senderId: "dispatcher",
    chatId: workChat(scope, workId),
    text,
  });
}

export function codingDependencies(env: Env): CodingDependencies {
  return {
    db: env.HYPERDRIVE,
    coding: modeOf(env).coding,
    note: async (scope, workItemId, note) => {
      await postEvent(env, scope.businessId, `work:${workItemId}`, note);
    },
    evidence: async (scope, workItemId, entry) => {
      await Effect.runPromise(
        addEvidence(env.HYPERDRIVE, scope.businessId, workItemId, {
          by: `employee:${scope.employeeId}`,
          ...entry,
        }),
      );
    },
    coordinates: (scope) => coordinates(env.HYPERDRIVE, scope),
    knownCommits: async (scope, workItemId) =>
      (
        (await Effect.runPromise(workItem(env.HYPERDRIVE, scope.businessId, workItemId)))
          ?.evidence ?? []
      ).flatMap((entry) => (entry.commit ? [entry.commit] : [])),
  };
}

/**
 * Work with a coding build is complete only once its last accepted commit passed the
 * repository's check (the check's result is recorded as evidence when it reports).
 */
export async function codingIncomplete(env: Env, businessId: string, work: WorkItem) {
  const builds = (
    await Effect.runPromise(codingSessionsFor(env.HYPERDRIVE, businessId, work.id))
  ).filter((item) => item.purpose === "build");
  if (!builds.length) return undefined;
  // An acceptance records the commit with its changes; its check reports later against it.
  const accepted = work.evidence.findLast((entry) => entry.changes !== undefined)?.commit;
  const check =
    accepted && work.evidence.findLast((entry) => entry.check && entry.commit === accepted)?.check;
  if (!check)
    return "This work has a coding session: accept it with codingAccept and wait for the check of the accepted commit to pass before completing.";
  if (check.exit_code !== 0)
    return "The last check failed: fix it with codingSend, accept again, and complete once the check passes.";
  return undefined;
}

/** Employee Stop also interrupts its coding sessions, so no child keeps working unnoticed. */
export async function interruptCodingSessions(env: Env, scope: Scope) {
  const coding = modeOf(env).coding(scope);
  const started = await Effect.runPromise(
    employeeCodingSessions(env.HYPERDRIVE, scope.businessId, scope.employeeId),
  );
  // Interrupting an idle session changes nothing, so all are asked at once.
  await Promise.allSettled(started.map((item) => coding.interrupt(item.id)));
}

/** A check's outcome in words, with the short commit: "The check passed on 1a2b3c4". */
const checkedLine = (check: NonNullable<CodingEvent["check"]>) =>
  `The check ${check.exitCode === 0 ? "passed" : check.exitCode === null ? "didn't finish" : "failed"} on ${check.commit.slice(0, 7)}`;

/** A deploy's outcome in words: where it went and whether its address answers. */
const deployedLine = ({ stage, commit, exitCode, url, live }: Deployed) =>
  exitCode !== 0
    ? `The deploy of ${commit.slice(0, 7)} to ${stage} failed`
    : live
      ? `Deployed ${commit.slice(0, 7)} to ${stage} · live at ${url}`
      : url
        ? `Deployed ${commit.slice(0, 7)} to ${stage}, but ${url} isn't answering`
        : `Deployed ${commit.slice(0, 7)} to ${stage}; there was no address to check`;

/** The "3 files changed, …" line of a diff stat, or how many files are new. */
const changeSummary = (diffStat: string) => {
  const lines = diffStat.split("\n");
  const total = lines.find((line) => /files? changed/.test(line))?.trim();
  const added = lines.filter((line) => line.endsWith("(new)")).length;
  return [total, added ? `${added} new file${added === 1 ? "" : "s"}` : ""]
    .filter(Boolean)
    .join(", ");
};

/**
 * Events from the Mac host. Each becomes a card in the work item's thread; anything but a
 * start also wakes the employee that started the session, in its session for that work.
 * Both are keyed by the event id, so a repeated delivery changes nothing.
 */
export async function codingEventsRoute(request: Request, env: Env) {
  if (!(await modeOf(env).fromHost(request))) return new Response("Unauthorized", { status: 401 });
  const { events } = await body<{ events: CodingEvent[] }>(request, 8_000_000);
  // Each event is answered on its own, so one that keeps failing never holds up the rest.
  const delivered: string[] = [];
  for (const event of Array.isArray(events) ? events : [])
    await deliverEvent(env, event).then(
      () => delivered.push(event.id),
      (error: unknown) => console.error(`Coding event ${event.id} failed:`, error),
    );
  return Response.json({ delivered });
}

async function deliverEvent(env: Env, event: CodingEvent) {
  if (!event.codingSessionId) return deliverRepositoryDeploy(env, event);
  const item = await Effect.runPromise(codingSessionById(env.HYPERDRIVE, event.codingSessionId));
  if (!item) return;
  const scope = { businessId: item.business_id, employeeId: item.employee_id };
  const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
  const who = providerName(item.provider);
  const changed = event.diffStat ? changeSummary(event.diffStat) : "";
  // What the owner reads: a short line in words; the provider's and host's own text (commands,
  // paths, output) stays in the session layer and goes to the employee below.
  const card = {
    started: `${employee?.name ?? "An employee"} started ${who}${item.purpose === "review" ? " to review the change" : ""}`,
    finished: `${who} finished${changed ? ` · ${changed}` : ""}`,
    failed: `${who} stopped with an error`,
    interrupted: `${who} was interrupted`,
    checked: event.check ? checkedLine(event.check) : "The check ended",
    deployed: event.deploy ? deployedLine(event.deploy) : "The deploy ended",
  }[event.kind];
  await postEvent(env, item.business_id, `work:${item.work_item_id}`, {
    clientId: `coding:${event.id}`,
    text: card,
    ref: ref("code", "session", item.id),
  });
  if (event.kind === "checked" && event.check)
    await Effect.runPromise(
      addEvidence(env.HYPERDRIVE, item.business_id, item.work_item_id, {
        by: "devys",
        note: card,
        commit: event.check.commit,
        check: { command: event.check.command, exit_code: event.check.exitCode },
        source: `coding:${event.id}`,
      }),
    );
  if (event.kind === "deployed" && event.deploy)
    await recordDeploy(env, item.business_id, item.work_item_id, event.id, event.deploy);
  if (event.kind === "started") return;
  // While a person holds the work they drive the session; its employee is briefed once, on
  // hand-back, rather than woken by every turn it may not act on.
  const work = await Effect.runPromise(
    workItem(env.HYPERDRIVE, item.business_id, item.work_item_id),
  );
  if (work?.taken_over_by) return;
  const text = [
    `Your ${who} session ${ref("code", "session", item.id)} (${item.purpose}) on this work item: ${card}.`,
    event.text &&
      `${event.kind === "finished" ? "Its reply" : "What the Mac host reported"}:\n${event.text.slice(0, 8000)}`,
    event.diffStat &&
      `Changes in its worktree ${item.worktree}:\n${event.diffStat.length > 8000 ? `${event.diffStat.slice(0, 8000)}\n… (run git diff --stat in the worktree for the rest)` : event.diffStat}`,
    event.check?.output && `Check output (end):\n${event.check.output.slice(-6000)}`,
    event.deploy?.output &&
      `Deploy output (end, secrets redacted):\n${event.deploy.output.slice(-6000)}`,
    event.kind === "deployed"
      ? event.deploy?.live
        ? "It is live and recorded as evidence. If the work item is done, complete it; production needs its own deploy."
        : "It isn't working: read the output, fix it in the session, accept again and redeploy, or roll back by deploying the last good commit."
      : event.kind === "checked"
        ? event.check?.exitCode === 0
          ? "The check passed and is recorded as evidence. Decide whether the work item is done; publishing and deploying are separate."
          : "Fix it: tell the session what failed with codingSend, then accept again."
        : "Review the result (codingStatus, or read and run things in the worktree). Iterate with codingSend, or accept with codingAccept and the repository's check command.",
  ]
    .filter(Boolean)
    .join("\n\n");
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `coding:${event.id}`.slice(0, 512),
    senderId: "coding",
    chatId: workChat(scope, item.work_item_id),
    text,
  });
}

/**
 * A repository deployed as it is, without a coding session: the line in its work item's thread,
 * the evidence, and the employee that deployed it told how it went.
 */
async function deliverRepositoryDeploy(env: Env, event: CodingEvent) {
  if (event.kind !== "deployed" || !event.deploy || !event.deployedFor) return;
  const { scope, workItemId } = event.deployedFor;
  const card = await recordDeploy(env, scope.businessId, workItemId, event.id, event.deploy);
  await postEvent(env, scope.businessId, `work:${workItemId}`, {
    clientId: `coding:${event.id}`,
    text: card,
  });
  const work = await Effect.runPromise(workItem(env.HYPERDRIVE, scope.businessId, workItemId));
  if (!work || work.taken_over_by) return;
  const text = [
    `Your deploy on this work item: ${card}.`,
    `What the Mac host reported:\n${event.text.slice(0, 8000)}`,
    event.deploy.output &&
      `Deploy output (end, secrets redacted):\n${event.deploy.output.slice(-6000)}`,
    event.deploy.live
      ? "It is live and recorded as evidence. If the work item is done, complete it."
      : "It isn't working: read the output, then fix the repository in a coding session and deploy its accepted work, or deploy again once the cause is fixed.",
  ]
    .filter(Boolean)
    .join("\n\n");
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `coding:${event.id}`.slice(0, 512),
    senderId: "coding",
    chatId: workChat(scope, workItemId),
    text,
  });
}

/** A deploy as the work item's evidence; returns its line in words. */
async function recordDeploy(
  env: Env,
  businessId: string,
  workItemId: string,
  eventId: string,
  deploy: Deployed,
) {
  const note = deployedLine(deploy);
  await Effect.runPromise(
    addEvidence(env.HYPERDRIVE, businessId, workItemId, {
      by: "devys",
      note,
      commit: deploy.commit,
      deploy: { stage: deploy.stage, url: deploy.url, live: deploy.live },
      source: `coding:${eventId}`,
    }),
  );
  return note;
}

const notFound = () => new Response("Not found", { status: 404 });
const forbidden = () => new Response("Forbidden", { status: 403 });
