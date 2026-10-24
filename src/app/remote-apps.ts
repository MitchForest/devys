/**
 * Remote apps (LP6, .docs/APPS_AND_CAPABILITIES.md): an MCP server a business connects, found by
 * search (installed apps and the MCP Registry) or by its address. The owner connects it (the
 * provider's own sign-in, discovered per the MCP spec; tokens to the vault, opened only by the Mac
 * host), then turns it on with one review whose acceptance is its policy: each tool's line and who
 * uses it, as grants. Its tools are capabilities of that app through the one gate; tools that hand
 * out payment credentials are never offered. Its identity (name, logo) comes from what it says
 * (serverInfo), then the registry, then its site's icon; clients draw a letter tile otherwise.
 */
import { Effect, Schema } from "effect";
import { parse } from "tldts";
import type { Env } from "./env.ts";
import { listedApps } from "../../config/apps.ts";
import type { Database } from "../data/database.ts";
import { modeOf } from "./mode.ts";
import { answerText, askOwnerFor, tellEmployee } from "./asking.ts";
import type { OwnerRequest } from "../authority/contract.ts";
import {
  cardTool,
  paymentCredentialTools,
  remoteCapabilityName,
  suggestedLine,
  type FoundApp,
  type InstalledApp,
  type Line,
  type ListedApp,
  type RemotePolicy,
  type RemoteServer,
  type RemoteTool,
} from "../apps/contract.ts";
import { offered, remoteCapability } from "../apps/capabilities.ts";
import {
  acceptRemoteApp,
  addRemoteApp,
  claimSignIn,
  connectedRemoteApp,
  connectionName,
  lapseRemoteApp,
  remoteApp,
  remoteAppFor,
  remoteApps,
  removeRemoteApp,
  startSignIn,
  type RemoteApp,
} from "../apps/remote.ts";
import {
  activeGrant,
  connectAnswered,
  grantAll,
  revokeCapabilities,
  standingRequest,
} from "../authority/service.ts";
import type { CardSource } from "../browser/contract.ts";
import { remoteUrl } from "../connections/contract.ts";
import { employeesOf } from "../identity/service.ts";
import { publicFetch } from "../egress/public.ts";
import { sha256, sha256Bytes } from "../protocol/bytes.ts";
import type { Capability } from "../protocol/capability.ts";
import { HostRefusal } from "../protocol/host.ts";
import type { Sealed } from "../vault/contract.ts";

/** The official MCP Registry (registry.modelcontextprotocol.io, API v0.1). */
export const registryUrl = "https://registry.modelcontextprotocol.io";

/** Where the provider sends the owner back after signing in. */
export const callbackPath = "/api/apps/callback";
const redirectOf = (env: Pick<Env, "PUBLIC_URL">) => `${env.PUBLIC_URL}${callbackPath}`;

const refused = (status: number, message: string) => new HostRefusal(status, message);

// Logos.

/** Image types a logo may be, told by its first bytes (an SVG, which may carry script, is not). */
function imageType(bytes: Uint8Array) {
  const at = (index: number) => bytes[index] ?? -1;
  if (at(0) === 0x89 && at(1) === 0x50 && at(2) === 0x4e && at(3) === 0x47) return "image/png";
  if (at(0) === 0xff && at(1) === 0xd8 && at(2) === 0xff) return "image/jpeg";
  if (at(0) === 0x47 && at(1) === 0x49 && at(2) === 0x46) return "image/gif";
  if (at(0) === 0x52 && at(1) === 0x49 && at(8) === 0x57 && at(9) === 0x45) return "image/webp";
  if (at(0) === 0 && at(1) === 0 && at(2) === 1 && at(3) === 0) return "image/x-icon";
  return undefined;
}

const logoKey = (businessId: string, sha: string) => `apps/${businessId}/${sha}`;

/** The link a client loads a logo from (a member's sign-in). */
export const logoUrl = (businessId: string, sha: string | null) =>
  sha ? `/api/businesses/${businessId}/apps/logos/${sha}` : null;

