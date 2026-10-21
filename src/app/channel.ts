import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appChannel } from "../channels/app.ts";
import { channelOf, type Channel } from "../channels/contract.ts";
import { imessageChannel } from "../channels/photon-adapter.ts";
import { workChannel } from "../channels/work.ts";
import { workItem } from "../work/service.ts";
import { activeEmployee, channelBinding, memberBusiness } from "../identity/service.ts";
import type { Scope } from "../identity/contract.ts";
import { postFromEmployee, recordChannelMessage, recordChannelReply } from "./conversations.ts";

/**
 * Channels a person can bind a chat of their own to (the apps bind by sign-in, and the
 * dispatcher is internal). Adding Telegram is one adapter, one entry below and one here.
 */
export const bindableChannels = ["imessage"] as const;
export type BindableChannel = (typeof bindableChannels)[number];

/** Every channel, listed explicitly. Inputs and replies route by their chat id's prefix. */
export function channelFor(env: Env): Channel {
  const photon = imessageChannel(env, (sender, chat) =>
    Effect.runPromise(channelBinding(env.HYPERDRIVE, "imessage", sender, chat)),
  );
  // iMessage is another way into the employee's DM: both sides are kept in that conversation.
  const imessage: Channel = {
    ...photon,
    prepare: async (scope, input) => {
      const binding = await photon.binding(input);
      if (binding)
        await recordChannelMessage(env, binding, input.messageId, await photon.readText(input));
      return photon.prepare(scope, input);
    },
    send: async (scope, chatId, text, operationId, inReplyTo) => {
      const delivery = await photon.send(scope, chatId, text, operationId, inReplyTo);
      if (delivery.status === "sent") await recordChannelReply(env, scope, text, operationId);
      return delivery;
    },
  };
  const active = async (scope: Scope) =>
    Boolean(await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope)));
  const app = appChannel({
    allowed: async (senderId, scope) => {
      if (!(await active(scope))) return false;
      const colleague = senderId.startsWith("employee:")
        ? senderId.slice("employee:".length)
        : undefined;
      if (colleague) return active({ businessId: scope.businessId, employeeId: colleague });
      const person = senderId.startsWith("person:") ? senderId.slice("person:".length) : senderId;
      return Boolean(
        await Effect.runPromise(memberBusiness(env.HYPERDRIVE, person, scope.businessId)),
      );
    },
    post: (chatId, text, operationId, inReplyTo) =>
      postFromEmployee(env, chatId, text, operationId, inReplyTo),
  });
  const work = workChannel({
    open: async (scope, workItemId) => {
      const item = await Effect.runPromise(workItem(env.HYPERDRIVE, scope.businessId, workItemId));
      return (
        item?.owner_employee_id === scope.employeeId &&
        !item.taken_over_by &&
        item.state !== "cancelled"
      );
    },
    post: (chatId, text, operationId) => postFromEmployee(env, chatId, text, operationId),
  });
  const channels = [app, work, imessage];
  const pick = (chatId: string) => {
    const channel = channels.find((candidate) => candidate.id === channelOf(chatId));
    if (!channel) throw new Error(`Unknown channel for chat ${chatId}`);
    return channel;
  };
  return {
    id: "routed",
    inputKey: (input) => pick(input.chatId).inputKey(input),
    binding: (input) => pick(input.chatId).binding(input),
    readText: (input) => pick(input.chatId).readText(input),
    prepare: (scope, input) => pick(input.chatId).prepare(scope, input),
    send: (scope, chatId, text, operationId, inReplyTo) =>
      pick(chatId).send(scope, chatId, text, operationId, inReplyTo),
  };
}
