import type { PiHarness } from "agents/harness/pi";
import type { LifecycleJobs } from "agents/lifecycle";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { Channel, Inbound, Notice } from "../channels/contract.ts";
import type { ConversationKey } from "../conversations/contract.ts";
import type { Scope } from "../identity/contract.ts";
import { defaultLimits } from "../protocol/limits.ts";
import { sha256 } from "../protocol/bytes.ts";
import type { WorkspacePort } from "../workspace/contract.ts";
import {
  messageKey,
  messageOf,
  outboxKey,
  recentKey,
  replyTurn,
  type ChannelMessage,
  type Outbox,
} from "./delivery.ts";
import { withMemory } from "./memory.ts";
import type { MemoryUpkeep } from "./memory-upkeep.ts";
import { deliver, queueReply, reaches } from "./outbox.ts";
import { conversationIn, conversationOf, type Sessions } from "./sessions.ts";

type Later = { rescheduleAt: number };
/**
 * What answers a message: the employee's words, Devys's notice when the turn failed, or nothing
 * when the employee finished without saying anything even when asked once more for its reply.
 */
type Answer = string | { notice: Notice } | null;

/** The Pi operations a message has: its turn and, once asked, its reply follow-up. */
const operationsOf = (message: ChannelMessage) =>
  message.replyAsked ? [message.id, replyTurn(message.id)] : [message.id];

/**
 * Devys's own inputs (dispatched work, coding events): their turns may end in cards and
 * records alone, so a turn without words is not a missing reply.
 */
const fromDevys = (message: ChannelMessage) =>
  message.input.senderId === "dispatcher" || message.input.senderId === "coding";

const expired = (message: ChannelMessage) =>
  Date.now() >= message.receivedAt + defaultLimits.maxDurationMs;

/**
 * The employee's channel inbox: each input is received once, prepared, answered in its
 * conversation's Pi session and its reply delivered, by a lifecycle job that survives restarts.
 * Stop and status answer at once.
 */
