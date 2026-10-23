/**
 * Bringing the owner in (LP1, .docs/AUTHORITY.md#bringing-the-owner-in-askowner-and-signed-spend-approvals):
 * an employee's `askOwner` becomes authority's request; a spend approval is answered only with a
 * device signature over its canonical payload; Take over and Hand back answer take-over
 * requests; a file request is answered with the file the owner chose; the owner's Mac and iPhone
 * enroll their signing keys here.
 */
import { Effect } from "effect";
import type { Env } from "./env.ts";
import {
  activeGrant,
  askOwner,
  fileProvided,
  handBackRequests,
  lapseDecision,
  takeOverRequests,
} from "../authority/service.ts";
import { deviceKey, deviceKeys, endorseKey, enrollKey, revokeKeys } from "../authority/keys.ts";
import {
  endorsementPayload,
  isPublicKey,
  spendPayload,
  verifySignature,
} from "../authority/signing.ts";
import {
  ownerRequest,
  previewOf,
  spendOf,
  type Decision,
  type OwnerRequest,
} from "../authority/contract.ts";
import { conversationKey } from "../conversations/contract.ts";
import { devices } from "../identity/sessions.ts";
import { respond } from "../protocol/http.ts";
import { HostRefusal } from "../protocol/host.ts";
import { parseRef, ref } from "../protocol/ref.ts";
import { readBounded } from "../protocol/bytes.ts";
import { revisionConflict } from "../workspace/contract.ts";
import { postEvent, postFromPerson } from "./conversations.ts";
import { modeOf } from "./mode.ts";
import { contentHash } from "./refs.ts";
import { decodedBody, forbidden, notFound } from "./request.ts";
import { DeviceKeys, KeyEndorsement, KeyEnrollment, SpendSignature } from "./wire.ts";
import { DeviceKey } from "../authority/contract.ts";

/**
 * `askOwner`, bound to the employee's grant revision and the work item it is asked in. A draft to
 * preview is bound by the hash of its content now, so a changed draft is a new request.
 */
