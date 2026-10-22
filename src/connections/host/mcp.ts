/**
 * Remote apps' side of the trusted Mac host (local mode): the MCP client. A remote app is an MCP
 * server behind its own OAuth 2.1 sign-in (.docs/APPS_AND_CAPABILITIES.md, slice LP6); the official
 * TypeScript SDK (`@modelcontextprotocol/client`) does discovery (RFC 9728, RFC 8414), client
 * registration, PKCE, the resource indicator, `iss` checks, refresh and Streamable HTTP. The tokens
 * live in the vault as the app's `connection` secret and are opened only here: the Worker hands
 * this host the sealed bundle with each call and gets back a resealed one when a refresh changed
 * it, never a token.
 */
import {
  Client,
  StreamableHTTPClientTransport,
  UnauthorizedError,
  type OAuthClientMetadata,
  type OAuthClientProvider,
  type OAuthDiscoveryState,
  type StoredOAuthClientInformation,
  type StoredOAuthTokens,
} from "@modelcontextprotocol/client";
import { HostRefusal, hostId, type HostRoutes } from "../../protocol/host.ts";
import type { Keyring, OpenSecrets, Sealed } from "../../vault/contract.ts";
import type { RemoteServer, RemoteTool, ToolResult } from "../../apps/contract.ts";
import { remoteUrl } from "../contract.ts";

/** What a connection's secret holds: the tokens, the registered client and the discovery. */
interface Bundle {
  tokens?: StoredOAuthTokens;
  client?: StoredOAuthClientInformation;
  discovery?: OAuthDiscoveryState;
  verifier?: string;
  /** The callback it signed in with: the SDK refreshes only interactive clients. */
  redirect?: string;
}

/** A sign-in waiting for its code: the PKCE verifier, the client and the discovery. Not a token. */
type Pending = Pick<Bundle, "client" | "discovery" | "verifier" | "redirect">;

/**
 * The SDK's OAuth client, over one bundle in memory. `redirect` is Devys's callback; the
 * authorization URL the SDK would send the owner to is kept, not followed.
 */
class Provider implements OAuthClientProvider {
  authorization?: URL;
  changed = false;
  constructor(
    readonly bundle: Bundle,
    private readonly stateValue?: string,
  ) {}
  get redirect() {
    return this.bundle.redirect;
  }
  get redirectUrl() {
    return this.redirect;
  }
  get clientMetadata(): OAuthClientMetadata {
    return {
      client_name: "Devys",
      redirect_uris: this.redirect ? [this.redirect] : [],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
    };
  }
  state() {
    return this.stateValue ?? crypto.randomUUID();
  }
  clientInformation() {
    return this.bundle.client;
  }
  saveClientInformation(client: StoredOAuthClientInformation) {
    this.bundle.client = client;
  }
  tokens() {
    return this.bundle.tokens;
  }
  saveTokens(tokens: StoredOAuthTokens) {
    this.bundle.tokens = tokens;
    this.changed = true;
  }
  redirectToAuthorization(url: URL) {
    this.authorization = url;
  }
  saveCodeVerifier(verifier: string) {
    this.bundle.verifier = verifier;
  }
  codeVerifier() {
    if (!this.bundle.verifier) throw new HostRefusal(400, "That sign-in expired; start again");
    return this.bundle.verifier;
  }
  saveDiscoveryState(state: OAuthDiscoveryState) {
    this.bundle.discovery = state;
  }
  discoveryState() {
    return this.bundle.discovery;
  }
  invalidateCredentials(scope: "all" | "client" | "tokens" | "verifier" | "discovery") {
    if (scope === "all" || scope === "tokens") delete this.bundle.tokens;
    if (scope === "all" || scope === "client") delete this.bundle.client;
    if (scope === "all" || scope === "verifier") delete this.bundle.verifier;
    if (scope === "all" || scope === "discovery") delete this.bundle.discovery;
    this.changed = true;
  }
}

/** The most of a tool result the host hands back. */
const resultChars = 200_000;
const requestMs = 30_000;

const text = (value: unknown, max: number) =>
  typeof value === "string" && value.trim() ? value.trim().slice(0, max) : undefined;

/** The server's identity as it states it (serverInfo), bounded; display only. */
function serverOf(client: Client): RemoteServer {
  const info = (client.getServerVersion() ?? {}) as Record<string, unknown>;
  const icons = Array.isArray(info.icons)
    ? info.icons
        .filter((icon): icon is { src: string } => typeof icon?.src === "string")
        .slice(0, 8)
        .map((icon) => ({ src: icon.src.slice(0, 100_000) }))
    : [];
  return {
    name: text(info.name, 80) ?? "App",
    ...(text(info.title, 80) ? { title: text(info.title, 80)! } : {}),
    ...(text(info.description, 500) ? { description: text(info.description, 500)! } : {}),
    ...(text(info.websiteUrl, 500) ? { website: text(info.websiteUrl, 500)! } : {}),
    icons,
  };
}

