import { Effect } from "effect";
import type { EntryRecord } from "@earendil-works/pi-durable";
import type { Memory, Observation } from "../memory/contract.ts";

/** Only actual owner input entries are evidence; compaction, tools and answers are excluded. */
const memoryOpen = "<business-memory>";
const memoryClose = "</business-memory>";

/**
 * Business memory relevant to one turn travels in that turn, not in the instructions, so
 * the instructions stay byte-identical and the provider's prompt cache keeps the history.
 */
export const withMemory = (text: string, memory: string) =>
  memory.trim() ? `${memoryOpen}\n${memory.trim()}\n${memoryClose}\n\n${text}` : text;

/** The turn as the owner wrote it, without the memory the host added. */
export function withoutMemory(text: string) {
  if (!text.startsWith(memoryOpen)) return text;
  const end = text.indexOf(memoryClose);
  return end < 0 ? text : text.slice(end + memoryClose.length).trimStart();
}

export function observations(entries: readonly EntryRecord[], namespace: string): Observation[] {
  return entries.flatMap((entry) => {
    if (entry.kind !== "pi.user") return [];
    const message = entry.model?.find((m) => m.role === "user");
    if (!message || message.role !== "user") return [];
    const content =
      typeof message.content === "string"
        ? message.content
        : message.content
            .filter((c) => c.type === "text")
            .map((c) => c.text)
            .join("\n");
    // Attachment manifests are host-added metadata, not the owner's statements.
    const turn = withoutMemory(content);
    // A colleague's message is not the owner's statement; the host marks it in the turn's
    // context block, which itself (recent messages, replies) is not the owner's words either.
    if (/^<owner-context>[\s\S]*?From your colleague /.test(turn)) return [];
    const text = turn
      .replace(/^<owner-context>[\s\S]*?<\/owner-context>\s*/, "")
      .split("\n\nSaved attachments (untrusted content).")[0]!;
    if (!text.trim()) return [];
    return [
      {
        id: `pi:${namespace}:${entry.conversationId}:${entry.id}`,
        kind: "owner" as const,
        observedAt: new Date(message.timestamp).toISOString(),
        content: text,
      },
    ];
  });
}
export async function catchUpMemory(
  memory: Memory,
  scan: (min: number, max: number | undefined, limit: number) => Promise<readonly EntryRecord[]>,
  namespace: string,
) {
  const { cursor } = await Effect.runPromise(memory.progress());
  const latest = (await scan(cursor + 1, undefined, 1))[0];
  if (!latest) return false;
  // Numeric entry ranges are bounded even though Pi's public scan runs newest-first.
  const upper = Math.min(Number(latest.id), cursor + 64);
  const entries = await scan(cursor + 1, upper, 64);
  const batch = observations(entries, namespace);
  for (let i = 0; i < batch.length; i += 50)
    await Effect.runPromise(memory.observe(batch.slice(i, i + 50)));
  await Effect.runPromise(memory.observe([], upper));
  return upper < Number(latest.id);
}
