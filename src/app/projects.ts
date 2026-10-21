import { Effect } from "effect";
import type { Env } from "./env.ts";
import { artifactLocation } from "../apps/documents/service.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { employeesOf } from "../identity/service.ts";
import {
  addToProject,
  createProject,
  projects,
  removeFromProject,
  updateProject,
  type ProjectChange,
} from "../work/projects.ts";
import { parseRef, type Ref } from "../protocol/ref.ts";
import { businessFile } from "./files.ts";
import { body, forbidden, label, notFound } from "./request.ts";

type Input = {
  name: string;
  goal: string | null;
  deadline: string | null;
  budget: { cents: number; currency: string } | null;
  lead: string;
  members: string[];
};

/**
 * The fields of a create or an update, checked: a null goal, deadline or budget clears it.
 * A string is the reason the input was refused.
 */
function change(input: Partial<Input>, employeeIds: readonly string[]): ProjectChange | string {
  const out: ProjectChange = {};
  if (input.name !== undefined) {
    const name = label(input.name, 80);
    if (!name) return "Send a project name of at most 80 characters";
    out.name = name;
  }
  if (input.goal !== undefined) {
    if (input.goal !== null && typeof input.goal !== "string") return "Send the goal as text";
    out.goal = input.goal?.trim().slice(0, 500) || null;
  }
  if (input.deadline !== undefined) {
    if (
      input.deadline !== null &&
      !(
        typeof input.deadline === "string" &&
        /^\d{4}-\d{2}-\d{2}$/.test(input.deadline) &&
        Number.isFinite(Date.parse(input.deadline))
      )
    )
      return "Send the deadline as YYYY-MM-DD";
    out.deadline = input.deadline;
  }
  if (input.budget !== undefined) {
    const budget = input.budget;
    if (
      budget !== null &&
      !(
        Number.isSafeInteger(budget?.cents) &&
        budget!.cents >= 0 &&
        /^[A-Z]{3}$/.test(String(budget?.currency))
      )
    )
      return "Send the budget as { cents, currency } with whole cents and a currency like USD";
    out.budget = budget && { cents: budget.cents, currency: budget.currency };
  }
  if (input.lead !== undefined) {
    if (!employeeIds.includes(input.lead)) return "The lead must be an employee of this business";
    out.lead = input.lead;
  }
  if (input.members !== undefined) {
    if (
      !Array.isArray(input.members) ||
      input.members.length > 50 ||
      input.members.some((id) => !employeeIds.includes(id))
    )
      return "Members must be employees of this business";
    out.members = [...new Set(input.members)];
  }
  return out;
}

/**
 * Whether a project can show this: the ref of an artifact of the business or of a file in its
 * folder. A project's work items belong to it instead; projects don't hold projects.
 */
export async function keepable(env: Env, businessId: string, value: unknown): Promise<boolean> {
  const parts = parseRef(value);
  if (parts?.app !== "documents") return false;
  if (parts.kind === "file") return businessFile(env, businessId, parts.id) !== undefined;
  return Boolean(await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, parts.id)));
}

/** Bounded initiatives: their work, channel and references. They grant no access of their own. */
export async function projectRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { business, trusted, path } = access;
  if (path === "/projects" && request.method === "GET")
    return Response.json({
      projects: await Effect.runPromise(projects(env.HYPERDRIVE, business.id)),
    });
  if (request.method !== "POST" && request.method !== "PUT") return notFound();
  if (!trusted) return forbidden();
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id));
  const employeeIds = employees.map((employee) => employee.id);
  const editing = /^\/projects\/([A-Za-z0-9-]{1,64})$/.exec(path)?.[1];
  if (editing && request.method === "PUT") {
    const checked = change(await body<Input>(request, 8_000), employeeIds);
    if (typeof checked === "string") return new Response(checked, { status: 400 });
    const updated = await Effect.runPromise(
      updateProject(env.HYPERDRIVE, business.id, editing, checked),
    );
    return updated ? Response.json(updated) : notFound();
  }
  if (request.method !== "POST") return notFound();
  if (path === "/projects") {
    const input = await body<Input>(request, 8_000);
    const checked = change(
      {
        ...input,
        name: input.name ?? "",
        // Operations leads a project nobody was named to lead.
        lead:
          input.lead ?? employees.find((employee) => employee.template === "operations")?.id ?? "",
      },
      employeeIds,
    );
    if (typeof checked === "string") return new Response(checked, { status: 400 });
    return Response.json(
      await Effect.runPromise(
        createProject(env.HYPERDRIVE, business.id, {
          ...(checked as ProjectChange & { name: string }),
          id: crypto.randomUUID(),
        }),
      ),
      { status: 201 },
    );
  }
  const remove = /^\/projects\/([A-Za-z0-9-]{1,64})\/items\/([A-Za-z0-9-]{1,64})\/remove$/.exec(
    path,
  );
  if (remove) {
    const removed = await Effect.runPromise(
      removeFromProject(env.HYPERDRIVE, business.id, remove[1]!, remove[2]!),
    );
    return removed ? Response.json({ removed: true }) : notFound();
  }
  const projectId = /^\/projects\/([A-Za-z0-9-]{1,64})\/items$/.exec(path)?.[1];
  if (!projectId) return notFound();
  const { ref } = await body<{ ref: unknown }>(request, 4_000);
  if (!(await keepable(env, business.id, ref)))
    return new Response(
      "Send the ref of an artifact or of a file in the business folder (devys:documents/…)",
      { status: 400 },
    );
  const item = await Effect.runPromise(
    addToProject(env.HYPERDRIVE, business.id, projectId, ref as Ref),
  );
  return item
    ? Response.json(item, { status: 201 })
    : new Response("No such project in this business", { status: 404 });
}
