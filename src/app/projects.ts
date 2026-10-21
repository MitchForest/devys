import { Effect } from "effect";
import type { Env } from "./env.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { employeesOf } from "../identity/service.ts";
import { addToProject, createProject, projects, removeFromProject } from "../work/projects.ts";
import { NewProject, Project, ProjectItem } from "../work/contract.ts";
import { respond } from "../protocol/http.ts";
import { Projects, Removed } from "./wire.ts";
import { parseRef, type Ref } from "../protocol/ref.ts";
import { businessRef } from "./refs.ts";
import { body, decodedBody, forbidden, notFound } from "./request.ts";

/**
 * Whether a project can show this: the ref of a document or a coding session of the business.
 * A project's work items belong to it instead; projects don't hold projects.
 */
export async function keepable(env: Env, businessId: string, value: unknown): Promise<boolean> {
  const parts = parseRef(value);
  if (parts?.app !== "documents" && parts?.app !== "code") return false;
  return (await businessRef(env, businessId, value)) !== undefined;
}

/** Bounded initiatives: their work, channel and references. They grant no access of their own. */
export async function projectRoute(
  request: Request,
  env: Env,
  access: { person: Person; business: Business; trusted: boolean; path: string },
) {
  const { business, trusted, path } = access;
  if (path === "/projects" && request.method === "GET")
    return respond(Projects, {
      projects: await Effect.runPromise(projects(env.HYPERDRIVE, business.id)),
    });
  // A project's details change by asking in its channel (the lead's projectUpdate capability).
  if (request.method !== "POST") return notFound();
  if (!trusted) return forbidden();
  const employees = await Effect.runPromise(employeesOf(env.HYPERDRIVE, business.id));
  const notEmployees = (input: { lead?: string | undefined; members?: readonly string[] }) =>
    [...(input.lead ? [input.lead] : []), ...(input.members ?? [])].some(
      (id) => !employees.some((employee) => employee.id === id),
    )
      ? new Response("The lead and members must be employees of this business", { status: 400 })
      : undefined;

  if (path === "/projects") {
    const { goal, deadline, budget, ...input } = await decodedBody(request, 8_000, NewProject);
    // Operations leads a project nobody was named to lead.
    const lead = input.lead ?? employees.find((employee) => employee.template === "operations")?.id;
    const refused = notEmployees(input);
    if (refused) return refused;
    return respond(
      Project,
      await Effect.runPromise(
        createProject(env.HYPERDRIVE, business.id, {
          ...input,
          ...(goal ? { goal } : {}),
          ...(deadline ? { deadline } : {}),
          ...(budget ? { budget } : {}),
          ...(lead ? { lead } : {}),
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
    return removed ? respond(Removed, { removed: true }) : notFound();
  }
  const projectId = /^\/projects\/([A-Za-z0-9-]{1,64})\/items$/.exec(path)?.[1];
  if (!projectId) return notFound();
  const { ref } = await body<{ ref: unknown }>(request, 4_000);
  if (!(await keepable(env, business.id, ref)))
    return new Response(
      "Send the ref of a document or a coding session of this business (devys:documents/… or devys:code/session/…)",
      { status: 400 },
    );
  const item = await Effect.runPromise(
    addToProject(env.HYPERDRIVE, business.id, projectId, ref as Ref),
  );
  return item
    ? respond(ProjectItem, item, { status: 201 })
    : new Response("No such project in this business", { status: 404 });
}
