import { Schema } from "effect";
import { ConversationKey } from "../conversations/contract.ts";
import { parseRef, Ref } from "../protocol/ref.ts";
import { Timestamp } from "../protocol/time.ts";
import { SecretName } from "../vault/contract.ts";

/** `auto` runs inside the grant; `ask` needs an owner decision. Absence of a grant denies. */
export const Mode = Schema.Literals(["auto", "ask"]);
export type Mode = typeof Mode.Type;

/** One employee's standing permission for one capability. Immutable: a change is a new grant. */
export const Grant = Schema.Struct({
  id: Schema.String,
  capability: Schema.String,
  mode: Mode,
  /** Values for the capability's own constraint fields; empty means no extra limits. */
  constraints: Schema.Record(Schema.String, Schema.Unknown),
  /** The area of accountability this grant serves, e.g. "Launch". */
  responsibility: Schema.NullOr(Schema.String),
  created_at: Timestamp,
});
export type Grant = typeof Grant.Type;

export type Outcome =
  | { outcome: "allow"; grantId: string }
  | { outcome: "ask"; grantId: string; decisionId?: string }
  | { outcome: "deny"; reason: string };

/**
 * What a request asks of the owner: `decision`, a modelled capability's `ask`; `approve`,
 * `take_over`, `secret`, `connect` and `file`, an employee's `askOwner`
 * (.docs/AUTHORITY.md#bringing-the-owner-in).
 */
export const RequestKind = Schema.Literals([
  "decision",
  "approve",
  "take_over",
  "secret",
  "connect",
  "file",
]);
export type RequestKind = typeof RequestKind.Type;

/** An amount in minor units (cents) of a three-letter currency. */
export const Amount = Schema.Struct({
  cents: Schema.Int.check(Schema.isGreaterThan(0), Schema.isLessThanOrEqualTo(100_000_000)),
  currency: Schema.String.check(Schema.isPattern(/^[A-Z]{3}$/)),
});
export type Amount = typeof Amount.Type;

const Words = (max: number) => Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(max));

/** A page or a file the owner sees in an approval, as it is when asked. */
export const PreviewRef = Ref.check(
  Schema.makeFilter((value) => {
    const parts = parseRef(value);
    return (
      (parts?.app === "documents" && (parts.kind === "artifact" || parts.kind === "file")) ||
      "Preview a page (devys:documents/artifact/<id>) or a file (devys:documents/file/<path>)"
    );
  }),
);

/** A media type a file request accepts: `application/pdf`, or a family like `image/*`. */
export const AcceptedType = Schema.String.check(
  Schema.isPattern(/^[a-z]+\/(\*|[a-z0-9][a-z0-9.+-]{0,99})$/),
);

/**
 * An employee's `askOwner` request, stored as its decision's input. An approve with an amount is
 * a spend approval, answered only with a signature from one of the owner's devices.
 */
