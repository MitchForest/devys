/**
 * Bringing the owner in (LP1, .docs/AUTHORITY.md#bringing-the-owner-in-askowner-and-signed-spend-approvals):
 * an employee's `askOwner` becomes authority's request; a spend approval is answered only with a
 * device signature over its canonical payload; Take over and Hand back answer take-over
 * requests; the owner's Mac and iPhone enroll their signing keys here.
 */
import { Effect } from "effect";
import type { Env } from "./env.ts";
import { activeGrant, askOwner, handBackRequests, takeOverRequests } from "../authority/service.ts";
import { deviceKey, deviceKeys, endorseKey, enrollKey, revokeKeys } from "../authority/keys.ts";
import {
  endorsementPayload,
  isPublicKey,
  spendPayload,
  verifySignature,
} from "../authority/signing.ts";
import { ownerRequest, spendOf, type Decision, type OwnerRequest } from "../authority/contract.ts";
import { conversationKey } from "../conversations/contract.ts";
import { devices } from "../identity/sessions.ts";
import { respond } from "../protocol/http.ts";
import { postFromPerson } from "./conversations.ts";
import { decodedBody, forbidden, notFound } from "./request.ts";
import { DeviceKeys, KeyEndorsement, KeyEnrollment, SpendSignature } from "./wire.ts";
import { DeviceKey } from "../authority/contract.ts";

/** `askOwner`, bound to the employee's grant revision and the work item it is asked in. */
export async function askOwnerFor(
  env: Pick<Env, "HYPERDRIVE">,
  asking: { businessId: string; employeeId: string; workItemId: string; conversation: string },
  request: OwnerRequest,
): Promise<Decision> {
  const scope = { businessId: asking.businessId, employeeId: asking.employeeId };
  const grant = await Effect.runPromise(activeGrant(env.HYPERDRIVE, scope, "askOwner"));
  if (!grant) throw new Error("Not granted: askOwner");
  return Effect.runPromise(
    askOwner(env.HYPERDRIVE, scope, {
      grantId: grant.id,
      request,
      workItemId: asking.workItemId,
      conversation: asking.conversation,
    }),
  );
}

const money = (amount: { cents: number; currency: string }) =>
  `${(amount.cents / 100).toFixed(2)} ${amount.currency}`;

/** The canonical payload a spend approval's signature covers, from the stored request. */
export function spendTerms(decision: Decision, businessId: string) {
  const spend = spendOf(decision);
  if (!spend || !decision.work_item_id) return undefined;
  return spendPayload({
    decision: decision.id,
    business: businessId,
    workItem: decision.work_item_id,
    action: spend.action,
    counterparty: spend.counterparty,
    amountCents: spend.amount.cents,
    currency: spend.amount.currency,
    renewal: spend.renewal ?? null,
    expiresAt: decision.expires_at,
  });
}

/**
 * The signature that approves this spend, checked against one of the answering person's active
 * keys over the request exactly as stored; a refusal otherwise. Only a Mac or iPhone signs.
 */
export async function signedSpend(
  request: Request,
  env: Pick<Env, "HYPERDRIVE">,
  personId: string,
  businessId: string,
  decision: Decision,
): Promise<{ keyId: string; signature: string } | Response> {
  const refused = (text: string) => new Response(text, { status: 403 });
  const signed = await decodedBody(request, 4_000, SpendSignature).catch(() => undefined);
  if (!signed)
    return refused(
      "A spend is approved only on your Mac or iPhone, signed with Face ID or Touch ID.",
    );
  const key = await Effect.runPromise(deviceKey(env.HYPERDRIVE, personId, signed.key_id));
  if (!key || key.status !== "active")
    return refused("That device can't sign approvals: enroll it, or allow it from another device.");
  const payload = spendTerms(decision, businessId);
  if (!payload || !(await verifySignature(key.public_key, payload, signed.signature)))
    return refused("That signature doesn't cover this exact request.");
  return { keyId: key.id, signature: signed.signature };
}

/** What the owner's answer says in the thread, which wakes the employee there. */
export function answerText(decision: Decision) {
  const request = ownerRequest(decision);
  const approved = decision.status === "approved";
  if (request?.kind === "approve") {
    const spend = request.amount ? ` for ${money(request.amount)}` : "";
    return approved
      ? `Approved${request.amount ? " and signed" : ""}: ${request.action} (${request.counterparty}${spend}). Go ahead, exactly as asked, once.`
      : `Declined: ${request.action}. Don't do it; find another way or ask me.`;
  }
  if (request?.kind === "take_over")
    return `I won't take this over: ${request.reason}. Find another way or ask me.`;
  if (request?.kind === "secret")
    return approved
      ? `Added ${request.name}${request.spend ? " (a card)" : ""}: use it by name.`
      : `I won't add ${request.name}. Find another way or ask me.`;
  return approved
    ? `Approved: ${decision.capability}. Go ahead: call it once more with exactly the input you asked for.`
    : `Declined: ${decision.capability}. Don't run it; find another way or ask me.`;
}

