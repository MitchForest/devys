import type { ConversationKey } from "../conversations/contract.ts";
import type { Scope } from "../identity/contract.ts";
import {
  employeeChat,
  employeeChatOf,
  type Binding,
  type Channel,
  type Inbound,
} from "./contract.ts";

/**
 * A routine's run is addressed `routine:<business>:<employee>[:project:<id>]`: it speaks in its
 * project's channel, or (without a conversation) in the employee's direct chat.
 */
export const routineChat = (scope: Scope, conversation?: ConversationKey) =>
  employeeChat("routine", scope, conversation);

/** A run's message id, which is its operation id: `routine:<routine>:<slot or event:<id>>`. */
export const routineRun = (routineId: string, run: string) => `routine:${routineId}:${run}`;

/** The routine a run's message id names, or undefined. */
export const routineOf = (messageId: string | undefined) =>
  /^routine:([A-Za-z0-9-]{1,64}):./.exec(messageId ?? "")?.[1];

/** What a quiet run (notify `when_found`) answers when it found nothing. */
export const nothingFound = "NOTHING";

/**
 * The dispatcher starting a routine's run. The input stays bound while the routine is active,
 * is still that employee's, speaks in this conversation and the employee is working; the reply
 * goes to `report`, which posts it or, for a quiet run that found nothing, records only that.
 */
export function routineChannel(dependencies: {
  open: (scope: Scope, routineId: string, conversation?: ConversationKey) => Promise<boolean>;
  report: (
    scope: Scope,
    chatId: string,
    routineId: string,
    reply: string,
    operationId: string,
  ) => Promise<void>;
}): Channel {
  const text = (input: Inbound) => {
    if (input.text === undefined) throw new Error("Routine runs carry their text");
    return input.text;
  };
  return {
    id: "routine",
    // The message id is already the run's operation id, namespaced by the routine.
    inputKey: (input) => input.messageId,
    binding: async (input): Promise<Binding | undefined> => {
      const chat = employeeChatOf(input.chatId);
      const routineId = routineOf(input.messageId);
      if (chat?.channel !== "routine" || !routineId) return undefined;
      return (await dependencies.open(chat.scope, routineId, chat.conversation))
        ? { personId: "dispatcher", ...chat.scope }
        : undefined;
    },
    readText: async (input) => text(input),
    prepare: async (_scope, input) => text(input),
    send: async (scope, chatId, reply, operationId, inReplyTo) => {
      const routineId = routineOf(inReplyTo);
      if (!routineId) throw new Error("A routine's reply names its run");
      await dependencies.report(scope, chatId, routineId, reply, operationId);
      return { status: "sent", guid: null };
    },
  };
}