/** Bytes of one image at `src` (https, or a base64 `data:` URI), at most 256 KB, or nothing. */
async function imageAt(env: Env, src: string) {
  try {
    if (src.startsWith("data:")) {
      const match = /^data:image\/[a-z+.-]+;base64,([A-Za-z0-9+/=]+)$/.exec(src);
      if (!match || match[1]!.length > 350_000) return undefined;
      const bytes = Uint8Array.from(atob(match[1]!), (char) => char.charCodeAt(0));
      return imageType(bytes) ? bytes : undefined;
    }
    const fetched = await publicFetch(src, env, 256_000);
    if (fetched.status !== 200) return undefined;
    const bytes = new Uint8Array(fetched.bytes);
    return imageType(bytes) ? bytes : undefined;
  } catch {
    return undefined;
  }
}

/** A site's own icons: its apple-touch-icon, its declared icons, then `/favicon.ico`. */
async function siteIcons(env: Env, site: string) {
  try {
    const page = await publicFetch(site, env, 512_000);
    const html = new TextDecoder().decode(page.bytes).slice(0, 512_000);
    const links = [...html.matchAll(/<link\b[^>]*>/gi)].map((match) => match[0]);
    const href = (tag: string) => /\bhref\s*=\s*["']([^"']+)["']/i.exec(tag)?.[1];
    const rel = (tag: string) => /\brel\s*=\s*["']([^"']+)["']/i.exec(tag)?.[1]?.toLowerCase();
    const ordered = [
      ...links.filter((tag) => rel(tag)?.includes("apple-touch-icon")),
      ...links.filter((tag) => rel(tag) === "icon" || rel(tag) === "shortcut icon"),
    ];
    return [
      ...ordered.flatMap((tag) => (href(tag) ? [new URL(href(tag)!, page.url).href] : [])),
      new URL("/favicon.ico", page.url).href,
    ];
  } catch {
    return [new URL("/favicon.ico", site).href];
  }
}

/**
 * The app's logo, fetched once and kept in R2 under its sha-256: the icons it names (serverInfo or
 * the registry), then its website's icon, then its address's site. Null when none is an image.
 */
async function resolveLogo(
  env: Env,
  businessId: string,
  from: { icons: readonly string[]; website: string | null; url: string },
) {
  const sites = [from.website, from.url]
    .filter((value): value is string => Boolean(value))
    .flatMap((value) => {
      const url = new URL(value);
      const domain = parse(url.hostname).domain;
      return [url.origin, ...(domain && domain !== url.hostname ? [`https://${domain}`] : [])];
    });
  const tried = new Set<string>();
  const candidates = async function* () {
    yield* from.icons.slice(0, 4);
    for (const site of [...new Set(sites)].slice(0, 3))
      yield* (await siteIcons(env, site)).slice(0, 4);
  };
  for await (const src of candidates()) {
    if (tried.has(src)) continue;
    tried.add(src);
    const bytes = await imageAt(env, src);
    if (!bytes) continue;
    const sha = await sha256Bytes(bytes);
    await env.FILES.put(logoKey(businessId, sha), bytes, {
      httpMetadata: { contentType: imageType(bytes)! },
    });
    return sha;
  }
  return null;
}

/** `GET …/apps/logos/:sha`: a remote app's logo, never anything that runs. */
export async function logoResponse(env: Env, businessId: string, sha: string) {
  const object = await env.FILES.get(logoKey(businessId, sha));
  if (!object) return new Response("Not found", { status: 404 });
  const bytes = new Uint8Array(await object.arrayBuffer());
  return new Response(bytes, {
    headers: {
      "content-type": imageType(bytes) ?? "application/octet-stream",
      "cache-control": "private, max-age=31536000, immutable",
      "content-security-policy": "sandbox; default-src 'none'",
      "x-content-type-options": "nosniff",
    },
  });
}

// The MCP Registry.

/** A registry entry Devys can connect: one Streamable HTTP address, no extra header or variable. */
interface Listed {
  name: string;
  title: string;
  description: string;
  website: string | null;
  icons: string[];
  url: string;
}

const RegistryServer = Schema.Struct({
  name: Schema.String,
  title: Schema.optional(Schema.String),
  description: Schema.optional(Schema.String),
  websiteUrl: Schema.optional(Schema.String),
  icons: Schema.optional(Schema.Array(Schema.Struct({ src: Schema.String }))),
  remotes: Schema.optional(
    Schema.Array(
      Schema.Struct({
        type: Schema.String,
        url: Schema.String,
        headers: Schema.optional(Schema.Array(Schema.Unknown)),
        variables: Schema.optional(Schema.Unknown),
      }),
    ),
  ),
});
const RegistryPage = Schema.Struct({
  servers: Schema.Array(Schema.Struct({ server: Schema.Unknown })),
});

