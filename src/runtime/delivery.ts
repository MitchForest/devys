import type { Inbound } from "../channels/contract.ts";
/** Adapter receipts only; Pi owns queued/running/completed work. */
export interface ChannelMessage {
  id: string;
  input: Inbound;
  receivedAt: number;
  text?: string;
  cancelled?: boolean;
  control?: "stop" | "status";
  targets?: string[];
  preparationAttempts?: number;
  /** Pi has the turn; later polls only wait for it. */
  submitted?: boolean;
}
export interface Outbox {
  id: string;
  chatId: string;
  text: string;
  /** The inbound message the reply answers. */
  replyTo?: string;
  attempts: number;
  status: "pending" | "sent" | "uncertain" | "cancelled";
}

export const messageKey = (id: string) => `message:${id}`;
export const outboxKey = (id: string) => `outbox:${id}`;
/** Receipts by arrival, so the oldest can be forgotten and status shows the latest. */
export const recentKey = (message: ChannelMessage) =>
  `recent:${String(message.receivedAt).padStart(16, "0")}:${message.id}`;
