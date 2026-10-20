import { Effect, Schema } from "effect";
import type { Env } from "../../infra/api.ts";
import { artifactLocation, listArtifacts } from "../artifacts/service.ts";
import { appReactions, setAppReaction } from "../channels/app.ts";
import {
  beginGoogle,
  disconnectGoogle,
  googleAccess,
  googleConfigured,
  googleConnectionStatus,
} from "../connections/google.ts";
import { listDrive, selectDrive } from "../connections/drive.ts";
import {
  scopeName,
  type Business,
  type Employee,
  type Person,
  type Scope,
} from "../identity/contract.ts";
import { conversationKey, employeeOf } from "../conversations/contract.ts";
import { conversationSummaries, markSeen } from "../conversations/service.ts";
import { conversationExists, conversationPage, postFromPerson } from "./conversations.ts";
import {
  activeEmployee,
  bindChannel,
  employeesOf,
  retireEmployee,
  updateBusiness,
  updateEmployee,
  setBusinessLook,
  setEmployeeLook,
  setEmployeeModel,
  setPaused,
} from "../identity/service.ts";
import { lookPhoto, parseLook, removeLookPhoto } from "../identity/looks.ts";
import type { Look } from "../identity/contract.ts";
import { memoryRoute } from "../memory/http.ts";
import { readBounded } from "../protocol/bytes.ts";
import {
  answerDecision,
  grant,
  grantsFor,
  pendingDecisions,
  revokeGrant,
} from "../authority/service.ts";
import {
  commitments,
  createCommitment,
  reassignOpen,
  setTakeover,
  updateCommitment,
  type Change,
} from "../work/service.ts";
import type { CommitmentState, SpaceItem } from "../work/contract.ts";
import { addToSpace, createSpace, removeFromSpace, spaces, updateSpace } from "../work/spaces.ts";
import type { Mode } from "../authority/contract.ts";
import { bindableChannels, type BindableChannel } from "./channel.ts";
import { capabilities } from "./capabilities.ts";
import { codingRoute, handBack } from "./coding.ts";
import { terminalRoute } from "./terminals.ts";
import { businessFile, filesRoute } from "./files.ts";
import { exportBusiness } from "./export.ts";
import { memoryFor } from "./memory.ts";
import { isConfiguredModel } from "./models.ts";
import { hire, hireInput } from "./team.ts";

/** What a chat address looks like on each bindable channel. */
const validAddress: Record<BindableChannel, (chat: string) => boolean> = {
  // Photon's canonical direct-chat GUID.
  imessage: (chat) => /^any;-;.+$/.test(chat),
};

const notFound = () => new Response("Not found", { status: 404 });
const forbidden = () => new Response("Forbidden", { status: 403 });
const body = async <T>(request: Request, limit: number) =>
  JSON.parse(new TextDecoder().decode(await readBounded(request.body, limit))) as Partial<T>;
const label = (value: unknown, max: number) =>
  typeof value === "string" && value.trim().length > 0 && value.trim().length <= max
    ? value.trim()
    : undefined;

