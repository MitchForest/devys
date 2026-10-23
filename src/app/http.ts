import { Effect } from "effect";
import type { Env } from "./env.ts";
import { addressOf } from "../channels/contract.ts";
import { authenticatePhoton } from "../channels/photon.ts";
import { finishGoogle } from "../connections/google.ts";
import { NameChange, scopeName } from "../identity/contract.ts";
import {
  devicesRoute,
  hello,
  joinRoute,
  localSession,
  logout,
  redeemSignInLink,
  requestPerson,
  waitingJoinsRoute,
} from "../identity/http.ts";
import { answerJoinRoute } from "./joining.ts";
import { profilePhoto } from "../identity/profile.ts";
import {
  businessesFor,
  channelBinding,
  createBusiness,
  memberBusiness,
  renamePerson,
} from "../identity/service.ts";
import { atomically } from "../data/database.ts";
import { defaultApps } from "./apps.ts";
import { install } from "../apps/service.ts";
import { modeOf } from "./mode.ts";
import { body, decodedBody, RequestError } from "./request.ts";
import { Unavailable } from "../protocol/host.ts";
import { respond, sameOrigin } from "../protocol/http.ts";
import { BusinessCreated, Me, ModelCatalog, Roles } from "./wire.ts";
import { grantAll } from "../authority/service.ts";
import { hire, hireInput, roleTemplate } from "../identity/team.ts";
import { hireableRoleIds } from "../protocol/roles.ts";
import { hiring, templateGrants } from "./team.ts";
import { capabilities } from "./capabilities.ts";
import { businessRoute } from "./routes.ts";
import { codingEventsRoute } from "./coding.ts";
import { deviceKeysRoute, signedOut } from "./asking.ts";
import { modelCatalog } from "./models.ts";
import { modelsConfig } from "../../config/models.ts";
import { connectionVault } from "./vault.ts";
import { callbackPath, finishConnect } from "./remote-apps.ts";

/** Webhooks and the API. Page rendering stays in the Worker entry. Undefined means "not an API path". */
export async function apiRoute(request: Request, env: Env): Promise<Response | undefined> {
  try {
    return await route(request, env);
  } catch (error) {
    if (error instanceof RequestError) return new Response(error.message, { status: error.status });
    if (error instanceof Unavailable) return new Response(error.message, { status: 503 });
    throw error;
  }
}