function listed(value: unknown): Listed | undefined {
  const decoded = Schema.decodeUnknownOption(RegistryServer)(value);
  if (decoded._tag === "None") return undefined;
  const server = decoded.value;
  const remote = server.remotes?.find(
    (each) =>
      each.type === "streamable-http" &&
      !each.headers?.length &&
      !each.variables &&
      !/[{}]/.test(each.url) &&
      remoteUrl(each.url),
  );
  if (!remote) return undefined;
  return {
    name: server.name.slice(0, 200),
    title: (server.title ?? server.name.split("/").at(-1) ?? server.name).slice(0, 80),
    description: (server.description ?? "").slice(0, 500),
    website: server.websiteUrl && remoteUrl(server.websiteUrl) ? server.websiteUrl : null,
    icons: (server.icons ?? []).map((icon) => icon.src),
    url: remoteUrl(remote.url)!,
  };
}

async function registry(env: Env, path: string) {
  const fetched = await publicFetch(`${registryUrl}${path}`, env, 2_000_000);
  if (fetched.status !== 200) throw refused(502, "The MCP Registry didn't answer");
  return JSON.parse(new TextDecoder().decode(fetched.bytes)) as unknown;
}

/** How long a registry search is kept, and how long a search waits for an uncached one. */
const registryKeptSeconds = 24 * 60 * 60;
const registryWaitMs = 8_000;

/**
 * Registry servers matching `query` that Devys can connect, latest versions only, or null when
 * the registry hasn't answered in time. Its first answer for a query can take most of a minute;
 * the search goes on and its answer is kept for a day, so asking again soon finds it at once.
 */
async function searchRegistry(env: Env, query: string): Promise<Listed[] | null> {
  const path = `/v0.1/servers?search=${encodeURIComponent(query.toLowerCase())}&version=latest&limit=30`;
  const cache = await caches.open("mcp-registry");
  const kept = await cache.match(`${registryUrl}${path}`);
  if (kept) return connectable(await kept.json());
  const answer = registry(env, path).then(async (body) => {
    await cache.put(
      `${registryUrl}${path}`,
      new Response(JSON.stringify(body), {
        headers: {
          "content-type": "application/json",
          "cache-control": `max-age=${registryKeptSeconds}`,
        },
      }),
    );
    return body;
  });
  answer.catch(() => undefined);
  const body = await Promise.race([
    answer,
    new Promise<null>((resolve) => setTimeout(() => resolve(null), registryWaitMs)),
  ]);
  return body === null ? null : connectable(body);
}

function connectable(body: unknown) {
  const page = Schema.decodeUnknownSync(RegistryPage)(body);
  const found = new Map<string, Listed>();
  for (const { server } of page.servers) {
    const entry = listed(server);
    if (entry && !found.has(entry.name)) found.set(entry.name, entry);
  }
  return [...found.values()];
}

/** One registry server by name (`com.example/server`), latest version. */
async function registryServer(env: Env, name: string) {
  const answer = (await registry(
    env,
    `/v0.1/servers/${encodeURIComponent(name)}/versions/latest`,
  )) as { server?: unknown };
  return listed(answer.server);
}

// The business's remote apps.

const usableLines = (app: RemoteApp) =>
  app.tools.flatMap((tool) => {
    const name = remoteCapabilityName(app.id, tool.name);
    const line = app.policy?.lines[name ?? ""];
    return name && !paymentCredentialTools.includes(tool.name) && offered(line)
      ? [{ name, tool, line }]
      : [];
  });

/** The capability names a business's remote apps offer now: on, and not withheld. */
export async function remoteNames(db: Database, businessId: string) {
  return (await Effect.runPromise(remoteApps(db, businessId)))
    .filter((app) => app.state === "on")
    .flatMap((app) => usableLines(app).map((line) => line.name));
}

/** The sealed sign-in of an app, or null for an app whose server needs none. */
async function signIn(env: Env, businessId: string, appId: string): Promise<Sealed | null> {
  try {
    return (
      await modeOf(env).secrets.sealed(businessId, [connectionName(appId)], ["connection"])
    )[0]!;
  } catch {
    return null;
  }
}

