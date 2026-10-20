import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { createMemory } from "../src/memory/service.ts";
import { Invocation } from "../src/protocol/capability.ts";
import { createCommitment } from "../src/work/service.ts";
import { createSpace } from "../src/work/spaces.ts";
import { business, db } from "./fixtures/postgres.ts";

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

it("B0 exit: an employee's capabilities see only its own business's work, spaces and memory", async () => {
  const acme = await business("Acme");
  const scribble = await business("Scribble");
  await Effect.runPromise(
    createCommitment(db, acme.business.id, {
      owner: acme.scope.employeeId,
      title: "Acme launch",
      createdBy: "person:t",
    }),
  );
  await Effect.runPromise(createSpace(db, acme.business.id, { name: "Launch" }));
  await Effect.runPromise(
    createMemory(db, acme.business.id).remember(
      { key: "launch-month", content: "Acme launches in November", source: "user" },
      "op-1",
    ),
  );
  const theirs = (await call(acme.scope, "commitmentList", {})) as { commitments: unknown[] };
  expect(theirs.commitments).toHaveLength(1);
  expect(await call(scribble.scope, "commitmentList", {})).toEqual({ commitments: [] });
  expect(await call(scribble.scope, "spaceList", {})).toEqual({ spaces: [] });
  const recalled = (await call(scribble.scope, "recall", { query: "launch November" })) as {
    items: unknown[];
  };
  expect(recalled.items).toEqual([]);
  // A Scribble employee cannot put itself in charge of Acme work.
  await expect(
    call(scribble.scope, "commitmentCreate", { title: "x", owner: acme.scope.employeeId }),
  ).rejects.toMatchObject({ code: "invalid_input" });
});
