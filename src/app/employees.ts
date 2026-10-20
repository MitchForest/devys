import { Effect } from "effect";
import type { Env } from "./env.ts";
import { setAppReaction } from "../channels/app.ts";
import { scopeName, type Employee, type Person, type Scope } from "../identity/contract.ts";
import {
  activeEmployee,
  bindChannel,
  retireEmployee,
  updateEmployee,
  setEmployeeLook,
  setEmployeeModel,
  setPaused,
} from "../identity/service.ts";
import { lookPhoto, parseLook, removeLookPhoto } from "../identity/looks.ts";
import type { Look } from "../identity/contract.ts";
import { atomically } from "../data/database.ts";
import { grant, grantsFor, revokeGrant } from "../authority/service.ts";
import { reassignOpen } from "../work/service.ts";
import type { Mode } from "../authority/contract.ts";
import { bindableChannels, type BindableChannel } from "./channel.ts";
import { capabilities } from "./capabilities.ts";
import { isConfiguredModel } from "./models.ts";
import { body, forbidden, label, notFound } from "./request.ts";

/** What a chat address looks like on each bindable channel. */
const validAddress: Record<BindableChannel, (chat: string) => boolean> = {
  // Photon's canonical direct-chat GUID.
  imessage: (chat) => /^any;-;.+$/.test(chat),
};

/** Routes under /api/businesses/:id/employees/:eid, for an active employee of that business. */
export async function employeeRoute(
  request: Request,
  env: Env,
  access: {
    person: Person;
    scope: Scope;
    record: Employee;
    paused: boolean;
    trusted: boolean;
    path: string;
  },
): Promise<Response> {
  const { person, scope, record, trusted, path } = access;
  const agent = () => env.AGENT.getByName(scopeName(scope));
  if (path === "/look" || path === "/look/photo")
    return lookRoute(
      request,
      env,
      { trusted, path, businessId: scope.businessId, subject: scope.employeeId },
      (look) => setEmployeeLook(env.HYPERDRIVE, scope, look),
    );
  if (path === "/profile" && request.method === "PUT") {
    if (!trusted) return forbidden();
    const input = await body<{ name: string; responsibilities: string }>(request, 8_000);
    const name = input.name === undefined ? undefined : label(input.name, 80);
    const role =
      input.responsibilities === undefined ? undefined : label(input.responsibilities, 2000);
    if ((input.name !== undefined && !name) || (input.responsibilities !== undefined && !role))
      return new Response("Send a name of up to 80 and responsibilities of up to 2000 characters", {
        status: 400,
      });
    await Effect.runPromise(
      updateEmployee(env.HYPERDRIVE, scope, {
        ...(name ? { name } : {}),
        ...(role ? { role } : {}),
      }),
    );
    return Response.json({ ...(name ? { name } : {}), ...(role ? { role } : {}) });
  }
  if (path === "/retire" && request.method === "POST") {
    if (!trusted) return forbidden();
    const { reassignTo } = await body<{ reassignTo: string }>(request, 1_000);
    const successor =
      typeof reassignTo === "string" && reassignTo !== scope.employeeId
        ? await Effect.runPromise(
            activeEmployee(env.HYPERDRIVE, {
              businessId: scope.businessId,
              employeeId: reassignTo,
            }),
          )
        : undefined;
    if (!successor)
      return new Response("Choose another employee to take over the open work", { status: 400 });
    if (record.template === "operations")
      return new Response("The Head of Operations can't be retired", { status: 409 });
    // Retire and hand the work over together: a retired employee must never hold open work.
    await atomically(env.HYPERDRIVE, async (db) => {
      await Effect.runPromise(retireEmployee(db, scope));
      await Effect.runPromise(reassignOpen(db, scope.businessId, scope.employeeId, successor.id));
    });
    await agent().stop(scope);
    return Response.json({ retired: true, reassignedTo: successor.id });
  }
  if (path === "/model" && request.method === "PUT") {
    if (!trusted) return forbidden();
    const { model } = await body<{ model: string }>(request, 1_000);
    if (!isConfiguredModel(model))
      return new Response("Choose a configured model", { status: 400 });
    await Effect.runPromise(setEmployeeModel(env.HYPERDRIVE, scope, model));
    return Response.json({ model });
  }
  if (path === "/status" && request.method === "GET")
    return Response.json({ state: JSON.parse(await agent().inspect(scope)) });
  if (path === "/stop" && request.method === "POST")
    return trusted ? Response.json(await agent().stop(scope)) : forbidden();
  if ((path === "/pause" || path === "/resume") && request.method === "POST") {
    if (!trusted) return forbidden();
    const pausing = path === "/pause";
    await Effect.runPromise(setPaused(env.HYPERDRIVE, scope, pausing));
    // Pausing also stops work already running; the fence stops anything after it.
    if (pausing) await agent().stop(scope);
    return Response.json({ paused: pausing });
  }
  if (path === "/access" || path.startsWith("/access/")) return accessRoute(request, env, access);
  if (path === "/channels" && request.method === "POST") {
    if (!trusted) return forbidden();
    const input = await body<{ channel: string; sender: string; chat: string }>(request, 2_000);
    const channel = bindableChannels.find((id) => id === input.channel);
    const sender = label(input.sender, 200);
    const chat = label(input.chat, 512);
    if (!channel || !sender || !chat || !validAddress[channel](chat))
      return new Response(
        `Send a channel (${bindableChannels.join(", ")}), the sender and the chat address`,
        { status: 400 },
      );
    try {
      await Effect.runPromise(
        bindChannel(env.HYPERDRIVE, { channel, personId: person.id, scope, sender, chat }),
      );
    } catch {
      return new Response("That chat is already bound elsewhere", { status: 409 });
    }
    return Response.json({ bound: true });
  }
  if (path === "/reactions" && request.method === "POST") {
    if (!trusted) return forbidden();
    const input = await body<{ targetId: string; targetText: string; emoji: string; on: boolean }>(
      request,
      4_000,
    );
    if (
      typeof input.targetId !== "string" ||
      !/^pi-\d{1,15}$/.test(input.targetId) ||
      typeof input.targetText !== "string" ||
      typeof input.emoji !== "string" ||
      !input.emoji ||
      [...input.emoji].length > 8 ||
      typeof input.on !== "boolean"
    )
      return new Response("Send a target, its text, an emoji and on", { status: 400 });
    await Effect.runPromise(
      setAppReaction(env.HYPERDRIVE, scope, {
        targetId: input.targetId,
        targetText: input.targetText,
        emoji: input.emoji,
        on: input.on,
      }),
    );
    return new Response(null, { status: 204 });
  }
  return notFound();
}

