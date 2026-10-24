import type { Scope } from "../identity/contract.ts";
import {
  employeeChat,
  employeeChatOf,
  type Binding,
  type Channel,
  type Inbound,
  type Notice,
} from "./contract.ts";
import { idOf, kindOf, type Worked } from "../conversations/contract.ts";

/** Work handed to an employee is addressed `work:<business>:<employee>:work:<work item>`. */
export const workChat = (scope: Scope, workItemId: string) =>
  employeeChat("work", scope, `work:${workItemId}`);

/**
 * The dispatcher handing a work item to its employee. The input stays bound while the
 * work item is still that employee's and not taken over or cancelled; the reply is posted
 * in the work item's thread, so a final report after completing it still arrives.
 */
export function workChannel(dependencies: {
  open: (scope: Scope, workItemId: string) => Promise<boolean>;
  post: (chatId: string, text: string, operationId: string, worked?: Worked) => Promise<void>;
  /** Posts Devys's notice about a turn as an event in the thread. */
  notice: (chatId: string, notice: Notice, operationId: string) => Promise<void>;
}): Channel {
  const text = (input: Inbound) => {
    if (input.text === undefined) throw new Error("Work inputs carry their text");
    return input.text;
  };
  return {
    id: "work",
    inputKey: (input) => `work:${input.messageId}`,
    binding: async (input): Promise<Binding | undefined> => {
      const chat = employeeChatOf(input.chatId);
      if (chat?.channel !== "work" || !chat.conversation || kindOf(chat.conversation) !== "work")
        return undefined;
      return (await dependencies.open(chat.scope, idOf(chat.conversation)))
        ? { personId: "dispatcher", ...chat.scope }
        : undefined;
    },
    readText: async (input) => text(input),
    prepare: async (_scope, input) => text(input),
    send: async (_scope, chatId, reply, operationId, _inReplyTo, worked) => {
      await dependencies.post(chatId, reply, operationId, worked);
      return { status: "sent", guid: null };
    },
    notice: async (_scope, chatId, notice, operationId) => {
      await dependencies.notice(chatId, notice, operationId);
      return { status: "sent", guid: null };
    },
  };
}
