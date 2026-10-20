import type { Env } from "../../infra/api.ts";
import { readBounded } from "../protocol/bytes.ts";
import { palettes, shapes, tints, type Look } from "./contract.ts";

const imageTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const maxBytes = 1_000_000;
/** One photo per business or employee, stored privately in R2 inside the business. */
const key = (businessId: string, subject: string) => `looks/${businessId}/${subject}`;

const oneOf = <T extends string>(values: readonly T[], value: unknown): value is T =>
  typeof value === "string" && (values as readonly string[]).includes(value);

/**
 * A look the owner may set directly. Photos are set only by uploading one, so a
 * client cannot point a look at bytes that were never stored. Undefined is invalid.
 */
export function parseLook(value: unknown): Exclude<Look, { kind: "photo" }> | null | undefined {
  if (value === null) return null;
  if (!value || typeof value !== "object") return undefined;
  const look = value as Record<string, unknown>;
  if (look.kind === "face" && oneOf(palettes, look.palette) && oneOf(shapes, look.shape)) {
    const seed = look.seed;
    if (typeof seed === "number" && Number.isInteger(seed) && seed >= 0 && seed < 97)
      return { kind: "face", palette: look.palette, shape: look.shape, seed };
  }
  if (look.kind === "emoji" && oneOf(tints, look.tint)) {
    const emoji = look.emoji;
    // One grapheme: a single emoji, including sequences joined into one.
    if (
      typeof emoji === "string" &&
      emoji.length <= 16 &&
      [...new Intl.Segmenter().segment(emoji)].length === 1
    )
      return { kind: "emoji", emoji, tint: look.tint };
  }
  return undefined;
}

/** Reads or replaces a look's photo. A successful upload returns the photo look to save. */
export async function lookPhoto(
  request: Request,
  env: Env,
  businessId: string,
  subject: string,
): Promise<Response | Look> {
  if (request.method === "GET") {
    const object = await env.FILES.get(key(businessId, subject));
    if (!object) return new Response(null, { status: 404 });
    return new Response(object.body, {
      headers: {
        "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
        "content-length": String(object.size),
        "cache-control": "private, max-age=31536000, immutable",
        "content-security-policy": "sandbox; default-src 'none'",
      },
    });
  }
  if (request.method !== "PUT") return new Response("Method not allowed", { status: 405 });
  const type = request.headers.get("content-type")?.split(";")[0]?.trim() ?? "";
  if (!imageTypes.has(type)) return new Response("Use a JPEG, PNG or WebP image", { status: 415 });
  const bytes = await readBounded(request.body, maxBytes).catch(() => undefined);
  if (!bytes) return new Response("Photos must be 1 MB or smaller", { status: 413 });
  await env.FILES.put(key(businessId, subject), bytes, { httpMetadata: { contentType: type } });
  return { kind: "photo", version: crypto.randomUUID().slice(0, 8) };
}

/** Deletes a photo once the look no longer uses it. */
export const removeLookPhoto = (env: Env, businessId: string, subject: string) =>
  env.FILES.delete(key(businessId, subject));