/** `/look` sets a Face or emoji (or null for the default); `/look/photo` uploads or reads a photo. */
export async function lookRoute(
  request: Request,
  env: Env,
  target: { trusted: boolean; path: string; businessId: string; subject: string },
  save: (look: Look | null) => Effect.Effect<unknown, unknown>,
): Promise<Response> {
  const { trusted, path, businessId, subject } = target;
  if (request.method !== "GET" && !trusted) return forbidden();
  if (path === "/look/photo") {
    const result = await lookPhoto(request, env, businessId, subject);
    if (result instanceof Response) return result;
    await Effect.runPromise(save(result));
    return Response.json({ look: result });
  }
  if (request.method !== "POST") return notFound();
  const look = parseLook((await body<{ look: unknown }>(request, 2_000)).look);
  if (look === undefined) return new Response("Send a Face, an emoji or null", { status: 400 });
  await Effect.runPromise(save(look));
  await removeLookPhoto(env, businessId, subject);
  return Response.json({ look });
}

/** What an employee may do: its grants, and the capabilities it could be granted. */
async function accessRoute(
  request: Request,
  env: Env,
  access: { scope: Scope; trusted: boolean; path: string },
) {
  const { scope, trusted, path } = access;
  const catalog = capabilities(env);
  const describe = (name: string) => {
    const contract = catalog.find((item) => item.name === name);
    return contract
      ? {
          description: contract.description,
          effect: contract.effect,
          limits: Boolean(contract.constraints),
        }
      : undefined;
  };
  if (path === "/access" && request.method === "GET") {
    const grants = await Effect.runPromise(grantsFor(env.HYPERDRIVE, scope));
    const held = new Set(grants.map((item) => item.capability));
    return Response.json({
      grants: grants.map((item) => ({ ...item, ...describe(item.capability) })),
      available: catalog
        .filter((item) => !held.has(item.name))
        .map((item) => ({ capability: item.name, ...describe(item.name) })),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (path === "/access") {
    const input = await body<{
      capability: string;
      mode: Mode;
      constraints: Record<string, unknown>;
    }>(request, 8_000);
    const contract = catalog.find((item) => item.name === input.capability);
    if (!contract || (input.mode !== "auto" && input.mode !== "ask"))
      return new Response("Send a known capability and a mode of auto or ask", { status: 400 });
    if (
      input.constraints !== undefined &&
      (typeof input.constraints !== "object" || input.constraints === null)
    )
      return new Response("Limits must be an object", { status: 400 });
    try {
      return Response.json(
        await Effect.runPromise(
          grant(env.HYPERDRIVE, scope, {
            capability: contract,
            mode: input.mode,
            ...(input.constraints ? { constraints: input.constraints } : {}),
          }),
        ),
        { status: 201 },
      );
    } catch {
      return new Response(`Those limits don't fit ${contract.name}`, { status: 400 });
    }
  }
  const revoke = /^\/access\/([A-Za-z0-9-]{1,64})\/revoke$/.exec(path)?.[1];
  if (revoke) {
    const changed = await Effect.runPromise(revokeGrant(env.HYPERDRIVE, scope, revoke));
    return changed ? Response.json({ revoked: true }) : notFound();
  }
  return notFound();
}
