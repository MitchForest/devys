import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { authenticatePhoton, sendReply } from "../src/channels/photon.ts";
import { IMessageError } from "@photon-ai/advanced-imessage/http";

const now = 1_800_000_000_000;
const secret = "fixture-secret-only";
const payload = {
  event: "messages",
  message: { id: "m1", direction: "inbound", sender: { id: "sender1" } },
  space: { id: "any;-;sender1", type: "dm" },
};
function request(body: unknown = payload, timestamp = String(now / 1000)) {
  const raw = JSON.stringify(body);
  const signature = `v0=${createHmac("sha256", secret).update(`v0:${timestamp}:${raw}`).digest("hex")}`;
  return new Request("https://devys.test/webhooks/photon", {
    method: "POST",
    body: raw,
    headers: { "x-spectrum-timestamp": timestamp, "x-spectrum-signature": signature },
  });
}

describe("Photon ingress", () => {
  it("authenticates exact signed bytes", async () => {
    expect(await authenticatePhoton(request(), secret, now)).toEqual({
      messageId: "m1",
      senderId: "sender1",
      chatId: "imessage:any;-;sender1",
    });
  });
  it("rejects a different key", async () => {
    await expect(authenticatePhoton(request(), "wrong", now)).rejects.toMatchObject({
      status: 401,
    });
  });
  it("rejects expired signatures", async () => {
    await expect(
      authenticatePhoton(request(payload, String(now / 1000 - 301)), secret, now),
    ).rejects.toMatchObject({ status: 401 });
  });
  it("ignores outbound echoes", async () => {
    expect(
      await authenticatePhoton(
        request({ ...payload, message: { ...payload.message, direction: "outbound" } }),
        secret,
        now,
      ),
    ).toBeUndefined();
  });
  it("does not infer authority for unsigned direction or sender fields", async () => {
    await expect(
      authenticatePhoton(request({ ...payload, message: { id: "m1" } }), secret, now),
    ).rejects.toMatchObject({ status: 400 });
  });
  it("ignores group messages in the one-to-one phase", async () => {
    expect(
      await authenticatePhoton(
        request({ ...payload, space: { ...payload.space, type: "group" } }),
        secret,
        now,
      ),
    ).toBeUndefined();
  });
});

it("reconciles a timed-out send using the same provider identity after restart", async () => {
  let sends = 0;
  const keys: string[] = [];
  const connect = (() => ({
    messages: {
      sendText: async (_chat: string, _text: string, options: { clientMessageId: string }) => {
        keys.push(options.clientMessageId);
        if (keys.length === 1) {
          sends++;
          throw new Error("Response lost after provider accepted message");
        }
        throw new IMessageError("Already sent", {
          code: "duplicateMessage",
          grpcCode: 6,
          retryable: false,
        });
      },
    },
    close: async () => {},
  })) as unknown as NonNullable<Parameters<typeof sendReply>[4]>;
  const config = {
    PHOTON_HTTP_ADDRESS: "https://fixture.invalid",
    PHOTON_TOKEN: "fixture",
    PHOTON_SERVER: "",
  };
  expect(await sendReply(config, "chat", "hello", "same-operation", connect)).toEqual({
    status: "uncertain",
  });
  expect(await sendReply(config, "chat", "hello", "same-operation", connect)).toEqual({
    status: "sent",
    guid: null,
  });
  expect(keys).toEqual(["same-operation", "same-operation"]);
  expect(sends).toBe(1);
});
