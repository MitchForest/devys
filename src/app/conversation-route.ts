import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appReactions } from "../channels/app.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { conversationKey, employeeOf } from "../conversations/contract.ts";
import { conversationSummaries, markSeen, setFollowing } from "../conversations/service.ts";
import { conversationExists, conversationPage, postFromPerson } from "./conversations.ts";
import { body, forbidden, notFound } from "./request.ts";

/**
 * The business's shared conversations: DMs (`direct:<employee>`), spaces (`space:<id>`) and
 * work threads (`work:<id>`). Posting wakes whoever the conversation's rules say answers.
 */
export async function conversationRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/conversations" && request.method === "GET")
    return Response.json({
      conversations: await Effect.runPromise(
        conversationSummaries(env.HYPERDRIVE, business.id, person.id),
      ),
    });
  const [, raw, action] =
    /^\/conversations\/([^/]+)(?:\/(messages|read|follow))?$/.exec(path) ?? [];
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
    return Response.json({
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
    return Response.json({ read: true });
  }
  if (action === "follow") {
    const { on } = await body<{ on: boolean }>(request, 1_000);
    if (typeof on !== "boolean") return new Response("Send on: true or false", { status: 400 });
    await Effect.runPromise(setFollowing(env.HYPERDRIVE, business.id, key, person.id, on));
    return Response.json({ following: on });
  }
  if (action !== "messages") return notFound();
  const input = await body<{
    id: string;
    text: string;
    replyTo: string;
    mentions: string[];
    viaVoice: boolean;
  }>(request, 70_000);
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (
    typeof input.id !== "string" ||
    !/^[A-Za-z0-9-]{8,64}$/.test(input.id) ||
    !text ||
    text.length > 60_000
  )
    return new Response("Send an id and non-empty text", { status: 400 });
  const posted = await postFromPerson(env, business.id, person.id, key, {
    id: input.id,
    text,
    ...(typeof input.replyTo === "string" ? { replyTo: input.replyTo } : {}),
    ...(Array.isArray(input.mentions)
      ? { mentions: input.mentions.filter((m) => typeof m === "string") }
      : {}),
    viaVoice: input.viaVoice === true,
  });
  if ("paused" in posted)
    return new Response(`${posted.paused.join(" and ")} is paused. Resume them to send.`, {
      status: 409,
    });
  return Response.json(posted, { status: 201 });
}
