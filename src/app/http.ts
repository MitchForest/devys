import { Effect } from "effect";
import type { Env } from "./env.ts";
import { addressOf } from "../channels/contract.ts";
import { authenticatePhoton } from "../channels/photon.ts";
import { finishGoogle } from "../connections/google.ts";
import { scopeName } from "../identity/contract.ts";
import { devicesRoute, enroll, enrollDevice, logout, requestPerson } from "../identity/http.ts";
import { profilePhoto } from "../identity/profile.ts";
import {
  businessesFor,
  channelBinding,
  createBusiness,
  memberBusiness,
} from "../identity/service.ts";
import { atomically } from "../data/database.ts";
import { defaultApps } from "./apps.ts";
import { install } from "../apps/service.ts";
import { modeOf } from "./mode.ts";
import { body, RequestError } from "./request.ts";
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
import { modelCatalog } from "./models.ts";
import { modelsConfig } from "../../config/models.ts";

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
  if (path === "/api/enroll" && request.method === "POST") return enroll(request, env);
  if (path === "/api/native/session" && request.method === "POST")
    return enrollDevice(request, env);
  if (path === "/api/logout" && request.method === "POST") return logout(request, env);
  if (!path.startsWith("/api/")) return undefined;
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
  if (path === "/api/devices" || path.startsWith("/api/devices/"))
    return devicesRoute(request, env, {
      personId: person.id,
      device: access.device,
      trusted,
      path,
    });
  if (path === "/api/me" && request.method === "GET")
    return respond(Me, {
      person,
      businesses: await Effect.runPromise(businessesFor(env.HYPERDRIVE, person.id)),
    });
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
    // The starting team: templates hired alongside the Head of Operations.
    const team = Array.isArray(input.team) ? input.team.map(roleTemplate) : [];
    if (
      team.some((template) => !template || template.id === "operations" || template.id === "custom")
    )
      return new Response("The starting team takes engineering, growth or business-operations", {
        status: 400,
      });
    const operations = roleTemplate("operations")!;
    const catalog = capabilities(env);
    const hirer = hiring(() => catalog);
    // The business, its Head of Operations, their grants and the starting team, or nothing.
    const { created, hired } = await atomically(env.HYPERDRIVE, async (db) => {
      const created = await Effect.runPromise(
        createBusiness(db, person.id, {
          name,
          brief,
          model: modelsConfig.defaults.employee,
          operations: { name: operations.name, responsibilities: operations.responsibilities },
        }),
      );
      await Effect.runPromise(
        grantAll(
          db,
          { businessId: created.business.id, employeeId: created.operations.id },
          templateGrants(operations.id, catalog),
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
    return respond(BusinessCreated, { ...created, team: hired }, { status: 201 });
  }
  if (path === "/api/connections/google/callback" && request.method === "GET")
    return finishGoogle(request, env, person.id, async (businessId) =>
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
