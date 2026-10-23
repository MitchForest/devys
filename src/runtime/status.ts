import type { Usage } from "@earendil-works/pi-ai";
import type { PiHarness } from "agents/harness/pi";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { defaultLimits } from "../protocol/limits.ts";
import { messageKey, messageOf, outboxKey, type ChannelMessage, type Outbox } from "./delivery.ts";
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
    storage.get<Checkpoint>("workspaceCheckpoint"),
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
      // A reply follow-up still pending is the message's own turn.
      const state = pending.find((item) => messageOf(item.operationId) === message.id)?.status;
      return {
        id: message.id,
        text: message.text,
        received_at: message.receivedAt,
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
  const current =
    running && (await storage.get<ChannelMessage>(messageKey(messageOf(running.operationId))));
  return {
    run: running
      ? {
          id: messageOf(running.operationId),
          stopped: Boolean(current?.cancelled),
          deadline: current ? current.receivedAt + defaultLimits.maxDurationMs : null,
        }
      : null,
    inbox,
    outbox: [...outbox.values()].map(({ chatId, replyTo, ...reply }) => ({
      ...reply,
      chat_id: chatId,
      ...(replyTo === undefined ? {} : { reply_to: replyTo }),
    })),
    checkpoint: checkpoint && checkpointOf(checkpoint),
    usage: usage && { models: spendBy(usage.models), tools: spendBy(usage.tools) },
  };
}

/** The checkpoint as stored by the inbox, in the API's field names. */
type Checkpoint =
  | { status: "saved"; at: number; kind: "snapshot"; snapshotId: string; bytes: number }
  | { status: "saved"; at: number; kind: "durable" }
  | { status: "failed"; at: number; message: string };
const checkpointOf = (checkpoint: Checkpoint) =>
  "snapshotId" in checkpoint
    ? (({ snapshotId, ...rest }) => ({ ...rest, snapshot_id: snapshotId }))(checkpoint)
    : checkpoint;

/** Pi's spend in the API's field names. */
const spend = ({ cacheRead, cacheWrite, cacheWrite1h, totalTokens, cost, ...usage }: Usage) => ({
  ...usage,
  cache_read: cacheRead,
  cache_write: cacheWrite,
  ...(cacheWrite1h === undefined ? {} : { cache_write_1h: cacheWrite1h }),
  total_tokens: totalTokens,
  cost: {
    input: cost.input,
    output: cost.output,
    cache_read: cost.cacheRead,
    cache_write: cost.cacheWrite,
    total: cost.total,
  },
});
const spendBy = (byName: Record<string, Usage>) =>
  Object.fromEntries(Object.entries(byName).map(([name, usage]) => [name, spend(usage)]));
