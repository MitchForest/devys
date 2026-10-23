import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import {
  deleteSession,
  devices,
  issueLink,
  ownerSession,
  redeemLink,
  revokeDevice,
  sessionDays,
  sessionPerson,
} from "./sessions.ts";
import { askToJoin, joinMatch, joinStatus, waitingJoins } from "./joins.ts";
import { sha256, readBounded } from "../protocol/bytes.ts";
import { respond, sameOrigin } from "../protocol/http.ts";
import {
  DeviceList,
  Hello,
  JoinRequest,
  JoinRequests,
  JoinStatus,
  sessionCookie,
} from "./contract.ts";
import { Timestamp } from "../protocol/time.ts";

/** `POST /api/local/session`: the Mac's owner's session for the Mac app, returned in the body. */
export const DeviceSession = Schema.Struct({
  session_token: Schema.String,
  expires_in_seconds: Schema.Number,
});

/** `POST /api/devices/link`: a one-time link's token that signs a browser in as this person. */
export const SignInLink = Schema.Struct({ token: Schema.String, expires_at: Timestamp });

const sessionSeconds = 60 * 60 * 24 * sessionDays;

// Lax permits the Google OAuth callback; every browser mutation also checks Origin.
export const cookie = (token: string, age = sessionSeconds) =>
  `${sessionCookie}=${token}; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=${age}`;

const tokenPattern = /^[a-f0-9]{64}$/;
const bearerPattern = /^Bearer ([a-f0-9]{64})$/;

function cookieToken(request: Request) {
  return request.headers
    .get("cookie")
    ?.split(";")
    .map((value) => value.trim())
    .find((value) => value.startsWith(`${sessionCookie}=`))
    ?.slice(sessionCookie.length + 1);
}

/** 32 random bytes as hex: a session token or a one-time link. */
export const randomToken = () =>
  crypto
    .getRandomValues(new Uint8Array(32))
    .reduce((text, byte) => text + byte.toString(16).padStart(2, "0"), "");

/** A small JSON body, or an empty object when it is not one. */
async function smallBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = JSON.parse(new TextDecoder().decode(await readBounded(request.body, 2_000)));
    return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** A device's own name for itself, trimmed to what a device list shows. */
const deviceName = (value: unknown) =>
  typeof value === "string" && value.trim() ? value.trim().slice(0, 80) : undefined;

/**
 * Native clients present `Authorization: Bearer`; browsers present the session cookie.
 * A request carrying an Authorization header is judged on it alone, never on a cookie.
 * Bearer requests cannot be forged cross-site, so they skip the browser Origin check.
 */
export async function requestPerson(request: Request, env: { HYPERDRIVE: Database }) {
  const authorization = request.headers.get("authorization");
  const bearer = authorization !== null;
  const token = bearer ? bearerPattern.exec(authorization)?.[1] : cookieToken(request);
  if (!token || !tokenPattern.test(token)) return;
  const sessionHash = await sha256(token);
  const person = await Effect.runPromise(sessionPerson(env.HYPERDRIVE, sessionHash));
  return person ? { person, bearer, device: sessionHash.slice(0, 16) } : undefined;
}

/** `GET /api/hello`: the name a device shows on its one button, "Connect to <name>". */
export const hello = (name: string, url: string) => respond(Hello, { name, url });

/**
 * `POST /api/local/session`: the Mac app on the Mac running Devys signs in as the Mac's owner
 * with the key only that macOS user can read (`isOwnerKey`); there is no sign-in screen.
 */
export async function localSession(
  request: Request,
  env: { HYPERDRIVE: Database },
  isOwnerKey: (key: string) => Promise<boolean>,
) {
  const body = await smallBody(request);
  if (typeof body.key !== "string" || !(await isOwnerKey(body.key)))
    return new Response("Not found", { status: 404 });
  const session = randomToken();
  await Effect.runPromise(
    ownerSession(env.HYPERDRIVE, {
      sessionHash: await sha256(session),
      name: deviceName(body.name) ?? "Owner",
      label: deviceName(body.label) ?? null,
    }),
  );
  return respond(DeviceSession, { session_token: session, expires_in_seconds: sessionSeconds });
}

/** `POST /api/link`: a browser opened with a one-time link (`/#signin=<token>`) signs in. */
export async function redeemSignInLink(request: Request, env: { HYPERDRIVE: Database }) {
  if (!sameOrigin(request)) return new Response("Forbidden", { status: 403 });
  const { token } = await smallBody(request);
  if (typeof token !== "string" || !tokenPattern.test(token))
    return new Response("Invalid link", { status: 400 });
  const session = randomToken();
  const redeemed = await Effect.runPromise(
    redeemLink(env.HYPERDRIVE, await sha256(token), await sha256(session), "Web browser"),
  );
  if (!redeemed) return new Response("That link expired or was already used", { status: 401 });
  return Response.json({ signed_in: true }, { headers: { "set-cookie": cookie(session) } });
}

