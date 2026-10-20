import { expect, it } from "vitest";
import { nextResponder, responders, type Message } from "../src/conversations/contract.ts";
import { observations } from "../src/runtime/memory.ts";
import type { EntryRecord } from "@earendil-works/pi-durable";

type Item = Pick<Message, "id" | "author" | "mentions" | "kind">;
const owner = "person:p";
const said = (id: string, author: string, mentions: string[] = []): Item => ({
  id,
  author,
  mentions,
  kind: "message",
});

it("the owner's message goes to whoever they reply to, else the last speaker, else the default", () => {
  const history = [said("1", owner), said("2", "employee:ops"), said("3", "employee:growth")];
  const answer = (reply_to: string | null, mentions: string[] = []) =>
    responders({
      message: { author: owner, mentions, reply_to },
      history,
      defaultResponder: "ops",
    });
  expect(answer(null)).toEqual(["growth"]);
  expect(answer("2")).toEqual(["ops"]);
  expect(answer("2", ["eng"])).toEqual(["eng"]);
  expect(
    responders({
      message: { author: owner, mentions: [], reply_to: null },
      history: [],
      defaultResponder: "ops",
    }),
  ).toEqual(["ops"]);
  // Events never count as speaking.
  expect(
    nextResponder([said("1", "employee:growth"), { ...said("2", "system"), kind: "event" }], "ops"),
  ).toBe("growth");
});

it("an employee wakes only those it mentions, and the asker when answering a request", () => {
  const history = [said("1", owner), said("2", "employee:ops", ["eng"])];
  const answer = (author: string, reply_to: string | null, mentions: string[] = []) =>
    responders({ message: { author, mentions, reply_to }, history, defaultResponder: "ops" });
  expect(answer("employee:eng", "2")).toEqual(["ops"]);
  expect(answer("employee:eng", null)).toEqual([]);
  expect(answer("employee:ops", null, ["growth", "ops"])).toEqual(["growth"]);
  // Operations thanking Engineering wakes nobody: Engineering asked nothing.
  const thanks = [...history, said("3", "employee:eng")];
  expect(
    responders({
      message: { author: "employee:ops", mentions: [], reply_to: "3" },
      history: thanks,
      defaultResponder: "ops",
    }),
  ).toEqual([]);
});

it("stops after three employee turns in a row between owner messages", () => {
  const history = [
    said("1", owner),
    said("2", "employee:ops", ["eng"]),
    said("3", "employee:eng", ["ops"]),
  ];
  expect(
    responders({
      message: { author: "employee:ops", mentions: ["eng"], reply_to: null },
      history,
      defaultResponder: "ops",
    }),
  ).toEqual([]);
});

it("memory learns the owner's words, not catch-up context or colleagues' messages", () => {
  const entry = (content: string, id: number) =>
    ({
      kind: "pi.user",
      id,
      conversationId: 1,
      model: [{ role: "user", content, timestamp: 0 }],
    }) as unknown as EntryRecord;
  const learned = observations(
    [
      entry(
        "<owner-context>\nSince you last looked:\n[Growth] Instagram\n</owner-context>\n\nShip Friday.",
        1,
      ),
      entry(
        "<owner-context>\nFrom your colleague Operations.\n</owner-context>\n\nPlease check Stripe.",
        2,
      ),
    ],
    "ns",
  );
  expect(learned.map((o) => o.content)).toEqual(["Ship Friday."]);
});
