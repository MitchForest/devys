import type { Env } from "../infra/api.ts";
import { WebhookError } from "./channels/photon.ts";
import { createStartHandler, defaultStreamHandler } from "@tanstack/react-start/server";
import { apiRoute } from "./app/http.ts";
import { dispatchDue } from "./app/dispatch.ts";
export { DevysAgent } from "./app/agent.ts";
export { Workspace } from "./workspace/workspace.ts";
export { PublicEgress } from "./egress/public.ts";
export { DirectoryBackupGateway } from "@cloudflare/sandbox";
const render = createStartHandler(defaultStreamHandler);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const response = (await apiRoute(request, env)) ?? (await render(request));
      // A WebSocket upgrade is handed over as it is.
      if (response.status === 101) return response;
      response.headers.set("cache-control", "no-store");
      response.headers.set("x-content-type-options", "nosniff");
      response.headers.set("referrer-policy", "no-referrer");
      return response;
    } catch (error) {
      return new Response(
        error instanceof WebhookError ? error.message : "Request could not be completed",
        {
          status: error instanceof WebhookError ? error.status : 503,
          headers: { "cache-control": "no-store" },
        },
      );
    }
  },
  /** Every minute: hand ready work to its employees. */
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(dispatchDue(env));
  },
} satisfies ExportedHandler<Env>;