/** Every tool the server lists (paged), bounded. */
async function toolsOf(client: Client): Promise<RemoteTool[]> {
  const tools: RemoteTool[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < 20; page++) {
    const listed = await client.listTools(cursor ? { cursor } : {}, { timeout: requestMs });
    for (const tool of listed.tools) {
      if (tools.length >= 200) break;
      const annotations = (tool.annotations ?? {}) as Record<string, unknown>;
      const hint = (name: string) =>
        typeof annotations[name] === "boolean" ? { [name]: annotations[name] as boolean } : {};
      tools.push({
        name: tool.name.slice(0, 128),
        ...(text(tool.title ?? annotations.title, 120)
          ? { title: text(tool.title ?? annotations.title, 120)! }
          : {}),
        description: text(tool.description, 2_000) ?? "",
        input: (tool.inputSchema ?? { type: "object" }) as Record<string, unknown>,
        hints: {
          ...hint("readOnlyHint"),
          ...hint("destructiveHint"),
          ...hint("idempotentHint"),
          ...hint("openWorldHint"),
        },
      });
    }
    cursor = listed.nextCursor;
    if (!cursor) break;
  }
  return tools;
}

/** A connected client for one call; the caller closes it. */
async function connected(url: string, provider: Provider, fetchFn?: typeof fetch) {
  const client = new Client(
    { name: "Devys", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );
  const transport = new StreamableHTTPClientTransport(new URL(url), {
    authProvider: provider,
    ...(fetchFn ? { fetch: fetchFn } : {}),
  });
  await client.connect(transport, { timeout: requestMs });
  return client;
}

/** A call's outcome: the connection lapsed (the owner reconnects), or a refused request. */
function failure(error: unknown): never {
  if (error instanceof HostRefusal) throw error;
  const message = error instanceof Error ? error.message.split("\n")[0]!.slice(0, 300) : "";
  throw new HostRefusal(502, `The app didn't answer as expected${message ? `: ${message}` : ""}`);
}

const lapsed = (error: unknown) => error instanceof UnauthorizedError;

/** The text a tool's content says, and its structured data, bounded. */
function resultOf(raw: unknown): ToolResult {
  const result = (raw ?? {}) as {
    content?: { type: string; text?: string }[];
    structuredContent?: unknown;
    isError?: boolean;
  };
  const said = (result.content ?? [])
    .map((block) => (block.type === "text" ? (block.text ?? "") : `[${block.type}]`))
    .join("\n")
    .slice(0, resultChars);
  const data =
    result.structuredContent !== undefined &&
    JSON.stringify(result.structuredContent).length <= resultChars
      ? result.structuredContent
      : undefined;
  return { text: said, ...(data !== undefined ? { data } : {}), error: result.isError === true };
}

interface McpHostOptions {
  /** Opens a sealed connection (the vault's keyring, passed in by `src/host.ts`). */
  open: OpenSecrets;
  seal: Keyring["seal"];
  /** Tests answer the app's requests in process. */
  fetch?: typeof fetch;
}

/**
 * The MCP client on the host. `/mcp/begin` starts a sign-in (or finds the server open);
 * `/mcp/finish` exchanges the code and seals the tokens; `/mcp/tools` and `/mcp/call` reach the
 * server with the sealed tokens, resealing them after a refresh. `call` is also how the browser's
 * card fill asks a card app for a one-time card, in this process.
 */
export function mcpHost(options: McpHostOptions) {
  /** The connection's bundle and its name, or none for an app that needs no sign-in. */
  async function open(business: string, sealed: unknown) {
    if (sealed === null || sealed === undefined) return { name: "", bundle: {} as Bundle };
    const [entry] = [...(await options.open(business, [sealed], ["connection"])).entries()];
    if (!entry) throw new HostRefusal(403, "That connection could not be opened");
    try {
      return { name: entry[0], bundle: JSON.parse(entry[1]) as Bundle };
    } catch {
      throw new HostRefusal(403, "That connection could not be opened");
    }
  }

  /** The bundle without the PKCE verifier, which is spent once the code is exchanged. */
  const withoutVerifier = (bundle: Bundle) => {
    const kept = { ...bundle };
    delete kept.verifier;
    return kept;
  };

  /** The bundle sealed again under its own name, when the SDK changed it. */
  const reseal = async (business: string, name: string, provider: Provider) =>
    provider.changed && name
      ? options.seal(business, name, "connection", JSON.stringify(withoutVerifier(provider.bundle)))
      : undefined;

  /** Runs `use` against the connected server; a lapsed connection answers `{lapsed: true}`. */
  async function reach<T>(
    input: Record<string, unknown>,
    use: (client: Client) => Promise<T>,
  ): Promise<{ lapsed: true } | (T & { sealed?: Sealed })> {
    const business = String(input.business ?? "");
    if (!hostId.test(business)) throw new HostRefusal(400, "Missing business");
    const url = remoteUrl(String(input.url ?? ""));
    if (!url) throw new HostRefusal(400, "An app's address is https (or http on this Mac)");
    const { name, bundle } = await open(business, input.sealed);
    const provider = new Provider(bundle);
    let client: Client | undefined;
    try {
      client = await connected(url, provider, options.fetch);
      const done = await use(client);
      const sealed = await reseal(business, name, provider);
      return { ...done, ...(sealed ? { sealed } : {}) };
    } catch (error) {
      if (lapsed(error)) return { lapsed: true };
      return failure(error);
    } finally {
      await client?.close().catch(() => undefined);
    }
  }

  /** A tool call, as `/mcp/call` and the card fill make it. */
  const call = (input: Record<string, unknown>) =>
    reach(input, async (client) => {
      const tool = String(input.tool ?? "");
      const args = input.arguments;
      if (!tool || tool.length > 128) throw new HostRefusal(400, "Name a tool");
      if (!args || typeof args !== "object" || Array.isArray(args))
        throw new HostRefusal(400, "A tool takes an object");
      const raw = await client.callTool(
        { name: tool, arguments: args as Record<string, unknown> },
        { timeout: requestMs },
      );
      return { result: resultOf(raw) };
    });

  const routes: HostRoutes = {
    prefix: "/mcp/",
    async handle(path, input) {
      if (path === "/mcp/begin") {
        const business = String(input.business ?? "");
        const url = remoteUrl(String(input.url ?? ""));
        const redirect = String(input.redirect ?? "");
        const state = String(input.state ?? "");
        if (!hostId.test(business) || !url || !/^https?:\/\/\S+$/.test(redirect) || !state)
          throw new HostRefusal(
            400,
            "Begin with a business, an app's address, a redirect and a state",
          );
        const provider = new Provider({ redirect }, state);
        let client: Client | undefined;
        try {
          client = await connected(url, provider, options.fetch);
          // The server answered without a sign-in: nothing to keep.
          return { open: true, server: serverOf(client), tools: await toolsOf(client) };
        } catch (error) {
          if (!lapsed(error) || !provider.authorization) return failure(error);
          const pending: Pending = {
            ...(provider.bundle.client ? { client: provider.bundle.client } : {}),
            ...(provider.bundle.discovery ? { discovery: provider.bundle.discovery } : {}),
            ...(provider.bundle.verifier ? { verifier: provider.bundle.verifier } : {}),
            redirect,
          };
          return { authorize: provider.authorization.href, pending };
        } finally {
          await client?.close().catch(() => undefined);
        }
      }
      if (path === "/mcp/finish") {
        const business = String(input.business ?? "");
        const url = remoteUrl(String(input.url ?? ""));
        const name = String(input.name ?? "");
        const redirect = String(input.redirect ?? "");
        const code = String(input.code ?? "");
        if (!hostId.test(business) || !url || !/^[a-z][a-z0-9_-]{0,63}$/.test(name) || !code)
          throw new HostRefusal(400, "Finish with a business, an app, its connection and a code");
        const pending = (input.pending ?? {}) as Pending;
        const provider = new Provider({ ...pending, redirect });
        const transport = new StreamableHTTPClientTransport(new URL(url), {
          authProvider: provider,
          ...(options.fetch ? { fetch: options.fetch } : {}),
        });
        try {
          await transport.finishAuth(code, typeof input.iss === "string" ? input.iss : undefined);
        } catch (error) {
          return failure(error);
        }
        let client: Client | undefined;
        try {
          client = await connected(url, provider, options.fetch);
          const server = serverOf(client);
          const tools = await toolsOf(client);
          const sealed = await options.seal(
            business,
            name,
            "connection",
            JSON.stringify(withoutVerifier(provider.bundle)),
          );
          return { sealed, server, tools };
        } catch (error) {
          return failure(error);
        } finally {
          await client?.close().catch(() => undefined);
        }
      }
      if (path === "/mcp/tools")
        return reach(input, async (client) => ({
          server: serverOf(client),
          tools: await toolsOf(client),
        }));
      if (path === "/mcp/call") return call(input);
      throw new HostRefusal(404, "Not found");
    },
    close: async () => {},
  };
  return { routes, call };
}
