import { createHmac, timingSafeEqual } from "node:crypto";
import { createHttpClient, IMessageError } from "@photon-ai/advanced-imessage/http";
import { Schema } from "effect";
import { readBounded } from "../protocol/bytes.ts";

const Id = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(512));
const Event = Schema.Struct({
  event: Schema.Literal("messages"),
  message: Schema.Struct({
    id: Id,
    direction: Schema.Literals(["inbound", "outbound"]),
    sender: Schema.optional(Schema.Struct({ id: Id })),
  }),
  space: Schema.Struct({ id: Id, type: Schema.Literals(["dm", "group"]) }),
});

export { Inbound } from "./contract.ts";
import type { Inbound, Delivery } from "./contract.ts";
export type { Delivery } from "./contract.ts";

export class WebhookError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/** Spectrum signs the exact body using v0:timestamp:body, not parsed JSON. */
export async function authenticatePhoton(
  request: Request,
  secret: string,
  now = Date.now(),
): Promise<Inbound | undefined> {
  if (!secret) throw new WebhookError(503, "Messaging is not configured");
  const timestamp = request.headers.get("x-spectrum-timestamp");
  const signature = request.headers.get("x-spectrum-signature");
  if (
    !timestamp ||
    !/^\d+$/.test(timestamp) ||
    !signature ||
    !/^v0=[a-f0-9]{64}$/.test(signature)
  ) {
    throw new WebhookError(401, "Invalid webhook signature");
  }
  if (Math.abs(now / 1000 - Number(timestamp)) > 300)
    throw new WebhookError(401, "Expired webhook signature");
  let bytes: Uint8Array;
  try {
    bytes = await readBounded(request.body, 256_000);
  } catch {
    throw new WebhookError(413, "Webhook exceeds limit");
  }
  const expected = createHmac("sha256", secret).update(`v0:${timestamp}:`).update(bytes).digest();
  if (!timingSafeEqual(expected, Buffer.from(signature.slice(3), "hex"))) {
    throw new WebhookError(401, "Invalid webhook signature");
  }
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new WebhookError(400, "Invalid webhook JSON");
  }
  if (
    typeof value !== "object" ||
    value === null ||
    !("event" in value) ||
    value.event !== "messages"
  )
    return;
  let event: typeof Event.Type;
  try {
    event = Schema.decodeUnknownSync(Event)(value);
  } catch {
    throw new WebhookError(400, "Invalid message event");
  }
  if (event.message.direction !== "inbound" || event.space.type !== "dm") return;
  if (!event.message.sender) throw new WebhookError(400, "Missing sender");
  return {
    messageId: event.message.id,
    senderId: event.message.sender.id,
    chatId: `imessage:${event.space.id}`,
  };
}

export interface PhotonConfig {
  PHOTON_HTTP_ADDRESS: string;
  PHOTON_TOKEN: string;
  PHOTON_SERVER: string;
}

export function photon(config: PhotonConfig) {
  return createHttpClient({
    address: config.PHOTON_HTTP_ADDRESS,
    token: config.PHOTON_TOKEN,
    ...(config.PHOTON_SERVER ? { server: config.PHOTON_SERVER } : {}),
    autoIdempotency: true,
    retry: false, // The durable outbox owns retries and their identity.
    timeout: 15_000,
  });
}

/** Stable clientMessageId is reused across process restarts for the same send. */
export async function sendReply(
  config: PhotonConfig,
  chatId: string,
  text: string,
  operationId: string,
  connect: (config: PhotonConfig) => Pick<ReturnType<typeof photon>, "messages" | "close"> = photon,
): Promise<Delivery> {
  const client = connect(config);
  try {
    const sent = await client.messages.sendText(chatId, text, { clientMessageId: operationId });
    return { status: "sent", guid: sent.guid };
  } catch (error) {
    // The provider documents this as evidence that the original send succeeded.
    if (error instanceof IMessageError && error.code === "duplicateMessage")
      return { status: "sent", guid: null };
    return { status: "uncertain" };
  } finally {
    await client.close();
  }
}
