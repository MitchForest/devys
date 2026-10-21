import type { PiHarness } from "agents/harness/pi";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { defaultLimits } from "../protocol/limits.ts";
import { messageKey, outboxKey, type ChannelMessage, type Outbox } from "./delivery.ts";
import { conversationOf, type Sessions } from "./sessions.ts";

/** What the employee is doing: its run, the last 100 inputs and replies, checkpoint and usage. */
export async function employeeStatus(
  storage: DurableObjectStorage,
  harness: PiHarness,
  sessions: Sessions,
) {
  const pi = await harness.pi();
  const [pending, recent, checkpoint, usage, known] = await Promise.all([
    harness.pending(),
    storage.list<string>({ prefix: "recent:", reverse: true, limit: 100 }),
    storage.get("workspaceCheckpoint"),
    // Pi's usage is already the sum of every conversation's own ledger.
    pi.usage(BACKGROUND_CONTEXT),
    sessions.all(),
  ]);
  const ids = [...recent.values()];
  const [messages, outbox] = await Promise.all([
    ids.length
      ? storage.get<ChannelMessage>(ids.map(messageKey))
      : new Map<string, ChannelMessage>(),
    ids.length ? storage.get<Outbox>(ids.map(outboxKey)) : new Map<string, Outbox>(),
  ]);
  const inbox = await Promise.all(
    [...messages.values()].map(async (message) => {
      const session = sessions.sessionIn(known, message.input.chatId);
      const submission =
        session === undefined
          ? undefined
          : await pi.commit(
              (tx) => tx.submissionByRequest(conversationOf(session), message.id),
              BACKGROUND_CONTEXT,
            );
      const state = pending.find((item) => item.operationId === message.id)?.status;
      return {
        id: message.id,
        text: message.text,
        receivedAt: message.receivedAt,
        status:
          state ??
          (submission?.status === "unanswered" || message.cancelled
            ? "failed"
            : submission?.status === "done" || message.control || outbox.has(outboxKey(message.id))
              ? "done"
              : "queued"),
      };
    }),
  );
  const running = pending.find((item) => item.status === "running");
  const current = running && (await storage.get<ChannelMessage>(messageKey(running.operationId)));
  return {
    run: running
      ? {
          id: running.operationId,
          stopped: Boolean(current?.cancelled),
          deadline: current ? current.receivedAt + defaultLimits.maxDurationMs : null,
        }
      : null,
    inbox,
    outbox: [...outbox.values()],
    checkpoint,
    usage,
  };
}
