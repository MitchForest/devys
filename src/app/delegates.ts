import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
import { workChat } from "../channels/work.ts";
import { providerName, type DelegateDependencies } from "../delegates/capabilities.ts";
import type { DelegateEvent, Delegates } from "../delegates/contract.ts";
import { hostDelegates, unavailableDelegates } from "../delegates/host-client.ts";
import { assignmentById, employeeAssignments } from "../delegates/service.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import { sha256 } from "../protocol/bytes.ts";
import { addEvidence } from "../work/service.ts";
import { postEvent } from "./conversations.ts";

type LocalVariables = Partial<Record<"DEVYS_HOST_URL" | "DEVYS_HOST_TOKEN", string>>;

/** The deployment mode decides the delegate runner: the Mac host locally, none in the cloud yet. */
export function delegatesFor(env: Env): (scope: Scope) => Delegates {
  switch (env.DEVYS_MODE) {
    case "local": {
      const { DEVYS_HOST_URL: url, DEVYS_HOST_TOKEN: token } = env as Env & LocalVariables;
      return (scope) => {
        if (!url || !token)
          throw new Error("The Mac host is not configured; run `bun run local install`.");
        return hostDelegates({ url, token }, scope);
      };
    }
    case "cloud":
      return () => unavailableDelegates();
    default:
      throw new Error(`Unknown DEVYS_MODE: ${String(env.DEVYS_MODE)}`);
  }
}

export function delegateDependencies(env: Env): DelegateDependencies {
  return {
    db: env.HYPERDRIVE,
    delegates: delegatesFor(env),
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

/** Employee Stop also interrupts its coding sessions, so no child keeps working unnoticed. */
export async function interruptAssignments(env: Env, scope: Scope) {
  const delegates = delegatesFor(env)(scope);
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
  const token = (env as Env & LocalVariables).DEVYS_HOST_TOKEN;
  const offered = await sha256(request.headers.get("authorization") ?? "");
  if (!token || offered !== (await sha256(`Bearer ${token}`)))
    return new Response("Unauthorized", { status: 401 });
  const { events } = (await request.json()) as { events: DelegateEvent[] };
  for (const event of events ?? []) await deliverEvent(env, event);
  return Response.json({ accepted: events?.length ?? 0 });
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
    checked: event.text,
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
      }),
    );
  if (event.kind === "started") return;
  const text = [
    `Your ${who} session ${item.id} (${item.purpose}) on this work item: ${card}`,
    event.diffStat && `Changes in its worktree ${item.worktree}:\n${event.diffStat}`,
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
