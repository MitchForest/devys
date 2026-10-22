/**
 * A remote app for tests: an MCP server over Streamable HTTP behind its own OAuth 2.1 authorization
 * server, as the MCP spec (2026-07-28) has it: protected resource metadata (RFC 9728),
 * authorization server metadata (RFC 8414), dynamic client registration, PKCE (S256), the
 * resource indicator (RFC 8707) and `iss` in the authorization response (RFC 9207). A plain
 * `fetch(request)` handler, so Bun serves it on a port and the Workers suite answers fetches with
 * it. The "owner" signing in is `authorize`, which approves at once and redirects with a code.
 */
import { createMcpHandler, fromJsonSchema, McpServer } from "@modelcontextprotocol/server";

/** A 1×1 PNG, the app's logo. */
export const logoPng = Uint8Array.from(
  atob(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  ),
  (c) => c.charCodeAt(0),
);

/** The card the fake Ramp tool issues: a test Visa number. */
export const issuedCard = {
  card_number: "4242424242424242",
  expiration_month: "12",
  expiration_year: "2031",
  cvv: "123",
  cardholder_name: "Sam Owner",
  billing_address: { postal_code: "94107" },
  token_id: "ramp-token-77",
};

export interface FakeMcp {
  readonly origin: string;
  /** The MCP endpoint (the remote app's URL). */
  readonly url: string;
  fetch(request: Request): Promise<Response>;
  /** Every tool call the server answered, in order. */
  readonly calls: { tool: string; args: Record<string, unknown> }[];
  /** Access tokens stop working (a refresh gets new ones). */
  expireAccess(): void;
  /** The refresh token stops working too: the connection lapses. */
  revoke(): void;
  /** How many refreshes the token endpoint answered. */
  refreshes(): number;
}

const json = (value: unknown, status = 200) => Response.json(value, { status });