/** Keeps a sign-in a refresh changed; marks the app lapsed when it stopped working. */
async function settle(
  env: Env,
  app: RemoteApp,
  businessId: string,
  outcome: { sealed?: Sealed } | { lapsed: true },
) {
  if ("lapsed" in outcome) {
    await Effect.runPromise(lapseRemoteApp(env.HYPERDRIVE, businessId, app.id));
    throw refused(
      409,
      `${app.name}'s sign-in stopped working: the owner reconnects it (Needs you)`,
    );
  }
  if (outcome.sealed) await modeOf(env).secrets.putSealed(outcome.sealed, app.added_by);
}

/** Calls one of an app's tools through the Mac host, with its sign-in. */
async function callTool(
  env: Env,
  businessId: string,
  appId: string,
  tool: string,
  args: Record<string, unknown>,
) {
  const app = await Effect.runPromise(remoteApp(env.HYPERDRIVE, businessId, appId));
  if (!app || app.state !== "on")
    throw refused(
      409,
      app?.state === "lapsed" ? `${app.name} needs reconnecting` : "That app is off",
    );
  const reached = await modeOf(env).remoteApps.call({
    business: businessId,
    url: app.url,
    sealed: await signIn(env, businessId, app.id),
    tool,
    arguments: args,
  });
  await settle(env, app, businessId, reached);
  if ("lapsed" in reached) throw refused(409, `${app.name} needs reconnecting`);
  return reached.result;
}

/**
 * The capabilities a business's remote apps offer now, one per tool the owner allowed, each
 * belonging to its app. The gate (installed, grant, work-item conditions) applies as to any other.
 */
export async function remoteCapabilities(env: Env, businessId: string): Promise<Capability[]> {
  return (await Effect.runPromise(remoteApps(env.HYPERDRIVE, businessId)))
    .filter((app) => app.state === "on")
    .flatMap((app) =>
      usableLines(app).map(({ name, tool }) =>
        remoteCapability(name, app, tool, (business, args) =>
          callTool(env, business, app.id, tool.name, args),
        ),
      ),
    );
}

/** A remote app as the directory lists it. */
export function remoteEntry(businessId: string, app: RemoteApp): InstalledApp {
  return {
    id: app.id,
    name: app.name,
    icon: "app.connected.to.app.below.fill",
    summary: app.summary,
    kind: "business",
    records: [],
    capabilities: app.state === "on" ? usableLines(app).map((line) => line.name) : [],
    skills: [],
    connections: [],
    appears: "always",
    installed: app.state === "on" || app.state === "lapsed",
    pinned: app.pinned,
    visible: app.state === "on" || app.state === "lapsed",
    logo: logoUrl(businessId, app.logo),
    state: app.state,
  };
}

// Finding and adding apps.

/**
 * Apps for a query: the business's built-in apps and remote apps, then the MCP Registry's. An
 * address (https://…) is offered as itself.
 */
