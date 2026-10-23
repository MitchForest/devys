import { Effect } from "effect";
import { expect, it } from "vitest";
import {
  appChannel,
  appChat,
  appReactions,
  composeAppMessage,
  readAppInput,
  setAppReaction,
} from "../src/channels/app.ts";
import { business, db } from "./fixtures/postgres.ts";

const run = <A>(effect: Effect.Effect<A, unknown>) => Effect.runPromise(effect);

it("an app message reaches only the employee in its chat, and only from a member", async () => {
  const acme = await business("Acme");
  const app = appChannel({
    allowed: async (senderId, scope) =>
      senderId === acme.person && scope.businessId === acme.scope.businessId,
    post: async () => {},
    notice: async () => {},
  });
  const input = {
    messageId: "msg-00000001",
    senderId: acme.person,
    chatId: appChat(acme.scope),
    text: "What is blocking launch?",
  };
  expect(await app.binding(input)).toEqual({ personId: acme.person, ...acme.scope });
  expect(await app.readText(input)).toBe("What is blocking launch?");
  expect(await app.prepare(acme.scope, input)).toBe("What is blocking launch?");
  expect(await app.binding({ ...input, senderId: "stranger" })).toBeUndefined();
  expect(
    await app.binding({ ...input, chatId: appChat({ businessId: "other", employeeId: "x" }) }),
  ).toBeUndefined();
  expect(await app.binding({ ...input, chatId: "app:only-one-part" })).toBeUndefined();
  await expect(app.readText({ ...input, text: undefined })).rejects.toThrow();
  expect(await app.send(acme.scope, input.chatId, "Done", "op-1")).toEqual({
    status: "sent",
    guid: null,
  });
});

it("the employee hears the quoted reply, voice provenance and reactions since its last message", async () => {
  const { scope } = await business();
  await run(
    setAppReaction(db, scope, {
      targetId: "pi-11",
      targetText: "Draft ready",
      emoji: "👍",
      on: true,
    }),
  );
  await run(
    setAppReaction(db, scope, { targetId: "pi-12", targetText: "Sent", emoji: "❓", on: true }),
  );
  await run(
    setAppReaction(db, scope, { targetId: "pi-12", targetText: "Sent", emoji: "❓", on: false }),
  );
  expect(await run(appReactions(db, scope))).toEqual([{ targetId: "pi-11", emoji: "👍" }]);
  const message = {
    id: "msg-00000003",
    text: "Make it shorter",
    replyToText: "Draft ready",
    viaVoice: true,
  };
  const composed = await run(composeAppMessage(db, scope, message));
  expect(composed).toContain('Replying to your message: "Draft ready"');
  expect(composed).toContain('Reacted 👍 to your message: "Draft ready"');
  expect(composed).toContain("Dictated by voice");
  expect(composed.endsWith("Make it shorter")).toBe(true);
  // A retried request composes the same text; the next message sees no old reactions.
  expect(await run(composeAppMessage(db, scope, message))).toBe(composed);
  expect(await run(composeAppMessage(db, scope, { id: "msg-00000004", text: "Thanks" }))).toBe(
    "Thanks",
  );
  expect(readAppInput(composed)).toEqual({
    text: "Make it shorter",
    replyToText: "Draft ready",
    viaVoice: true,
  });
  expect(readAppInput("Plain words")).toEqual({ text: "Plain words" });
});

it("reactions belong to one employee's conversation", async () => {
  const acme = await business("Acme");
  const globex = await business("Globex");
  await run(
    setAppReaction(db, acme.scope, {
      targetId: "pi-1",
      targetText: "Hi",
      emoji: "❤️",
      on: true,
    }),
  );
  expect(await run(appReactions(db, globex.scope))).toEqual([]);
  expect(await run(composeAppMessage(db, globex.scope, { id: "msg-0000000a", text: "Hi" }))).toBe(
    "Hi",
  );
});