export const OwnerRequest = Schema.Union([
  Schema.Struct({
    kind: Schema.Literal("approve"),
    /** Exactly what will be done: "Register acme.example for one year". */
    action: Words(500),
    /** Who or where: the merchant, site, registrar or person it is done with. */
    counterparty: Words(200),
    amount: Schema.optionalKey(Amount),
    /** What recurs, in words: "Renews yearly at $12.99". */
    renewal: Schema.optionalKey(Words(200)),
    /**
     * Each step the approval covers, exactly ("Merge PR #12 at a1b2c3", "Deploy a1b2c3 of site
     * to production"): approving covers those steps and nothing else.
     */
    steps: Schema.optionalKey(Schema.Array(Words(300)).check(Schema.isMaxLength(10))),
    /** The draft the owner approves (an email, a post, an invoice), shown on the card. */
    preview: Schema.optionalKey(PreviewRef),
  }),
  Schema.Struct({
    kind: Schema.Literal("take_over"),
    /** What the owner does in the business's browser: "Sign in to the registrar (2FA)". */
    reason: Words(500),
    url: Schema.optionalKey(
      Schema.String.check(Schema.isPattern(/^https?:\/\//), Schema.isMaxLength(2000)),
    ),
  }),
  Schema.Struct({
    kind: Schema.Literal("secret"),
    /** The name it will be used by: `STRIPE_KEY`, `RAMP_CARD`. */
    name: SecretName,
    /** What it is and why it is needed: "Stripe's restricted key, to read payouts". */
    why: Words(500),
    /** A card (number, expiry, security code, name, postal code), for checkouts. */
    spend: Schema.optionalKey(Schema.Boolean),
  }),
  Schema.Struct({
    kind: Schema.Literal("connect"),
    /** The app as appSearch found it (its id or registry name) or its MCP server's address. */
    app: Words(2000),
    /** What it is for, in one line the owner reads on the card: "To pay bills from Ramp". */
    why: Words(300),
  }),
  Schema.Struct({
    kind: Schema.Literal("file"),
    /** What the file is for, in one line on the card: "Your logo, for the site's header". */
    purpose: Words(300),
    /** The media types it may be: `image/*`, `application/pdf`. Any when absent. */
    accept: Schema.optionalKey(Schema.Array(AcceptedType).check(Schema.isMaxLength(10))),
  }),
]);
export type OwnerRequest = typeof OwnerRequest.Type;

/** A one-off owner approval of one exact request. Single-use; expires to rejected. */
export const Decision = Schema.Struct({
  id: Schema.String,
  kind: RequestKind,
  employee_id: Schema.String,
  capability: Schema.String,
  /** The exact input the employee asked to run; an `OwnerRequest` for `askOwner`. */
  input: Schema.Unknown,
  work_item_id: Schema.NullOr(Schema.String),
  /** The conversation the asking turn was answering; the answer is posted there. */
  conversation: Schema.NullOr(ConversationKey),
  status: Schema.Literals(["pending", "approved", "rejected", "used"]),
  requested_at: Timestamp,
  expires_at: Timestamp,
  /** The device key that signed a spend approval. */
  signed_by: Schema.NullOr(Schema.String),
  /** What answered a file request: the file the owner chose, in the business folder. */
  answer: Schema.NullOr(Ref),
});
export type Decision = typeof Decision.Type;

/** The `askOwner` request a decision carries, if it is one. */
export const ownerRequest = (decision: Pick<Decision, "kind" | "input">) =>
  decision.kind !== "decision" && Schema.is(OwnerRequest)(decision.input)
    ? decision.input
    : undefined;

/**
 * The draft an approve shows, with the hash of its content when it was asked (set by the
 * server, never by the employee): the approval stands only while the draft is unchanged.
 */
export const previewOf = (decision: Pick<Decision, "kind" | "input">) => {
  const request = ownerRequest(decision);
  if (request?.kind !== "approve" || !request.preview) return undefined;
  const hash = (decision.input as { previewHash?: unknown }).previewHash;
  return { ref: request.preview, hash: typeof hash === "string" ? hash : null };
};

/** The spend a decision asks the owner to sign: an approve with an amount. */
export const spendOf = (decision: Pick<Decision, "kind" | "input">) => {
  const request = ownerRequest(decision);
  return request?.kind === "approve" && request.amount
    ? { ...request, amount: request.amount }
    : undefined;
};

/**
 * A device's signing key, as the owner's devices list it: active, or pending until an active key
 * of theirs signs it.
 */
export const DeviceKey = Schema.Struct({
  id: Schema.String,
  /** The signed-in device (its session id, as `GET /api/devices` lists it). */
  device: Schema.String,
  label: Schema.NullOr(Schema.String),
  /** X9.63 uncompressed P-256 public key, base64. */
  public_key: Schema.String,
  status: Schema.Literals(["pending", "active"]),
  created_at: Timestamp,
});
export type DeviceKey = typeof DeviceKey.Type;
