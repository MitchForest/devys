import { Effect } from "effect";
import type { Env } from "../../infra/api.ts";
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
  isMachineOwner,
  memberBusiness,
} from "../identity/service.ts";
import { atomically } from "../data/database.ts";
import { onTheMac } from "./runner.ts";
import { readBounded } from "../protocol/bytes.ts";
import { sameOrigin } from "../protocol/http.ts";
import { grantAll } from "../authority/service.ts";
import { hire, hireInput, roleTemplate, roleTemplates, templateGrants } from "./team.ts";
import { capabilities } from "./capabilities.ts";
import { businessRoute } from "./routes.ts";
import { delegateEventsRoute } from "./delegates.ts";
import { modelCatalog } from "./models.ts";
import { modelsConfig } from "../../config/models.ts";

/** Webhooks and the API. Page rendering stays in the Worker entry. Undefined means "not an API path". */
export async function apiRoute(request: Request, env: Env): Promise<Response | undefined> {
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
  if (path === "/internal/delegates/events" && request.method === "POST")
    return delegateEventsRoute(request, env);
  if (path === "/api/enroll" && request.method === "POST") return enroll(request, env);
  if (path === "/api/native/session" && request.method === "POST")
    return enrollDevice(request, env);
  if (path === "/api/logout" && request.method === "POST") return logout(request, env);
  if (!path.startsWith("/api/")) return undefined;
  const access = await requestPerson(request, env);
  if (!access) return new Response("Sign in required", { status: 401 });
  const { person } = access;
  const trusted = access.bearer || sameOrigin(request);
  if (path === "/api/models" && request.method === "GET") return Response.json(modelCatalog());
  if (path === "/api/roles" && request.method === "GET")
    return Response.json({
      roles: roleTemplates
        .filter((template) => template.id !== "operations")
        .map(({ id, name, summary, responsibilities, capabilities: granted }) => ({
          id,
          name,
          summary,
          responsibilities,
          capabilities:
            granted === "all" ? capabilities(env).map((contract) => contract.name) : granted,
        })),
    });
  if (path === "/api/devices" || path.startsWith("/api/devices/"))
    return devicesRoute(request, env, {
      personId: person.id,
      device: access.device,
      trusted,
      path,
    });
  if (path === "/api/me" && request.method === "GET")
    return Response.json({
      person,
      businesses: await Effect.runPromise(businessesFor(env.HYPERDRIVE, person.id)),
    });
  if (path === "/api/businesses" && request.method === "POST") {
    if (!trusted) return new Response("Forbidden", { status: 403 });
    if (onTheMac(env) && !(await Effect.runPromise(isMachineOwner(env.HYPERDRIVE, person.id))))
      return new Response("On a Mac in local mode only its owner creates businesses", {
        status: 403,
      });
    const body = JSON.parse(new TextDecoder().decode(await readBounded(request.body, 8_000))) as {
      name?: unknown;
      brief?: unknown;
      team?: unknown;
    };
    const name = typeof body.name === "string" ? body.name.trim() : "";
    if (!name || name.length > 80) return new Response("Send a business name", { status: 400 });
    const brief = typeof body.brief === "string" ? body.brief.trim().slice(0, 4000) : "";
    // The starting team: templates hired alongside the Head of Operations.
    const team = Array.isArray(body.team) ? body.team.map(roleTemplate) : [];
    if (
      team.some((template) => !template || template.id === "operations" || template.id === "custom")
    )
      return new Response("The starting team takes engineering, growth or business-operations", {
        status: 400,
      });
    const operations = roleTemplate("operations")!;
    const catalog = capabilities(env);
    // The business, its Head of Operations, their grants and the starting team, or nothing.
    const { created, hired } = await atomically(env.HYPERDRIVE, async (db) => {
      const created = await Effect.runPromise(
        createBusiness(db, person.id, {
          name,
          brief,
          model: modelsConfig.defaults.employee,
          operations: { name: operations.name, role: operations.responsibilities },
        }),
      );
      await Effect.runPromise(
        grantAll(
          db,
          { businessId: created.business.id, employeeId: created.operations.id },
          templateGrants(operations, catalog),
        ),
      );
      const hired = [];
      for (const template of team) {
        const input = hireInput({ template: template!.id });
        if (typeof input !== "string")
          hired.push(await hire(db, created.business.id, input, catalog));
      }
      return { created, hired };
    });
    return Response.json({ ...created, team: hired }, { status: 201 });
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
