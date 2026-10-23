/**
 * A signed-in device answers a device asking to join (.docs/AUTHORITY.md "Signing in"). Allowing
 * signs that device in as the person who allowed it and enrolls its signing key under the
 * device-key rules: active as the person's first key, otherwise pending until an active key signs
 * it, which the allowing Mac or iPhone does at once with the key this answer returns.
 */
import { Effect } from "effect";
import { enrollKey } from "../authority/keys.ts";
import { isPublicKey } from "../authority/signing.ts";
import { answerJoin } from "../identity/joins.ts";
import { respond } from "../protocol/http.ts";
import type { Env } from "./env.ts";
import { forbidden, notFound } from "./request.ts";
import { JoinAnswered } from "./wire.ts";

export async function answerJoinRoute(
  request: Request,
  env: Env,
  access: { personId: string; trusted: boolean; path: string },
) {
  const action = /^\/api\/joins\/([0-9a-f-]{36})\/(allow|deny)$/.exec(access.path);
  if (!action || request.method !== "POST") return notFound();
  if (!access.trusted) return forbidden();
  const allow = action[2] === "allow";
  const answered = await Effect.runPromise(
    answerJoin(env.HYPERDRIVE, action[1]!, access.personId, allow),
  );
  if (!answered)
    return new Response("That request was already answered or has expired", { status: 409 });
  const publicKey = allow && answered.public_key;
  const key =
    publicKey && isPublicKey(publicKey)
      ? await Effect.runPromise(
          enrollKey(env.HYPERDRIVE, {
            personId: access.personId,
            device: answered.device,
            label: answered.name,
            publicKey,
          }),
        ).catch(() => null)
      : null;
  return respond(JoinAnswered, { key });
}
