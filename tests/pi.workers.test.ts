import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { PiRecoveryProbe } from "./fixtures/pi.ts";
const bindings = env as {
  PI: DurableObjectNamespace<PiRecoveryProbe>;
  DEVYS_MODEL_GATEWAY_KEY?: string;
};

it("Pi uses the actual Effect capability bridge through Code Mode", async () => {
  const probe = bindings.PI.getByName(crypto.randomUUID());
  const result = JSON.parse(await probe.run(false));
  expect(result.status).toBe("done");
  expect(await probe.writes()).toBe(1);
  expect(await probe.messages()).toContain("persistent");
});

it.skipIf(!bindings.DEVYS_MODEL_GATEWAY_KEY)(
  "Gemini 3.8 Flash performs useful work through the gateway, Pi and Code Mode",
  async () => {
    const probe = bindings.PI.getByName(crypto.randomUUID());
    const result = JSON.parse(await probe.runLive());
    expect(result.status).toBe("done");
    expect(await probe.writes()).toBe(1);
    expect(await probe.messages()).toContain("persistent");
  },
  90_000,
);

it("Pi reports an interrupted Code Mode tool without replaying its effects", async () => {
  const name = crypto.randomUUID();
  await expect(bindings.PI.getByName(name).run(true)).rejects.toThrow();
  const restarted = bindings.PI.getByName(name);
  const result = JSON.parse(await restarted.resume());
  expect(result.status).toBe("done");
  expect(await restarted.writes()).toBe(1);
  expect(await restarted.messages()).toContain("persistent");
  expect(await restarted.messages()).toContain("interrupted");
});

it("direct Pi tools use the same Effect capability contracts", async () => {
  const probe = bindings.PI.getByName(crypto.randomUUID());
  const result = JSON.parse(await probe.run(false, true));
  expect(result.status).toBe("done");
  expect(await probe.writes()).toBe(1);
});

it("Pi activates a discovered capability and calls it without exposing all integration schemas", async () => {
  const probe = bindings.PI.getByName(crypto.randomUUID());
  const { before, after, result } = JSON.parse(await probe.discoverAndImport());
  expect(before).not.toContain("importAttachment");
  expect(before).not.toContain("driveCreate");
  expect(after).toContain("importAttachment");
  expect(after).not.toContain("driveCreate");
  expect(result.status).toBe("done");
  expect(await probe.writes()).toBe(1);
});

it("native Pi compaction preserves older entries for later retrieval", async () => {
  const probe = bindings.PI.getByName(crypto.randomUUID());
  const result = JSON.parse(await probe.compactAndReadOlder());
  expect(JSON.stringify(result.stored)).toContain("cobalt-2718");
  expect(JSON.stringify(result.active)).not.toContain("cobalt-2718");
  expect(JSON.stringify(result.active)).toContain("older context available");
});
