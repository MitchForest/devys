import { Effect, Schema } from "effect";
import type { Env } from "./env.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { activeEmployee } from "../identity/service.ts";
import {
  answerDecision,
  decision as findDecision,
  decisionsFor,
  pendingDecisions,
} from "../authority/service.ts";
import { spendOf } from "../authority/contract.ts";
import {
  answerText,
  answerWithFile,
  draftUnchanged,
  handedBack,
  signedSpend,
  tellEmployee,
  tookOver,
} from "./asking.ts";
import {
  workItem,
  workItems,
  createWorkItem,
  setTakeover,
  updateWorkItem,
  type Change,
} from "../work/service.ts";
import { NewWorkItem, WorkItem, WorkItemChange } from "../work/contract.ts";
import { respond } from "../protocol/http.ts";
import { Answered, Decisions, WorkItems } from "./wire.ts";
import { project } from "../work/projects.ts";
import { capabilities } from "./capabilities.ts";
import { handBack } from "./coding.ts";
import { decodedBody, forbidden, notFound } from "./request.ts";

const when = (value: string | null) =>
  value && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : undefined;

/** The business's work items, operated by its members through the same rules as employees. */
export async function workRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/work" && request.method === "GET") {
    const since = when(new URL(request.url).searchParams.get("since"));
    return respond(WorkItems, {
      work_items: await Effect.runPromise(workItems(env.HYPERDRIVE, business.id, since)),
    });
  }
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const isEmployee = async (id: string) =>
    Boolean(
      await Effect.runPromise(
        activeEmployee(env.HYPERDRIVE, { businessId: business.id, employeeId: id }),
      ),
    );
  if (path === "/work") {
    const input = await decodedBody(request, 16_000, NewWorkItem);
    if (!(await isEmployee(input.owner)))
      return new Response("The owner must be an employee of this business", { status: 400 });
    if (
      input.project_id !== undefined &&
      !(await Effect.runPromise(project(env.HYPERDRIVE, business.id, input.project_id)))
    )
      return new Response("No such project in this business", { status: 400 });
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
    const dueAt = when(input.due_at ?? null);
    const created = await Effect.runPromise(
      createWorkItem(env.HYPERDRIVE, business.id, {
        id: crypto.randomUUID(),
        owner: input.owner,
        title: input.title,
        ...(input.objective !== undefined ? { objective: input.objective } : {}),
        ...(input.next_action !== undefined ? { nextAction: input.next_action } : {}),
        ...(dueAt ? { dueAt } : {}),
        conditions,
        ...(input.project_id ? { projectId: input.project_id } : {}),
        createdBy: `person:${person.id}`,
      }),
    );
    return respond(WorkItem, created, { status: 201 });
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
    if (!item) return notFound();
    // Taking over answers the work's take-over requests; handing back says they are done.
    if (takeover[2] === "takeover") await tookOver(env, business.id, person.id, item.id);
    else {
      await handedBack(env, business.id, person.id, item.id);
      await handBack(env, business.id, item.id);
    }
    return respond(WorkItem, item);
  }
  const id = /^\/work\/([A-Za-z0-9-]{1,64})$/.exec(path)?.[1];
  if (!id) return notFound();
  const input = await decodedBody(request, 8_000, WorkItemChange);
  // Work is read-only to people until they take it over, which fences its employee; until then
  // they ask in its thread (.docs/PRODUCT_EXPERIENCE.md#layers).
  const current = await Effect.runPromise(workItem(env.HYPERDRIVE, business.id, id));
  if (!current) return notFound();
  if (current.taken_over_by !== person.id)
    return new Response(
      "Take over the work item to change it by hand, or ask its employee in its thread.",
      { status: 409 },
    );
  if (input.owner !== undefined && !(await isEmployee(input.owner)))
    return new Response("The owner must be an employee of this business", { status: 400 });
  const change: Change = {
    ...(input.title !== undefined ? { title: input.title } : {}),
    ...(input.owner !== undefined ? { owner: input.owner } : {}),
    ...(input.state !== undefined ? { state: input.state } : {}),
    ...(input.next_action !== undefined ? { nextAction: input.next_action } : {}),
    ...(input.wait_condition !== undefined ? { waitCondition: input.wait_condition } : {}),
    ...(input.due_at !== undefined ? { dueAt: when(input.due_at) ?? null } : {}),
  };
  const updated = await Effect.runPromise(
    updateWorkItem(env.HYPERDRIVE, business.id, id, input.expected_revision, change, {
      kind: "person",
      id: person.id,
    }),
  );
  return updated
    ? respond(WorkItem, updated)
    : new Response("The work item changed; reload it", { status: 409 });
}

/** Requests waiting on the owner. Approval allows exactly one identical retry. */
export async function decisionRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { person, business, trusted, path } = access;
  if (path === "/decisions" && request.method === "GET") {
    // `?work_item=` lists one work item's requests with their answers, not only pending ones.
    const workItemId = new URL(request.url).searchParams.get("work_item");
    return respond(Decisions, {
      decisions: await Effect.runPromise(
        workItemId
          ? decisionsFor(env.HYPERDRIVE, business.id, workItemId)
          : pendingDecisions(env.HYPERDRIVE, business.id),
      ),
    });
  }
  const answer = /^\/decisions\/([A-Za-z0-9-]{1,64})\/(approve|reject|file)$/.exec(path);
  if (!answer || request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  if (answer[2] === "file") {
    const asked = await Effect.runPromise(findDecision(env.HYPERDRIVE, business.id, answer[1]!));
    if (!asked) return notFound();
    const answered = await answerWithFile(
      request,
      env,
      { personId: person.id, businessId: business.id },
      asked,
    );
    return answered instanceof Response ? answered : respond(Answered, { status: answered.status });
  }
  const approve = answer[2] === "approve";
  const asked = await Effect.runPromise(findDecision(env.HYPERDRIVE, business.id, answer[1]!));
  if (!asked) return notFound();
  if (asked.status !== "pending")
    return new Response("That request was already answered or has expired", { status: 409 });
  if (approve && asked.kind === "take_over")
    return new Response("Take the work over to do this; handing it back answers it.", {
      status: 409,
    });
  if (approve && asked.kind === "secret")
    return new Response("Add the secret to answer this; it is answered once it exists.", {
      status: 409,
    });
  if (approve && asked.kind === "connect")
    return new Response("Connect the app and turn it on to answer this.", { status: 409 });
  if (approve && asked.kind === "file")
    return new Response("Choose the file to answer this.", { status: 409 });
  // A draft that changed since it was asked is not what the owner is approving now.
  if (approve && !(await draftUnchanged(env, business.id, person.id, asked)))
    return new Response("That draft changed after it was asked; it will be asked again.", {
      status: 409,
    });
  // A spend is approved only with a device signature over exactly this request.
  const signed =
    approve && spendOf(asked)
      ? await signedSpend(request, env, person.id, business.id, asked)
      : undefined;
  if (signed instanceof Response) return signed;
  const answered = await Effect.runPromise(
    answerDecision(env.HYPERDRIVE, business.id, asked.id, {
      approve,
      by: person.id,
      ...(signed ? { signed } : {}),
    }),
  );
  if (!answered)
    return new Response("That request was already answered or has expired", { status: 409 });
  // The answer is said where the employee asked, which wakes it to continue.
  await tellEmployee(env, business.id, person.id, answered, answerText(answered));
  return respond(Answered, { status: answered.status });
}
