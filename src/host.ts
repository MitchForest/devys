/**
 * The trusted Mac host process (local mode): the runner, coding sessions, terminals, the
 * businesses' browsers and the vault's master key behind one loopback server and one token. The
 * local launcher bundles and supervises it.
 */
import { join } from "node:path";
import { browsersHost } from "./browser/host/server.ts";
import { claudeAdapter } from "./apps/code/host/claude.ts";
import { codexAdapter } from "./apps/code/host/codex.ts";
import { codingHost } from "./apps/code/host/server.ts";
import { forgetHostSettings } from "./protocol/host.ts";
import { bunPty, terminalsHost } from "./terminal/host/server.ts";
import { confine } from "./workspace/host/seatbelt.ts";
import { startHost } from "./workspace/host/server.ts";
import type { OpenSecrets } from "./vault/contract.ts";
import { hostKeyring, openFor, vaultHost } from "./vault/host/server.ts";

const token = process.env.DEVYS_HOST_TOKEN;
if (!token) throw new Error("DEVYS_HOST_TOKEN is required");
const home = process.env.HOME ?? "";
// Each business works in ~/Devys/<business>, where the Worker expects it (src/app/mode.ts).
const work = join(home, "Devys");
const data = process.env.DEVYS_HOST_DATA ?? join(work, ".host");
const worker = process.env.DEVYS_WORKER_URL ?? "http://127.0.0.1:8787";
const port = Number(process.env.DEVYS_HOST_PORT ?? 8788);
/**
 * The server's own data outside the businesses folder, hidden from everything an employee
 * starts: the vault's master key, every business's browser profile, and, when installed, the
 * whole server folder (Postgres, the Worker's state and vars, logs, backups).
 */
const hidden = [data, ...(process.env.DEVYS_SERVER_HOME ? [process.env.DEVYS_SERVER_HOME] : [])];

/** The vault's master key, in the hidden data folder; secrets are opened only on this host. */
const keyring = await hostKeyring(data);
const open: OpenSecrets = (business, sealed, kinds) => openFor(keyring, business, sealed, kinds);

const codexHome = process.env.DEVYS_CODEX_HOME ?? join(home, ".codex");
const claudeConfig = process.env.DEVYS_CLAUDE_CONFIG_DIR ?? join(home, ".claude");
// Everything below inherits this environment: employees' shells, coding sessions and
// terminals. The host's settings, including its token, stop here.
forgetHostSettings(process.env);
/** The owner's environment without Anthropic or Claude Code settings that override a login. */
const ownLogin = Object.fromEntries(
  Object.entries(process.env).filter(
    ([name]) => !name.startsWith("ANTHROPIC_") && !name.startsWith("CLAUDE"),
  ),
);

/**
 * What an employee starts for a business (commands, coding harnesses, checks, deploys) cannot
 * reach the other businesses' folders. The owner's terminals are the owner's own and run as is.
 */
const confineTo =
  (folder: string, readOnly: boolean) => (command: string, args: readonly string[]) =>
    confine({ root: work, folder, readOnly, hidden }, command, args);

const terminals = terminalsHost({
  spawn: bunPty,
  env: process.env,
  shell: process.env.SHELL ?? "/bin/zsh",
  resume: ({ provider, session }) => {
    if (provider === "codex")
      return { argv: ["codex", "resume", session], env: { ...process.env, CODEX_HOME: codexHome } };
    if (provider === "claude")
      return {
        argv: ["claude", "--resume", session],
        env: { ...ownLogin, CLAUDE_CONFIG_DIR: claudeConfig },
      };
    throw new Error(`No coding provider ${provider}`);
  },
});

const coding = codingHost({
  open,
  spared: () => terminals.ttys(),
  work,
  data,
  confine: confineTo,
  providers: (events, confined) => ({
    codex: codexAdapter({ home: codexHome, env: process.env, confine: confined }, events),
    claude: claudeAdapter(
      {
        configDir: claudeConfig,
        env: process.env,
        confine: confined,
      },
      events,
    ),
  }),
  async deliver(events) {
    const response = await fetch(`${worker}/internal/coding/events`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ events }),
    });
    if (!response.ok) throw new Error(`The Worker refused coding events: ${response.status}`);
    return ((await response.json()) as { delivered: string[] }).delivered;
  },
});

const host = await startHost({
  token,
  data,
  hidden,
  work,
  port,
  open,
  routes: [coding, terminals, browsersHost({ data, work, open }), vaultHost(keyring)],
});
console.log(`Devys Mac host on 127.0.0.1:${host.port}`);
const stop = () => void host.close().then(() => process.exit(0));
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
