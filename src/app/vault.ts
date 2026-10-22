/**
 * Secrets by name (LP3, .docs/AUTHORITY.md#credentials): Settings › Secrets and the secure entry
 * sheet post here. A value passes through on its way to the Mac host, which seals it, and is never
 * answered back, logged or echoed in an error; the business's pending `askOwner` secret requests
 * for that name are answered in their threads. A card fill spends one signed spend approval.
 */
import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import { modeOf } from "./mode.ts";
import { answerText, tellEmployee } from "./asking.ts";
import { forbidden, notFound } from "./request.ts";
import { Secrets } from "./wire.ts";
import { spendOf } from "../authority/contract.ts";
import { claimSpend, secretProvided, unclaimSpend } from "../authority/service.ts";
import type { Filling } from "../browser/capabilities.ts";
import type { Business, Person } from "../identity/contract.ts";
import { readBounded } from "../protocol/bytes.ts";
import { HostRefusal } from "../protocol/host.ts";
import { respond } from "../protocol/http.ts";
import { NewSecret } from "../vault/contract.ts";
import { addEvidence } from "../work/service.ts";

/** A card number's own check digit (Luhn): a mistyped number is refused before it is stored. */
function luhn(number: string) {
  let sum = 0;
  for (let index = 0; index < number.length; index++) {
    let digit = Number(number[number.length - 1 - index]);
    if (index % 2) digit = digit * 2 > 9 ? digit * 2 - 9 : digit * 2;
    sum += digit;
  }
  return sum % 10 === 0;
}

const refused = (text: string) => new Response(text, { status: 400 });

/**
 * The sheet's entry, or a refusal that never repeats what was sent: a schema's own message would
 * quote the value.
 */
async function entryOf(request: Request) {
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(await readBounded(request.body, 20_000)));
  } catch {
    return refused("Send a name and a value, or a card, as JSON (at most 16 KB)");
  }
  const decoded = Schema.decodeUnknownExit(NewSecret)(value);
  if (decoded._tag === "Failure")
    return refused(
      "Name it in capitals (A–Z, 0–9 and _) and give its value, or a card's number, expiry (MM/YY), name and postal code",
    );
  const entry = decoded.value;
  if (entry.kind === "spend" && !luhn(entry.card.number))
    return refused("That card number isn't valid; check it and try again");
  return entry;
}

/** `/api/businesses/:id/secrets`: names and kinds, adding and removing; never a value. */
export async function secretsRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  const { secrets } = modeOf(env);
  const listed = async (status = 200) =>
    respond(Secrets, { secrets: await secrets.list(business.id) }, { status });
  if (path === "/secrets" && request.method === "GET") return listed();
  if (!trusted) return forbidden();
  if (path === "/secrets" && request.method === "POST") {
    const entry = await entryOf(request);
    if (entry instanceof Response) return entry;
    await secrets.put(
      business.id,
      entry.name,
      entry.kind,
      entry.kind === "spend" ? JSON.stringify(entry.card) : entry.value,
      person.id,
    );
    const answered = await Effect.runPromise(
      secretProvided(
        env.HYPERDRIVE,
        business.id,
        { name: entry.name, spend: entry.kind === "spend" },
        person.id,
      ),
    );
    for (const decision of answered)
      await tellEmployee(
        env,
        business.id,
        person.id,
        decision,
        answerText(decision),
        `secret:${decision.id}`,
      );
    return listed(201);
  }
  const named = /^\/secrets\/([A-Z][A-Z0-9_]{0,63})$/.exec(path);
  if (named && request.method === "DELETE")
    return (await secrets.remove(business.id, named[1]!)) ? listed() : notFound();
  return notFound();
}

/** What `browserFill` needs outside the browser: the sealed secret, the approval, the evidence. */
export const filling = (env: Env): Filling => ({
  sealed: async (businessId, name) =>
    (await modeOf(env).secrets.sealed(businessId, [name], ["secret", "spend"]))[0]!,
  async claim(businessId, workItemId, approval) {
    const decision = await Effect.runPromise(
      claimSpend(env.HYPERDRIVE, businessId, workItemId, approval),
    );
    const spend = decision && spendOf(decision);
    if (!spend)
      throw new HostRefusal(
        403,
        "No approved, signed and unused spend approval with that id in this work item: ask with askOwner (approve, with the amount and the merchant's site); each approval is one fill",
      );
    return { counterparty: spend.counterparty };
  },
  unclaim: async (businessId, approval) => {
    await Effect.runPromise(unclaimSpend(env.HYPERDRIVE, businessId, approval));
  },
  record: async (businessId, workItemId, note, source) => {
    await Effect.runPromise(
      addEvidence(env.HYPERDRIVE, businessId, workItemId, { by: "devys", note, source }),
    );
  },
});

/** The vault as a connection uses it: its store, and requests sent with a secret injected. */
export const connectionVault = (env: Env) => {
  const mode = modeOf(env);
  return { secrets: mode.secrets, send: mode.sendWithSecret };
};
