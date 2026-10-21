import { Effect } from "effect";
import type { Env } from "./env.ts";
import type { InstalledApp } from "../apps/contract.ts";
import { install, installs, setPinned, uninstall } from "../apps/service.ts";
import { ads } from "../apps/ads/app.ts";
import { browser } from "../apps/browser/app.ts";
import { code } from "../apps/code/app.ts";
import { hasAssignments } from "../apps/code/service.ts";
import { computer } from "../apps/computer/app.ts";
import { conversations } from "../apps/conversations/app.ts";
import { customers } from "../apps/customers/app.ts";
import { documents } from "../apps/documents/app.ts";
import { mail } from "../apps/mail/app.ts";
import { memory } from "../apps/memory/app.ts";
import { money } from "../apps/money/app.ts";
import { team } from "../apps/team/app.ts";
import { web } from "../apps/web/app.ts";
import { website } from "../apps/website/app.ts";
import { work } from "../apps/work/app.ts";
import type { Database } from "../data/database.ts";
import { type Business, type Person } from "../identity/contract.ts";
import type { AppManifest } from "../protocol/app.ts";
import { body, forbidden, notFound } from "./request.ts";

/** Every Devys app: the system apps, then the business apps (available, then coming). */
export const appCatalog: readonly AppManifest[] = [
  computer,
  browser,
  web,
  memory,
  conversations,
  work,
  team,
  documents,
  code,
  mail,
  money,
  website,
  ads,
  customers,
];

export const appById = (id: string) => appCatalog.find((app) => app.id === id);

/** The app a capability belongs to. Every capability belongs to exactly one. */
export const appOf = (capability: string) =>
  appCatalog.find((app) => app.capabilities.includes(capability));

/** The business apps every new business has installed. */
export const defaultApps = ["documents", "code"] as const;

/** The apps a business has: every system app and the business apps it installed. */
async function installedApps(db: Database, businessId: string) {
  const installed = new Set(
    (await Effect.runPromise(installs(db, businessId))).map((row) => row.app_id),
  );
  return appCatalog.filter((app) => app.kind === "system" || installed.has(app.id));
}

/**
 * The one app gate: a capability is usable in a business only while its app is installed
 * there; system apps always are. Discovery and invocation both ask it.
 */
export async function usableIn(db: Database, businessId: string) {
  const apps = new Set((await installedApps(db, businessId)).map((app) => app.id));
  return (capability: string) => {
    const app = appOf(capability);
    return app !== undefined && apps.has(app.id);
  };
}

/** The skills the business's apps ship. */
export async function appSkills(db: Database, businessId: string) {
  return (await installedApps(db, businessId)).flatMap((app) => app.skills);
}

/** Whether an installed app has something to show, by its `appears` rule. */
async function hasSomething(
  env: Env,
  businessId: string,
  app: Pick<AppManifest, "id" | "appears">,
) {
  if (app.appears === "always") return true;
  // Code's records are coding sessions (and the deploys and pull requests they made).
  if (app.appears === "records" && app.id === code.id)
    return Effect.runPromise(hasAssignments(env.HYPERDRIVE, businessId));
  // System apps never show; no available app appears only once connected yet.
  return false;
}

/** The app directory for one business: every Devys app, with whether it is installed. */
export async function directory(env: Env, businessId: string): Promise<InstalledApp[]> {
  const rows = await Effect.runPromise(installs(env.HYPERDRIVE, businessId));
  return Promise.all(
    appCatalog.map(async ({ skills, ...manifest }) => {
      const row = rows.find((candidate) => candidate.app_id === manifest.id);
      const installed = manifest.kind === "system" || Boolean(row);
      return {
        ...manifest,
        skills: skills.map(({ name, description }) => ({ name, description })),
        installed,
        pinned: row?.pinned ?? false,
        visible: installed && (await hasSomething(env, businessId, manifest)),
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
  if (app.kind === "system")
    return new Response(`${app.name} is part of every business`, { status: 409 });
  if (action === "install") {
    if (app.status !== "available")
      return new Response(`${app.name} is coming soon`, { status: 409 });
    await Effect.runPromise(install(env.HYPERDRIVE, business.id, [app.id]));
  } else if (action === "uninstall") {
    if (app.id === documents.id)
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