export async function searchApps(
  env: Env,
  businessId: string,
  query: string,
  builtIn: readonly InstalledApp[],
): Promise<{ apps: FoundApp[]; registryAnswered: boolean }> {
  const words = query.toLowerCase().trim();
  const matches = (text: string) => text.toLowerCase().includes(words);
  const own = builtIn
    .filter((app) => app.kind === "business" && (matches(app.name) || matches(app.summary)))
    .map((app) => ({
      app: app.id,
      name: app.name,
      description: app.summary,
      logo: app.logo,
      installed: app.installed,
    }));
  const added = (await Effect.runPromise(remoteApps(env.HYPERDRIVE, businessId)))
    .filter((app) => matches(app.name) || matches(app.summary) || matches(app.url))
    .map((app) => ({
      app: app.id,
      name: app.name,
      description: app.summary,
      logo: logoUrl(businessId, app.logo),
      installed: app.state === "on",
    }));
  // The listed apps that fit, before anything the registry finds: known, and at once.
  const fitting = (await listedFor(env, businessId)).filter(
    (app) =>
      !added.some((each) => each.app === app.app) &&
      (matches(app.name) || matches(app.description) || matches(app.category)),
  );
  const address = remoteUrl(query.trim());
  const typed: FoundApp[] =
    address && !added.length
      ? [
          {
            app: address,
            name: new URL(address).hostname,
            description: "An MCP server at this address",
            logo: null,
            installed: false,
          },
        ]
      : [];
  const known = new Set(
    (await Effect.runPromise(remoteApps(env.HYPERDRIVE, businessId))).flatMap((app) => [
      app.url,
      app.registry_name,
    ]),
  );
  const registryEntries = address
    ? []
    : await searchRegistry(env, query.trim()).catch(() => [] as Listed[]);
  const registryAnswered = registryEntries !== null;
  const fromRegistry = await Promise.all(
    (registryEntries ?? [])
      .filter((entry) => !known.has(entry.url) && !known.has(entry.name))
      .slice(0, 8)
      .map(async (entry) => ({
        app: entry.name,
        name: entry.title,
        description: entry.description,
        // A slow site doesn't hold the search up: its logo is resolved when it is added.
        logo: logoUrl(
          businessId,
          await Promise.race([
            resolveLogo(env, businessId, {
              icons: entry.icons,
              website: entry.website,
              url: entry.url,
            }).catch(() => null),
            new Promise<null>((resolve) => setTimeout(() => resolve(null), 4_000)),
          ]),
        ),
        installed: false,
      })),
  );
  const listedUrls = new Set(listedApps.map((app) => app.url));
  return {
    apps: [
      ...own,
      ...added,
      ...fitting.map((app) => ({
        app: app.app,
        name: app.name,
        description: app.description,
        logo: app.logo,
        installed: app.installed,
      })),
      ...typed,
      ...fromRegistry.filter((app) => !listedUrls.has(app.app)),
    ].slice(0, 12),
    registryAnswered,
  };
}

/** A listed app's slug: its name, lower case (the logo's path). */
const slugOf = (app: (typeof listedApps)[number]) =>
  app.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");

/**
 * The Connect apps sheet's list (config/apps.ts), each with whether the business has it on, its
 * logo (fetched once from the service's site) and its category.
 */
export async function listedFor(env: Env, businessId: string): Promise<ListedApp[]> {
  const added = await Effect.runPromise(remoteApps(env.HYPERDRIVE, businessId));
  return listedApps.map((app) => {
    const mine = added.find((each) => each.url === app.url);
    return {
      app: mine?.id ?? app.url,
      name: app.name,
      description: app.summary,
      category: app.category,
      logo: `/api/businesses/${businessId}/apps/listed/${slugOf(app)}/logo`,
      installed: mine?.state === "on",
    };
  });
}

/**
 * `GET …/apps/listed/:slug/logo`: a listed app's logo, fetched from its site once for this whole
 * install (every business shows the same logo) and kept in R2; clients keep it a week.
 */
export async function listedLogo(env: Env, slug: string) {
  const app = listedApps.find((each) => slugOf(each) === slug);
  if (!app) return new Response("Not found", { status: 404 });
  const key = `listed-logos/${slug}`;
  let image = await env.FILES.get(key).then(async (object) =>
    object ? new Uint8Array(await object.arrayBuffer()) : undefined,
  );
  if (!image) {
    for (const src of (await siteIcons(env, app.website)).slice(0, 6)) {
      image = await imageAt(env, src);
      if (image) break;
    }
    if (!image) return new Response("Not found", { status: 404 });
    await env.FILES.put(key, image);
  }
  return new Response(image, {
    headers: {
      "content-type": imageType(image) ?? "application/octet-stream",
      "cache-control": "private, max-age=604800, immutable",
      "content-security-policy": "sandbox; default-src 'none'",
      "x-content-type-options": "nosniff",
    },
  });
}

/**
 * The business's remote app for an id, address or registry name, added (not yet connected) if
 * new. A built-in app's id is refused: it is installed, not connected.
 */
