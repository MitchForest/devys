import * as oauth from "oauth4webapi";
import { query, transaction, type Database } from "../data/database.ts";
import { sha256 } from "../protocol/bytes.ts";
import { sessionCookie } from "../identity/contract.ts";
import { Authorization, type Connection, type ConnectionAccess } from "./contract.ts";
import { respond } from "../protocol/http.ts";
import type { SecretStore, SendWithSecret } from "../vault/contract.ts";

/** What the Google connection needs from the deployment: its OAuth client. */
interface GoogleBindings {
  HYPERDRIVE: Database;
  PUBLIC_URL: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
}

/**
 * Where the refresh token lives: the business's vault, as the connection secret `google`. It is
 * opened only by the vault's master key holder, which sends the token requests with it.
 */
export interface GoogleVault {
  secrets: SecretStore;
  send: SendWithSecret;
}
const tokenName = "google";

export const driveScope = "https://www.googleapis.com/auth/drive.file";
const server: oauth.AuthorizationServer = {
  issuer: "https://accounts.google.com",
  authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
  token_endpoint: "https://oauth2.googleapis.com/token",
};
const client = (env: GoogleBindings): oauth.Client => ({ client_id: env.GOOGLE_CLIENT_ID });
const redirect = (env: GoogleBindings) => `${env.PUBLIC_URL}/api/connections/google/callback`;
export const googleConfigured = (env: GoogleBindings) =>
  Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);

/**
 * A request oauth4webapi builds with `placeholder` for the refresh token, sent by the vault's
 * holder with the token in its place: the Worker never holds the stored token.
 */
async function withToken(vault: GoogleVault, business: string) {
  const [sealed] = await vault.secrets.sealed(business, [tokenName], ["connection"]);
  const placeholder = `devys-google-${crypto.randomUUID()}`;
  const send: oauth.HttpRequestOptions<"POST", URLSearchParams>[typeof oauth.customFetch] = async (
    url,
    options,
  ) => {
    const answer = await vault.send(
      sealed!,
      {
        url,
        method: "POST",
        headers: options.headers,
        body: options.body ? String(options.body) : null,
      },
      placeholder,
    );
    return new Response(answer.body, {
      status: answer.status,
      headers: answer.type ? { "content-type": answer.type } : {},
    });
  };
  return { placeholder, send };
}

const sessionHash = (request: Request) =>
  sha256(
    request.headers
      .get("cookie")
      ?.split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith(`${sessionCookie}=`))
      ?.slice(sessionCookie.length + 1) ?? "",
  );

export async function beginGoogle(
  request: Request,
  env: GoogleBindings,
  business: string,
  person: string,
) {
  if (!googleConfigured(env))
    return new Response("Google Drive is not configured", { status: 503 });
  const state = oauth.generateRandomState();
  const verifier = oauth.generateRandomCodeVerifier();
  const hash = await sha256(state);
  const values = [
    hash,
    business,
    person,
    await sessionHash(request),
    // Ten minutes, single use, and useless without the code only the callback receives.
    verifier,
    Date.now() + 600_000,
  ];
  await query(env.HYPERDRIVE, (sql) =>
    sql.run(
      `INSERT INTO google_oauth_states (state_hash, business_id, person_id, session_hash, verifier, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (business_id) DO UPDATE SET state_hash = excluded.state_hash,
         person_id = excluded.person_id, session_hash = excluded.session_hash, verifier = excluded.verifier,
         expires_at = excluded.expires_at, claimed = false`,
      values,
    ),
  );
  const url = new URL(server.authorization_endpoint!);
  url.search = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: redirect(env),
    response_type: "code",
    scope: driveScope,
    state,
    code_challenge: await oauth.calculatePKCECodeChallenge(verifier),
    code_challenge_method: "S256",
    access_type: "offline",
    prompt: "consent",
  }).toString();
  return respond(Authorization, { url: url.href });
}

