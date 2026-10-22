/**
 * The vault (.docs/COMPONENTS.md#vault): secrets by name, per business. The owner adds a secret
 * (directly or for an employee's `askOwner` secret request); employees refer to it by name; the
 * Mac host, which alone holds the master key, opens it only to inject it into the one command,
 * request or browser field that needs it. No caller in the Worker ever receives a value.
 */
import { Schema } from "effect";
import { Timestamp } from "../protocol/time.ts";

/**
 * A secret's name as the owner gives it and employees use it: also the environment variable a
 * command it is injected into reads (`STRIPE_KEY`, `RAMP_CARD`).
 */
export const SecretName = Schema.String.check(Schema.isPattern(/^[A-Z][A-Z0-9_]{0,63}$/));

/**
 * `secret`: a value injected by name. `spend`: a card, filled into a checkout only against a
 * signed spend approval, never into a command or request. `connection`: an app connection's
 * credential (Google's refresh token), used only by that connection, named in lowercase so it
 * never shares a name with the owner's secrets.
 */
export type SecretKind = "secret" | "spend" | "connection";

/** A secret as the owner sees it: never its value. */
export const SecretEntry = Schema.Struct({
  name: Schema.String,
  kind: Schema.Literals(["secret", "spend"]),
  /** The person who added it. */
  added_by: Schema.String,
  added_at: Timestamp,
  /** When it was last handed to the host for a command, deploy, fill or request. */
  last_used_at: Schema.NullOr(Timestamp),
});
export type SecretEntry = typeof SecretEntry.Type;

/** A card, as the secure entry sheet takes it; stored as one `spend` secret. */
export const Card = Schema.Struct({
  number: Schema.String.check(Schema.isPattern(/^\d{12,19}$/)),
  /** `MM/YY`. */
  expiry: Schema.String.check(Schema.isPattern(/^(0[1-9]|1[0-2])\/\d{2}$/)),
  /** Absent when the owner keeps the security code to themselves. */
  cvc: Schema.optionalKey(Schema.String.check(Schema.isPattern(/^\d{3,4}$/))),
  name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(100)),
  postal: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(20)),
});
export type Card = typeof Card.Type;

/** The most a `secret` value may hold (an API key, a password, a PEM key). */
export const secretBytes = 16_000;

/** What the secure entry sheet sends: a value, or a card. Never echoed back. */
export const NewSecret = Schema.Union([
  Schema.Struct({
    name: SecretName,
    kind: Schema.Literal("secret"),
    value: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(secretBytes)),
  }),
  Schema.Struct({ name: SecretName, kind: Schema.Literal("spend"), card: Card }),
]);
export type NewSecret = typeof NewSecret.Type;

/**
 * A secret as stored: its value encrypted under its own data key, which is wrapped by the master
 * key, both bound to the business, name and kind (moved to another business, renamed or relabelled
 * it does not open). Only the master key's holder can open it. Base64.
 */
export interface Sealed {
  business: string;
  name: string;
  kind: SecretKind;
  /** The wrapped data key. */
  key: string;
  /** The encrypted value. */
  data: string;
}

/** The master key's holder (the Mac host in local mode): it seals values and never returns one. */
export interface Keyring {
  seal(business: string, name: string, kind: SecretKind, value: string): Promise<Sealed>;
}

/**
 * The store port. Values go in through `put` (from the owner's sheet, or a connection) and come
 * out only sealed, to the host's injection paths. Adapters: the envelope vault in Postgres; others
 * (1Password, Infisical) when someone uses one.
 */
export interface SecretStore {
  put(
    business: string,
    name: string,
    kind: SecretKind,
    value: string,
    addedBy: string,
  ): Promise<void>;
  /**
   * Stores a value the master key's holder sealed itself (a remote app's tokens, which never reach
   * the caller): a connection's credential only.
   */
  putSealed(sealed: Sealed, addedBy: string): Promise<void>;
  /** The owner's secrets (never connection credentials), by name. */
  list(business: string): Promise<SecretEntry[]>;
  remove(business: string, name: string): Promise<boolean>;
  /**
   * The named secrets of these kinds, sealed, for the host to inject; fails naming any the
   * business does not have. Marks them used.
   */
  sealed(
    business: string,
    names: readonly string[],
    kinds: readonly SecretKind[],
  ): Promise<Sealed[]>;
}

/** An HTTP request the host sends with a connection's secret put where `placeholder` stands. */
export interface SecretRequest {
  url: string;
  method: "GET" | "POST";
  headers: Record<string, string>;
  body: string | null;
}

/** The host's answer to a `SecretRequest`, the secret redacted from it. */
export interface SecretResponse {
  status: number;
  type: string | null;
  body: string;
}

/** Sends a request with a sealed connection secret injected by the host (`/vault/request`). */
export type SendWithSecret = (
  sealed: Sealed,
  request: SecretRequest,
  placeholder: string,
) => Promise<SecretResponse>;

/** The value's forms a command might print: as is, and URL-encoded. Short values are left alone. */
export const redactable = (value: string) =>
  [...new Set([value, encodeURIComponent(value)])].filter((form) => form.length >= 4);

/**
 * `text` with every form of each value replaced, so output that echoes a secret leaks nothing. Text
 * cut to size may begin with the end of a value or end with its start: those pieces (four or more
 * characters) are replaced too.
 */
export function redact(text: string, values: readonly string[]) {
  const forms = values.flatMap(redactable).sort((a, b) => b.length - a.length);
  let out = forms.reduce((done, form) => done.split(form).join("[redacted]"), text);
  for (const form of forms)
    for (let size = form.length - 1; size >= 4; size--) {
      if (out.startsWith(form.slice(-size))) out = `[redacted]${out.slice(size)}`;
      if (out.endsWith(form.slice(0, size))) out = `${out.slice(0, -size)}[redacted]`;
    }
  return out;
}

/**
 * How a host injection path opens the sealed secrets a request carries (the host's keyring,
 * passed in by `src/host.ts`): by name, only for its business and only of the kinds that path may
 * use; a refusal otherwise. Values never leave the host.
 */
export type OpenSecrets = (
  business: string,
  sealed: unknown,
  kinds: readonly SecretKind[],
) => Promise<Map<string, string>>;
