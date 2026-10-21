import { Effect, Schema } from "effect";
import type { Database } from "../data/database.ts";
import {
  deleteSession,
  devices,
  issueDeviceCode,
  redeemEnrollment,
  revokeDevice,
  sessionPerson,
} from "./sessions.ts";
import { sha256, readBounded } from "../protocol/bytes.ts";
import { respond, sameOrigin } from "../protocol/http.ts";
import { DeviceCode, DeviceList, sessionCookie } from "./contract.ts";

/** `POST /api/native/session`: a device session for an app, returned in the body. */
export const DeviceSession = Schema.Struct({
  session_token: Schema.String,
  expires_in_seconds: Schema.Number,
});

// Lax permits the Google OAuth callback; every browser mutation also checks Origin.
export const cookie = (token: string, age = 60 * 60 * 24 * 7) =>
  `${sessionCookie}=${token}; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=${age}`;

const tokenPattern = /^[a-f0-9]{64}$/;

function cookieToken(request: Request) {
  return request.headers
    .get("cookie")
    ?.split(";")
    .map((value) => value.trim())
    .find((value) => value.startsWith(`${sessionCookie}=`))
    ?.slice(sessionCookie.length + 1);
}

/**
 * Native clients present `Authorization: Bearer`; browsers present the session cookie.
 * A request carrying an Authorization header is judged on it alone, never on a cookie.
 * Bearer requests cannot be forged cross-site, so they skip the browser Origin check.
 */
/** 32 random bytes as hex: a session token or a one-use code. */
const randomToken = () =>
  crypto
    .getRandomValues(new Uint8Array(32))
    .reduce((text, byte) => text + byte.toString(16).padStart(2, "0"), "");

export async function requestPerson(request: Request, env: { HYPERDRIVE: Database }) {
  const authorization = request.headers.get("authorization");
  const bearer = authorization !== null;
  const token = bearer ? /^Bearer ([a-f0-9]{64})$/.exec(authorization)?.[1] : cookieToken(request);
  if (!token || !tokenPattern.test(token)) return;
  const sessionHash = await sha256(token);
  const person = await Effect.runPromise(sessionPerson(env.HYPERDRIVE, sessionHash));
  return person ? { person, bearer, device: sessionHash.slice(0, 16) } : undefined;
}

async function redeem(request: Request, env: { HYPERDRIVE: Database }, fallbackLabel: string) {
  const body = JSON.parse(new TextDecoder().decode(await readBounded(request.body, 2_000))) as {
    token?: unknown;
    name?: unknown;
  };
  if (typeof body.token !== "string" || !tokenPattern.test(body.token)) return "invalid";
  const label =
    typeof body.name === "string" && body.name.trim()
      ? body.name.trim().slice(0, 80)
      : fallbackLabel;
  const session = randomToken();
  const redeemed = await Effect.runPromise(
    redeemEnrollment(env.HYPERDRIVE, await sha256(body.token), await sha256(session), label),
  );
  return redeemed ? session : "expired";
}

/** Exchanges a one-time enrollment code for a device session returned in the body. */
export async function enrollDevice(request: Request, env: { HYPERDRIVE: Database }) {
  const session = await redeem(request, env, "Device");
  if (session === "invalid") return new Response("Invalid enrollment token", { status: 400 });
  if (session === "expired") return new Response("Token expired or already used", { status: 401 });
  return respond(DeviceSession, { session_token: session, expires_in_seconds: 60 * 60 * 24 * 7 });
}

export async function enroll(request: Request, env: { HYPERDRIVE: Database }) {
  if (!sameOrigin(request)) return new Response("Forbidden", { status: 403 });
  const session = await redeem(request, env, "Web browser");
  if (session === "invalid") return new Response("Invalid enrollment token", { status: 400 });
  if (session === "expired") return new Response("Token expired or already used", { status: 401 });
  return Response.json({ enrolled: true }, { headers: { "set-cookie": cookie(session) } });
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

/**
 * A signed-in person's devices: list them, sign one out, or issue a code that signs in
 * another device (shown by the apps as a QR code and a `devys://enroll` link).
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
  if (access.path === "/api/devices/codes") {
    const code = randomToken();
    await Effect.runPromise(issueDeviceCode(env.HYPERDRIVE, access.personId, await sha256(code)));
    return respond(
      DeviceCode,
      { code, expires_at: new Date(Date.now() + 10 * 60_000).toISOString() },
      { status: 201 },
    );
  }
  const id = /^\/api\/devices\/([a-f0-9]{16})\/revoke$/.exec(access.path)?.[1];
  if (!id) return new Response("Not found", { status: 404 });
  const removed = await Effect.runPromise(revokeDevice(env.HYPERDRIVE, access.personId, id));
  return removed ? Response.json({ revoked: true }) : new Response("Not found", { status: 404 });
}
