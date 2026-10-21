import type { PiHarness } from "agents/harness/pi";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { Effect } from "effect";
import type { Outcome } from "../authority/contract.ts";
import { idOf, kindOf } from "../conversations/contract.ts";
import type { Scope } from "../identity/contract.ts";
import { CapabilityError, type Capability } from "../protocol/capability.ts";
import { defaultLimits } from "../protocol/limits.ts";
import type { ToolHost } from "./codemode.ts";
import { messageKey, type ChannelMessage } from "./delivery.ts";
import { observations } from "./memory.ts";
import type { MemoryUpkeep } from "./memory-upkeep.ts";
import { conversationIn, conversationOf } from "./sessions.ts";

/** The employee while it and its business are active. */
export interface ActiveEmployee {
  name: string;
  responsibilities: string;
  businessName: string;
  brief: string;
  paused: boolean;
  /** The other employees, as "Name (what they do)". */
  colleagues: string[];
}

/**
 * The trusted host behind the employee's tools: who it is, what it may discover, and the
 * authority each tool call acts with, re-checked for the exact input it serves.
 */
export function toolHost(deps: {
  storage: DurableObjectStorage;
  harness: PiHarness;
  memory: MemoryUpkeep;
  scope: () => Scope;
  employee: () => Promise<ActiveEmployee | undefined>;
  /** Whether a stop is cancelling work right now. */
  stopping: () => boolean;
  workplace: string;
  authorize: (
    capability: Capability,
    input: unknown,
    context: { workItemId?: string; conversation?: string },
  ) => Promise<Outcome>;
  granted: () => Promise<string[]>;
  skills: () => Promise<readonly { name: string; description: string }[]>;
}) {
  const { storage, harness } = deps;

  /** Work Pi is running, in one session or, without one, in every session. */
  const running = async (session?: string) =>
    (await harness.pending(session === undefined ? {} : { session })).filter(
      (operation) => operation.status === "running",
    );

  /**
   * Model requests do not say which session they serve. Sessions run independently, so
   * without one, refuse only when every running input is cancelled or expired; Pi's abort
   * signal still stops the cancelled run itself.
   */
  async function checkAccess(signal?: AbortSignal, session?: string) {
    signal?.throwIfAborted();
    if (deps.stopping()) throw new Error("Stopping work");
    const employee = await deps.employee();
    if (!employee) throw new Error("Employee access revoked");
    if (employee.paused) throw new Error("Employee is paused");
    const messages = await Promise.all(
      (await running(session)).map((operation) =>
        storage.get<ChannelMessage>(messageKey(operation.operationId)),
      ),
    );
    if (
      messages.length &&
      messages.every(
        (message) =>
          message &&
          (message.cancelled || Date.now() >= message.receivedAt + defaultLimits.maxDurationMs),
      )
    )
      throw new Error("Message cancelled or expired");
    signal?.throwIfAborted();
    if (deps.stopping()) throw new Error("Stopping work");
  }

  async function identity() {
    const employee = await deps.employee();
    if (!employee) throw new Error("Employee access revoked");
    const about = employee.brief.trim()
      ? ` About ${employee.businessName}: ${employee.brief.trim()}`
      : "";
    const team = employee.colleagues.length
      ? ` Your colleagues: ${employee.colleagues.join("; ")}. To ask one, write @ and their name in your reply; their answer comes back to you. Hand over lasting work as a work item they own.`
      : "";
    return `You are ${employee.name} at ${employee.businessName}, an employee operated by Devys.${about} Your responsibilities: ${employee.responsibilities}${team} Work toward the business's goals and the owner's requests. ${deps.workplace}`;
  }

  /** The calling tool's session decides which input, and so which work item, it acts for. */
  async function authority(signal: AbortSignal | undefined, session: string) {
    await checkAccess(signal, session);
    const pi = await harness.pi();
    const [current] = await running(session);
    const latest = current
      ? await pi.commit(async (tx) => {
          const submission = await tx.submissionByRequest(
            conversationOf(current.session),
            current.operationId,
          );
          return submission?.entry === undefined ? undefined : tx.entry(submission.entry);
        }, BACKGROUND_CONTEXT)
      : undefined;
    const evidence = observations(latest ? [latest] : [], await deps.memory.sourceNamespace());
    // Work handed over by the dispatcher, or a message in a work item's thread, names its
    // work item; the host, not the model, says so.
    const input = current
      ? (await storage.get<ChannelMessage>(messageKey(current.operationId)))?.input
      : undefined;
    const inConversation = input ? conversationIn(input.chatId) : undefined;
    const workItemId =
      inConversation && kindOf(inConversation) === "work" ? idOf(inConversation) : undefined;
    const scope = deps.scope();
    const conversation = input ? (inConversation ?? `direct:${scope.employeeId}`) : undefined;
    const observed = await deps.memory.observe(evidence);
    const context = {
      ...(workItemId ? { workItemId } : {}),
      ...(conversation ? { conversation } : {}),
    };
    return {
      evidenceIds: observed ? evidence.map((item) => item.id) : [],
      ...scope,
      ...context,
      authorize: (capability: Capability, args: unknown) =>
        Effect.tryPromise({
          try: () => deps.authorize(capability, args, context),
          catch: () =>
            new CapabilityError({ code: "unavailable", message: "Authority is unavailable" }),
        }).pipe(
          Effect.flatMap((decision) =>
            decision.outcome === "allow"
              ? Effect.void
              : Effect.fail(
                  decision.outcome === "ask"
                    ? new CapabilityError({
                        code: "approval_required",
                        message: `${capability.name} needs the owner's approval for this request`,
                      })
                    : new CapabilityError({ code: "forbidden", message: decision.reason }),
                ),
          ),
        ),
      assertActive: () =>
        Effect.tryPromise({
          try: () => checkAccess(signal, session),
          catch: () =>
            new CapabilityError({
              code: "cancelled",
              message: "Work stopped, expired, or access was revoked",
            }),
        }),
    };
  }

  return {
    identity,
    authority,
    checkAccess,
    granted: async () => new Set(await deps.granted()),
    skills: deps.skills,
  } satisfies ToolHost & { checkAccess: typeof checkAccess };
}
