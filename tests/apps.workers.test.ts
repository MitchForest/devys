import { env } from "cloudflare:workers";
import { Effect } from "effect";
import { expect, it } from "vitest";
import type { Env } from "../infra/api.ts";
import { agentDependencies } from "../src/app/agent.ts";
import { authorize } from "../src/app/authorize.ts";
import { capabilities } from "../src/app/capabilities.ts";
import { appCatalog, directory } from "../src/app/apps.ts";
import { install, uninstall } from "../src/apps/service.ts";
import { grant } from "../src/authority/service.ts";
import { driveScope } from "../src/connections/google.ts";
import { refKinds } from "../src/protocol/ref.ts";
import { business, db } from "./fixtures/postgres.ts";

const bindings = env as unknown as Env;
const catalog = capabilities(bindings);

it("every capability belongs to exactly one app, and every name an app lists exists", () => {
  const names = catalog.map((item) => item.name);
  const claimed = appCatalog.flatMap((app) => app.capabilities);
  expect(new Set(names).size).toBe(names.length);
  expect(claimed.filter((name) => !names.includes(name))).toEqual([]);
  expect(new Set(claimed).size).toBe(claimed.length);
  expect(names.filter((name) => !claimed.includes(name))).toEqual([]);
});

it("every Ref kind is owned by exactly one app's records, and apps own no other kinds", () => {
  const owned = appCatalog.flatMap((app) =>
    app.records.map((record) => `${app.id}/${record.kind}`),
  );
  const kinds = Object.entries(refKinds).flatMap(([app, list]) =>
    list.map((kind) => `${app}/${kind}`),
  );
  expect(owned.sort()).toEqual(kinds.sort());
  expect(new Set(owned).size).toBe(owned.length);
});

it("manifests are consistent: ids unique, system apps never shown, coming apps own nothing yet", () => {
  const ids = appCatalog.map((app) => app.id);
  expect(new Set(ids).size).toBe(ids.length);
  expect(appCatalog.filter((app) => app.kind === "system").map((app) => app.id)).toEqual([
    "computer",
    "browser",
    "web",
    "memory",
    "conversations",
    "work",
    "team",
  ]);
  for (const app of appCatalog) {
    if (app.kind === "system") expect(app.appears, app.id).toBe("never");
    else expect(app.appears, app.id).not.toBe("never");
    if (app.status === "coming") expect(app.capabilities, app.id).toEqual([]);
    for (const [role, granted] of Object.entries(app.defaultGrants ?? {}))
      for (const name of granted ?? [])
        expect(app.capabilities, `${app.id} proposes ${name} to ${role}`).toContain(name);
  }
  // Documents asks Google for the scope the connection requests.
  expect(appCatalog.find((app) => app.id === "documents")!.connections).toEqual([
    { provider: "google", scopes: [driveScope] },
  ]);
  // Only the core capabilities are offered as direct tools to every employee.
  expect(
    catalog
      .filter((item) => item.core)
      .map((item) => item.name)
      .sort(),
  ).toEqual(["forget", "read", "readSkill", "recall", "remember", "run", "write"]);
});

it("system apps are listed as installed without an install row, never pinned or shown", async () => {
  const { business: created } = await business("Directory");
  const apps = await directory(bindings, created.id);
  const computer = apps.find((app) => app.id === "computer")!;
  expect(computer).toMatchObject({
    kind: "system",
    installed: true,
    pinned: false,
    visible: false,
  });
  expect(apps.find((app) => app.id === "documents")).toMatchObject({
    installed: true,
    visible: true,
    skills: [{ name: "writing-pages", description: expect.any(String) }],
  });
  expect(JSON.stringify(apps)).not.toContain("## Versions");
  expect(apps.find((app) => app.id === "mail")).toMatchObject({ installed: false });
});

it("an uninstalled app's capabilities are hidden from discovery and refused at the gate", async () => {
  const { scope } = await business("Gated");
  const named = (name: string) => catalog.find((item) => item.name === name)!;
  for (const name of ["codingStatus", "workList"])
    await Effect.runPromise(grant(db, scope, { capability: named(name), mode: "auto" }));
  const granted = () => agentDependencies(bindings).granted(scope);
  const outcome = async (name: string) =>
    (await authorize(bindings, scope, named(name), {})).outcome;
  expect(await granted()).toEqual(expect.arrayContaining(["codingStatus", "workList"]));
  expect(await outcome("codingStatus")).toBe("allow");

  await Effect.runPromise(uninstall(db, scope.businessId, "code"));
  expect(await granted()).not.toContain("codingStatus");
  // A system app's capabilities need no install.
  expect(await granted()).toContain("workList");
  expect(await authorize(bindings, scope, named("codingStatus"), {})).toMatchObject({
    outcome: "deny",
    reason: expect.stringContaining("hasn't installed"),
  });
  expect(await outcome("workList")).toBe("allow");

  await Effect.runPromise(install(db, scope.businessId, ["code"]));
  expect(await outcome("codingStatus")).toBe("allow");
});

it("employees see the skills of their business's installed apps", async () => {
  const { scope } = await business("Skills");
  const skills = async () =>
    (await agentDependencies(bindings).skills(scope)).map((skill) => skill.name);
  expect(await skills()).toContain("writing-pages");
  await Effect.runPromise(uninstall(db, scope.businessId, "documents"));
  expect(await skills()).not.toContain("writing-pages");
});