export async function addApp(
  env: Env,
  businessId: string,
  address: string,
  addedBy: string,
  builtIn: readonly { id: string; name: string }[],
) {
  const wanted = address.trim();
  const existing = await Effect.runPromise(remoteAppFor(env.HYPERDRIVE, businessId, wanted));
  if (existing) return existing;
  const own = builtIn.find((app) => app.id === wanted.toLowerCase());
  if (own)
    throw refused(409, `${own.name} is part of Devys: install it in Apps, no connection needed`);
  const url = remoteUrl(wanted);
  const entry = url
    ? undefined
    : /^[A-Za-z0-9.-]+\/[A-Za-z0-9._-]+$/.test(wanted)
      ? await registryServer(env, wanted).catch(() => undefined)
      : undefined;
  if (!url && !entry)
    throw refused(
      400,
      "Name an app as appSearch found it (its registry name) or give its MCP server's https address",
    );
  const at = url ?? entry!.url;
  // A listed app brings its own name, line and site.
  const listed = listedApps.find((app) => app.url === at);
  const host = new URL(at).hostname;
  const domain = parse(host).domainWithoutSuffix;
  const name =
    listed?.name ??
    entry?.title ??
    (domain ? domain.charAt(0).toUpperCase() + domain.slice(1) : host);
  const website = listed?.website ?? entry?.website ?? null;
  const logo = await resolveLogo(env, businessId, {
    icons: entry?.icons ?? [],
    website,
    url: at,
  }).catch(() => null);
  return Effect.runPromise(
    addRemoteApp(
      env.HYPERDRIVE,
      businessId,
      {
        name,
        summary: listed?.summary ?? entry?.description ?? "",
        url: at,
        registryName: entry?.name ?? null,
        website,
        logo,
        addedBy,
      },
      builtIn.map((app) => app.id),
    ),
  );
}

// Connecting.

/** After signing in (or for a server that needs none): its identity and tools, kept. */
async function connected(
  env: Env,
  businessId: string,
  app: RemoteApp,
  found: { server: RemoteServer; tools: RemoteTool[] },
) {
  const logo = await resolveLogo(env, businessId, {
    icons: found.server.icons.map((icon) => icon.src),
    website: found.server.website ?? app.website,
    url: app.url,
  }).catch(() => null);
  return (await Effect.runPromise(
    connectedRemoteApp(env.HYPERDRIVE, businessId, app.id, {
      ...found,
      logo: logo ?? app.logo,
    }),
  ))!;
}

/**
 * Starts the owner's sign-in at the app's provider: the URL to open (a popup on the web, the
 * system sign-in sheet on Mac and iPhone), or null when the server needs no sign-in (it is
 * connected now). `native` sends the callback back to the app (`devys://`).
 */
export async function beginConnect(
  env: Env,
  businessId: string,
  app: RemoteApp,
  personId: string,
  native: boolean,
) {
  const state = crypto.randomUUID();
  const begun = await modeOf(env).remoteApps.begin({
    business: businessId,
    url: app.url,
    redirect: redirectOf(env),
    state,
  });
  if ("open" in begun) return { url: null, app: await connected(env, businessId, app, begun) };
  await Effect.runPromise(
    startSignIn(env.HYPERDRIVE, {
      stateHash: await sha256(state),
      businessId,
      appId: app.id,
      personId,
      pending: begun.pending,
      native,
    }),
  );
  return { url: begun.authorize, app };
}

const page = (title: string, text: string, status = 200) =>
  new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${title}</title><body style="font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:90vh;color:#222"><p>${text}</p><script>try{window.opener&&window.opener.postMessage("devys:app-connected","*")}catch(e){}setTimeout(function(){window.close()},400)</script>`,
    {
      status,
      headers: {
        "content-type": "text/html; charset=utf-8",
        "content-security-policy":
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
        "cache-control": "no-store",
      },
    },
  );

const escape = (text: string) => text.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

/**
 * `GET /api/apps/callback`: the provider sends the owner back. The state (random, hashed, ten
 * minutes, one use) names the business, app and person; the host exchanges the code and seals the
 * tokens, which go to the vault. The web popup closes itself; Mac and iPhone get `devys://`.
 */
export async function finishConnect(request: Request, env: Env) {
  const query = new URL(request.url).searchParams;
  const claimed = await Effect.runPromise(
    claimSignIn(env.HYPERDRIVE, await sha256(query.get("state") ?? "")),
  );
  if (!claimed) return page("Not connected", "That sign-in expired. Start again in Devys.", 400);
  const back = (text: string, status = 200) =>
    claimed.native
      ? new Response(null, {
          status: 303,
          headers: { location: `devys://apps/${claimed.business_id}/${claimed.app_id}` },
        })
      : page("Devys", escape(text), status);
  const app = await Effect.runPromise(
    remoteApp(env.HYPERDRIVE, claimed.business_id, claimed.app_id),
  );
  const code = query.get("code");
  if (!app || !code) return back("Not connected. You can close this window.", 400);
  try {
    const finished = await modeOf(env).remoteApps.finish({
      business: claimed.business_id,
      url: app.url,
      name: connectionName(app.id),
      redirect: redirectOf(env),
      code,
      ...(query.get("iss") ? { iss: query.get("iss")! } : {}),
      pending: claimed.pending,
    });
    await modeOf(env).secrets.putSealed(finished.sealed, claimed.person_id);
    await connected(env, claimed.business_id, app, finished);
  } catch (error) {
    const why = error instanceof HostRefusal ? error.message : "The sign-in didn't finish";
    return back(`${app.name} isn't connected: ${why}. You can close this window.`, 502);
  }
  return back(`${app.name} is connected. You can close this window.`);
}

