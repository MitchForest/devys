import { Effect } from "effect";
import type { Env } from "./env.ts";
import { listArtifacts } from "../apps/documents/service.ts";
import { artifactDownload, artifactPath } from "./artifacts.ts";
import { Employee, type Business, type Person } from "../identity/contract.ts";
import {
  activeEmployee,
  employeesOf,
  membersOf,
  setBusinessLook,
  updateBusiness,
} from "../identity/service.ts";
import { memoryRoute } from "../memory/http.ts";
import { modeOf } from "./mode.ts";
import { capabilities } from "./capabilities.ts";
import { browserRoute } from "./browser-route.ts";
import { codingRoute } from "./coding.ts";
import { terminalRoute } from "./terminals.ts";
import { filesRoute } from "./files.ts";
import { exportBusiness } from "./export.ts";
import { memoryFor } from "./memory.ts";
import { hire, hireInput } from "../identity/team.ts";
import { hiring } from "./team.ts";
import { body, forbidden, label, notFound } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { BusinessDetail, BusinessUpdated } from "./wire.ts";
import { employeeRoute, lookRoute } from "./employees.ts";
import { decisionRoute, workRoute } from "./work.ts";
import { projectRoute } from "./projects.ts";
import { appsRoute } from "./apps.ts";
import { homeRoute } from "./home.ts";
import { googleRoute } from "./google-route.ts";
import { conversationRoute } from "./conversation-route.ts";

/** Routes under /api/businesses/:id. The caller is a verified member of `business`. */
export async function businessRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
): Promise<Response> {
  const { person, business, trusted, path } = access;
  const method = request.method;
  if (path === "" && method === "GET") {
    const [employees, members, artifacts] = await Promise.all([
      Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id)),
      Effect.runPromise(membersOf(env.HYPERDRIVE, business.id)),
      Effect.runPromise(listArtifacts(env.HYPERDRIVE, business.id)),
    ]);
    return respond(BusinessDetail, { business, employees, members, artifacts });
  }
  if (path === "" && method === "PUT") {
    if (!trusted) return forbidden();
    const input = await body<{ name: string; brief: string }>(request, 8_000);
    const name = input.name === undefined ? undefined : label(input.name, 80);
    if (input.name !== undefined && !name)
      return new Response("Send a business name", { status: 400 });
    const brief = typeof input.brief === "string" ? input.brief.trim().slice(0, 4000) : undefined;
    await Effect.runPromise(
      updateBusiness(env.HYPERDRIVE, business.id, {
        ...(name ? { name } : {}),
        ...(brief !== undefined ? { brief } : {}),
      }),
    );
    return respond(BusinessUpdated, {
      business: {
        ...business,
        ...(name ? { name } : {}),
        ...(brief !== undefined ? { brief } : {}),
      },
    });
  }
  if (path === "/look" || path === "/look/photo")
    return lookRoute(
      request,
      env,
      { trusted, path, businessId: business.id, subject: "business" },
      (look) => setBusinessLook(env.HYPERDRIVE, business.id, look),
    );
  if (path === "/employees" && method === "POST") {
    if (!trusted) return forbidden();
    const input = await body<{
      template: string;
      name: string;
      responsibilities: string;
      model: string;
    }>(request, 8_000);
    const team = hiring(() => capabilities(env));
    const hireable = hireInput(input, team);
    if (typeof hireable === "string") return new Response(hireable, { status: 400 });
    return respond(Employee, await hire(env.HYPERDRIVE, business.id, hireable, team), {
      status: 201,
    });
  }
  if (path === "/export" && method === "GET")
    return exportBusiness(
      env,
      business,
      await Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id)),
    );
  if (path === "/memory" || path.startsWith("/memory/"))
    return memoryRoute(
      request,
      business.id,
      path.slice("/memory".length),
      (id) => memoryFor(env, id),
      trusted,
    );
  if (path.startsWith("/connections/google")) return googleRoute(request, env, access);
  // Coding, terminals, files and the browser run on the Mac as its owner.
  if (
    /^\/(coding|terminals|files|browser)(\/|$)|^\/work\/[^/]+\/sessions/.test(path) &&
    !(await modeOf(env).mayUseMachine(person.id))
  )
    return forbidden();
  const browsing = await browserRoute(request, env, access);
  if (browsing) return browsing;
  const coding = await codingRoute(request, env, access);
  if (coding) return coding;
  const terminal = await terminalRoute(request, env, access);
  if (terminal) return terminal;
  const file = await filesRoute(request, env, access);
  if (file) return file;
  if (path === "/work" || path.startsWith("/work/")) return workRoute(request, env, access);
  if (path === "/decisions" || path.startsWith("/decisions/"))
    return decisionRoute(request, env, access);
  if (path === "/projects" || path.startsWith("/projects/"))
    return projectRoute(request, env, access);
  if (path === "/apps" || path.startsWith("/apps/")) return appsRoute(request, env, access);
  if (path === "/home" && method === "GET") return homeRoute(env, access);
  if (path === "/conversations" || path.startsWith("/conversations/"))
    return conversationRoute(request, env, access);
  const artifactId = artifactPath.exec(path)?.[1];
  if (artifactId && method === "GET") return artifactDownload(env, business.id, artifactId);
  const employee = /^\/employees\/([A-Za-z0-9-]{1,64})(\/.*)$/.exec(path);
  if (employee) {
    const scope = { businessId: business.id, employeeId: employee[1]! };
    const record = await Effect.runPromise(activeEmployee(env.HYPERDRIVE, scope));
    if (!record) return notFound();
    return employeeRoute(request, env, {
      person,
      scope,
      record,
      paused: record.paused,
      trusted,
      path: employee[2]!,
    });
  }
  return notFound();
}
