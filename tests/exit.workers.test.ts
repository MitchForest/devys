import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { createMemory } from "../src/memory/service.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { createCommitment } from "../src/work/service.ts";
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
    createCommitment(db, acme.business.id, {
      owner: acme.scope.employeeId,
      title: "Acme launch",
      createdBy: "person:t",
    }),
  );
  const launch = await Effect.runPromise(createProject(db, acme.business.id, { name: "Launch" }));
  await Effect.runPromise(
    createMemory(db, acme.business.id).remember(
      { key: "launch-month", content: "Acme launches in November", source: "user" },
      "op-1",
    ),
  );
  const theirs = (await call(acme.scope, "commitmentList", {})) as { commitments: unknown[] };
  expect(theirs.commitments).toHaveLength(1);
  expect(await call(globex.scope, "commitmentList", {})).toEqual({ commitments: [] });
  expect(await call(globex.scope, "projectList", {})).toEqual({ projects: [] });
  const recalled = (await call(globex.scope, "recall", { query: "launch November" })) as {
    items: unknown[];
  };
  expect(recalled.items).toEqual([]);
  // A Globex employee cannot put itself in charge of Acme work.
  await expect(
    call(globex.scope, "commitmentCreate", { title: "x", owner: acme.scope.employeeId }),
  ).rejects.toMatchObject({ code: "invalid_input" });
  // Nor put its own work in Acme's project, or change that project.
  await expect(
    call(globex.scope, "commitmentCreate", { title: "x", projectId: launch.id }),
  ).rejects.toMatchObject({ code: "invalid_input" });
  await expect(
    call(globex.scope, "projectUpdate", { id: launch.id, goal: "Theirs now" }),
  ).rejects.toMatchObject({ code: "invalid_input" });
});

it("capabilities that create a record return its ref; projectAdd takes refs of this business only", async () => {
  const acme = await business("Acme refs");
  const globex = await business("Globex refs");
  const task = (await call(acme.scope, "commitmentCreate", { title: "Write the plan" })) as {
    id: string;
    ref: string;
  };
  expect(task.ref).toBe(`devys:work/item/${task.id}`);
  const launch = (await call(acme.scope, "projectCreate", { name: "Launch" })) as {
    id: string;
    ref: string;
  };
  expect(launch.ref).toBe(`devys:work/project/${launch.id}`);
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
  await call(acme.scope, "projectAdd", { projectId: launch.id, ref: ours });
  const listed = (await call(acme.scope, "projectList", {})) as {
    projects: { items: { ref: string }[] }[];
  };
  expect(listed.projects[0]!.items.map((item) => item.ref)).toEqual([ours]);
  for (const ref of [theirs, task.ref, `artifact:${ours.split("/").at(-1)}`])
    await expect(
      call(acme.scope, "projectAdd", { projectId: launch.id, ref }),
    ).rejects.toMatchObject({ code: "invalid_input" });
});
