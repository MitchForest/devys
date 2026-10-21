import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { agentDependencies } from "../src/app/agent.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { appCatalog } from "../src/apps/catalog.ts";
import { install, uninstall } from "../src/apps/service.ts";
import { grant } from "../src/authority/service.ts";
import { business, db } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);

it("every capability an app names exists, and belongs to one app at most", () => {
  const names = catalog.map((item) => item.name);
  const claimed = appCatalog.flatMap((app) => app.capabilities);
  expect(claimed.filter((name) => !names.includes(name))).toEqual([]);
  expect(new Set(claimed).size).toBe(claimed.length);
});

it("an uninstalled app's capabilities are hidden from discovery and refused at the gate", async () => {
  const { scope } = await business("Gated");
  const named = (name: string) => catalog.find((item) => item.name === name)!;
  for (const name of ["codingStatus", "commitmentList"])
    await Effect.runPromise(grant(db, scope, { capability: named(name), mode: "auto" }));
  const granted = () => agentDependencies(bindings).granted(scope);
  const outcome = async (name: string) =>
    (await authorize(bindings, scope, named(name), {})).outcome;
  expect(await granted()).toEqual(expect.arrayContaining(["codingStatus", "commitmentList"]));
  expect(await outcome("codingStatus")).toBe("allow");

  await Effect.runPromise(uninstall(db, scope.businessId, "code"));
  expect(await granted()).not.toContain("codingStatus");
  // Built-in tools belong to no app and stay usable.
  expect(await granted()).toContain("commitmentList");
  expect(await authorize(bindings, scope, named("codingStatus"), {})).toMatchObject({
    outcome: "deny",
    reason: expect.stringContaining("hasn't installed"),
  });
  expect(await outcome("commitmentList")).toBe("allow");

  await Effect.runPromise(install(db, scope.businessId, ["code"]));
  expect(await outcome("codingStatus")).toBe("allow");
});
