/**
 * The trusted Mac host process (local mode): the runner and the coding delegates behind one
 * loopback server and one token. The local launcher bundles and supervises it.
 */
import { join } from "node:path";
import { claudeAdapter } from "./delegates/host/claude.ts";
import { codexAdapter } from "./delegates/host/codex.ts";
import { delegatesHost } from "./delegates/host/server.ts";
import { bunPty, terminalsHost } from "./terminal/host/server.ts";
import { startHost } from "./workspace/host/server.ts";

const token = process.env.DEVYS_HOST_TOKEN;
if (!token) throw new Error("DEVYS_HOST_TOKEN is required");
const home = process.env.HOME ?? "";
const work = process.env.DEVYS_HOST_WORK ?? join(home, "Devys");
const data = process.env.DEVYS_HOST_DATA ?? join(work, ".host");
const worker = process.env.DEVYS_WORKER_URL ?? "http://127.0.0.1:8787";

const codexHome = process.env.DEVYS_CODEX_HOME ?? join(home, ".codex");
const claudeConfig = process.env.DEVYS_CLAUDE_CONFIG_DIR ?? join(home, ".claude");
/** The owner's environment without Anthropic or Claude Code settings that override a login. */
const ownLogin = Object.fromEntries(
  Object.entries(process.env).filter(
    ([name]) => !name.startsWith("ANTHROPIC_") && !name.startsWith("CLAUDE"),
  ),
);

const terminals = terminalsHost({
  spawn: bunPty,
  env: process.env,
  shell: process.env.SHELL ?? "/bin/zsh",
  resume: ({ provider, session }) =>
    provider === "codex"
      ? { argv: ["codex", "resume", session], env: { ...process.env, CODEX_HOME: codexHome } }
      : {
          argv: ["claude", "--resume", session],
          env: { ...ownLogin, CLAUDE_CONFIG_DIR: claudeConfig },
        },
});

const delegates = delegatesHost({
  spared: () => terminals.ttys(),
  work,
  data,
  providers: (events) => ({
    codex: codexAdapter({ home: codexHome, env: process.env }, events),
    claude: claudeAdapter(
      {
        configDir: claudeConfig,
        env: process.env,
      },
      events,
    ),
  }),
  async deliver(events) {
    const response = await fetch(`${worker}/internal/delegates/events`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ events }),
    });
    if (!response.ok) throw new Error(`The Worker refused delegate events: ${response.status}`);
  },
});

const host = await startHost({
  token,
  data,
  work,
  skills: join(work, "skills"),
  port: Number(process.env.DEVYS_HOST_PORT ?? 8788),
  routes: [delegates, terminals],
});
console.log(`Devys Mac host on 127.0.0.1:${host.port}`);
const stop = () => void host.close().then(() => process.exit(0));
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