export async function logout(request: Request, env: { HYPERDRIVE: Database }) {
  const authorization = request.headers.get("authorization");
  if (authorization === null && !sameOrigin(request))
    return new Response("Forbidden", { status: 403 });
  const token =
    authorization === null ? cookieToken(request) : /^Bearer (\S+)$/.exec(authorization)?.[1];
  if (token) await Effect.runPromise(deleteSession(env.HYPERDRIVE, await sha256(token)));
  return Response.json(
    { signed_out: true },
    authorization === null ? { headers: { "set-cookie": cookie("", 0) } } : undefined,
  );
}

const asRequest = async (row: {
  id: string;
  session_hash: string;
  name: string;
  expires_at: string;
}) =>
  ({
    id: row.id,
    name: row.name,
    match: await joinMatch(row.id, row.session_hash),
    expires_at: row.expires_at,
  }) satisfies JoinRequest;

/**
 * The signed-out side of joining: a device asks (`POST /api/joins` with its name, the hash of the
 * session token it chose and, from an app, its signing key's public half), then asks how it went
 * (`GET /api/joins/:id`, presenting that token). Allowed, the token is its session; a browser
 * trades it for its cookie (`POST /api/joins/:id/cookie`). Undefined: not one of these paths.
 */
export async function joinRoute(request: Request, env: { HYPERDRIVE: Database }, path: string) {
  if (path === "/api/joins" && request.method === "POST") {
    const body = await smallBody(request);
    const name = deviceName(body.name);
    const publicKey =
      typeof body.public_key === "string" && /^[A-Za-z0-9+/=]{80,100}$/.test(body.public_key)
        ? body.public_key
        : null;
    if (!name || typeof body.session_hash !== "string" || !tokenPattern.test(body.session_hash))
      return new Response("Send a name and a session hash", { status: 400 });
    const asked = await Effect.runPromise(
      askToJoin(env.HYPERDRIVE, { sessionHash: body.session_hash, name, publicKey }),
    );
    if (!asked) return new Response("Too many devices are asking; try again soon", { status: 429 });
    return respond(JoinRequest, await asRequest(asked), { status: 201 });
  }
  const own = /^\/api\/joins\/([0-9a-f-]{36})(\/cookie)?$/.exec(path);
  if (!own) return undefined;
  const cookieRequest = own[2] === "/cookie";
  if (request.method !== (cookieRequest ? "POST" : "GET")) return undefined;
  if (cookieRequest && !sameOrigin(request)) return new Response("Forbidden", { status: 403 });
  const token = cookieRequest
    ? (await smallBody(request)).token
    : bearerPattern.exec(request.headers.get("authorization") ?? "")?.[1];
  if (typeof token !== "string" || !tokenPattern.test(token))
    return new Response("Not found", { status: 404 });
  const status = await Effect.runPromise(joinStatus(env.HYPERDRIVE, own[1]!, await sha256(token)));
  if (!status) return new Response("Not found", { status: 404 });
  if (!cookieRequest) return respond(JoinStatus, { status });
  if (status !== "allowed") return new Response("Not allowed", { status: 403 });
  return Response.json({ signed_in: true }, { headers: { "set-cookie": cookie(token) } });
}

/** `GET /api/joins` for a signed-in device: who is asking to join now. */
export async function waitingJoinsRoute(env: { HYPERDRIVE: Database }) {
  const rows = await Effect.runPromise(waitingJoins(env.HYPERDRIVE));
  return respond(JoinRequests, { joins: await Promise.all(rows.map(asRequest)) });
}

/**
 * A signed-in person's devices: list them, sign one out, or make a one-time link that signs a
 * browser in as them (the Mac app's "Open in browser").
 */
export async function devicesRoute(
  request: Request,
  env: { HYPERDRIVE: Database },
  access: { personId: string; device: string; trusted: boolean; path: string },
) {
  if (access.path === "/api/devices" && request.method === "GET")
    return respond(DeviceList, {
      devices: (await Effect.runPromise(devices(env.HYPERDRIVE, access.personId))).map(
        (device) => ({ ...device, current: device.id === access.device }),
      ),
    });
  if (request.method !== "POST") return new Response("Not found", { status: 404 });
  if (!access.trusted) return new Response("Forbidden", { status: 403 });
  if (access.path === "/api/devices/link") {
    const token = randomToken();
    await Effect.runPromise(issueLink(env.HYPERDRIVE, access.personId, await sha256(token)));
    return respond(
      SignInLink,
      { token, expires_at: new Date(Date.now() + 10 * 60_000).toISOString() },
      { status: 201 },
    );
  }
  const id = /^\/api\/devices\/([a-f0-9]{16})\/revoke$/.exec(access.path)?.[1];
  if (!id) return new Response("Not found", { status: 404 });
  const removed = await Effect.runPromise(revokeDevice(env.HYPERDRIVE, access.personId, id));
  return removed ? Response.json({ revoked: true }) : new Response("Not found", { status: 404 });
}
