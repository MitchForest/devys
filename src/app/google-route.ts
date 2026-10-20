import type { Env } from "./env.ts";
import {
  beginGoogle,
  disconnectGoogle,
  googleAccess,
  googleConfigured,
  googleConnectionStatus,
} from "../connections/google.ts";
import { listDrive, selectDrive } from "../connections/drive.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { body, forbidden, notFound } from "./request.ts";

export async function googleRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/connections/google" && request.method === "GET") {
    const connection = await googleConnectionStatus(env.HYPERDRIVE, business.id);
    return Response.json({
      configured: googleConfigured(env),
      connected: Boolean(connection),
      files: await listDrive(env, business.id),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (path === "/connections/google/connect")
    return beginGoogle(request, env, business.id, person.id);
  if (path === "/connections/google/disconnect")
    return Response.json(await disconnectGoogle(env, business.id));
  if (path === "/connections/google/picker") {
    if (!env.GOOGLE_PICKER_API_KEY || !env.GOOGLE_PROJECT_NUMBER)
      return new Response("Picker is not configured", { status: 503 });
    const google = await googleAccess(env, business.id);
    return Response.json({
      token: google.token,
      key: env.GOOGLE_PICKER_API_KEY,
      appId: env.GOOGLE_PROJECT_NUMBER,
    });
  }
  if (path === "/connections/google/select") {
    const input = await body<{ ids: unknown }>(request, 8_000);
    if (!Array.isArray(input.ids) || !input.ids.every((id) => typeof id === "string"))
      return new Response("Invalid file selection", { status: 400 });
    return Response.json(await selectDrive(env, business.id, input.ids));
  }
  return notFound();
}
