import { Effect } from "effect";
import type { Env } from "./env.ts";
import { artifactLocation } from "../apps/documents/service.ts";
import { notFound } from "./request.ts";

/** An artifact's download under its business, the one route its links point at. */
export const artifactPath = /^\/artifacts\/([a-f0-9-]{36})$/;

/** The link to an artifact's download; it requires a member's sign-in. */
export const artifactUrl = (env: { PUBLIC_URL: string }, businessId: string, id: string) =>
  `${env.PUBLIC_URL}/api/businesses/${businessId}/artifacts/${id}`;

/** `GET /api/businesses/:id/artifacts/:artifact`: the bytes, as an attachment. */
export async function artifactDownload(env: Env, businessId: string, id: string) {
  const location = await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, id));
  if (!location) return notFound();
  const object = await env.FILES.get(location.object_key);
  if (!object) return new Response("File temporarily unavailable", { status: 503 });
  return new Response(object.body, {
    headers: {
      "content-type": location.content_type,
      "content-disposition": `attachment; filename="${location.filename.replace(/["\\\r\n]/g, "_")}"`,
      "content-length": String(object.size),
      "content-security-policy": "sandbox; default-src 'none'",
    },
  });
}