/** The callback URL is fixed, so the business comes from the stored state; wiring confirms membership. */
export async function finishGoogle(
  request: Request,
  env: GoogleBindings,
  vault: GoogleVault,
  person: string,
  member: (business: string) => Promise<boolean>,
) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? "";
  const hash = await sha256(state);
  const session = await sessionHash(request);
  const row = await query(env.HYPERDRIVE, (sql) =>
    sql.row<{ verifier: string; business_id: string }>(
      `UPDATE google_oauth_states SET claimed = true
       WHERE state_hash = $1 AND person_id = $2 AND session_hash = $3
         AND expires_at > $4 AND NOT claimed
       RETURNING verifier, business_id`,
      [hash, person, session, Date.now()],
    ),
  );
  if (!row || !(await member(row.business_id)))
    return new Response("Connection request expired; start again", { status: 400 });
  const business = row.business_id;
  const parameters = oauth.validateAuthResponse(server, client(env), url, state);
  const response = await oauth.authorizationCodeGrantRequest(
    server,
    client(env),
    oauth.ClientSecretPost(env.GOOGLE_CLIENT_SECRET),
    parameters,
    redirect(env),
    row.verifier,
    { signal: AbortSignal.timeout(20_000) },
  );
  const tokens = await oauth.processAuthorizationCodeResponse(server, client(env), response);
  if (!tokens.refresh_token || (tokens.scope && !tokens.scope.split(" ").includes(driveScope)))
    throw new Error("Drive permission was not granted");
  const id = crypto.randomUUID();
  // The state must still exist: disconnect or a newer connection request invalidates this callback.
  const connected = await transaction(env.HYPERDRIVE, async (sql) => {
    const current = await sql.row(
      `SELECT 1 FROM google_oauth_states
       WHERE state_hash = $1 AND business_id = $2 AND expires_at > $3 FOR UPDATE`,
      [hash, business, Date.now()],
    );
    if (!current) return false;
    await sql.run("DELETE FROM google_connections WHERE business_id = $1", [business]);
    await sql.run(
      "INSERT INTO google_connections (business_id, id, connected_by) VALUES ($1, $2, $3)",
      [business, id, person],
    );
    await sql.run("DELETE FROM google_oauth_states WHERE state_hash = $1", [hash]);
    return true;
  });
  if (!connected) return new Response("Connection cancelled; start again", { status: 409 });
  try {
    await vault.secrets.put(business, tokenName, "connection", tokens.refresh_token, person);
  } catch (error) {
    await query(env.HYPERDRIVE, (sql) =>
      sql.run("DELETE FROM google_connections WHERE business_id = $1 AND id = $2", [business, id]),
    );
    throw error;
  }
  return new Response(null, { status: 303, headers: { location: "/" } });
}

export async function googleAccess(
  env: GoogleBindings,
  vault: GoogleVault,
  business: string,
): Promise<ConnectionAccess> {
  const row = await query(env.HYPERDRIVE, (sql) =>
    sql.row<{ id: string; connected_by: string }>(
      "SELECT id, connected_by FROM google_connections WHERE business_id = $1",
      [business],
    ),
  );
  if (!row) throw new Error("Connect Google Drive for this business first");
  const { placeholder, send } = await withToken(vault, business);
  const response = await oauth.refreshTokenGrantRequest(
    server,
    client(env),
    oauth.ClientSecretPost(env.GOOGLE_CLIENT_SECRET),
    placeholder,
    { signal: AbortSignal.timeout(20_000), [oauth.customFetch]: send },
  );
  const tokens = await oauth.processRefreshTokenResponse(server, client(env), response);
  if (tokens.scope && !tokens.scope.split(" ").includes(driveScope))
    throw new Error("Reconnect Google Drive");
  // A disconnect while refreshing wins: the token answers nothing once the connection is gone.
  const current = await query(env.HYPERDRIVE, (sql) =>
    sql.row("SELECT id FROM google_connections WHERE business_id = $1 AND id = $2", [
      business,
      row.id,
    ]),
  );
  if (!current) throw new Error("Connection changed; try again");
  // A new refresh token replaces the stored one; the stored one sent back comes redacted.
  if (tokens.refresh_token && !tokens.refresh_token.includes("[redacted]"))
    await vault.secrets.put(
      business,
      tokenName,
      "connection",
      tokens.refresh_token,
      row.connected_by,
    );
  return { id: row.id, token: tokens.access_token };
}

async function assertGoogle(env: GoogleBindings, business: string, access: ConnectionAccess) {
  const current = await query(env.HYPERDRIVE, (sql) =>
    sql.row("SELECT id FROM google_connections WHERE business_id = $1 AND id = $2", [
      business,
      access.id,
    ]),
  );
  if (!current) throw new Error("Google Drive access disconnected");
}

export async function disconnectGoogle(env: GoogleBindings, vault: GoogleVault, business: string) {
  const row = await transaction(env.HYPERDRIVE, async (sql) => {
    await sql.run("DELETE FROM google_oauth_states WHERE business_id = $1", [business]);
    return sql.row<{ id: string }>(
      "DELETE FROM google_connections WHERE business_id = $1 RETURNING id",
      [business],
    );
  });
  let revoked = !row;
  if (row) {
    try {
      const { placeholder, send } = await withToken(vault, business);
      revoked = (
        await send("https://oauth2.googleapis.com/revoke", {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token: placeholder }),
          redirect: "manual",
        })
      ).ok;
    } catch {
      /* Local access is already removed; report provider revocation truthfully. */
    }
    await vault.secrets.remove(business, tokenName);
  }
  return { disconnected: true, revoked };
}

export async function googleConnectionStatus(db: Database, business: string) {
  return query(db, (sql) =>
    sql.row<{ connected_at: string }>(
      "SELECT connected_at FROM google_connections WHERE business_id = $1",
      [business],
    ),
  );
}

/** The Google connection as the apps that use it see it (Documents, for Drive). */
export const googleConnection = (env: GoogleBindings, vault: GoogleVault): Connection => ({
  access: (business) => googleAccess(env, vault, business),
  assertCurrent: (business, access) => assertGoogle(env, business, access),
});

/** The providers a business has connected; Google is the only one today. */
export async function connectedProviders(db: Database, business: string) {
  return (await googleConnectionStatus(db, business)) ? ["google"] : [];
}