/** Routes under /api/businesses/:id. The caller is a verified member of `business`. */
export async function businessRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
): Promise<Response> {
  const { person, business, trusted, path } = access;
  const method = request.method;
  if (path === "" && method === "GET") {
    const [employees, artifacts] = await Promise.all([
      Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id)),
      Effect.runPromise(listArtifacts(env.HYPERDRIVE, business.id)),
    ]);
    return Response.json({ business, employees, artifacts });
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
    return Response.json({
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
    const hireable = hireInput(input);
    if (typeof hireable === "string") return new Response(hireable, { status: 400 });
    return Response.json(await hire(env, business.id, hireable, capabilities(env)), {
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
  const coding = await codingRoute(request, env, access);
  if (coding) return coding;
  const terminal = await terminalRoute(request, env, access);
  if (terminal) return terminal;
  const file = await filesRoute(request, env, access);
  if (file) return file;
  if (path === "/work" || path.startsWith("/work/")) return workRoute(request, env, access);
  if (path === "/decisions" || path.startsWith("/decisions/"))
    return decisionRoute(request, env, access);
  if (path === "/spaces" || path.startsWith("/spaces/")) return spaceRoute(request, env, access);
  if (path === "/conversations" || path.startsWith("/conversations/"))
    return conversationRoute(request, env, access);
  const artifactId = /^\/artifacts\/([a-f0-9-]{36})$/.exec(path)?.[1];
  if (artifactId && method === "GET") return artifact(env, business.id, artifactId);
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

/** Routes under /api/businesses/:id/employees/:eid, for an active employee of that business. */
async function employeeRoute(
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
    // Hand the work over first: a retired employee must never hold open work.
    await Effect.runPromise(
      reassignOpen(env.HYPERDRIVE, scope.businessId, scope.employeeId, successor.id),
    );
    await Effect.runPromise(retireEmployee(env.HYPERDRIVE, scope));
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

/** What an employee may do: its grants, and the capabilities it could be granted. */
/** `/look` sets a Face or emoji (or null for the default); `/look/photo` uploads or reads a photo. */
async function lookRoute(
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

const states: CommitmentState[] = [
  "proposed",
  "ready",
  "in_progress",
  "waiting",
  "needs_decision",
  "completed",
  "cancelled",
];
const when = (value: unknown) =>
  typeof value === "string" && Number.isFinite(Date.parse(value))
    ? new Date(value).toISOString()
    : undefined;

/** The business's commitments, operated by its members through the same rules as employees. */
async function workRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/work" && request.method === "GET") {
    const since = when(new URL(request.url).searchParams.get("since"));
    return Response.json({
      commitments: await Effect.runPromise(commitments(env.HYPERDRIVE, business.id, since)),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const isEmployee = async (id: unknown) =>
    typeof id === "string" &&
    Boolean(
      await Effect.runPromise(
        activeEmployee(env.HYPERDRIVE, { businessId: business.id, employeeId: id }),
      ),
    );
  if (path === "/work") {
    const input = await body<{
      title: string;
      owner: string;
      objective: string;
      nextAction: string;
      dueAt: string;
      conditions: Record<string, Record<string, unknown>>;
      spaceId: string;
    }>(request, 16_000);
    const title = label(input.title, 200);
    if (!title || !(await isEmployee(input.owner)))
      return new Response("Send a title and an employee of this business", { status: 400 });
    const conditions = input.conditions ?? {};
    const catalog = capabilities(env);
    for (const [name, values] of Object.entries(conditions)) {
      const contract = catalog.find((item) => item.name === name);
      try {
        if (!contract?.constraints) throw new Error("no limits");
        Schema.decodeUnknownSync(contract.constraints.schema)(values);
      } catch {
        return new Response(`Conditions for ${name} don't fit it`, { status: 400 });
      }
    }
    const created = await Effect.runPromise(
      createCommitment(env.HYPERDRIVE, business.id, {
        owner: input.owner!,
        title,
        ...(typeof input.objective === "string"
          ? { objective: input.objective.slice(0, 4000) }
          : {}),
        ...(typeof input.nextAction === "string"
          ? { nextAction: input.nextAction.slice(0, 1000) }
          : {}),
        ...(when(input.dueAt) ? { dueAt: when(input.dueAt) } : {}),
        conditions,
        createdBy: `person:${person.id}`,
      }),
    );
    // Created from a space, the task is also shown there.
    if (typeof input.spaceId === "string")
      await Effect.runPromise(
        addToSpace(env.HYPERDRIVE, business.id, input.spaceId, {
          kind: "commitment",
          ref: created.id,
        }),
      );
    return Response.json(created, { status: 201 });
  }
  const takeover = /^\/work\/([A-Za-z0-9-]{1,64})\/(takeover|release)$/.exec(path);
  if (takeover) {
    const item = await Effect.runPromise(
      setTakeover(
        env.HYPERDRIVE,
        business.id,
        takeover[1]!,
        takeover[2] === "takeover" ? person.id : null,
      ),
    );
    if (item && takeover[2] === "release") await handBack(env, business.id, item.id);
    return item ? Response.json(item) : notFound();
  }
  const id = /^\/work\/([A-Za-z0-9-]{1,64})$/.exec(path)?.[1];
  if (!id) return notFound();
  const input = await body<{
    expectedRevision: number;
    title: string;
    owner: string;
    state: CommitmentState;
    nextAction: string;
    waitCondition: string | null;
    dueAt: string | null;
  }>(request, 8_000);
  if (!Number.isSafeInteger(input.expectedRevision))
    return new Response("Send the commitment's expectedRevision", { status: 400 });
  if (input.state !== undefined && !states.includes(input.state))
    return new Response("Unknown state", { status: 400 });
  if (input.owner !== undefined && !(await isEmployee(input.owner)))
    return new Response("The owner must be an employee of this business", { status: 400 });
  const change: Change = {
    ...(label(input.title, 200) ? { title: label(input.title, 200) } : {}),
    ...(input.owner ? { owner: input.owner } : {}),
    ...(input.state ? { state: input.state } : {}),
    ...(typeof input.nextAction === "string"
      ? { nextAction: input.nextAction.slice(0, 1000) }
      : {}),
    ...(input.waitCondition !== undefined
      ? { waitCondition: input.waitCondition?.slice(0, 1000) ?? null }
      : {}),
    ...(input.dueAt !== undefined
      ? { dueAt: input.dueAt === null ? null : (when(input.dueAt) ?? null) }
      : {}),
  };
  const updated = await Effect.runPromise(
    updateCommitment(env.HYPERDRIVE, business.id, id, input.expectedRevision!, change, {
      kind: "person",
      id: person.id,
    }),
  );
  return updated
    ? Response.json(updated)
    : new Response("The commitment changed; reload it", { status: 409 });
}

/** Persistent places that reference work and files; they grant no access of their own. */
async function spaceRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { business, trusted, path } = access;
  if (path === "/spaces" && request.method === "GET")
    return Response.json({ spaces: await Effect.runPromise(spaces(env.HYPERDRIVE, business.id)) });
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id));
  const employeeOf = (id: unknown) => employees.find((employee) => employee.id === id);
  const editing = /^\/spaces\/([A-Za-z0-9-]{1,64})$/.exec(path)?.[1];
  if (editing && request.method === "PUT") {
    if (!trusted) return forbidden();
    const input = await body<{ name: string; purpose: string; lead: string }>(request, 2_000);
    if (input.lead !== undefined && !employeeOf(input.lead))
      return new Response("The lead must be an employee of this business", { status: 400 });
    const name = label(input.name, 80);
    const purpose =
      typeof input.purpose === "string" ? input.purpose.trim().slice(0, 500) : undefined;
    const changed = await Effect.runPromise(
      updateSpace(env.HYPERDRIVE, business.id, editing, {
        ...(name ? { name } : {}),
        ...(purpose !== undefined ? { purpose } : {}),
        ...(input.lead ? { lead: input.lead } : {}),
      }),
    );
    return changed ? Response.json({ updated: true }) : notFound();
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (path === "/spaces") {
    const input = await body<{ name: string; purpose: string; lead: string }>(request, 2_000);
    const name = label(input.name, 80);
    if (!name) return new Response("Send a space name", { status: 400 });
    const purpose = label(input.purpose, 500);
    const lead =
      input.lead === undefined
        ? employees.find((employee) => employee.template === "operations")
        : employeeOf(input.lead);
    if (!lead)
      return new Response("The lead must be an employee of this business", { status: 400 });
    return Response.json(
      await Effect.runPromise(
        createSpace(env.HYPERDRIVE, business.id, {
          name,
          ...(purpose ? { purpose } : {}),
          lead: lead.id,
        }),
      ),
      { status: 201 },
    );
  }
  const remove = /^\/spaces\/[A-Za-z0-9-]{1,64}\/items\/([A-Za-z0-9-]{1,64})\/remove$/.exec(
    path,
  )?.[1];
  if (remove) {
    const removed = await Effect.runPromise(removeFromSpace(env.HYPERDRIVE, business.id, remove));
    return removed ? Response.json({ removed: true }) : notFound();
  }
  const spaceId = /^\/spaces\/([A-Za-z0-9-]{1,64})\/items$/.exec(path)?.[1];
  if (!spaceId) return notFound();
  const input = await body<{ kind: string; ref: string }>(request, 4_000);
  const file = input.kind === "file" && businessFile(env, business.id, input.ref) !== undefined;
  if (
    !file &&
    ((input.kind !== "commitment" && input.kind !== "artifact") || !label(input.ref, 64))
  )
    return new Response(
      "Send a kind (commitment, artifact, or a file in the business folder) and a ref",
      {
        status: 400,
      },
    );
  if (
    input.kind === "artifact" &&
    !(await Effect.runPromise(artifactLocation(env.HYPERDRIVE, business.id, input.ref!)))
  )
    return new Response("No such file in this business", { status: 400 });
  const item = await Effect.runPromise(
    addToSpace(env.HYPERDRIVE, business.id, spaceId, {
      kind: input.kind as SpaceItem["kind"],
      ref: input.ref!,
    }),
  );
  return item
    ? Response.json(item, { status: 201 })
    : new Response("No such space or commitment in this business", { status: 400 });
}

/**
 * The business's shared conversations: DMs (`direct:<employee>`), spaces (`space:<id>`) and
 * work threads (`work:<id>`). Posting wakes whoever the conversation's rules say answers.
 */
async function conversationRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/conversations" && request.method === "GET")
    return Response.json({
      conversations: await Effect.runPromise(
        conversationSummaries(env.HYPERDRIVE, business.id, person.id),
      ),
    });
  const [, raw, action] = /^\/conversations\/([^/]+)(?:\/(messages|read))?$/.exec(path) ?? [];
  const key = conversationKey(decodeURIComponent(raw ?? ""));
  if (!key || !(await conversationExists(env, business.id, key))) return notFound();
  if (!action && request.method === "GET") {
    const before = new URL(request.url).searchParams.get("before") ?? undefined;
    const page = await conversationPage(env, business.id, key, before);
    // Reactions belong to each employee's messages.
    const authors = [...new Set(page.messages.map((m) => employeeOf(m.author)).filter(Boolean))];
    const reactions = (
      await Promise.all(
        authors.map((employeeId) =>
          Effect.runPromise(
            appReactions(env.HYPERDRIVE, { businessId: business.id, employeeId: employeeId! }),
          ),
        ),
      )
    ).flat();
    return Response.json({
      ...page,
      messages: page.messages.map((message) => ({
        ...message,
        reactions: reactions.filter((r) => r.targetId === message.id).map((r) => r.emoji),
      })),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (action === "read") {
    const { at } = await body<{ at: string }>(request, 1_000);
    if (typeof at !== "string" || !Number.isFinite(Date.parse(at)))
      return new Response("Send the time of the last message read", { status: 400 });
    await Effect.runPromise(markSeen(env.HYPERDRIVE, business.id, key, `person:${person.id}`, at));
    return Response.json({ read: true });
  }
  if (action !== "messages") return notFound();
  const input = await body<{
    id: string;
    text: string;
    replyTo: string;
    mentions: string[];
    viaVoice: boolean;
  }>(request, 70_000);
  const text = typeof input.text === "string" ? input.text.trim() : "";
  if (
    typeof input.id !== "string" ||
    !/^[A-Za-z0-9-]{8,64}$/.test(input.id) ||
    !text ||
    text.length > 60_000
  )
    return new Response("Send an id and non-empty text", { status: 400 });
  const posted = await postFromPerson(env, business.id, person.id, key, {
    id: input.id,
    text,
    ...(typeof input.replyTo === "string" ? { replyTo: input.replyTo } : {}),
    ...(Array.isArray(input.mentions)
      ? { mentions: input.mentions.filter((m) => typeof m === "string") }
      : {}),
    viaVoice: input.viaVoice === true,
  });
  if ("paused" in posted)
    return new Response(`${posted.paused.join(" and ")} is paused. Resume them to send.`, {
      status: 409,
    });
  return Response.json(posted, { status: 201 });
}

/** Requests waiting on the owner. Approval allows exactly one identical retry. */
async function decisionRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/decisions" && request.method === "GET")
    return Response.json({
      decisions: await Effect.runPromise(pendingDecisions(env.HYPERDRIVE, business.id)),
    });
  const answer = /^\/decisions\/([A-Za-z0-9-]{1,64})\/(approve|reject)$/.exec(path);
  if (!answer || request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const answered = await Effect.runPromise(
    answerDecision(env.HYPERDRIVE, business.id, answer[1]!, {
      approve: answer[2] === "approve",
      by: person.id,
    }),
  );
  if (!answered)
    return new Response("That request was already answered or has expired", { status: 409 });
  // The answer is said where the employee asked, which wakes it to continue.
  const key = answered.conversation ? conversationKey(answered.conversation) : undefined;
  if (key)
    await postFromPerson(env, business.id, person.id, key, {
      id: `decision:${answered.id}`,
      text:
        answered.status === "approved"
          ? `Approved: ${answered.capability}. Go ahead; it runs once, with exactly the input you asked for.`
          : `Declined: ${answered.capability}. Don't run it; find another way or ask me.`,
      mentions: [answered.employee_id],
    });
  return Response.json({ status: answered.status });
}

async function googleRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/connections/google" && request.method === "GET") {
    const connection = await googleConnectionStatus(env.HYPERDRIVE, business.id);
    return Response.json({
      configured: googleConfigured(env),
      connected: Boolean(connection),
      files: await listDrive(env, business.id),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (path === "/connections/google/connect")
    return beginGoogle(request, env, business.id, person.id);
  if (path === "/connections/google/disconnect")
    return Response.json(await disconnectGoogle(env, business.id));
  if (path === "/connections/google/picker") {
    if (!env.GOOGLE_PICKER_API_KEY || !env.GOOGLE_PROJECT_NUMBER)
      return new Response("Picker is not configured", { status: 503 });
    const google = await googleAccess(env, business.id);
    return Response.json({
      token: google.token,
      key: env.GOOGLE_PICKER_API_KEY,
      appId: env.GOOGLE_PROJECT_NUMBER,
    });
  }
  if (path === "/connections/google/select") {
    const input = await body<{ ids: unknown }>(request, 8_000);
    if (!Array.isArray(input.ids) || !input.ids.every((id) => typeof id === "string"))
      return new Response("Invalid file selection", { status: 400 });
    return Response.json(await selectDrive(env, business.id, input.ids));
  }
  return notFound();
}

async function artifact(env: Env, businessId: string, id: string) {
  const location = await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, id));
  if (!location) return notFound();
  const object = await env.FILES.get(location.object_key);
  if (!object) return new Response("File temporarily unavailable", { status: 503 });
  return new Response(object.body, {
    headers: {
      "content-type": location.content_type,
      "content-disposition": `attachment; filename="${location.filename.replace(/["\\\r\n]/g, "_")}"`,
      "content-length": String(object.size),
      "content-security-policy": "sandbox; default-src 'none'",
    },
  });
}
