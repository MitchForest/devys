import { Effect } from "effect";
import type { Env } from "./env.ts";
import type { InstalledApp } from "../apps/contract.ts";
import { install, installs, setPinned, uninstall } from "../apps/service.ts";
import { pinRemoteApp, remoteApp, remoteApps, type RemoteApp } from "../apps/remote.ts";
import { RemotePolicy } from "../apps/contract.ts";
import {
  accept,
  addApp,
  beginConnect,
  logoResponse,
  remoteEntry,
  remoteNames,
  removeApp,
  review,
  searchApps,
} from "./remote-apps.ts";
import { HostRefusal } from "../protocol/host.ts";
import { browser } from "../apps/browser/app.ts";
import { code } from "../apps/code/app.ts";
import { hasCodingSessions } from "../apps/code/service.ts";
import { computer } from "../apps/computer/app.ts";
import { conversations } from "../apps/conversations/app.ts";
import { documents } from "../apps/documents/app.ts";
import { memory } from "../apps/memory/app.ts";
import { team } from "../apps/team/app.ts";
import { web } from "../apps/web/app.ts";
import { work } from "../apps/work/app.ts";
import type { Database } from "../data/database.ts";
import { type Business, type Person } from "../identity/contract.ts";
import type { AppManifest } from "../protocol/app.ts";
import { body, decodedBody, forbidden, notFound } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { AddApp, AppChanged, AppReview, Apps, AppSearch, Connecting } from "./wire.ts";

/** Every Devys app: the system apps, then the business apps. */
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
];

const appById = (id: string) => appCatalog.find((app) => app.id === id);

/** The app a capability belongs to. Every capability belongs to exactly one. */
const appOf = (capability: string) =>
  appCatalog.find((app) => app.capabilities.includes(capability));

/** The business apps every new business has installed. */
export const defaultApps = [documents.id, code.id];

/** The apps a business has: every system app and the business apps it installed. */
async function installedApps(db: Database, businessId: string) {
  const installed = new Set(
    (await Effect.runPromise(installs(db, businessId))).map((row) => row.app_id),
  );
  return appCatalog.filter((app) => app.kind === "system" || installed.has(app.id));
}

/**
 * The one app gate: a capability is usable in a business only while its app is installed
 * there; system apps always are; a remote app's only while it is on and the owner's acceptance
 * offers that tool. Discovery and invocation both ask it.
 */
export async function usableIn(db: Database, businessId: string) {
  const [installed, remote] = await Promise.all([
    installedApps(db, businessId),
    remoteNames(db, businessId),
  ]);
  const apps = new Set(installed.map((app) => app.id));
  const offered = new Set(remote);
  return (capability: string) => {
    const app = appOf(capability);
    return (app !== undefined && apps.has(app.id)) || offered.has(capability);
  };
}

/** The skills the business's apps ship. */
export async function appSkills(db: Database, businessId: string) {
  return (await installedApps(db, businessId)).flatMap((app) => app.skills);
}

/**
 * How wiring tells an app with `appears: "records"` has records yet, by app id: each such
 * app's own records check. Code's records are coding sessions (and their deploys and pull
 * requests).
 */
export const recordsChecks: Readonly<
  Record<string, (db: Database, businessId: string) => Promise<boolean>>
> = {
  [code.id]: (db, businessId) => Effect.runPromise(hasCodingSessions(db, businessId)),
};

/** Whether an installed app has something to show, by its `appears` rule. */
async function hasSomething(
  env: Env,
  businessId: string,
  app: Pick<AppManifest, "id" | "appears">,
) {
  switch (app.appears) {
    case "always":
      return true;
    case "never":
      return false;
    case "records": {
      const check = recordsChecks[app.id];
      if (!check) throw new Error(`${app.id} appears once it has records but has no records check`);
      return check(env.HYPERDRIVE, businessId);
    }
  }
}

/**
 * The app directory for one business: every Devys app, with whether it is installed, then the
 * remote apps it added.
 */
export async function directory(env: Env, businessId: string): Promise<InstalledApp[]> {
  const [builtIn, remote] = await Promise.all([
    builtInDirectory(env, businessId),
    Effect.runPromise(remoteApps(env.HYPERDRIVE, businessId)),
  ]);
  return [...builtIn, ...remote.map((app) => remoteEntry(businessId, app))];
}

export async function builtInDirectory(env: Env, businessId: string): Promise<InstalledApp[]> {
  const rows = await Effect.runPromise(installs(env.HYPERDRIVE, businessId));
  return Promise.all(
    appCatalog.map(async ({ skills, defaultGrants, ...manifest }) => {
      const row = rows.find((candidate) => candidate.app_id === manifest.id);
      const installed = manifest.kind === "system" || Boolean(row);
      return {
        ...manifest,
        ...(defaultGrants ? { default_grants: defaultGrants } : {}),
        skills: skills.map(({ name, description }) => ({ name, description })),
        installed,
        pinned: row?.pinned ?? false,
        visible: installed && (await hasSomething(env, businessId, manifest)),
        logo: null,
        state: null,
      };
    }),
  );
}

