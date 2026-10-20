import type { Env } from "../../infra/api.ts";
import { addressOf, type Binding, type Channel, type Inbound } from "./contract.ts";
import { loadInput, readMessageText } from "./input.ts";
import { sendReply } from "./photon.ts";

/** Photon names a chat by its own GUID; Devys prefixes it with the channel id. */
const raw = (input: Inbound): Inbound => ({ ...input, chatId: addressOf(input.chatId) });

/** iMessage through Photon. Binding lookup is supplied by wiring; channels do not read identity storage. */
export function imessageChannel(
  env: Env,
  bindingFor: (sender: string, chat: string) => Promise<Binding | undefined>,
): Channel {
  return {
    id: "imessage",
    inputKey: (input) => `imessage:${input.messageId}`,
    binding: (input) => bindingFor(input.senderId, addressOf(input.chatId)),
    readText: (input) => readMessageText(env, raw(input)),
    prepare: (scope, input) => loadInput(env, scope.businessId, raw(input)),
    send: (_scope, chat, text, operation) => sendReply(env, addressOf(chat), text, operation),
  };
}
