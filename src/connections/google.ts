import * as oauth from "oauth4webapi";
import { query, transaction, type Database } from "../data/database.ts";
import { sha256 } from "../protocol/bytes.ts";
import { sessionCookie } from "../identity/contract.ts";

/** What the Google connection needs from the deployment: its OAuth client and storage key. */
export interface GoogleBindings {
  HYPERDRIVE: Database;
  PUBLIC_URL: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  CONNECTIONS_KEY: string;
}

export const driveScope = "https://www.googleapis.com/auth/drive.file";
const server: oauth.AuthorizationServer = {
  issuer: "https://accounts.google.com",
  authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
  token_endpoint: "https://oauth2.googleapis.com/token",
};
const client = (env: GoogleBindings): oauth.Client => ({ client_id: env.GOOGLE_CLIENT_ID });
const redirect = (env: GoogleBindings) => `${env.PUBLIC_URL}/api/connections/google/callback`;
export const googleConfigured = (env: GoogleBindings) =>
  Boolean(
    env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && /^[a-f0-9]{64}$/.test(env.CONNECTIONS_KEY),
  );

/** Ciphertext is bound to both the business and this grant; no token reaches a model tool. */
export async function protect(
  env: GoogleBindings,
  business: string,
  grant: string,
  value: string,
  decrypt = false,
) {
  if (!/^[a-f0-9]{64}$/.test(env.CONNECTIONS_KEY))
    throw new Error("Connection encryption is not configured");
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(env.CONNECTIONS_KEY.match(/../g)!, (hex) => parseInt(hex, 16)),
    "AES-GCM",
    false,
    ["encrypt", "decrypt"],
  );
  const data = decrypt
    ? Uint8Array.from(atob(value), (c) => c.charCodeAt(0))
    : new TextEncoder().encode(value);
  const iv = decrypt ? data.slice(0, 12) : crypto.getRandomValues(new Uint8Array(12));
  const algorithm = {
    name: "AES-GCM",
    iv,
    additionalData: new TextEncoder().encode(`${business}:${grant}`),
  };
  if (decrypt)
    return new TextDecoder().decode(await crypto.subtle.decrypt(algorithm, key, data.slice(12)));
  const cipher = new Uint8Array(await crypto.subtle.encrypt(algorithm, key, data));
  return btoa(String.fromCharCode(...iv, ...cipher));
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
    await protect(env, business, hash, verifier),
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
  return Response.json({ url: url.href });
}

/** The callback URL is fixed, so the business comes from the stored state; wiring confirms membership. */
export async function finishGoogle(
  request: Request,
  env: GoogleBindings,
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
    await protect(env, business, hash, row.verifier, true),
    { signal: AbortSignal.timeout(20_000) },
  );
  const tokens = await oauth.processAuthorizationCodeResponse(server, client(env), response);
  if (!tokens.refresh_token || (tokens.scope && !tokens.scope.split(" ").includes(driveScope)))
    throw new Error("Drive permission was not granted");
  const id = crypto.randomUUID();
  const encrypted = await protect(env, business, id, tokens.refresh_token);
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
      "INSERT INTO google_connections (business_id, id, refresh_token, connected_by) VALUES ($1, $2, $3, $4)",
      [business, id, encrypted, person],
    );
    await sql.run("DELETE FROM google_oauth_states WHERE state_hash = $1", [hash]);
    return true;
  });
  if (!connected) return new Response("Connection cancelled; start again", { status: 409 });
  return new Response(null, { status: 303, headers: { location: "/" } });
}

export interface GoogleAccess {
  id: string;
  token: string;
}
export async function googleAccess(env: GoogleBindings, business: string): Promise<GoogleAccess> {
  const row = await query(env.HYPERDRIVE, (sql) =>
    sql.row<{ id: string; refresh_token: string }>(
      "SELECT id, refresh_token FROM google_connections WHERE business_id = $1",
      [business],
    ),
  );
  if (!row) throw new Error("Connect Google Drive for this business first");
  const refresh = await protect(env, business, row.id, row.refresh_token, true);
  const response = await oauth.refreshTokenGrantRequest(
    server,
    client(env),
    oauth.ClientSecretPost(env.GOOGLE_CLIENT_SECRET),
    refresh,
    { signal: AbortSignal.timeout(20_000) },
  );
  const tokens = await oauth.processRefreshTokenResponse(server, client(env), response);
  if (tokens.scope && !tokens.scope.split(" ").includes(driveScope))
    throw new Error("Reconnect Google Drive");
  const refreshed = tokens.refresh_token
    ? await protect(env, business, row.id, tokens.refresh_token)
    : row.refresh_token;
  const changed = await query(env.HYPERDRIVE, (sql) =>
    sql.run(
      `UPDATE google_connections SET refresh_token = $1
       WHERE business_id = $2 AND id = $3 AND refresh_token = $4`,
      [refreshed, business, row.id, row.refresh_token],
    ),
  );
  if (changed !== 1) throw new Error("Connection changed; try again");
  return { id: row.id, token: tokens.access_token };
}

export async function assertGoogle(env: GoogleBindings, business: string, access: GoogleAccess) {
  const current = await query(env.HYPERDRIVE, (sql) =>
    sql.row("SELECT id FROM google_connections WHERE business_id = $1 AND id = $2", [
      business,
      access.id,
    ]),
  );
  if (!current) throw new Error("Google Drive access disconnected");
}

export async function disconnectGoogle(env: GoogleBindings, business: string) {
  const row = await transaction(env.HYPERDRIVE, async (sql) => {
    await sql.run("DELETE FROM google_oauth_states WHERE business_id = $1", [business]);
    return sql.row<{ id: string; refresh_token: string }>(
      "DELETE FROM google_connections WHERE business_id = $1 RETURNING id, refresh_token",
      [business],
    );
  });
  let revoked = !row;
  if (row) {
    try {
      const token = await protect(env, business, row.id, row.refresh_token, true);
      revoked = (
        await fetch("https://oauth2.googleapis.com/revoke", {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token }),
          signal: AbortSignal.timeout(15_000),
        })
      ).ok;
    } catch {
      /* Local access is already removed; report provider revocation truthfully. */
    }
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