// Review and acceptance.

/** A tool's title as the owner reads it: its own, or its name in words ("list_bills" → "List bills"). */
const titled = (tool: RemoteTool) =>
  tool.title ??
  tool.name
    .replace(/[_-]+/g, " ")
    .trim()
    .replace(/^./, (char) => char.toUpperCase());

/** The review card: each tool's suggested (or accepted) line, and who uses the app. */
export async function review(env: Env, businessId: string, app: RemoteApp) {
  const team = await Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId));
  const users = app.policy?.employees ?? team.map((employee) => employee.id);
  return {
    app: remoteEntry(businessId, app),
    tools: app.tools.flatMap((tool) => {
      const name = remoteCapabilityName(app.id, tool.name);
      if (!name) return [];
      const fixed = paymentCredentialTools.includes(tool.name);
      return [
        {
          capability: name,
          title: titled(tool),
          description: tool.description.slice(0, 300),
          line: fixed ? ("never" as const) : (app.policy?.lines[name] ?? suggestedLine(tool)),
          fixed,
        },
      ];
    }),
    employees: team.map((employee) => ({
      id: employee.id,
      name: employee.name,
      uses: users.includes(employee.id),
    })),
  };
}

/**
 * The owner turns the app on (or changes it): their acceptance is its policy. Each employee who
 * uses it gets a grant per allowed tool, `auto` for "on its own" and `ask` for "asks you first";
 * everyone else's grants for the app end. Pending connect requests for it are answered.
 */
export async function accept(
  env: Env,
  businessId: string,
  app: RemoteApp,
  acceptance: RemotePolicy,
  personId: string,
) {
  if (app.state !== "review" && app.state !== "on") throw refused(409, `Connect ${app.name} first`);
  const team = await Effect.runPromise(employeesOf(env.HYPERDRIVE, businessId));
  const known = new Map(
    app.tools.flatMap((tool) => {
      const name = remoteCapabilityName(app.id, tool.name);
      return name ? [[name, tool] as const] : [];
    }),
  );
  const lines: Record<string, Line> = {};
  for (const [name, tool] of known)
    lines[name] = paymentCredentialTools.includes(tool.name)
      ? "never"
      : (acceptance.lines[name] ?? suggestedLine(tool));
  if (Object.keys(acceptance.lines).some((name) => !known.has(name)))
    throw refused(400, "That isn't one of this app's tools");
  const employees = acceptance.employees.filter((id) => team.some((member) => member.id === id));
  const policy = { lines, employees };
  const accepted = (await Effect.runPromise(
    acceptRemoteApp(env.HYPERDRIVE, businessId, app.id, policy),
  ))!;
  const offeredNow = usableLines(accepted);
  const capabilities = await remoteCapabilities(env, businessId);
  await Effect.runPromise(revokeCapabilities(env.HYPERDRIVE, businessId, [...known.keys()]));
  for (const employeeId of employees)
    await Effect.runPromise(
      grantAll(
        env.HYPERDRIVE,
        { businessId, employeeId },
        offeredNow.map(({ name, line }) => ({
          capability: capabilities.find((each) => each.name === name)!,
          mode: line === "own" ? ("auto" as const) : ("ask" as const),
          responsibility: accepted.name,
        })),
      ),
    );
  const answered = await Effect.runPromise(
    connectAnswered(
      env.HYPERDRIVE,
      businessId,
      [accepted.id, accepted.url, ...(accepted.registry_name ? [accepted.registry_name] : [])],
      personId,
    ),
  );
  for (const decision of answered)
    await tellEmployee(
      env,
      businessId,
      personId,
      decision,
      employees.includes(decision.employee_id)
        ? `${accepted.name} is on: find what it does with describe_capabilities.`
        : answerText(decision),
      `connected:${decision.id}`,
    );
  return accepted;
}

