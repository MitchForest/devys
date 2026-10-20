import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { workChat } from "../channels/work.ts";
import { delegateInstructions, providerName } from "../delegates/capabilities.ts";
import {
  providers,
  type Assignment,
  type Delegates,
  type Provider,
} from "../delegates/contract.ts";
import {
  assignment,
  assignmentsFor,
  recordAssignment,
  recordStarted,
} from "../delegates/service.ts";
import { scopeName, type Business, type Person, type Scope } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { sha256 } from "../protocol/bytes.ts";
import { commitment, createCommitment, setTakeover } from "../work/service.ts";
import { delegatesFor } from "./delegates.ts";
import { postEvent } from "./conversations.ts";

type Access = { person: Person; business: Business; trusted: boolean; path: string };

const json = async <T>(request: Request) => (await request.json().catch(() => ({}))) as Partial<T>;

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
  delegates: (scope: Scope) => Delegates = delegatesFor(env),
) {
  const { person, business, trusted, path } = access;
  if (path === "/coding" && request.method === "POST")
    return trusted ? startOwned(request, env, access, delegates) : forbidden();
  const match =
    /^\/work\/([A-Za-z0-9-]{1,64})\/sessions(?:\/([A-Za-z0-9-]{1,64})(?:\/(diff|send|interrupt))?)?$/.exec(
      path,
    );
  if (!match) return undefined;
  const [, workId, assignmentId, action] = match;
  const work = await Effect.runPromise(commitment(env.HYPERDRIVE, business.id, workId!));
  if (!work) return notFound();
  if (!assignmentId && request.method === "GET") {
    const items = (
      await Effect.runPromise(assignmentsFor(env.HYPERDRIVE, business.id, work.id))
    ).filter((item) => item.session_id);
    return Response.json({
      sessions: await Promise.all(items.map((item) => sessionOf(delegates, business.id, item))),
    });
  }
  const item = assignmentId
    ? await Effect.runPromise(assignment(env.HYPERDRIVE, business.id, assignmentId))
    : undefined;
  if (!item || item.commitment_id !== work.id || !item.session_id) return notFound();
  const host = delegates({ businessId: business.id, employeeId: item.employee_id });
  if (action === "diff" && request.method === "GET") return Response.json(await host.diff(item.id));
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (action === "interrupt") {
    await host.interrupt(item.id);
    return Response.json({ interrupted: true });
  }
  if (action === "send") {
    // Steering a session yourself is taking the work over, so its employee stops steering it.
    if (work.taken_over_by !== person.id)
      return new Response("Take over the work item to steer its session yourself.", {
        status: 409,
      });
    const { text } = await json<{ text: string }>(request);
    if (typeof text !== "string" || !text.trim() || text.length > 8000)
      return new Response("Say what the session should do.", { status: 400 });
    const sent = await host.send(item.id, text);
    await postEvent(env, business.id, `work:${work.id}`, {
      clientId: `owner-send:${crypto.randomUUID()}`,
      text: `${person.display_name} → ${providerName(item.provider)}: ${text}`,
      ref: item.id,
    });
    return Response.json(sent);
  }
  return notFound();
}

/** A session as the owner sees it: the reference, plus live state from the provider. */
async function sessionOf(
  delegates: (scope: Scope) => Delegates,
  businessId: string,
  item: Assignment,
) {
  try {
    const status = await delegates({ businessId, employeeId: item.employee_id }).inspect(item.id);
    return { ...item, ...status };
  } catch (error) {
    return {
      ...item,
      state: "unavailable" as const,
      reply: null,
      diffStat: "",
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
  delegates: (scope: Scope) => Delegates,
) {
  const { person, business } = access;
  const input = await json<{
    clientId: string;
    employee: string;
    provider: Provider;
    objective: string;
    repository: string;
    newRepository: string;
  }>(request);
  if (
    typeof input.clientId !== "string" ||
    !/^[A-Za-z0-9-]{8,64}$/.test(input.clientId) ||
    !providers.includes(input.provider as Provider) ||
    typeof input.objective !== "string" ||
    !input.objective.trim() ||
    input.objective.length > 8000 ||
    !input.repository === !input.newRepository
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
  const digest = await sha256(`${business.id}:owned:${input.clientId}`);
  const id = `${digest.slice(0, 8)}-${digest.slice(8, 12)}-${digest.slice(12, 16)}-${digest.slice(16, 20)}-${digest.slice(20, 32)}`;
  const existing = await Effect.runPromise(assignment(env.HYPERDRIVE, business.id, id));
  const workId =
    existing?.commitment_id ??
    (
      await Effect.runPromise(
        createCommitment(env.HYPERDRIVE, business.id, {
          owner: scope.employeeId,
          title: input.objective.split("\n")[0]!.slice(0, 200),
          objective: input.objective.slice(0, 4000),
          createdBy: `person:${person.id}`,
        }),
      )
    ).id;
  await Effect.runPromise(setTakeover(env.HYPERDRIVE, business.id, workId, person.id));
  await Effect.runPromise(
    recordAssignment(env.HYPERDRIVE, business.id, {
      id,
      commitmentId: workId,
      employeeId: scope.employeeId,
      provider: input.provider as Provider,
      purpose: "build",
      objective: input.objective,
    }),
  );
  const started = await delegates(scope).start({
    id,
    scope,
    provider: input.provider as Provider,
    purpose: "build",
    repository: input.repository ? { path: input.repository } : { create: input.newRepository! },
    objective: input.objective,
    instructions: delegateInstructions("build"),
  });
  await Effect.runPromise(recordStarted(env.HYPERDRIVE, business.id, id, started));
  return Response.json({ work: workId, assignment: id, ...started }, { status: 201 });
}

/**
 * Handing a work item back: when it has coding sessions, its employee is woken in its work
 * session to read what changed while the owner drove, then carries on.
 */
export async function handBack(
  env: Env,
  businessId: string,
  workId: string,
  delegates: (scope: Scope) => Delegates = delegatesFor(env),
) {
  const work = await Effect.runPromise(commitment(env.HYPERDRIVE, businessId, workId));
  if (!work) return;
  const items = (
    await Effect.runPromise(assignmentsFor(env.HYPERDRIVE, businessId, workId))
  ).filter((item) => item.session_id);
  if (!items.length) return;
  const scope = { businessId, employeeId: work.owner_employee_id };
  const sessions = await Promise.all(items.map((item) => sessionOf(delegates, businessId, item)));
  const text = [
    "The owner handed this work item back to you after driving its coding sessions. Read what changed, then carry on: review, iterate with codingSend, accept with codingAccept and the repository's check.",
    ...sessions.map(
      (session) =>
        `${providerName(session.provider)} session ${session.id} (${session.purpose}, ${session.state}) in ${session.worktree}:\n${session.diffStat || "no changes"}${session.reply ? `\nIts latest reply: ${session.reply.slice(0, 2000)}` : ""}`,
    ),
  ].join("\n\n");
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `handback:${workId}:${work.revision}`,
    senderId: "dispatcher",
    chatId: workChat(scope, workId),
    text,
  });
}

const notFound = () => new Response("Not found", { status: 404 });
const forbidden = () => new Response("Forbidden", { status: 403 });
