/**
 * A one-time card from a card app's tool answer (Ramp's `ramp_get_agent_card_creds`), as the
 * host's fill takes a card: number, expiry (MM/YY), security code, name and postal code. Ramp
 * documents the answer as "a one-time payment token" with "card details" and "cardholder and
 * billing values" for the payment form, without naming its fields (checked 2026-10-22), so the
 * card is read from the field names cards are commonly given; an answer without a number and an
 * expiry is refused naming only its keys, never a value.
 */
import { HostRefusal } from "../../protocol/host.ts";
import type { CardSource } from "../../browser/contract.ts";
import type { ToolResult } from "../../apps/contract.ts";
import type { Reached } from "../contract.ts";

const names = {
  number: ["pan", "card_number", "cardnumber", "number", "account_number", "token_number"],
  cvc: ["cvv", "cvc", "cvv2", "cvc2", "security_code", "card_security_code", "dynamic_cvv"],
  expiry: ["expiry", "expiration", "expiration_date", "exp", "expiry_date"],
  month: ["exp_month", "expiration_month", "expiry_month", "month"],
  year: ["exp_year", "expiration_year", "expiry_year", "year"],
  name: ["cardholder_name", "name_on_card", "cardholder", "holder_name", "name"],
  postal: ["postal_code", "zip", "zip_code", "postcode", "billing_postal_code"],
  reference: ["token_id", "payment_token_id", "credential_id", "reference", "id"],
} as const;

/** Every key and value in a JSON value, depth first (keys lowercased). */
function* entries(value: unknown, depth = 0): Generator<[string, unknown]> {
  if (depth > 6 || !value || typeof value !== "object") return;
  for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
    yield [key.toLowerCase(), inner];
    yield* entries(inner, depth + 1);
  }
}

const scalar = (value: unknown) =>
  typeof value === "string" ? value.trim() : typeof value === "number" ? String(value) : undefined;

/** The first value under any of these keys, as text. */
function find(data: unknown, keys: readonly string[]) {
  for (const key of keys)
    for (const [name, value] of entries(data))
      if (name === key && scalar(value)) return scalar(value)!;
  return undefined;
}

/** `MM/YY` from an expiry written `MM/YY`, `MM/YYYY`, `YYYY-MM` or as a month and a year. */
function expiryOf(data: unknown) {
  const written = find(data, names.expiry);
  const parts = written
    ? (/^(\d{4})-(\d{1,2})/.exec(written)?.slice(1).reverse() ??
      /^(\d{1,2})\s*\/\s*(\d{2,4})$/.exec(written)?.slice(1))
    : [find(data, names.month), find(data, names.year)];
  const [month, year] = parts ?? [];
  if (!month || !year || !/^\d{1,2}$/.test(month) || !/^\d{2,4}$/.test(year)) return undefined;
  const mm = month.padStart(2, "0");
  return Number(mm) >= 1 && Number(mm) <= 12 ? `${mm}/${year.slice(-2)}` : undefined;
}

/** The tool's answer as data: its structured content, or its text read as JSON. */
function dataOf(result: ToolResult): unknown {
  if (result.data !== undefined) return result.data;
  try {
    return JSON.parse(result.text) as unknown;
  } catch {
    return undefined;
  }
}

/** The card a card app's answer carries, as a spend secret's value, and its reference. */
export function cardFrom(result: ToolResult) {
  const data = dataOf(result);
  if (result.error)
    throw new HostRefusal(
      409,
      `The card app refused: ${result.text.replace(/\d{12,19}/g, "[number]").slice(0, 300)}`,
    );
  const number = find(data, names.number)?.replace(/[\s-]/g, "");
  const expiry = expiryOf(data);
  if (!number || !/^\d{12,19}$/.test(number) || !expiry) {
    const keys = [...new Set([...entries(data)].map(([key]) => key))].slice(0, 30);
    throw new HostRefusal(
      502,
      `The card app answered without a card Devys can fill (its fields: ${keys.join(", ") || "none"})`,
    );
  }
  const cvc = find(data, names.cvc);
  const card = {
    number,
    expiry,
    ...(cvc && /^\d{3,4}$/.test(cvc) ? { cvc } : {}),
    name: find(data, names.name) ?? "",
    postal: find(data, names.postal) ?? "",
  };
  const reference = find(data, names.reference) ?? null;
  return { card: JSON.stringify(card), reference: reference === number ? null : reference };
}

/**
 * The browser fill's card source over the host's MCP client: calls the card app's tool, reads the
 * card from its answer, and passes back a resealed sign-in; a lapsed one is a 401 refusal.
 */
export const cardIssuer =
  (call: (input: Record<string, unknown>) => Promise<Reached<{ result: ToolResult }>>) =>
  async (business: string, source: CardSource) => {
    const reached = await call({ business, ...source });
    if ("lapsed" in reached)
      throw new HostRefusal(401, "The card app's sign-in stopped working: the owner reconnects it");
    return { ...cardFrom(reached.result), ...(reached.sealed ? { sealed: reached.sealed } : {}) };
  };
