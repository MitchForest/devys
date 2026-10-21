import type { Ref } from "../../protocol/ref.ts";
import type { ShownMessage } from "./api.ts";

/** A conversation as Messages lays it out: grouped bubbles, with a heading when time passes. */
export type Position = "single" | "first" | "middle" | "last";
export interface Bubble {
  id: string;
  /** `person:<id>`, `employee:<id>` or `system`. */
  author: string;
  /** Whether the signed-in person wrote it, so it sits on the right. */
  mine: boolean;
  kind: "message" | "event";
  text: string;
  /** The message it answers, quoted only when that isn't the message right above it. */
  replyTo: string | null;
  viaVoice: boolean;
  reactions: string[];
  /** What an event opens: a hand-off card's work item, a page. */
  ref: Ref | null;
  sentAt?: Date;
  position: Position;
  /** Set for messages sent from this browser that the conversation doesn't show yet. */
  delivery?: "sending" | "delivered" | "failed";
  /** Why a send failed, in the server's words. */
  error?: string;
}
export type TimelineItem =
  | { kind: "heading"; id: string; date: Date }
  | { kind: "bubble"; id: string; bubble: Bubble };

/** A message sent from this browser, as the timeline needs it. */
export interface Unsent {
  id: string;
  text: string;
  replyTo?: string;
  viaVoice?: boolean;
  delivery: "sending" | "delivered" | "failed";
  error?: string;
}

export const endsGroup = (bubble: Bubble) =>
  bubble.position === "single" || bubble.position === "last";
export const startsGroup = (bubble: Bubble) =>
  bubble.position === "single" || bubble.position === "first";

const groupGap = 5 * 60_000;
const headingGap = 60 * 60_000;
const sameDay = (a: Date, b: Date) => a.toDateString() === b.toDateString();

/** `me` is the signed-in person's author string, `person:<id>`. */
export function timeline(
  history: ShownMessage[],
  unsent: Unsent[],
  me: string,
  now: Date,
): TimelineItem[] {
  const bubbles: Bubble[] = [
    ...history.map((m, index) => ({
      id: m.id,
      author: m.author,
      mine: m.author === me,
      kind: m.kind,
      text: m.text,
      replyTo: m.reply_to === history[index - 1]?.id ? null : m.reply_to,
      viaVoice: m.via_voice,
      reactions: m.reactions,
      ref: m.ref,
      sentAt: new Date(m.created_at),
      position: "single" as const,
    })),
    ...unsent.map((p) => ({
      id: p.id,
      author: me,
      mine: true,
      kind: "message" as const,
      text: p.text,
      replyTo: p.replyTo ?? null,
      viaVoice: p.viaVoice ?? false,
      reactions: [],
      ref: null,
      sentAt: now,
      position: "single" as const,
      delivery: p.delivery,
      ...(p.error ? { error: p.error } : {}),
    })),
  ];
  const items: TimelineItem[] = [];
  let previous: Bubble | undefined;
  for (const bubble of bubbles) {
    const gap =
      previous?.sentAt && bubble.sentAt
        ? bubble.sentAt.getTime() - previous.sentAt.getTime()
        : undefined;
    const newDay =
      previous?.sentAt && bubble.sentAt ? !sameDay(previous.sentAt, bubble.sentAt) : false;
    if (bubble.sentAt && (!previous || newDay || (gap ?? 0) > headingGap)) {
      items.push({
        kind: "heading",
        id: `heading-${bubble.sentAt.getTime()}`,
        date: bubble.sentAt,
      });
      previous = undefined;
    }
    const last = items[items.length - 1];
    // Consecutive messages from one author group; events always stand alone.
    if (
      previous &&
      previous.kind === "message" &&
      bubble.kind === "message" &&
      previous.author === bubble.author &&
      (gap ?? 0) <= groupGap &&
      last?.kind === "bubble"
    ) {
      last.bubble.position = last.bubble.position === "single" ? "first" : "middle";
      bubble.position = "last";
    }
    items.push({ kind: "bubble", id: bubble.id, bubble });
    previous = bubble;
  }
  return items;
}

/** "Today 2:21 PM", "Yesterday 9:04 AM", "Mon 9:04 AM" or a date. */
export function headingLabel(date: Date, now = new Date()) {
  const time = date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  if (sameDay(date, now)) return `Today ${time}`;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return `Yesterday ${time}`;
  if (now.getTime() - date.getTime() < 7 * 86_400_000)
    return `${date.toLocaleDateString(undefined, { weekday: "short" })} ${time}`;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}