/** Removes a remote app: its grants end, its sign-in leaves the vault. */
export async function removeApp(env: Env, businessId: string, app: RemoteApp) {
  const names = app.tools.flatMap((tool) => remoteCapabilityName(app.id, tool.name) ?? []);
  await Effect.runPromise(revokeCapabilities(env.HYPERDRIVE, businessId, names));
  await modeOf(env).secrets.remove(businessId, connectionName(app.id));
  await Effect.runPromise(removeRemoteApp(env.HYPERDRIVE, businessId, app.id));
}

// A card from a card app (Ramp), for browserFill.

/**
 * What the host asks a card app for, for one fill: the signed approval's exact amount, currency
 * and merchant, and the approval's id as the retry key (one approval, one card).
 */
export async function cardSource(
  env: Env,
  businessId: string,
  card: { app: string; fund: string; country?: string },
  spend: { counterparty: string; site: string; amount: { cents: number; currency: string } },
  approval: string,
): Promise<CardSource> {
  const app = await Effect.runPromise(remoteAppFor(env.HYPERDRIVE, businessId, card.app));
  if (!app || (app.state !== "on" && app.state !== "review"))
    throw refused(
      409,
      "That card app isn't connected: ask the owner to connect it (askOwner connect)",
    );
  if (!app.tools.some((tool) => tool.name === cardTool))
    throw refused(409, `${app.name} doesn't issue cards`);
  const sealed = await signIn(env, businessId, app.id);
  if (!sealed) throw refused(409, `${app.name} isn't signed in`);
  return {
    app: app.id,
    url: app.url,
    sealed,
    tool: cardTool,
    arguments: {
      fund_id: card.fund,
      amount: (spend.amount.cents / 100).toFixed(2),
      currency_code: spend.amount.currency,
      merchant_name: spend.counterparty,
      merchant_url: `https://${spend.site}`,
      merchant_country_code: card.country ?? "US",
      idempotency_key: `devys-${approval}`,
      rationale: `A purchase the owner approved and signed: ${spend.counterparty}`,
    },
  };
}

/** After a card fill: a refreshed sign-in is kept; a lapsed one shows in Needs you. */
export async function cardSettled(
  env: Env,
  businessId: string,
  appId: string,
  outcome: { sealed?: Sealed } | { lapsed: true },
) {
  const app = await Effect.runPromise(remoteApp(env.HYPERDRIVE, businessId, appId));
  if (!app) return;
  await settle(env, app, businessId, outcome).catch(() => undefined);
}

/**
 * `askOwner`, with the connect kind's own steps: the app named is added (not yet connected) so
 * the owner sees its name and logo, an app already on is refused (it is there to use), and a new
 * request posts the connect card in the thread. The request names the app by the business's own
 * id, however the employee named it (an id, a registry name or an address), so every client
 * finds the app whose Connect the card shows.
 */
export async function askOwnerConnecting(
  env: Env,
  asking: { businessId: string; employeeId: string; workItemId: string; conversation: string },
  request: OwnerRequest,
  builtIn: readonly { id: string; name: string }[],
) {
  if (request.kind !== "connect") return askOwnerFor(env, asking, request);
  const app = await addApp(
    env,
    asking.businessId,
    request.app,
    `employee:${asking.employeeId}`,
    builtIn,
  );
  const asked: OwnerRequest = { ...request, app: app.id };
  if (app.state === "on") {
    // Asking again reads where it stands; a new request for an app already on is refused.
    const grant = await Effect.runPromise(
      activeGrant(
        env.HYPERDRIVE,
        { businessId: asking.businessId, employeeId: asking.employeeId },
        "askOwner",
      ),
    );
    const standing =
      grant &&
      (await Effect.runPromise(
        standingRequest(env.HYPERDRIVE, {
          grantId: grant.id,
          request: asked,
          workItemId: asking.workItemId,
        }),
      ));
    if (standing) return standing;
    throw refused(
      409,
      `${app.name} is already on: use it (describe_capabilities); ask the owner if you need more of it`,
    );
  }
  // The work item's card shows the request with the app's name and logo, and its Connect.
  return askOwnerFor(env, asking, asked);
}
