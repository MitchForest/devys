import { database, type Database } from "../data/database.ts";
import type { Scope } from "../identity/contract.ts";
import type { ConversationKey } from "../conversations/contract.ts";
import {
  employeeChat,
  employeeChatOf,
  type Binding,
  type Channel,
  type Inbound,
} from "./contract.ts";

/**
 * App conversations reach an employee at `app:<business>:<employee>[:<conversation>]`; the
 * sender is a person or a colleague (`employee:<id>`).
 */
export const appChat = (scope: Scope, conversation?: ConversationKey) =>
  employeeChat("app", scope, conversation);
const scopeOf = (chatId: string): Scope | undefined => {
  const chat = employeeChatOf(chatId);
  return chat?.channel === "app" ? chat.scope : undefined;
};

/** Toggles a reaction on one of an employee's messages. */
export const setAppReaction = (
  db: Database,
  scope: Scope,
  reaction: { targetId: string; targetText: string; emoji: string; on: boolean },
) =>
  database(db, (sql) =>
    reaction.on
      ? sql.run(
          `INSERT INTO app_reactions (business_id, employee_id, target_id, emoji, target_text)
           VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`,
          [
            scope.businessId,
            scope.employeeId,
            reaction.targetId,
            reaction.emoji,
            reaction.targetText.slice(0, 280),
          ],
        )
      : sql.run(
          `DELETE FROM app_reactions
           WHERE business_id = $1 AND employee_id = $2 AND target_id = $3 AND emoji = $4`,
          [scope.businessId, scope.employeeId, reaction.targetId, reaction.emoji],
        ),
  );

export const appReactions = (db: Database, scope: Scope) =>
  database(db, async (sql) =>
    (
      await sql.rows<{ target_id: string; emoji: string }>(
        `SELECT target_id, emoji FROM app_reactions
         WHERE business_id = $1 AND employee_id = $2 ORDER BY created_at`,
        [scope.businessId, scope.employeeId],
      )
    ).map((row) => ({ targetId: row.target_id, emoji: row.emoji })),
  );

const contextOpen = "<owner-context>";
const contextClose = "</owner-context>";

/**
 * The text the employee receives: the owner's words, preceded by what they should
 * know (what they replied to, reactions since the last message, voice dictation).
 * Reactions are claimed by this message id, so a retried request composes the same text.
 */
export const composeAppMessage = (
  db: Database,
  scope: Scope,
  message: {
    id: string;
    text: string;
    replyToText?: string;
    viaVoice?: boolean;
    /** What the message is about, such as the project or work item it was sent in. */
    about?: string;
  },
) =>
  database(
    db,
    async (sql) => {
      await sql.run(
        `UPDATE app_reactions SET consumed_by = $3
         WHERE business_id = $1 AND employee_id = $2 AND consumed_by IS NULL`,
        [scope.businessId, scope.employeeId, message.id],
      );
      const reactions = await sql.rows<{ emoji: string; target_text: string }>(
        `SELECT emoji, target_text FROM app_reactions
         WHERE business_id = $1 AND employee_id = $2 AND consumed_by = $3 ORDER BY created_at`,
        [scope.businessId, scope.employeeId, message.id],
      );
      const lines = [
        ...(message.about ? [message.about] : []),
        ...(message.replyToText ? [`Replying to your message: "${message.replyToText}"`] : []),
        ...reactions.map((r) => `Reacted ${r.emoji} to your message: "${r.target_text}"`),
        ...(message.viaVoice ? ["Dictated by voice; it may contain transcription errors."] : []),
      ];
      return lines.length
        ? `${contextOpen}\n${lines.join("\n")}\n${contextClose}\n\n${message.text}`
        : message.text;
    },
    { transaction: true },
  );

/** Splits an employee-facing input back into what the owner wrote and how. */
export function readAppInput(input: string) {
  if (!input.startsWith(contextOpen)) return { text: input };
  const end = input.indexOf(contextClose);
  if (end < 0) return { text: input };
  const context = input.slice(contextOpen.length, end);
  const reply = /Replying to your message: "([\s\S]*?)"\n/.exec(context)?.[1];
  return {
    text: input.slice(end + contextClose.length).trim(),
    ...(reply ? { replyToText: reply } : {}),
    ...(context.includes("Dictated by voice") ? { viaVoice: true } : {}),
  };
}

/**
 * The Devys apps' conversations. A member or a colleague speaks to the employee; its reply
 * is posted back into the conversation the input came from.
 */
export function appChannel(dependencies: {
  /** A member of the business (`person`'s id) or an active colleague (`employee:<id>`). */
  allowed: (senderId: string, scope: Scope) => Promise<boolean>;
  post: (chatId: string, text: string, operationId: string, inReplyTo?: string) => Promise<void>;
}): Channel {
  const text = (input: Inbound) => {
    if (input.text === undefined) throw new Error("App messages carry their text");
    return input.text;
  };
  return {
    id: "app",
    inputKey: (input) => `app:${input.messageId}`,
    binding: async (input): Promise<Binding | undefined> => {
      const scope = scopeOf(input.chatId);
      return scope && (await dependencies.allowed(input.senderId, scope))
        ? { personId: input.senderId, ...scope }
        : undefined;
    },
    readText: async (input) => text(input),
    prepare: async (_scope, input) => text(input),
    send: async (_scope, chatId, reply, operationId, inReplyTo) => {
      await dependencies.post(chatId, reply, operationId, inReplyTo);
      return { status: "sent", guid: null };
    },
  };
}
