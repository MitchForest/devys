import { describe, expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { appChannel, appChat } from "../src/channels/app.ts";
import {
  addressOf,
  channelOf,
  type Binding,
  type Channel,
  type Inbound,
} from "../src/channels/contract.ts";
import { imessageChannel } from "../src/channels/photon-adapter.ts";
import { workChannel, workChat } from "../src/channels/work.ts";

const scope = { businessId: "b1", employeeId: "e1" };
const person = "p1";

/** One adapter under test: a bound input, and a variant whose sender or chat must not bind. */
interface Case {
  channel: Channel;
  bound: Inbound;
  stranger: Inbound;
  /** Whether text arrives inline (apps, dispatcher) or is read from the provider. */
  inline: boolean;
}

const cases: Case[] = [
  {
    channel: appChannel({
      allowed: async (senderId, target) => senderId === person && target.businessId === "b1",
      post: async () => {},
      notice: async () => {},
    }),
    bound: { messageId: "m-1", senderId: person, chatId: appChat(scope), text: "Hello" },
    stranger: { messageId: "m-1", senderId: "intruder", chatId: appChat(scope), text: "Hello" },
    inline: true,
  },
  {
    channel: workChannel({
      open: async (target, id) => target.employeeId === "e1" && id === "c1",
      post: async () => {},
      notice: async () => {},
    }),
    bound: {
      messageId: "c1:1",
      senderId: "dispatcher",
      chatId: workChat(scope, "c1"),
      text: "Work",
    },
    stranger: {
      messageId: "c2:1",
      senderId: "dispatcher",
      chatId: workChat(scope, "c2"),
      text: "Work",
    },
    inline: true,
  },
  {
    channel: imessageChannel({} as Env, async (sender, chat): Promise<Binding | undefined> =>
      sender === "+15550001" && chat === "any;-;+15550001"
        ? { personId: person, ...scope }
        : undefined,
    ),
    bound: { messageId: "g-1", senderId: "+15550001", chatId: "imessage:any;-;+15550001" },
    stranger: { messageId: "g-1", senderId: "+15550001", chatId: "imessage:any;-;+15559999" },
    inline: false,
  },
];

describe.each(cases)("channel $channel.id", ({ channel, bound, stranger, inline }) => {
  it("owns the chat ids that carry its prefix", () => {
    expect(channelOf(bound.chatId)).toBe(channel.id);
    expect(addressOf(bound.chatId).length).toBeGreaterThan(0);
  });

  it("keys inputs stably and within its own namespace", () => {
    expect(channel.inputKey(bound)).toBe(channel.inputKey({ ...bound }));
    expect(channel.inputKey(bound).startsWith(`${channel.id}:`)).toBe(true);
  });

  it("binds the right input to its scope and refuses a mismatched sender or chat", async () => {
    expect(await channel.binding(bound)).toMatchObject(scope);
    expect(await channel.binding(stranger)).toBeUndefined();
  });

  it.runIf(inline)("returns inline text for reading and preparing", async () => {
    expect(await channel.readText(bound)).toBe(bound.text);
    expect(await channel.prepare(scope, bound)).toBe(bound.text);
  });

  it.runIf(inline)("reports a delivery for replies", async () => {
    expect(await channel.send(scope, bound.chatId, "Reply", "op-1")).toEqual({
      status: "sent",
      guid: null,
    });
  });
});

it("chat ids split into channel and address at the first colon", () => {
  expect(channelOf("imessage:any;-;+1555")).toBe("imessage");
  expect(addressOf("imessage:any;-;+1555")).toBe("any;-;+1555");
  expect(channelOf("no-prefix")).toBe("");
});
