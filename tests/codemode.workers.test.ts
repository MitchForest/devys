import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { RecoveryProbe } from "./fixtures/worker.ts";
const bindings = env as { PROBE: DurableObjectNamespace<RecoveryProbe> };

it("uses Code Mode's public executor to compose host capabilities", async () => {
  const probe = bindings.PROBE.getByName(crypto.randomUUID());
  const result = JSON.parse(
    await probe.execute(
      "async () => { const a = await codemode.increment(); return [a, await codemode.increment()]; }",
    ),
  );
  expect(result.error).toBeUndefined();
  expect(result.result).toEqual([1, 2]);
  expect(await probe.count()).toBe(2);
});

it("generated programs cannot bypass host capabilities with direct networking", async () => {
  const probe = bindings.PROBE.getByName(crypto.randomUUID());
  const result = JSON.parse(
    await probe.execute('async () => (await fetch("https://example.com")).status'),
  );
  expect(result.error).toBeTruthy();
});
