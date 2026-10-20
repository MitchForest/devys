import type { Env } from "./app/env.ts";
import { WebhookError } from "./channels/photon.ts";
import { createStartHandler, defaultStreamHandler } from "@tanstack/react-start/server";
import { apiRoute } from "./app/http.ts";
import { minuteTick } from "./app/dispatch.ts";
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
      const headers = { "cache-control": "no-store" };
      if (error instanceof WebhookError)
        return new Response(error.message, { status: error.status, headers });
      // Malformed or oversized input is the sender's to fix, not an outage.
      if (error instanceof SyntaxError)
        return new Response("Send valid JSON", { status: 400, headers });
      if (error instanceof Error && error.message === "Input exceeds limit")
        return new Response("The request is too large", { status: 413, headers });
      console.error("Request failed:", error);
      return new Response("Request could not be completed", { status: 503, headers });
    }
  },
  /** Every minute: unanswered decisions expire and ready work reaches its employees. */
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(minuteTick(env));
  },
} satisfies ExportedHandler<Env>;