async function s256(verifier: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * The fake server at `origin`. `icons` decides whether its serverInfo names a logo (the identity
 * chain's first step); without one Devys falls back to the registry, then the site's icon (`site`),
 * then a letter tile.
 */
export function fakeMcp(
  origin: string,
  options: { icons?: boolean; title?: string; site?: boolean } = {},
): FakeMcp {
  const url = `${origin}/mcp`;
  const clients = new Map<string, { redirect_uris: string[] }>();
  const codes = new Map<string, { challenge: string; client: string; redirect: string }>();
  let access = new Set<string>();
  let refresh = new Set<string>();
  let refreshed = 0;
  const calls: FakeMcp["calls"] = [];

  const issue = () => {
    const token = { access: crypto.randomUUID(), refresh: crypto.randomUUID() };
    access.add(token.access);
    refresh.add(token.refresh);
    return {
      access_token: token.access,
      refresh_token: token.refresh,
      token_type: "Bearer",
      expires_in: 3600,
      scope: "books:read books:write",
    };
  };

  const server = () => {
    const mcp = new McpServer({
      name: "acme-books",
      title: options.title ?? "Acme Books",
      version: "1.0.0",
      description: "Bills and cards for Acme",
      websiteUrl: origin,
      ...(options.icons === false
        ? {}
        : { icons: [{ src: `${origin}/logo.png`, mimeType: "image/png", sizes: ["1x1"] }] }),
    });
    const object = (properties: Record<string, unknown>, required: string[]) =>
      fromJsonSchema({ type: "object", properties, required } as never);
    // The SDK's overloads type tools by zod or Standard Schema; these take plain JSON Schema.
    const register = mcp.registerTool.bind(mcp) as (
      name: string,
      config: Record<string, unknown>,
      handler: (args: Record<string, unknown>) => Promise<unknown>,
    ) => void;
    const answer = (tool: string) => async (args: Record<string, unknown>) => {
      calls.push({ tool, args });
      const data =
        tool === "list_bills"
          ? { bills: [{ id: "bill-1", vendor: "Paper Co", amount: "12.00" }] }
          : tool === "create_bill"
            ? { id: "bill-2", vendor: args.vendor }
            : tool === "ramp_get_agent_card_creds"
              ? issuedCard
              : { credential: "mpp-credential" };
      return { content: [{ type: "text" as const, text: JSON.stringify(data) }] };
    };
    register(
      "list_bills",
      {
        title: "List bills",
        description: "List the business's bills.",
        inputSchema: object({ status: { type: "string" } }, []),
        annotations: { readOnlyHint: true },
      },
      answer("list_bills"),
    );
    register(
      "create_bill",
      {
        title: "Create a bill",
        description: "Create a draft bill for a vendor.",
        inputSchema: object({ vendor: { type: "string" }, amount: { type: "string" } }, ["vendor"]),
        annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: true },
      },
      answer("create_bill"),
    );
    register(
      "ramp_get_agent_card_creds",
      {
        description: "Get a one-time payment token for a fund.",
        inputSchema: object(
          {
            fund_id: { type: "string" },
            amount: { type: "string" },
            currency_code: { type: "string" },
            merchant_name: { type: "string" },
            merchant_url: { type: "string" },
            merchant_country_code: { type: "string" },
          },
          ["fund_id", "amount", "currency_code", "merchant_name", "merchant_url"],
        ),
      },
      answer("ramp_get_agent_card_creds"),
    );
    register(
      "ramp_mpp_creds",
      {
        description: "Issue or recover a Stripe MPP credential using an existing fund.",
        inputSchema: object({ fund_id: { type: "string" } }, ["fund_id"]),
      },
      answer("ramp_mpp_creds"),
    );
    return mcp;
  };
  const handler = createMcpHandler(server);

  async function fetch(request: Request): Promise<Response> {
    const at = new URL(request.url);
    const path = at.pathname;
    if (
      path === "/.well-known/oauth-protected-resource/mcp" ||
      path === "/.well-known/oauth-protected-resource"
    )
      return json({
        resource: url,
        authorization_servers: [origin],
        scopes_supported: ["books:read", "books:write"],
        bearer_methods_supported: ["header"],
      });
    if (
      path === "/.well-known/oauth-authorization-server" ||
      path === "/.well-known/openid-configuration"
    )
      return json({
        issuer: origin,
        authorization_endpoint: `${origin}/authorize`,
        token_endpoint: `${origin}/token`,
        registration_endpoint: `${origin}/register`,
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code", "refresh_token"],
        token_endpoint_auth_methods_supported: ["none"],
        code_challenge_methods_supported: ["S256"],
        authorization_response_iss_parameter_supported: true,
      });
    if (path === "/register" && request.method === "POST") {
      const metadata = (await request.json()) as { redirect_uris: string[] };
      const client_id = `client-${crypto.randomUUID()}`;
      clients.set(client_id, metadata);
      return json({ ...metadata, client_id, token_endpoint_auth_method: "none" }, 201);
    }
    if (path === "/authorize") {
      const q = at.searchParams;
      const client = clients.get(q.get("client_id") ?? "");
      const redirect = q.get("redirect_uri") ?? "";
      if (!client || !client.redirect_uris.includes(redirect))
        return new Response("Unsupported redirect URI", { status: 400 });
      if (q.get("code_challenge_method") !== "S256" || q.get("resource") !== url)
        return new Response("PKCE and the resource are required", { status: 400 });
      const code = crypto.randomUUID();
      codes.set(code, {
        challenge: q.get("code_challenge")!,
        client: q.get("client_id")!,
        redirect,
      });
      const back = new URL(redirect);
      back.searchParams.set("code", code);
      back.searchParams.set("state", q.get("state") ?? "");
      back.searchParams.set("iss", origin);
      return new Response(null, { status: 302, headers: { location: back.href } });
    }
    if (path === "/token" && request.method === "POST") {
      const form = new URLSearchParams(new TextDecoder().decode(await request.arrayBuffer()));
      if (form.get("grant_type") === "authorization_code") {
        const code = codes.get(form.get("code") ?? "");
        codes.delete(form.get("code") ?? "");
        if (
          !code ||
          code.client !== form.get("client_id") ||
          code.redirect !== form.get("redirect_uri") ||
          (await s256(form.get("code_verifier") ?? "")) !== code.challenge ||
          form.get("resource") !== url
        )
          return json({ error: "invalid_grant" }, 400);
        return json(issue());
      }
      if (form.get("grant_type") === "refresh_token") {
        const token = form.get("refresh_token") ?? "";
        if (!refresh.has(token)) return json({ error: "invalid_grant" }, 400);
        refresh.delete(token);
        refreshed++;
        return json(issue());
      }
      return json({ error: "unsupported_grant_type" }, 400);
    }
    if (path === "/logo.png")
      return new Response(logoPng, { headers: { "content-type": "image/png" } });
    // Its site: a page naming its icon (the identity chain's last step before a letter tile).
    if (path === "/")
      return new Response(
        `<html><head><title>Acme</title>${options.site === false ? "" : '<link rel="apple-touch-icon" href="/logo.png">'}</head></html>`,
        { headers: { "content-type": "text/html" } },
      );
    if (path === "/favicon.ico") return new Response("Not found", { status: 404 });
    if (path === "/mcp") {
      const bearer = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
      if (!access.has(bearer))
        return new Response(JSON.stringify({ error: "invalid_token" }), {
          status: 401,
          headers: {
            "content-type": "application/json",
            "www-authenticate": `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource/mcp"`,
          },
        });
      return handler.fetch(request);
    }
    return new Response("Not found", { status: 404 });
  }

  return {
    origin,
    url,
    fetch,
    calls,
    expireAccess: () => {
      access = new Set();
    },
    revoke: () => {
      access = new Set();
      refresh = new Set();
    },
    refreshes: () => refreshed,
  };
}