async function route(request: Request, env: Env): Promise<Response | undefined> {
  const path = new URL(request.url).pathname;
  if (path === "/health") return Response.json({ status: "ok" });
  if (path === "/webhooks/photon" && request.method === "POST") {
    const input = await authenticatePhoton(request, env.PHOTON_WEBHOOK_SECRET);
    if (!input) return new Response(null, { status: 204 });
    const binding = await Effect.runPromise(
      channelBinding(env.HYPERDRIVE, "imessage", input.senderId, addressOf(input.chatId)),
    );
    if (!binding) return new Response(null, { status: 204 });
    const scope = { businessId: binding.businessId, employeeId: binding.employeeId };
    await env.AGENT.getByName(scopeName(scope)).receive(scope, input);
    return new Response(null, { status: 204 });
  }
  if (path === "/internal/coding/events" && request.method === "POST")
    return codingEventsRoute(request, env);
  // Signing in (.docs/AUTHORITY.md "Signing in"): the Mac app as the Mac's owner, a browser with
  // a one-time link, and any other device by asking to join.
  if (path === "/api/hello" && request.method === "GET")
    return hello(env.DEVYS_MACHINE_NAME || "Devys", env.PUBLIC_URL || new URL(request.url).origin);
  if (path === "/api/local/session" && request.method === "POST")
    return localSession(request, env, (key) => modeOf(env).isOwnerKey(key));
  if (path === "/api/link" && request.method === "POST") return redeemSignInLink(request, env);
  const joining = await joinRoute(request, env, path);
  if (joining) return joining;
  if (path === "/api/logout" && request.method === "POST") {
    // A signed-out device's signing key stops signing.
    const leaving = await requestPerson(request, env);
    const response = await logout(request, env);
    if (leaving && response.ok) await signedOut(env, leaving.person.id, leaving.device);
    return response;
  }
  if (!path.startsWith("/api/")) return undefined;
  // A provider sends the owner back from signing in to a remote app: the state, not a session,
  // names the business (the native sign-in sheet has no Devys session).
  if (path === callbackPath && request.method === "GET") return finishConnect(request, env);
  const access = await requestPerson(request, env);
  if (!access) return new Response("Sign in required", { status: 401 });
  const { person } = access;
  const trusted = access.bearer || sameOrigin(request);
  if (path === "/api/models" && request.method === "GET")
    return respond(ModelCatalog, modelCatalog());
  if (path === "/api/roles" && request.method === "GET")
    return respond(Roles, {
      roles: hireableRoleIds.map((id) => {
        const { name, summary, responsibilities } = roleTemplate(id)!;
        return {
          id,
          name,
          summary,
          responsibilities,
          capabilities: templateGrants(id, capabilities(env)).map(
            (granted) => granted.capability.name,
          ),
        };
      }),
    });
  if (path === "/api/joins" && request.method === "GET") return waitingJoinsRoute(env);
  if (path.startsWith("/api/joins/"))
    return answerJoinRoute(request, env, { personId: person.id, trusted, path });
  if (path === "/api/devices" || path.startsWith("/api/devices/")) {
    const response = await devicesRoute(request, env, {
      personId: person.id,
      device: access.device,
      trusted,
      path,
    });
    const revoked = /^\/api\/devices\/([a-f0-9]{16})\/revoke$/.exec(path)?.[1];
    if (revoked && response.ok) await signedOut(env, person.id, revoked);
    return response;
  }
  if (path === "/api/device-keys" || path.startsWith("/api/device-keys/"))
    return deviceKeysRoute(request, env, {
      personId: person.id,
      device: access.device,
      bearer: access.bearer,
      trusted,
      path,
    });
  if (path === "/api/me" && (request.method === "GET" || request.method === "PUT")) {
    if (request.method === "PUT" && !trusted) return new Response("Forbidden", { status: 403 });
    const renamed =
      request.method === "PUT"
        ? await Effect.runPromise(
            renamePerson(
              env.HYPERDRIVE,
              person.id,
              (await decodedBody(request, 2_000, NameChange)).display_name,
            ),
          )
        : undefined;
    return respond(Me, {
      person: renamed ?? person,
      businesses: await Effect.runPromise(businessesFor(env.HYPERDRIVE, person.id)),
    });
  }
  if (path === "/api/businesses" && request.method === "POST") {
    if (!trusted) return new Response("Forbidden", { status: 403 });
    if (!(await modeOf(env).mayUseMachine(person.id)))
      return new Response("On a Mac in local mode only its owner creates businesses", {
        status: 403,
      });
    const input = await body<{ name: unknown; brief: unknown; team: unknown }>(request, 8_000);
    const name = typeof input.name === "string" ? input.name.trim() : "";
    if (!name || name.length > 80) return new Response("Send a business name", { status: 400 });
    const brief = typeof input.brief === "string" ? input.brief.trim().slice(0, 4000) : "";
    // The starting team: templates hired alongside the Chief of Staff.
    const team = Array.isArray(input.team) ? input.team.map(roleTemplate) : [];
    if (
      team.some(
        (template) => !template || template.id === "chief-of-staff" || template.id === "custom",
      )
    )
      return new Response("The starting team takes admin, finance, growth or engineering", {
        status: 400,
      });
    const chiefOfStaff = roleTemplate("chief-of-staff")!;
    const catalog = capabilities(env);
    const hirer = hiring(() => catalog);
    // The business, its Chief of Staff, their grants and the starting team, or nothing.
    const { created, hired } = await atomically(env.HYPERDRIVE, async (db) => {
      const created = await Effect.runPromise(
        createBusiness(db, person.id, {
          name,
          brief,
          model: modelsConfig.defaults.employee,
          chiefOfStaff: {
            name: chiefOfStaff.name,
            responsibilities: chiefOfStaff.responsibilities,
          },
        }),
      );
      await Effect.runPromise(
        grantAll(
          db,
          { businessId: created.business.id, employeeId: created.chiefOfStaff.id },
          templateGrants(chiefOfStaff.id, catalog),
        ),
      );
      await Effect.runPromise(install(db, created.business.id, defaultApps));
      const hired = [];
      for (const template of team) {
        const input = hireInput({ template: template!.id }, hirer);
        if (typeof input !== "string")
          hired.push(await hire(db, created.business.id, input, hirer));
      }
      return { created, hired };
    });
    return respond(
      BusinessCreated,
      { business: created.business, chief_of_staff: created.chiefOfStaff, team: hired },
      { status: 201 },
    );
  }
  if (path === "/api/connections/google/callback" && request.method === "GET")
    return finishGoogle(request, env, connectionVault(env), person.id, async (businessId) =>
      Boolean(await Effect.runPromise(memberBusiness(env.HYPERDRIVE, person.id, businessId))),
    );
  if (path === "/api/profile/photo") {
    if (request.method !== "GET" && !trusted) return new Response("Forbidden", { status: 403 });
    return profilePhoto(request, env, person.id);
  }
  const scoped = /^\/api\/businesses\/([A-Za-z0-9-]{1,64})(\/.*)?$/.exec(path);
  if (scoped) {
    // Membership decides access; a business the person cannot see does not exist for them.
    const business = await Effect.runPromise(memberBusiness(env.HYPERDRIVE, person.id, scoped[1]!));
    if (!business) return new Response("Not found", { status: 404 });
    return businessRoute(request, env, { person, business, trusted, path: scoped[2] ?? "" });
  }
  return new Response("Not found", { status: 404 });
}
