import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appReactions } from "../channels/app.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { conversationKey, employeeOf } from "../conversations/contract.ts";
import {
  conversationSummaries,
  markConversation,
  markSeen,
  setFollowing,
} from "../conversations/service.ts";
import { conversationExists, conversationPage, postFromPerson } from "./conversations.ts";
import { businessRef } from "./refs.ts";
import { body, decodedBody, forbidden, notFound } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { ConversationPage, Conversations, Following, Posted, Read, SidebarMark } from "./wire.ts";

/**
 * The business's shared conversations: DMs (`direct:<employee>`), project channels
 * (`project:<id>`) and work threads (`work:<id>`). Posting wakes whoever the conversation's rules
 * say answers.
 */
export async function conversationRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/conversations" && request.method === "GET")
    return respond(Conversations, {
      conversations: await Effect.runPromise(
        conversationSummaries(env.HYPERDRIVE, business.id, person.id),
      ),
    });
  const [, raw, action] =
    /^\/conversations\/([^/]+)(?:\/(messages|read|follow|sidebar))?$/.exec(path) ?? [];
  const key = conversationKey(decodeURIComponent(raw ?? ""));
  if (!key || !(await conversationExists(env, business.id, key))) return notFound();
  if (!action && request.method === "GET") {
    const before = new URL(request.url).searchParams.get("before") ?? undefined;
    const page = await conversationPage(env, business.id, key, before);
    // Reactions belong to each employee's messages.
    const authors = [...new Set(page.messages.map((m) => employeeOf(m.author)).filter(Boolean))];
    const reactions = (
      await Promise.all(
        authors.map((employeeId) =>
          Effect.runPromise(
            appReactions(env.HYPERDRIVE, { businessId: business.id, employeeId: employeeId! }),
          ),
        ),
      )
    ).flat();
    return respond(ConversationPage, {
      ...page,
      messages: page.messages.map((message) => ({
        ...message,
        reactions: reactions.filter((r) => r.targetId === message.id).map((r) => r.emoji),
      })),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (action === "read") {
    const { at } = await body<{ at: string }>(request, 1_000);
    if (typeof at !== "string" || !Number.isFinite(Date.parse(at)))
      return new Response("Send the time of the last message read", { status: 400 });
    await Effect.runPromise(
      markSeen(env.HYPERDRIVE, business.id, key, `person:${person.id}`, { at }),
    );
    return respond(Read, { read: true });
  }
  if (action === "follow") {
    const { on } = await body<{ on: boolean }>(request, 1_000);
    if (typeof on !== "boolean") return new Response("Send on: true or false", { status: 400 });
    await Effect.runPromise(setFollowing(env.HYPERDRIVE, business.id, key, person.id, on));
    return respond(Following, { following: on });
  }
  if (action === "sidebar") {
    const mark = await decodedBody(request, 1_000, SidebarMark);
    await Effect.runPromise(markConversation(env.HYPERDRIVE, business.id, key, person.id, mark));
    return respond(SidebarMark, mark);
  }
  if (action !== "messages") return notFound();
  const input = await body<{
    id: string;
    text: string;
    reply_to: string;
    mentions: string[];
    via_voice: boolean;
    ref: string | null;
  }>(request, 70_000);
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (
    typeof input.id !== "string" ||
    !/^[A-Za-z0-9-]{8,64}$/.test(input.id) ||
    !text ||
    text.length > 60_000
  )
    return new Response("Send an id and non-empty text", { status: 400 });
  // The record the owner is viewing goes with the message as its ref, never as text.
  const viewing =
    input.ref === undefined || input.ref === null
      ? undefined
      : await businessRef(env, business.id, input.ref);
  if (input.ref != null && !viewing)
    return new Response("Send the ref of a record of this business, or none", { status: 400 });
  const posted = await postFromPerson(env, business.id, person.id, key, {
    id: input.id,
    text,
    ...(typeof input.reply_to === "string" ? { replyTo: input.reply_to } : {}),
    ...(Array.isArray(input.mentions)
      ? { mentions: input.mentions.filter((m) => typeof m === "string") }
      : {}),
    viaVoice: input.via_voice === true,
    ...(viewing ? { ref: viewing } : {}),
  });
  if ("refused" in posted) return new Response(posted.refused, { status: 409 });
  return respond(Posted, posted, { status: 201 });
}
