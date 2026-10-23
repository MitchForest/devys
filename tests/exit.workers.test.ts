import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { createMemory } from "../src/memory/service.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { ref } from "../src/protocol/ref.ts";
import { createWorkItem } from "../src/work/service.ts";
import { createProject } from "../src/work/projects.ts";
import { business, db, sql } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);
const call = (scope: { businessId: string; employeeId: string }, name: string, input: unknown) =>
  Effect.runPromise(
    catalog
      .find((item) => item.name === name)!
      .execute(input)
      .pipe(
        Effect.provideService(Invocation, {
          ...scope,
          operationId: crypto.randomUUID(),
          authorize: () => Effect.void,
          assertActive: () => Effect.void,
        }),
      ),
  );

it("B0 exit: an employee's capabilities see only its own business's work, projects and memory", async () => {
  const acme = await business("Acme");
  const globex = await business("Globex");
  await Effect.runPromise(
    createWorkItem(db, acme.business.id, {
      id: crypto.randomUUID(),
      owner: acme.scope.employeeId,
      title: "Acme launch",
      createdBy: "person:t",
    }),
  );
  const launch = await Effect.runPromise(
    createProject(db, acme.business.id, { id: crypto.randomUUID(), name: "Launch" }),
  );
  await Effect.runPromise(
    createMemory(db, acme.business.id).remember(
      { key: "launch-month", content: "Acme launches in November", source: "user" },
      "op-1",
    ),
  );
  const theirs = (await call(acme.scope, "workList", {})) as { workItems: unknown[] };
  expect(theirs.workItems).toHaveLength(1);
  expect(await call(globex.scope, "workList", {})).toEqual({ workItems: [] });
  expect(await call(globex.scope, "projectList", {})).toEqual({ projects: [] });
  const recalled = (await call(globex.scope, "recall", { query: "launch November" })) as {
    items: unknown[];
  };
  expect(recalled.items).toEqual([]);
  // A Globex employee cannot put itself in charge of Acme work.
  await expect(
    call(globex.scope, "workCreate", { title: "x", owner: acme.scope.employeeId }),
  ).rejects.toMatchObject({ code: "invalid_input" });
  // Nor put its own work in Acme's project, or change that project.
  const launchRef = ref("work", "project", launch.id);
  await expect(
    call(globex.scope, "workCreate", { title: "x", project: launchRef }),
  ).rejects.toMatchObject({ code: "invalid_input" });
  await expect(
    call(globex.scope, "projectUpdate", { ref: launchRef, goal: "Theirs now" }),
  ).rejects.toMatchObject({ code: "invalid_input" });
});

it("capabilities that create a record return its ref; projectAdd takes refs of this business only", async () => {
  const acme = await business("Acme refs");
  const globex = await business("Globex refs");
  const task = (await call(acme.scope, "workCreate", { title: "Write the plan" })) as {
    ref: string;
  };
  expect(task.ref).toMatch(/^devys:work\/item\/[0-9a-f-]+$/);
  expect(task).not.toHaveProperty("id");
  const launch = (await call(acme.scope, "projectCreate", { name: "Launch" })) as {
    ref: string;
  };
  expect(launch.ref).toMatch(/^devys:work\/project\/[0-9a-f-]+$/);
  expect(launch).not.toHaveProperty("id");
  // Pointers are refs of the right kind: a bare id or another kind's ref is refused.
  const launchId = launch.ref.split("/").at(-1)!;
  for (const project of [launchId, task.ref])
    await expect(
      call(acme.scope, "projectUpdate", { ref: project, goal: "Ship it" }),
    ).rejects.toMatchObject({ code: "invalid_input" });
  const placed = (await call(acme.scope, "workCreate", {
    title: "Draft the launch post",
    project: launch.ref,
  })) as { project: string };
  expect(placed.project).toBe(launch.ref);
  const artifact = async (businessId: string) => {
    const id = crypto.randomUUID();
    await sql.run(
      `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
       VALUES ($1, $2, $1, $1, 'plan.html', 'text/html', 1)`,
      [id, businessId],
    );
    return id;
  };
  const ours = `devys:documents/artifact/${await artifact(acme.business.id)}`;
  const theirs = `devys:documents/artifact/${await artifact(globex.business.id)}`;
  // Inputs and outputs name the record they change the same way: its ref.
  expect(await call(acme.scope, "projectAdd", { ref: launch.ref, record: ours })).toMatchObject({
    ref: launch.ref,
    items: [ours],
  });
  const listed = (await call(acme.scope, "projectList", {})) as {
    projects: { ref: string; items: string[] }[];
  };
  expect(listed.projects.map((project) => [project.ref, project.items])).toEqual([
    [launch.ref, [ours]],
  ]);
  for (const kept of [theirs, task.ref, `artifact:${ours.split("/").at(-1)}`])
    await expect(
      call(acme.scope, "projectAdd", { ref: launch.ref, record: kept }),
    ).rejects.toMatchObject({ code: "invalid_input" });
});