export async function askOwnerFor(
  env: Env,
  asking: { businessId: string; employeeId: string; workItemId: string; conversation: string },
  request: OwnerRequest,
): Promise<Decision> {
  const scope = { businessId: asking.businessId, employeeId: asking.employeeId };
  const grant = await Effect.runPromise(activeGrant(env.HYPERDRIVE, scope, "askOwner"));
  if (!grant) throw new Error("Not granted: askOwner");
  let asked: OwnerRequest = request;
  if (request.kind === "approve" && request.preview) {
    const previewHash = await contentHash(env, asking.businessId, request.preview);
    if (!previewHash)
      throw new HostRefusal(
        400,
        "Preview a page or a file of this business by its ref (devys:documents/artifact/<id> or devys:documents/file/<path>)",
      );
    asked = { ...request, previewHash } as OwnerRequest;
  }
  return Effect.runPromise(
    askOwner(env.HYPERDRIVE, scope, {
      grantId: grant.id,
      request: asked,
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
  const preview = previewOf(decision);
  return spendPayload({
    decision: decision.id,
    business: businessId,
    workItem: decision.work_item_id,
    action: spend.action,
    counterparty: spend.counterparty,
    amountCents: spend.amount.cents,
    currency: spend.amount.currency,
    renewal: spend.renewal ?? null,
    steps: spend.steps ?? [],
    preview: preview?.ref ?? null,
    previewHash: preview?.hash ?? null,
    expiresAt: decision.expires_at,
  });
}

/**
 * Whether the draft an approve shows is still what was asked; a request without one always is.
 * A changed draft voids the request: it lapses, and the employee is told to ask again.
 */
export async function draftUnchanged(
  env: Env,
  businessId: string,
  personId: string,
  decision: Decision,
) {
  const preview = previewOf(decision);
  if (!preview) return true;
  if (preview.hash && (await contentHash(env, businessId, preview.ref)) === preview.hash)
    return true;
  await Effect.runPromise(lapseDecision(env.HYPERDRIVE, businessId, decision.id));
  await tellEmployee(
    env,
    businessId,
    personId,
    decision,
    "That draft changed after you asked, so I can't approve it. Ask again with it as it is now.",
  );
  return false;
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

/** What a secret request asks for, as the owner reads it: what it is, never its name. */
const secretWhat = (request: { why: string; spend?: boolean }) =>
  request.spend ? "the card you asked for" : `the secret you asked for (${request.why})`;

/** A file's name, from its ref. */
const fileName = (file: string) =>
  decodeURIComponent(parseRef(file)?.id ?? file)
    .split("/")
    .at(-1) ?? file;

/**
 * What the owner's answer says in the thread, which wakes the employee there: `text` everyone
 * reads, and `forEmployee`, what only the employee's delivery adds (a secret's name, a file's
 * ref), so identifiers stay out of what the owner reads.
 */
export function answerText(decision: Decision): { text: string; forEmployee?: string } {
  const request = ownerRequest(decision);
  const approved = decision.status === "approved";
  if (request?.kind === "approve") {
    const spend = request.amount ? ` for ${money(request.amount)}` : "";
    const steps = request.steps?.length ? ` These steps: ${request.steps.join("; ")}.` : "";
    return {
      text: approved
        ? `Approved${request.amount ? " and signed" : ""}: ${request.action} (${request.counterparty}${spend}).${steps} Go ahead, exactly as asked, once.`
        : `Declined: ${request.action}. Don't do it; find another way or ask me.`,
    };
  }
  if (request?.kind === "take_over")
    return { text: `I won't take this over: ${request.reason}. Find another way or ask me.` };
  if (request?.kind === "connect")
    return {
      text: approved
        ? `Connected: ${request.app}. Find what it does with describe_capabilities.`
        : `I won't connect ${request.app}. Find another way or ask me.`,
    };
  if (request?.kind === "secret")
    return approved
      ? { text: `Added ${secretWhat(request)}.`, forEmployee: `Use it by name: ${request.name}.` }
      : {
          text: `I won't add ${secretWhat(request)}. Find another way or ask me.`,
          forEmployee: `(The secret you asked for as ${request.name}.)`,
        };
  if (request?.kind === "file")
    return approved && decision.answer
      ? {
          text: `Here's the file: ${fileName(decision.answer)}.`,
          forEmployee: `It is ${decision.answer} in the business folder; read it there.`,
        }
      : { text: `I won't send a file for this: ${request.purpose}. Find another way or ask me.` };
  return {
    text: approved
      ? `Approved: ${decision.capability}. Go ahead: call it once more with exactly the input you asked for.`
      : `Declined: ${decision.capability}. Don't run it; find another way or ask me.`,
  };
}

/**
 * Posts the owner's answer where the employee asked, mentioning it, which wakes it. What only the
 * employee should read (`forEmployee`) goes into its delivery, not into the shared message.
 */
export async function tellEmployee(
  env: Env,
  businessId: string,
  personId: string,
  decision: Decision,
  answer: string | { text: string; forEmployee?: string },
  id = `decision:${decision.id}`,
) {
  const { text, forEmployee } = typeof answer === "string" ? { text: answer } : answer;
  const key = decision.conversation ? conversationKey(decision.conversation) : undefined;
  if (key)
    await postFromPerson(env, businessId, personId, key, {
      id,
      text,
      mentions: [decision.employee_id],
      ...(forEmployee ? { forEmployees: forEmployee } : {}),
    });
}

/** The largest file a file request takes. */
const fileBytes = 20_000_000;

/** Whether a media type is one a file request accepts (`image/*` takes any image). */
export const accepts = (accept: readonly string[] | undefined, type: string) =>
  !accept?.length ||
  accept.some((each) =>
    each.endsWith("/*") ? type.startsWith(each.slice(0, -1)) : each === type.toLowerCase(),
  );

/**
 * `POST …/decisions/:id/file?name=`: the file the owner chose for a file request, its bytes as the
 * body. It goes into the business folder's Uploads (never over another file), answers the
 * request with its ref, and shows it in the thread.
 */
export async function answerWithFile(
  request: Request,
  env: Env,
  access: { personId: string; businessId: string },
  decision: Decision,
) {
  const asked = ownerRequest(decision);
  if (asked?.kind !== "file" || decision.status !== "pending")
    return new Response("That request was already answered or has expired", { status: 409 });
  const type = (request.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  if (!accepts(asked.accept, type))
    return new Response(`Choose a file of type ${asked.accept!.join(" or ")}`, { status: 415 });
  // A name, never a path: separators and control characters become "_".
  const name = Array.from(new URL(request.url).searchParams.get("name") ?? "", (char) =>
    char === "/" || char === "\\" || char.charCodeAt(0) < 32 ? "_" : char,
  )
    .join("")
    .replace(/^\.+/, "")
    .slice(0, 200);
  if (!name) return new Response("Send the file's name", { status: 400 });
  const root = modeOf(env).businessFolder(access.businessId);
  if (!root) return new Response("Files run in local mode only for now.", { status: 503 });
  const bytes = await readBounded(request.body, fileBytes).catch(() => undefined);
  if (!bytes) return new Response("The file is too large", { status: 413 });
  const key = `${access.businessId}/file-saves/${crypto.randomUUID()}`;
  await env.FILES.put(key, bytes);
  const runner = modeOf(env).runner(root)({ businessId: access.businessId, employeeId: "owner" });
  const dot = name.lastIndexOf(".");
  const [stem, extension] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  let path: string | undefined;
  try {
    // Never over an existing file: "logo.png", then "logo 2.png", …
    for (let copy = 1; copy <= 20 && !path; copy++) {
      const candidate = `${root}/Uploads/${copy === 1 ? stem : `${stem} ${copy}`}${extension}`;
      path = await runner.importFile(candidate, key, null).then(
        () => candidate,
        (error: unknown) => {
          if (error instanceof Error && error.message.startsWith(revisionConflict))
            return undefined;
          throw error;
        },
      );
    }
  } catch {
    path = undefined;
  } finally {
    await env.FILES.delete(key);
  }
  if (!path) return new Response("The file couldn't be saved", { status: 409 });
  const file = ref("documents", "file", path);
  const answered = await Effect.runPromise(
    fileProvided(env.HYPERDRIVE, access.businessId, decision.id, file, access.personId),
  );
  if (!answered)
    return new Response("That request was already answered or has expired", { status: 409 });
  if (answered.conversation) {
    const key = conversationKey(answered.conversation)!;
    await postEvent(env, access.businessId, key, {
      clientId: `file:${answered.id}`,
      text: fileName(file),
      ref: file,
    });
  }
  await tellEmployee(env, access.businessId, access.personId, answered, answerText(answered));
  return answered;
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
