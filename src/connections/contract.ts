import { Schema } from "effect";
import type { RemoteServer, RemoteTool, ToolResult } from "../apps/contract.ts";
import type { Sealed } from "../vault/contract.ts";

/** Starting a connection: the provider's consent page the owner is sent to. */
export const Authorization = Schema.Struct({ url: Schema.String });
/** Removing a connection; `revoked` says whether the provider confirmed the revocation. */
export const Disconnected = Schema.Struct({
  disconnected: Schema.Literal(true),
  revoked: Schema.Boolean,
});

/**
 * A business's connection to an outside account, as an app that uses it sees it. The
 * connections component holds the grant and its stored credential; an app gets only a
 * short-lived access token, never the credential itself.
 */
export interface ConnectionAccess {
  /** The connection the token came from; replacing or removing it invalidates the token. */
  id: string;
  token: string;
}

/** One provider's connection for the apps that use it (Documents uses Google's). */
export interface Connection {
  /** A fresh access token for the business's connection; fails when it has none. */
  access(businessId: string): Promise<ConnectionAccess>;
  /** Fails unless `access` still belongs to the business's current connection. */
  assertCurrent(businessId: string, access: ConnectionAccess): Promise<void>;
}

/**
 * A remote app's address: an MCP server over https, or over http on this machine (a business's
 * own app in development). Undefined for anything else.
 */
export function remoteUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return undefined;
  }
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.username || url.password || url.hash || value.length > 2000) return undefined;
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) return undefined;
  return url.href;
}

/** A call that reached the app (tokens resealed when a refresh changed them), or a lapsed one. */
export type Reached<T> = { lapsed: true } | (T & { sealed?: Sealed });

/**
 * Remote apps' MCP client (the Mac host in local mode): sign-in, discovery and calls. Tokens stay
 * with the holder of the vault's key; callers hand it the sealed connection and store what it
 * reseals.
 */
export interface RemoteApps {
  /** A sign-in to start (`authorize`, and what finishing needs), or the server needs none. */
  begin(input: {
    business: string;
    url: string;
    redirect: string;
    state: string;
  }): Promise<
    | { authorize: string; pending: unknown }
    | { open: true; server: RemoteServer; tools: RemoteTool[] }
  >;
  /** Exchanges the code, seals the tokens as the connection `name`, and lists the tools. */
  finish(input: {
    business: string;
    url: string;
    name: string;
    redirect: string;
    code: string;
    iss?: string;
    pending: unknown;
  }): Promise<{ sealed: Sealed; server: RemoteServer; tools: RemoteTool[] }>;
  tools(input: {
    business: string;
    url: string;
    sealed: Sealed | null;
  }): Promise<Reached<{ server: RemoteServer; tools: RemoteTool[] }>>;
  call(input: {
    business: string;
    url: string;
    sealed: Sealed | null;
    tool: string;
    arguments: Record<string, unknown>;
  }): Promise<Reached<{ result: ToolResult }>>;
}