/** The owner's directory: install, uninstall and pin; search, add, connect and turn on remote apps. */
export async function appsRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  const method = request.method;
  if (path === "/apps" && method === "GET")
    return respond(Apps, { apps: await directory(env, business.id) });
  if (path === "/apps/search" && method === "GET") {
    const query = (new URL(request.url).searchParams.get("q") ?? "").trim().slice(0, 200);
    return respond(AppSearch, {
      apps: query
        ? await searchApps(env, business.id, query, await builtInDirectory(env, business.id))
        : [],
    });
  }
  const logo = /^\/apps\/logos\/([a-f0-9]{64})$/.exec(path);
  if (logo && method === "GET") return logoResponse(env, business.id, logo[1]!);
  const [, id, action] =
    /^\/apps\/([a-z0-9-]{1,40})\/(install|uninstall|pin|connect|review|accept)$/.exec(path) ?? [];
  if (path === "/apps/add" && method === "POST") {
    if (!trusted) return forbidden();
    const { app } = await decodedBody(request, 4_000, AddApp);
    return refusalOr(async () =>
      respond(AppChanged, {
        app: remoteEntry(
          business.id,
          await addApp(env, business.id, app, `person:${person.id}`, appCatalog),
        ),
      }),
    );
  }
  const remote = id
    ? await Effect.runPromise(remoteApp(env.HYPERDRIVE, business.id, id))
    : undefined;
  if (remote) return remoteRoute(request, env, { ...access, app: remote, action: action! });
  const app = id ? appById(id) : undefined;
  if (!app || method !== "POST" || !["install", "uninstall", "pin"].includes(action ?? ""))
    return notFound();
  if (!trusted) return forbidden();
  if (app.kind === "system")
    return new Response(`${app.name} is part of every business`, { status: 409 });
  if (action === "install") {
    await Effect.runPromise(install(env.HYPERDRIVE, business.id, [app.id]));
  } else if (action === "uninstall") {
    // Its records stay: owners still read them; only its capabilities and skills go.
    await Effect.runPromise(uninstall(env.HYPERDRIVE, business.id, app.id));
  } else {
    const { pinned } = await body<{ pinned: boolean }>(request, 1_000);
    if (typeof pinned !== "boolean")
      return new Response("Send pinned: true or false", { status: 400 });
    if (!(await Effect.runPromise(setPinned(env.HYPERDRIVE, business.id, app.id, pinned))))
      return new Response(`${app.name} is not installed`, { status: 409 });
  }
  return respond(AppChanged, {
    app: (await directory(env, business.id)).find((entry) => entry.id === app.id)!,
  });
}

/** A refusal answered with its status and words; anything else is thrown on. */
async function refusalOr(run: () => Promise<Response>) {
  try {
    return await run();
  } catch (error) {
    if (error instanceof HostRefusal) return new Response(error.message, { status: error.status });
    throw error;
  }
}

/** One remote app: its review, connecting, turning on, pinning and removing. */
async function remoteRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; app: RemoteApp; action: string },
) {
  const { person, business, trusted, app, action } = access;
  if (action === "review" && request.method === "GET")
    return respond(AppReview, await review(env, business.id, app));
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  return refusalOr(async () => {
    if (action === "connect") {
      const { native } = await body<{ native: boolean }>(request, 1_000);
      const begun = await beginConnect(env, business.id, app, person.id, native === true);
      return respond(Connecting, { url: begun.url, app: remoteEntry(business.id, begun.app) });
    }
    if (action === "accept") {
      const acceptance = await decodedBody(request, 64_000, RemotePolicy);
      const accepted = await accept(env, business.id, app, acceptance, person.id);
      return respond(AppChanged, { app: remoteEntry(business.id, accepted) });
    }
    if (action === "uninstall") {
      await removeApp(env, business.id, app);
      return respond(AppChanged, {
        app: { ...remoteEntry(business.id, app), installed: false, visible: false },
      });
    }
    if (action === "pin") {
      const { pinned } = await body<{ pinned: boolean }>(request, 1_000);
      if (typeof pinned !== "boolean")
        return new Response("Send pinned: true or false", { status: 400 });
      await Effect.runPromise(pinRemoteApp(env.HYPERDRIVE, business.id, app.id, pinned));
      return respond(AppChanged, { app: remoteEntry(business.id, { ...app, pinned }) });
    }
    return notFound();
  });
}
