import { Effect } from "effect";
import type { Env } from "./env.ts";
import { artifactLocation } from "../artifacts/service.ts";
import { type Business, type Person } from "../identity/contract.ts";
import { employeesOf } from "../identity/service.ts";
import type { SpaceItem } from "../work/contract.ts";
import { addToSpace, createSpace, removeFromSpace, spaces, updateSpace } from "../work/spaces.ts";
import { businessFile } from "./files.ts";
import { body, forbidden, label, notFound } from "./request.ts";

/** Persistent places that reference work and files; they grant no access of their own. */
export async function spaceRoute(
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
