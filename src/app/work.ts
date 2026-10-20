import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { conversationKey } from "../conversations/contract.ts";
import { postFromPerson } from "./conversations.ts";
import { activeEmployee } from "../identity/service.ts";
import { answerDecision, pendingDecisions } from "../authority/service.ts";
import {
  commitments,
  createCommitment,
  setTakeover,
  updateCommitment,
  type Change,
} from "../work/service.ts";
import type { CommitmentState } from "../work/contract.ts";
import { addToSpace } from "../work/spaces.ts";
import { capabilities } from "./capabilities.ts";
import { handBack } from "./coding.ts";
import { body, forbidden, label, notFound } from "./request.ts";

const states: CommitmentState[] = [
  "proposed",
  "ready",
  "in_progress",
  "waiting",
  "needs_decision",
  "completed",
  "cancelled",
];
const when = (value: unknown) =>
  typeof value === "string" && Number.isFinite(Date.parse(value))
    ? new Date(value).toISOString()
    : undefined;

/** The business's commitments, operated by its members through the same rules as employees. */
export async function workRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/work" && request.method === "GET") {
    const since = when(new URL(request.url).searchParams.get("since"));
    return Response.json({
      commitments: await Effect.runPromise(commitments(env.HYPERDRIVE, business.id, since)),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const isEmployee = async (id: unknown) =>
    typeof id === "string" &&
    Boolean(
      await Effect.runPromise(
        activeEmployee(env.HYPERDRIVE, { businessId: business.id, employeeId: id }),
      ),
    );
  if (path === "/work") {
    const input = await body<{
      title: string;
      owner: string;
      objective: string;
      nextAction: string;
      dueAt: string;
      conditions: Record<string, Record<string, unknown>>;
      spaceId: string;
    }>(request, 16_000);
    const title = label(input.title, 200);
    if (!title || !(await isEmployee(input.owner)))
      return new Response("Send a title and an employee of this business", { status: 400 });
    const conditions = input.conditions ?? {};
    const catalog = capabilities(env);
    for (const [name, values] of Object.entries(conditions)) {
      const contract = catalog.find((item) => item.name === name);
      try {
        if (!contract?.constraints) throw new Error("no limits");
        Schema.decodeUnknownSync(contract.constraints.schema)(values);
      } catch {
        return new Response(`Conditions for ${name} don't fit it`, { status: 400 });
      }
    }
    const created = await Effect.runPromise(
      createCommitment(env.HYPERDRIVE, business.id, {
        owner: input.owner!,
        title,
        ...(typeof input.objective === "string"
          ? { objective: input.objective.slice(0, 4000) }
          : {}),
        ...(typeof input.nextAction === "string"
          ? { nextAction: input.nextAction.slice(0, 1000) }
          : {}),
        ...(when(input.dueAt) ? { dueAt: when(input.dueAt) } : {}),
        conditions,
        createdBy: `person:${person.id}`,
      }),
    );
    // Created from a space, the task is also shown there.
    if (typeof input.spaceId === "string")
      await Effect.runPromise(
        addToSpace(env.HYPERDRIVE, business.id, input.spaceId, {
          kind: "commitment",
          ref: created.id,
        }),
      );
    return Response.json(created, { status: 201 });
  }
  const takeover = /^\/work\/([A-Za-z0-9-]{1,64})\/(takeover|release)$/.exec(path);
  if (takeover) {
    const item = await Effect.runPromise(
      setTakeover(
        env.HYPERDRIVE,
        business.id,
        takeover[1]!,
        takeover[2] === "takeover" ? person.id : null,
      ),
    );
    if (item && takeover[2] === "release") await handBack(env, business.id, item.id);
    return item ? Response.json(item) : notFound();
  }
  const id = /^\/work\/([A-Za-z0-9-]{1,64})$/.exec(path)?.[1];
  if (!id) return notFound();
  const input = await body<{
    expectedRevision: number;
    title: string;
    owner: string;
    state: CommitmentState;
    nextAction: string;
    waitCondition: string | null;
    dueAt: string | null;
  }>(request, 8_000);
  if (!Number.isSafeInteger(input.expectedRevision))
    return new Response("Send the commitment's expectedRevision", { status: 400 });
  if (input.state !== undefined && !states.includes(input.state))
    return new Response("Unknown state", { status: 400 });
  if (input.owner !== undefined && !(await isEmployee(input.owner)))
    return new Response("The owner must be an employee of this business", { status: 400 });
  const change: Change = {
    ...(label(input.title, 200) ? { title: label(input.title, 200) } : {}),
    ...(input.owner ? { owner: input.owner } : {}),
    ...(input.state ? { state: input.state } : {}),
    ...(typeof input.nextAction === "string"
      ? { nextAction: input.nextAction.slice(0, 1000) }
      : {}),
    ...(input.waitCondition !== undefined
      ? { waitCondition: input.waitCondition?.slice(0, 1000) ?? null }
      : {}),
    ...(input.dueAt !== undefined
      ? { dueAt: input.dueAt === null ? null : (when(input.dueAt) ?? null) }
      : {}),
  };
  const updated = await Effect.runPromise(
    updateCommitment(env.HYPERDRIVE, business.id, id, input.expectedRevision!, change, {
      kind: "person",
      id: person.id,
    }),
  );
  return updated
    ? Response.json(updated)
    : new Response("The commitment changed; reload it", { status: 409 });
}

/** Requests waiting on the owner. Approval allows exactly one identical retry. */
export async function decisionRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/decisions" && request.method === "GET")
    return Response.json({
      decisions: await Effect.runPromise(pendingDecisions(env.HYPERDRIVE, business.id)),
    });
  const answer = /^\/decisions\/([A-Za-z0-9-]{1,64})\/(approve|reject)$/.exec(path);
  if (!answer || request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const answered = await Effect.runPromise(
    answerDecision(env.HYPERDRIVE, business.id, answer[1]!, {
      approve: answer[2] === "approve",
      by: person.id,
    }),
  );
  if (!answered)
    return new Response("That request was already answered or has expired", { status: 409 });
  // The answer is said where the employee asked, which wakes it to continue.
  const key = answered.conversation ? conversationKey(answered.conversation) : undefined;
  if (key)
    await postFromPerson(env, business.id, person.id, key, {
      id: `decision:${answered.id}`,
      text:
        answered.status === "approved"
          ? `Approved: ${answered.capability}. Go ahead; it runs once, with exactly the input you asked for.`
          : `Declined: ${answered.capability}. Don't run it; find another way or ask me.`,
      mentions: [answered.employee_id],
    });
  return Response.json({ status: answered.status });
}
