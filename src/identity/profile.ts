import { readBounded } from "../protocol/bytes.ts";

const imageTypes = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);
const maxBytes = 2_000_000;
const key = (personId: string) => `profiles/${personId}/photo`;

/** A person's profile photo, stored privately in R2 under their own key. */
export async function profilePhoto(request: Request, env: { FILES: R2Bucket }, personId: string) {
  if (request.method === "GET") {
    const object = await env.FILES.get(key(personId));
    if (!object) return new Response(null, { status: 404 });
    return new Response(object.body, {
      headers: {
        "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
        "content-length": String(object.size),
        "content-security-policy": "sandbox; default-src 'none'",
      },
    });
  }
  if (request.method === "PUT") {
    const type = request.headers.get("content-type")?.split(";")[0]?.trim() ?? "";
    if (!imageTypes.has(type))
      return new Response("Use a JPEG, PNG, HEIC or WebP image", { status: 415 });
    const bytes = await readBounded(request.body, maxBytes).catch(() => undefined);
    if (!bytes) return new Response("Photos must be 2 MB or smaller", { status: 413 });
    await env.FILES.put(key(personId), bytes, { httpMetadata: { contentType: type } });
    return Response.json({ saved: true, bytes: bytes.byteLength });
  }
  if (request.method === "DELETE") {
    await env.FILES.delete(key(personId));
    return Response.json({ removed: true });
  }
  return new Response("Method not allowed", { status: 405 });
}
