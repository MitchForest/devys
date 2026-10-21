import { Effect } from "effect";
import type { Env } from "./env.ts";
import { ref } from "../protocol/ref.ts";
import { providerName } from "../apps/code/capabilities.ts";
import type { Provider } from "../apps/code/contract.ts";
import { codingSession, codingSessionsFor } from "../apps/code/service.ts";
import type { Business, Person } from "../identity/contract.ts";
import { workItem, setTakeover } from "../work/service.ts";
import { postEvent } from "./conversations.ts";
import { modeOf } from "./mode.ts";
import { body } from "./request.ts";
import { respond } from "../protocol/http.ts";
import { TerminalSession } from "../terminal/contract.ts";
import { Closed, Terminals } from "./wire.ts";

type Access = { person: Person; business: Business; trusted: boolean; path: string };
/**
 * The owner's terminals (.docs/PRODUCT_EXPERIENCE.md#first-class-coding-workspace): a business
 * terminal in its folder, a work item's build worktree, or a coding agent's own CLI resumed on
 * its session. Opening one on a work item takes the work over, so its employee stops acting on it.
 * Terminals are the owner acting directly on the Mac; employees use `run`.
 */
export async function terminalRoute(request: Request, env: Env, access: Access) {
  const { person, business, trusted, path } = access;
  if (path !== "/terminals" && !path.startsWith("/terminals/")) return undefined;
  const mode = modeOf(env);
  const terminals = mode.terminals(business.id);
  if (path === "/terminals" && request.method === "GET")
    return respond(Terminals, {
      terminals: await terminals.list({ businessId: business.id, employeeId: "owner" }),
    });
  // Everything else acts on the Mac: a bearer token, or a browser request from this origin.
  if (!trusted) return new Response("Forbidden", { status: 403 });
  const socket = /^\/terminals\/([A-Za-z0-9-]{1,64})\/socket$/.exec(path)?.[1];
  if (socket && request.headers.get("upgrade")?.toLowerCase() === "websocket") {
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    server.accept();
    const offset = Number(new URL(request.url).searchParams.get("offset") ?? 0) || 0;
    void terminals
      .relay({ businessId: business.id, employeeId: "owner" }, server, { id: socket, offset })
      .catch(() => server.close(1011, "Terminal unavailable"));
    return new Response(null, { status: 101, webSocket: client });
  }
  const closing = /^\/terminals\/([A-Za-z0-9-]{1,64})\/close$/.exec(path)?.[1];
  if (closing && request.method === "POST") {
    await terminals.close({ businessId: business.id, employeeId: "owner" }, closing);
    return respond(Closed, { closed: true });
  }
  if (path !== "/terminals" || request.method !== "POST")
    return new Response("Not found", { status: 404 });
  const input = (await body(request, 4_000)) as {
    work?: string;
    resume?: string;
    cols?: number;
    rows?: number;
  };
  const size = { cols: clamp(input.cols, 80), rows: clamp(input.rows, 24) };
  const scope = { businessId: business.id, employeeId: "owner" };
  // A coding agent's own CLI on its session: stop the background turn first, then take over.
  if (input.resume) {
    const item = await Effect.runPromise(codingSession(env.HYPERDRIVE, business.id, input.resume));
    if (!item?.provider_session_id || !item.worktree)
      return new Response("No such coding session", { status: 404 });
    await mode
      .coding({ businessId: business.id, employeeId: item.employee_id })
      .interrupt(item.id)
      .catch(() => undefined);
    await takeOver(
      env,
      business.id,
      item.work_item_id,
      person,
      `${person.display_name} opened ${providerName(item.provider)} in a terminal.`,
      item.id,
    );
    return respond(
      TerminalSession,
      await terminals.open({
        scope,
        title: `${providerName(item.provider)} · ${item.branch ?? item.id.slice(0, 8)}`,
        cwd: item.worktree,
        resume: { provider: item.provider as Provider, session: item.provider_session_id },
        codingSessionId: item.id,
        ...size,
      }),
      { status: 201 },
    );
  }
  // A work item's build worktree.
  if (input.work) {
    const work = await Effect.runPromise(workItem(env.HYPERDRIVE, business.id, input.work));
    const build = (
      await Effect.runPromise(codingSessionsFor(env.HYPERDRIVE, business.id, input.work))
    )
      .filter((item) => item.purpose === "build" && item.worktree)
      .at(-1);
    if (!work || !build?.worktree)
      return new Response("This work item has no worktree yet", { status: 404 });
    await takeOver(
      env,
      business.id,
      work.id,
      person,
      `${person.display_name} opened a terminal in the worktree.`,
      build.id,
    );
    return respond(
      TerminalSession,
      await terminals.open({ scope, title: work.title, cwd: build.worktree, ...size }),
      { status: 201 },
    );
  }
  // The business's own folder on the Mac.
  return respond(
    TerminalSession,
    await terminals.open({
      scope,
      title: business.name,
      cwd: mode.businessFolder(business.id)!,
      ...size,
    }),
    { status: 201 },
  );
}

const clamp = (value: number | undefined, fallback: number) =>
  Number.isInteger(value) && value! > 10 && value! < 1000 ? value! : fallback;

async function takeOver(
  env: Env,
  businessId: string,
  workId: string,
  person: Person,
  note: string,
  /** The coding session it takes over. */
  codingSessionId: string,
) {
  await Effect.runPromise(setTakeover(env.HYPERDRIVE, businessId, workId, person.id));
  await postEvent(env, businessId, `work:${workId}`, {
    clientId: `terminal:${crypto.randomUUID()}`,
    text: note,
    ref: ref("code", "session", codingSessionId),
  });
}