export function channelInbox(deps: {
  storage: DurableObjectStorage;
  jobs: LifecycleJobs;
  harness: PiHarness;
  sessions: Sessions;
  memory: MemoryUpkeep;
  channel: Channel;
  scope: () => Scope;
  runner: () => WorkspacePort;
  /** Whether the owner paused the employee. */
  paused: () => Promise<boolean>;
  /** Interrupts the employee's coding sessions. */
  interruptCoding: () => Promise<void>;
  /** Applies current operator settings to a session with nothing pending. */
  configureIdle: (session: string) => Promise<void>;
}) {
  const { storage, harness, sessions } = deps;
  let stopping = 0;

  const schedule = (messageId: string) =>
    deps.jobs.push({
      id: `channel:${messageId}`,
      fn: "channel",
      payload: messageId,
      time: Date.now(),
      singleflight: true,
      // Each run is short (prepare, submit once, wait 5s, reschedule), so a run still marked
      // running this long was cut off by a restart or reload: it is reset rather than waited on.
      // A rerun is safe: preparing is a rewrite, Pi's submit and the reply are keyed by message.
      hungTimeoutSeconds: 45,
    });

  /** Records an input once (by its channel key) and schedules its answer. */
  async function receive(input: Inbound) {
    const id = await sha256(deps.channel.inputKey(input));
    let message = await storage.get<ChannelMessage>(messageKey(id));
    if (message && message.input.text !== input.text)
      throw new Error("Message id already used for different text");
    let accepted = false;
    if (!message) {
      const text = (await deps.channel.readText(input)).trim();
      const control = /^\/?stop$/i.test(text)
        ? "stop"
        : /^\/?status$/i.test(text)
          ? "status"
          : undefined;
      const targets = control === "stop" ? await stopTargets() : undefined;
      const candidate: ChannelMessage = {
        id,
        input,
        receivedAt: Date.now(),
        ...(control ? { control, text } : {}),
        ...(targets ? { targets } : {}),
      };
      message = await storage.transaction(async (tx) => {
        const previous = await tx.get<ChannelMessage>(messageKey(id));
        if (previous) return previous;
        accepted = true;
        await tx.put(messageKey(id), candidate);
        await tx.put(recentKey(candidate), id);
        return candidate;
      });
    }
    if (accepted) await forgetOldMessages();
    // Stop/status must not wait behind an attachment download or model response.
    // Intent is already durable, so a lost ingress response safely retries it.
    if (message.control) await process(message.id);
    // Re-arm duplicates too: the previous request may have stopped after persistence.
    await schedule(message.id);
    return { accepted };
  }

  /** Inputs still being prepared and every operation Pi has not settled. */
  async function stopTargets() {
    const preparing = deps.jobs
      .list()
      .filter((job) => job.fn === "channel" && typeof job.payload === "string")
      .map((job) => job.payload as string);
    return [
      ...new Set(
        preparing.concat((await harness.pending()).map((operation) => operation.operationId)),
      ),
    ];
  }

  const stop = async () => cancel(await stopTargets());

  /** Cancels the selected inputs and aborts their Pi runs, the workspace and coding sessions. */
  async function cancel(selected: string[]) {
    deps.memory.yieldToWork();
    const pending = await harness.pending();
    const pi = await harness.pi();
    const known = await sessions.all();
    stopping++;
    try {
      const targets: { operationId: string; session: string }[] = [];
      for (const id of selected) {
        // A reply follow-up is cancelled as the message it answers.
        const message = await storage.get<ChannelMessage>(messageKey(messageOf(id)));
        const session =
          pending.find((item) => item.operationId === id)?.session ??
          (message ? sessions.sessionIn(known, message.input.chatId) : undefined);
        if (session !== undefined) targets.push({ operationId: id, session });
        const submission =
          session === undefined
            ? undefined
            : await pi.commit(
                (tx) => tx.submissionByRequest(conversationOf(session), id),
                BACKGROUND_CONTEXT,
              );
        if (submission?.status === "done" || submission?.status === "unanswered") continue;
        await storage.transaction(async (tx) => {
          const latest = await tx.get<ChannelMessage>(messageKey(messageOf(id)));
          if (latest && !latest.control)
            await tx.put(messageKey(latest.id), { ...latest, cancelled: true });
        });
      }
      const active = pending.some(
        (item) => item.status === "running" && selected.includes(item.operationId),
      );
      await Promise.all([
        ...targets.map((target) => harness.abort(target)),
        ...(active ? [deps.runner().cancel()] : []),
        deps.interruptCoding().catch(() => undefined),
      ]);
    } finally {
      stopping--;
    }
  }

  /**
   * Channel receipts older than 30 days go, a batch at a time: redeliveries arrive within
   * minutes, and status shows only recent messages. Pi keeps the conversation itself.
   */
  async function forgetOldMessages() {
    const cutoff = String(Date.now() - 30 * 24 * 60 * 60_000).padStart(16, "0");
    const old = await storage.list<string>({
      prefix: "recent:",
      end: `recent:${cutoff}`,
      limit: 50,
    });
    if (!old.size) return;
    await storage.delete([
      ...old.keys(),
      ...[...old.values()].flatMap((id) => [messageKey(id), outboxKey(id)]),
    ]);
  }

  /** Answers one channel message: prepare it, run it in its session, then deliver the reply. */
  async function process(id: string): Promise<Later | void> {
    let message = await storage.get<ChannelMessage>(messageKey(id));
    if (!message) return;
    let output = await storage.get<Outbox>(outboxKey(message.id));
    if (output && output.status !== "pending") return;
    const conversation = conversationIn(message.input.chatId);
    const scope = deps.scope();
    if (!reaches(scope, await deps.channel.binding(message.input))) {
      const session = await sessions.known(conversation);
      if (session !== undefined) await harness.abort({ operationId: message.id, session });
      if (output)
        await storage.put(outboxKey(message.id), {
          ...output,
          status: output.attempts ? "uncertain" : "cancelled",
        });
      return;
    }
    if (!output) {
      if (!message.control) {
        const prepared = await prepare(message);
        if ("rescheduleAt" in prepared) return prepared;
        message = prepared.message;
      }
      const answer = await answerOf(message, conversation);
      if (answer === null) return;
      if (typeof answer === "object" && "rescheduleAt" in answer) return answer;
      output = await queueReply(storage, message, answer);
    }
    return deliver({ storage, channel: deps.channel, scope }, message, output);
  }

  /** Reads a channel message's text once, giving up after three failed attempts. */
  async function prepare(message: ChannelMessage): Promise<{ message: ChannelMessage } | Later> {
    if (message.text !== undefined || message.cancelled || expired(message)) return { message };
    const key = messageKey(message.id);
    try {
      const prepared = await deps.channel.prepare(deps.scope(), message.input);
      return {
        message: await storage.transaction(async (tx) => {
          // A message forgotten meanwhile is treated as cancelled, never recreated.
          const latest = (await tx.get<ChannelMessage>(key)) ?? { ...message, cancelled: true };
          if (!latest.cancelled) {
            latest.text = prepared;
            await tx.put(key, latest);
          }
          return latest;
        }),
      };
    } catch {
      const latest = await storage.transaction(async (tx) => {
        const latest = await tx.get<ChannelMessage>(key);
        if (!latest) return { ...message, cancelled: true };
        latest.preparationAttempts = (latest.preparationAttempts ?? 0) + 1;
        if (latest.preparationAttempts >= 3) latest.cancelled = true;
        await tx.put(key, latest);
        return latest;
      });
      return latest.cancelled ? { message: latest } : { rescheduleAt: Date.now() + 5_000 };
    }
  }

  /** The answer to a message, or when to look again while Pi is still working. */
  async function answerOf(
    message: ChannelMessage,
    conversation: ConversationKey | undefined,
  ): Promise<Answer | Later> {
    if (message.control) {
      if (message.control === "stop") await cancel(message.targets ?? []);
      return message.control === "stop"
        ? "Stopped work received before your stop message. Incomplete actions may need inspection."
        : (await harness.pending()).length
          ? "I'm working on your request."
          : "There is no active run.";
    }
    if (message.cancelled || expired(message)) {
      const session = await sessions.known(conversation);
      const operations = operationsOf(message);
      const active = (await harness.pending()).some(
        (item) => operations.includes(item.operationId) && item.status === "running",
      );
      await Promise.all([
        ...(session === undefined
          ? []
          : operations.map((operationId) => harness.abort({ operationId, session }))),
        ...(active ? [deps.runner().cancel()] : []),
      ]);
      // A stop the owner sent is answered by the stop itself; the rest are Devys's to say.
      if (message.preparationAttempts && message.preparationAttempts >= 3)
        return { notice: "unreadable" };
      return expired(message) ? { notice: "too_long" } : null;
    }
    if (await deps.paused()) return { notice: "paused" };
    return run(message, conversation);
  }

  /** Submits the turn to Pi in the conversation's session (idempotent by message id) and waits. */
  async function run(
    message: ChannelMessage,
    conversation: ConversationKey | undefined,
  ): Promise<Answer | Later> {
    const session = await sessions.open(conversation);
    // Submitted once; the polls that follow only wait (no memory search per poll).
    if (!message.submitted) {
      await deps.memory.schedule();
      await deps.configureIdle(session);
      const turn = message.text ?? "";
      await harness.submit(withMemory(turn, await deps.memory.context(turn)), {
        session,
        operationId: message.id,
        whenBusy: "followUp",
      });
      await storage.transaction(async (tx) => {
        const latest = await tx.get<ChannelMessage>(messageKey(message.id));
        if (latest) await tx.put(messageKey(message.id), { ...latest, submitted: true });
      });
    }
    // After a turn without words, the one follow-up asking for the reply is what answers.
    const asked = (await storage.get<ChannelMessage>(messageKey(message.id))) ?? message;
    const operationId = asked.replyAsked ? replyTurn(message.id) : message.id;
    if (asked.cancelled) await harness.abort({ operationId, session });
    const signal = AbortSignal.timeout(5_000);
    let answer: Answer;
    try {
      const result = await harness.wait(operationId, { session, signal });
      if (result.status !== "done") answer = { notice: "failed" };
      else if (result.text?.trim()) answer = result.text;
      else if (!asked.replyAsked && !fromDevys(message)) return askForReply(message, session);
      else {
        await silent(message);
        answer = null;
      }
    } catch (error) {
      if (signal.aborted) return { rescheduleAt: Date.now() + 1_000 };
      throw error;
    }
    // The workspace is shared by every session, so checkpoint only when all are idle.
    if (!(await harness.pending()).length) await checkpointWorkspace();
    return answer;
  }

  /**
   * A turn that ended without words (often the reply was written only in its thinking): one
   * follow-up in the same session asks for it, admitted once by its stable operation id.
   */
  async function askForReply(message: ChannelMessage, session: string): Promise<Later> {
    await harness.submit(
      "Your reply wasn't written: nobody saw anything from that turn. Write your reply now, as plain text.",
      { session, operationId: replyTurn(message.id), whenBusy: "followUp" },
    );
    await storage.transaction(async (tx) => {
      const latest = await tx.get<ChannelMessage>(messageKey(message.id));
      if (latest) await tx.put(messageKey(message.id), { ...latest, replyAsked: true });
    });
    return { rescheduleAt: Date.now() + 1_000 };
  }

  /** Still no words after the follow-up. Logged; no stand-in text is posted. */
  async function silent(message: ChannelMessage) {
    await storage.transaction(async (tx) => {
      const latest = await tx.get<ChannelMessage>(messageKey(message.id));
      if (latest) await tx.put(messageKey(message.id), { ...latest, silent: true });
    });
    console.info(
      JSON.stringify({
        event: "turn_without_text",
        operation: message.id,
        chat: message.input.chatId,
      }),
    );
  }

  async function checkpointWorkspace() {
    try {
      const checkpoint = await deps.runner().checkpoint();
      await storage.put("workspaceCheckpoint", { status: "saved", at: Date.now(), ...checkpoint });
    } catch {
      await storage.put("workspaceCheckpoint", {
        status: "failed",
        at: Date.now(),
        message:
          "Workspace checkpoint failed. Saved artifacts remain available; newer scratch files may be lost.",
      });
    }
  }

  return {
    receive,
    stop,
    process,
    forgetOldMessages,
    /** Whether a stop is cancelling work right now; model requests are refused meanwhile. */
    stopping: () => stopping > 0,
  };
}
