import { Schema } from "effect";

/** Browser mutations must originate from this deployment. */
export function sameOrigin(request: Request) {
  return request.headers.get("origin") === new URL(request.url).origin;
}

/**
 * A JSON response in the shape its wire schema defines. Encoding refuses a missing, mistyped or
 * extra field, so a handler that drifts from the contract fails its tests instead of a client.
 */
export const respond = <T, E>(schema: Schema.Codec<T, E>, value: T, init?: ResponseInit) =>
  Response.json(Schema.encodeSync(schema)(value, { onExcessProperty: "error" }), init);