/** Posts the owner's answer where the employee asked, mentioning it, which wakes it. */
export async function tellEmployee(
  env: Env,
  businessId: string,
  personId: string,
  decision: Decision,
  text: string,
  id = `decision:${decision.id}`,
) {
  const key = decision.conversation ? conversationKey(decision.conversation) : undefined;
  if (key)
    await postFromPerson(env, businessId, personId, key, {
      id,
      text,
      mentions: [decision.employee_id],
    });
}

/** Taking work over answers its take-over requests: the owner is doing them now. */
export const tookOver = (env: Env, businessId: string, personId: string, workItemId: string) =>
  Effect.runPromise(takeOverRequests(env.HYPERDRIVE, businessId, workItemId, personId));

/** Handing it back says each take-over request is done, in its thread. */
export async function handedBack(
  env: Env,
  businessId: string,
  personId: string,
  workItemId: string,
) {
  const done = await Effect.runPromise(handBackRequests(env.HYPERDRIVE, businessId, workItemId));
  for (const decision of done) {
    const request = ownerRequest(decision);
    await tellEmployee(
      env,
      businessId,
      personId,
      decision,
      `Done: ${request?.kind === "take_over" ? request.reason : "what you asked me to take over"}. I've handed the work back; carry on.`,
      `take-over:${decision.id}`,
    );
  }
}

/**
 * `/api/device-keys`: a person's signing keys. Their Mac or iPhone app enrolls its Secure Enclave
 * key (the first active at once; later ones once an active key signs them), and a key is
 * revoked when its device signs out or here.
 */
export async function deviceKeysRoute(
  request: Request,
  env: Env,
  access: { personId: string; device: string; bearer: boolean; trusted: boolean; path: string },
) {
  const { personId, device, path } = access;
  if (path === "/api/device-keys" && request.method === "GET")
    return respond(DeviceKeys, {
      keys: (await Effect.runPromise(deviceKeys(env.HYPERDRIVE, personId))).map((key) => ({
        ...key,
        current: key.device === device,
      })),
    });
  if (request.method !== "POST") return notFound();
  if (!access.trusted) return forbidden();
  if (path === "/api/device-keys") {
    // Only an app holds a key: a browser cannot sign (.docs/AUTHORITY.md).
    if (!access.bearer)
      return new Response("Signing keys are enrolled from the Mac or iPhone app", { status: 403 });
    const { public_key } = await decodedBody(request, 2_000, KeyEnrollment);
    if (!isPublicKey(public_key))
      return new Response("Send a P-256 public key (X9.63, base64)", { status: 400 });
    const label =
      (await Effect.runPromise(devices(env.HYPERDRIVE, personId))).find(
        (each) => each.id === device,
      )?.label ?? null;
    const key = await Effect.runPromise(
      enrollKey(env.HYPERDRIVE, { personId, device, label, publicKey: public_key }),
    );
    return respond(DeviceKey, key, { status: 201 });
  }
  const action = /^\/api\/device-keys\/([A-Za-z0-9-]{1,64})\/(endorse|revoke)$/.exec(path);
  if (!action) return notFound();
  const target = await Effect.runPromise(deviceKey(env.HYPERDRIVE, personId, action[1]!));
  if (!target) return notFound();
  if (action[2] === "revoke") {
    await Effect.runPromise(revokeKeys(env.HYPERDRIVE, personId, { id: target.id }));
    return respond(DeviceKey, target);
  }
  const endorsement = await decodedBody(request, 4_000, KeyEndorsement);
  const signer = await Effect.runPromise(deviceKey(env.HYPERDRIVE, personId, endorsement.key_id));
  const payload = endorsementPayload({
    person: personId,
    key: target.id,
    device: target.device,
    publicKey: target.public_key,
  });
  if (
    !signer ||
    signer.status !== "active" ||
    !(await verifySignature(signer.public_key, payload, endorsement.signature))
  )
    return new Response("Allow a device with a signature from one already allowed", {
      status: 403,
    });
  const endorsed = await Effect.runPromise(
    endorseKey(env.HYPERDRIVE, personId, target.id, {
      by: signer.id,
      signature: endorsement.signature,
    }),
  );
  return endorsed
    ? respond(DeviceKey, endorsed)
    : new Response("That key is already allowed", { status: 409 });
}

/** A signed-out device's keys stop signing. */
export const signedOut = (env: Pick<Env, "HYPERDRIVE">, personId: string, device: string) =>
  Effect.runPromise(revokeKeys(env.HYPERDRIVE, personId, { device }));
