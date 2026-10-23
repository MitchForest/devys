import type { Channel, Notice } from "../channels/contract.ts";
import type { Scope } from "../identity/contract.ts";
import { outboxKey, type ChannelMessage, type Outbox } from "./delivery.ts";

/** A channel input may act only through the employee it is bound to. */
export const reaches = (scope: Scope, binding: Scope | undefined) =>
  binding?.businessId === scope.businessId && binding.employeeId === scope.employeeId;

/**
 * Queues the answer to a message once (the employee's words, or Devys's notice); an answer
 * already queued wins.
 */
export function queueReply(
  storage: DurableObjectStorage,
  message: ChannelMessage,
  answer: string | { notice: Notice },
) {
  const pending: Outbox = {
    id: message.id,
    chatId: message.input.chatId,
    ...(typeof answer === "string"
      ? { text: answer.slice(0, 16_000) }
      : { text: "", notice: answer.notice }),
    replyTo: message.input.messageId,
    attempts: 0,
    status: "pending",
  };
  return storage.transaction(async (tx) => {
    const existing = await tx.get<Outbox>(outboxKey(pending.id));
    if (existing) return existing;
    await tx.put(outboxKey(pending.id), pending);
    return pending;
  });
}

/**
 * Sends a queued reply through its channel, recording each attempt before it is made: pending
 * becomes sent, or uncertain after five attempts or once access ends after an attempt.
 */
export async function deliver(
  deps: { storage: DurableObjectStorage; channel: Channel; scope: Scope },
  message: ChannelMessage,
  queued: Outbox,
) {
  const { storage, channel, scope } = deps;
  let output = queued;
  if (output.status !== "pending") return;
  const key = outboxKey(message.id);
  // Check again immediately before a send: access may have changed while Pi ran.
  if (!reaches(scope, await channel.binding({ ...message.input, chatId: output.chatId }))) {
    output.status = output.attempts ? "uncertain" : "cancelled";
    await storage.put(key, output);
    return;
  }
  // Record an attempted send before networking so a crash cannot later
  // make an unconfirmed send look as though it was never attempted.
  output = await storage.transaction(async (tx) => {
    // An outbox forgotten meanwhile is not sent.
    const latest = await tx.get<Outbox>(key);
    if (!latest) return { ...output, status: "cancelled" as const };
    if (latest.status !== "pending") return latest;
    if (latest.attempts >= 5) latest.status = "uncertain";
    else latest.attempts++;
    await tx.put(key, latest);
    return latest;
  });
  if (output.status !== "pending") return;
  const sent = output.notice
    ? await channel.notice(scope, output.chatId, output.notice, output.id)
    : await channel.send(scope, output.chatId, output.text, output.id, output.replyTo);
  output = await storage.transaction(async (tx) => {
    // Forgotten meanwhile: the send's outcome is still what is reported, not stored.
    const latest = (await tx.get<Outbox>(key)) ?? { ...output };
    if (sent.status === "sent") latest.status = "sent";
    else if (latest.status === "pending" && latest.attempts >= 5) latest.status = "uncertain";
    await tx.put(key, latest);
    return latest;
  });
  if (output.status === "pending")
    return { rescheduleAt: Date.now() + Math.min(60_000, 2_000 * 2 ** output.attempts) };
}
