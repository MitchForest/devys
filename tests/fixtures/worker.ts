import { DurableObject } from "cloudflare:workers";
import { DynamicWorkerExecutor } from "@cloudflare/codemode";
export { PiRecoveryProbe } from "./pi.ts";
export { SessionsProbe } from "./sessions.ts";

interface Env {
  LOADER: WorkerLoader;
}
export class RecoveryProbe extends DurableObject<Env> {
  async execute(code: string) {
    const executor = new DynamicWorkerExecutor({ loader: this.env.LOADER, globalOutbound: null });
    return JSON.stringify(
      await executor.execute(code, {
        increment: async () => {
          const count = (await this.count()) + 1;
          await this.ctx.storage.put("count", count);
          return count;
        },
      }),
    );
  }
  async count() {
    return (await this.ctx.storage.get<number>("count")) ?? 0;
  }
}
export default {
  fetch() {
    return new Response("test fixture");
  },
};

import { DevysAgent } from "../../src/app/agent.ts";
export class AgentStatusProbe extends DevysAgent {
  async seed() {
    // Written in batches: one put per key is slow when the suite runs files in parallel.
    const entries: Record<string, unknown> = {};
    for (let index = 0; index < 150; index++) {
      const id = String(150 - index).padStart(3, "0");
      entries[`message:${id}`] = {
        id,
        receivedAt: index,
        text: `message ${index}`,
        control: "status",
        input: { messageId: id, senderId: "sender", chatId: "chat" },
      };
      entries[`recent:${String(index).padStart(16, "0")}:${id}`] = id;
      entries[`outbox:${id}`] = {
        id,
        chatId: "chat",
        text: `reply ${index}`,
        attempts: 1,
        status: "sent",
      };
    }
    const keys = Object.keys(entries);
    for (let at = 0; at < keys.length; at += 128)
      await this.ctx.storage.put(
        Object.fromEntries(keys.slice(at, at + 128).map((key) => [key, entries[key]])),
      );
  }

  /** Forgets receipts older than 30 days, then counts what is left. */
  async prune() {
    const now = Date.now();
    await this.ctx.storage.put(`message:new`, { id: "new", receivedAt: now });
    await this.ctx.storage.put(`recent:${String(now).padStart(16, "0")}:new`, "new");
    for (let pass = 0; pass < 4; pass++) await this.forgetOldMessages();
    return (await this.ctx.storage.list({ prefix: "" })).size;
  }
}
