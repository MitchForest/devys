import { Effect } from "effect";
import type { Env } from "./env.ts";
import { workChat } from "../channels/work.ts";
import { providerName, type DelegateDependencies } from "../delegates/capabilities.ts";
import type { DelegateEvent } from "../delegates/contract.ts";
import { assignmentById, assignmentsFor, employeeAssignments } from "../delegates/service.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { sha256 } from "../protocol/bytes.ts";
import type { Commitment } from "../work/contract.ts";
import { addEvidence, commitment } from "../work/service.ts";
import { postEvent } from "./conversations.ts";
import { modeOf } from "./mode.ts";

export function delegateDependencies(env: Env): DelegateDependencies {
  return {
    db: env.HYPERDRIVE,
    delegates: modeOf(env).delegates,
    note: async (scope, commitmentId, note) => {
      await postEvent(env, scope.businessId, `work:${commitmentId}`, note);
    },
    evidence: async (scope, commitmentId, entry) => {
      await Effect.runPromise(
        addEvidence(env.HYPERDRIVE, scope.businessId, commitmentId, {
          by: `employee:${scope.employeeId}`,
          ...entry,
        }),
      );
    },
  };
}

/**
 * Work with a coding build is complete only once its last accepted commit passed the
 * repository's check (the check's result is recorded as evidence when it reports).
 */
export async function codingIncomplete(env: Env, businessId: string, work: Commitment) {
  const builds = (
    await Effect.runPromise(assignmentsFor(env.HYPERDRIVE, businessId, work.id))
  ).filter((item) => item.purpose === "build");
  if (!builds.length) return undefined;
  const check = work.evidence.findLast((entry) => entry.check)?.check;
  if (!check)
    return "This work has a coding session: accept it with codingAccept and wait for the check to pass before completing.";
  if (check.exitCode !== 0)
    return "The last check failed: fix it with codingSend, accept again, and complete once the check passes.";
  return undefined;
}

/** Employee Stop also interrupts its coding sessions, so no child keeps working unnoticed. */
export async function interruptAssignments(env: Env, scope: Scope) {
  const delegates = modeOf(env).delegates(scope);
  for (const item of await Effect.runPromise(
    employeeAssignments(env.HYPERDRIVE, scope.businessId, scope.employeeId),
  ))
    await delegates.interrupt(item.id).catch(() => undefined);
}

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
export async function delegateEventsRoute(request: Request, env: Env) {
  const token = env.DEVYS_HOST_TOKEN;
  const offered = await sha256(request.headers.get("authorization") ?? "");
  if (!token || offered !== (await sha256(`Bearer ${token}`)))
    return new Response("Unauthorized", { status: 401 });
  const { events } = (await request.json()) as { events: DelegateEvent[] };
  // Each event is answered on its own, so one that keeps failing never holds up the rest.
  const delivered: string[] = [];
  for (const event of events ?? [])
    await deliverEvent(env, event).then(
      () => delivered.push(event.id),
      (error: unknown) => console.error(`Delegate event ${event.id} failed:`, error),
    );
  return Response.json({ delivered });
}

async function deliverEvent(env: Env, event: DelegateEvent) {
  const item = await Effect.runPromise(assignmentById(env.HYPERDRIVE, event.assignmentId));
  if (!item) return;
  const scope = { businessId: item.business_id, employeeId: item.employee_id };
  const employee = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
  const who = providerName(item.provider);
  const changed = event.diffStat ? changeSummary(event.diffStat) : "";
  const card = {
    started: `${employee?.name ?? "An employee"} started ${who}${item.purpose === "review" ? " (review)" : ""}${item.branch ? ` · ${item.branch}` : ""}: ${item.objective.slice(0, 200)}`,
    finished: `${who} finished${changed ? ` · ${changed}` : ""}: ${event.text.slice(0, 600)}`,
    failed: `${who} failed: ${event.text.slice(0, 600)}`,
    interrupted: `${who} was interrupted: ${event.text.slice(0, 600)}`,
    checked: event.text.slice(0, 2000),
  }[event.kind];
  await postEvent(env, item.business_id, `work:${item.commitment_id}`, {
    clientId: `delegate:${event.id}`,
    text: card,
    ref: item.id,
  });
  if (event.kind === "checked" && event.check)
    await Effect.runPromise(
      addEvidence(env.HYPERDRIVE, item.business_id, item.commitment_id, {
        by: "devys",
        note: `\`${event.check.command}\` ${event.check.exitCode === 0 ? "passed" : `failed (exit ${event.check.exitCode ?? "killed"})`} on ${event.check.commit.slice(0, 12)}.`,
        commit: event.check.commit,
        check: { command: event.check.command, exitCode: event.check.exitCode },
        source: `delegate:${event.id}`,
      }),
    );
  if (event.kind === "started") return;
  // While a person holds the work they drive the session; its employee is briefed once, on
  // hand-back, rather than woken by every turn it may not act on.
  const work = await Effect.runPromise(
    commitment(env.HYPERDRIVE, item.business_id, item.commitment_id),
  );
  if (work?.taken_over_by) return;
  const text = [
    `Your ${who} session ${item.id} (${item.purpose}) on this work item: ${card}`,
    event.diffStat &&
      `Changes in its worktree ${item.worktree}:\n${event.diffStat.length > 8000 ? `${event.diffStat.slice(0, 8000)}\n… (run git diff --stat in the worktree for the rest)` : event.diffStat}`,
    event.check?.output && `Check output (end):\n${event.check.output.slice(-6000)}`,
    event.kind === "checked"
      ? event.check?.exitCode === 0
        ? "The check passed and is recorded as evidence. Decide whether the work item is done; publishing and deploying are separate."
        : "Fix it: tell the session what failed with codingSend, then accept again."
      : "Review the result (codingStatus, or read and run things in the worktree). Iterate with codingSend, or accept with codingAccept and the repository's check command.",
  ]
    .filter(Boolean)
    .join("\n\n");
  await env.AGENT.getByName(scopeName(scope)).receive(scope, {
    messageId: `delegate:${event.id}`.slice(0, 512),
    senderId: "delegate",
    chatId: workChat(scope, item.commitment_id),
    text,
  });
}
