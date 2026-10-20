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
    for (let index = 0; index < 150; index++) {
      const id = String(150 - index).padStart(3, "0");
      await this.ctx.storage.put(`message:${id}`, {
        id,
        receivedAt: index,
        text: `message ${index}`,
        control: "status",
        input: { messageId: id, senderId: "sender", chatId: "chat" },
      });
      await this.ctx.storage.put(`recent:${String(index).padStart(16, "0")}:${id}`, id);
      await this.ctx.storage.put(`outbox:${id}`, {
        id,
        chatId: "chat",
        text: `reply ${index}`,
        attempts: 1,
        status: "sent",
      });
    }
  }
}
