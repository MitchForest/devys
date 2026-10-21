import { Schema } from "effect";
import { readBounded } from "../protocol/bytes.ts";

export const notFound = () => new Response("Not found", { status: 404 });
export const forbidden = () => new Response("Forbidden", { status: 403 });
/** A request the API refuses before reading further: answered with its status and text. */
export class RequestError extends Error {
  constructor(
    readonly status: 400 | 413,
    message: string,
  ) {
    super(message);
  }
}

/**
 * A JSON object body of at most `limit` bytes, its fields unchecked. Too large is 413; not a
 * JSON object is 400 (both thrown as `RequestError`, answered by `apiRoute`).
 */
export async function body<T>(request: Request, limit: number): Promise<Partial<T>> {
  const bytes = await readBounded(request.body, limit).catch(() => {
    throw new RequestError(413, "The request is too large");
  });
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new RequestError(400, "Send a JSON object");
  }
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new RequestError(400, "Send a JSON object");
  return value as Partial<T>;
}
/**
 * A JSON object body decoded with the schema that owns its rule (the same one a capability
 * uses). A mismatch is 400 with what was wrong, thrown as `RequestError`.
 */
export async function decodedBody<T>(
  request: Request,
  limit: number,
  schema: Schema.Codec<T, unknown>,
): Promise<T> {
  const value = await body(request, limit);
  try {
    return Schema.decodeUnknownSync(schema)(value);
  } catch (error) {
    throw new RequestError(400, error instanceof Error ? error.message : "Invalid request");
  }
}
export const label = (value: unknown, max: number) =>
  typeof value === "string" && value.trim().length > 0 && value.trim().length <= max
    ? value.trim()
    : undefined;
