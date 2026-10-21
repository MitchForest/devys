import { expect, it } from "vitest";
import type { AppManifest as App } from "../src/protocol/app.ts";
import { records } from "../src/web/panel/layers/registry.tsx";
import { recordNames } from "../src/web/panel/layers/titles.ts";

/** Every app's manifest, as declared in `src/apps/<id>/app.ts`. */
const manifests = Object.values(
  import.meta.glob<Record<string, unknown>>("../src/apps/*/app.ts", { eager: true }),
).flatMap((module) => Object.values(module) as App[]);

it("the web shows every record kind the app manifests declare, and no other", () => {
  const declared = manifests.flatMap((app) =>
    app.records.map((record) => `${app.id}/${record.kind}`),
  );
  expect(declared.length).toBeGreaterThan(0);
  expect(Object.keys(records).sort()).toEqual([...declared].sort());
  expect(Object.keys(recordNames).sort()).toEqual([...declared].sort());
});
