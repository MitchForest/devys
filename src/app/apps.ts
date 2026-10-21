import { Effect } from "effect";
import type { Env } from "./env.ts";
import { appById, appCatalog, appOf } from "../apps/catalog.ts";
import type { AppManifest, InstalledApp } from "../apps/contract.ts";
import { install, installs, setPinned, uninstall } from "../apps/service.ts";
import type { Database } from "../data/database.ts";
import { hasAssignments } from "../delegates/service.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { body, forbidden, notFound } from "./request.ts";

/**
 * The one app gate: a capability that belongs to an app is usable in a business only while
 * that app is installed there. Built-in tools always are. Discovery and invocation both ask it.
 */
export async function usableIn(db: Database, businessId: string) {
  const installed = new Set(
    (await Effect.runPromise(installs(db, businessId))).map((row) => row.app_id),
  );
  return (capability: string) => {
    const app = appOf(capability);
    return !app || installed.has(app.id);
  };
}

/** Whether an installed app has something to show, by its `appears` rule. */
async function hasSomething(env: Env, businessId: string, app: AppManifest) {
  if (app.appears === "always") return true;
  // Code's records are coding sessions (and the deploys and pull requests they made).
  if (app.appears === "records" && app.id === "code")
    return Effect.runPromise(hasAssignments(env.HYPERDRIVE, businessId));
  // No available app appears only once connected yet.
  return false;
}

/** The app directory for one business: every Devys app, with whether it is installed. */
export async function directory(env: Env, businessId: string): Promise<InstalledApp[]> {
  const rows = await Effect.runPromise(installs(env.HYPERDRIVE, businessId));
  return Promise.all(
    appCatalog.map(async (manifest) => {
      const row = rows.find((candidate) => candidate.app_id === manifest.id);
      return {
        ...manifest,
        installed: Boolean(row),
        pinned: row?.pinned ?? false,
        visible: Boolean(row) && (await hasSomething(env, businessId, manifest)),
      };
    }),
  );
}

/** The owner's directory: install, uninstall and pin. Installing grants nothing by itself. */
export async function appsRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { business, trusted, path } = access;
  if (path === "/apps" && request.method === "GET")
    return Response.json({ apps: await directory(env, business.id) });
  const [, id, action] = /^\/apps\/([a-z0-9-]{1,40})\/(install|uninstall|pin)$/.exec(path) ?? [];
  const app = id ? appById(id) : undefined;
  if (!app || request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (action === "install") {
    if (app.status !== "available")
      return new Response(`${app.name} is coming soon`, { status: 409 });
    await Effect.runPromise(install(env.HYPERDRIVE, business.id, [app.id]));
  } else if (action === "uninstall") {
    if (app.id === "documents")
      return new Response("Documents is part of every business", { status: 409 });
    await Effect.runPromise(uninstall(env.HYPERDRIVE, business.id, app.id));
  } else {
    const { pinned } = await body<{ pinned: boolean }>(request, 1_000);
    if (typeof pinned !== "boolean")
      return new Response("Send pinned: true or false", { status: 400 });
    if (!(await Effect.runPromise(setPinned(env.HYPERDRIVE, business.id, app.id, pinned))))
      return new Response(`${app.name} is not installed`, { status: 409 });
  }
  return Response.json({
    app: (await directory(env, business.id)).find((entry) => entry.id === app.id),
  });
}
