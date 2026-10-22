import type { Env } from "./env.ts";
import {
  beginGoogle,
  disconnectGoogle,
  googleAccess,
  googleConfigured,
  googleConnection,
  googleConnectionStatus,
} from "../connections/google.ts";
import { listDrive, selectDrive } from "../apps/documents/drive.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { body, forbidden, notFound } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { DrivePicker, DriveSelected, GoogleConnection } from "./wire.ts";
import { Disconnected } from "../connections/contract.ts";
import { connectionVault } from "./vault.ts";

export async function googleRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/connections/google" && request.method === "GET") {
    const connection = await googleConnectionStatus(env.HYPERDRIVE, business.id);
    return respond(GoogleConnection, {
      configured: googleConfigured(env),
      connected: Boolean(connection),
      files: (await listDrive(env.HYPERDRIVE, business.id)).map(({ mimeType, ...file }) => ({
        ...file,
        mime_type: mimeType,
      })),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (path === "/connections/google/connect")
    return beginGoogle(request, env, business.id, person.id);
  if (path === "/connections/google/disconnect")
    return respond(Disconnected, await disconnectGoogle(env, connectionVault(env), business.id));
  if (path === "/connections/google/picker") {
    if (!env.GOOGLE_PICKER_API_KEY || !env.GOOGLE_PROJECT_NUMBER)
      return new Response("Picker is not configured", { status: 503 });
    const google = await googleAccess(env, connectionVault(env), business.id);
    return respond(DrivePicker, {
      token: google.token,
      key: env.GOOGLE_PICKER_API_KEY,
      app_id: env.GOOGLE_PROJECT_NUMBER,
    });
  }
  if (path === "/connections/google/select") {
    const input = await body<{ ids: unknown }>(request, 8_000);
    if (!Array.isArray(input.ids) || !input.ids.every((id) => typeof id === "string"))
      return new Response("Invalid file selection", { status: 400 });
    return respond(
      DriveSelected,
      await selectDrive(
        { db: env.HYPERDRIVE, connection: googleConnection(env, connectionVault(env)) },
        business.id,
        input.ids,
      ),
    );
  }
  return notFound();
}
