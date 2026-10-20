import type { Scope } from "../identity/contract.ts";
import { commitmentOf, type Binding, type Channel, type Inbound } from "./contract.ts";

/** Work handed to an employee is addressed `work:<business>:<employee>:<commitment>`. */
export const workChat = (scope: Scope, commitmentId: string) =>
  `work:${scope.businessId}:${scope.employeeId}:${commitmentId}`;

/**
 * The dispatcher handing a commitment to its employee. The input stays bound while the
 * commitment is still that employee's and not taken over or cancelled; the reply is posted
 * in the work item's thread, so a final report after completing it still arrives.
 */
export function workChannel(dependencies: {
  open: (scope: Scope, commitmentId: string) => Promise<boolean>;
  post: (chatId: string, text: string, operationId: string) => Promise<void>;
}): Channel {
  const text = (input: Inbound) => {
    if (input.text === undefined) throw new Error("Work inputs carry their text");
    return input.text;
  };
  return {
    id: "work",
    inputKey: (input) => `work:${input.messageId}`,
    binding: async (input): Promise<Binding | undefined> => {
      const target = commitmentOf(input.chatId);
      if (!target) return undefined;
      const scope = { businessId: target.businessId, employeeId: target.employeeId };
      return (await dependencies.open(scope, target.commitmentId))
        ? { personId: "dispatcher", ...scope }
        : undefined;
    },
    readText: async (input) => text(input),
    prepare: async (_scope, input) => text(input),
    send: async (_scope, chatId, reply, operationId) => {
      await dependencies.post(chatId, reply, operationId);
      return { status: "sent", guid: null };
    },
  };
}
