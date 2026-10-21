import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import type { AgentStatusProbe } from "./fixtures/worker.ts";
import { scopeName } from "../src/identity/contract.ts";

it("status returns the latest 100 messages with their matching replies", async () => {
  const scope = { businessId: crypto.randomUUID(), employeeId: crypto.randomUUID() };
  const probe = (
    env as { AGENT_STATUS: DurableObjectNamespace<AgentStatusProbe> }
  ).AGENT_STATUS.getByName(scopeName(scope));
  await probe.seed();
  for (let attempt = 0; attempt < 2; attempt++) {
    const status = JSON.parse(await probe.inspect(scope));
    expect(status.inbox).toHaveLength(100);
    expect(
      status.inbox
        .map((message: { received_at: number }) => message.received_at)
        .sort((a: number, b: number) => a - b),
    ).toEqual(Array.from({ length: 100 }, (_, i) => i + 50));
    expect(status.outbox).toHaveLength(100);
    expect(status.outbox.find((reply: { id: string }) => reply.id === "001").text).toBe(
      "reply 149",
    );
  }
});

it("channel receipts older than 30 days are forgotten, newer ones kept", async () => {
  const scope = { businessId: crypto.randomUUID(), employeeId: crypto.randomUUID() };
  const probe = (
    env as { AGENT_STATUS: DurableObjectNamespace<AgentStatusProbe> }
  ).AGENT_STATUS.getByName(scopeName(scope));
  await probe.seed();
  // 150 old messages with their recent index and replies go; the new message and its index stay.
  expect(await probe.prune()).toBe(2);
});
