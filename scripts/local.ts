/**
 * Local mode: all of Devys on the owner's Mac, reached over Tailscale
 * (see .docs/COMPONENTS.md#deployment-modes). The constants below are its configuration;
 * the tailnet address is read from the machine. Data lives outside any checkout, so
 * development resets never touch it.
 *
 *   bun scripts/local.ts install    build, copy the app, serve it on the tailnet, start at login
 *   bun scripts/local.ts uninstall  stop and remove the LaunchAgent (data is kept)
 *   bun scripts/local.ts run        what launchd runs: Postgres, the Worker, the minute tick
 *   bun scripts/local.ts backup     dump Postgres and archive the Workers state now
 *   bun scripts/local.ts webhooks   publish only /webhooks/ to the internet with Funnel
 *   bun scripts/local.ts code       a sign-in code for the owner, as a code and a devys:// link
 *   bun scripts/local.ts status
 */
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir, userInfo } from "node:os";
import { join, resolve } from "node:path";
import { bin } from "./db.ts";

const checkout = resolve(import.meta.dirname, "..");
// Not "Devys": the Devys Mac app already keeps its own files there.
const home =
  process.env.DEVYS_LOCAL_HOME ?? join(homedir(), "Library/Application Support/Devys Server");
export const paths = {
  app: join(home, "app"),
  postgres: join(home, "postgres"),
  state: join(home, "state"),
  backups: join(home, "backups"),
  logs: join(home, "logs"),
  host: join(home, "host"),
};
export const appPort = 8787;
export const postgresPort = 54330;
const hostPort = 8788;
const webhookPort = 8443;
const label = "dev.devys.local";
const agentPath = join(homedir(), "Library/LaunchAgents", `${label}.plist`);
const keepBackups = 14;
const database = `postgres://devys:devys@127.0.0.1:${postgresPort}/devys`;
const postgresEnv = { DEVYS_PG_DATA: paths.postgres, DEVYS_PG_PORT: String(postgresPort) };

type ServeStatus = {
  TCP?: Record<string, { TCPForward?: string }>;
  Web?: Record<string, { Handlers?: Record<string, { Proxy?: string }> }>;
};

/**
 * The address other tailnet devices use. HTTPS Serve (needs the tailnet admin to enable
 * Serve once) is preferred because browsers keep secure session cookies there; a plain
 * TCP forward needs no approval, is still encrypted by WireGuard, and serves the apps.
 */
export function tailnetUrl(
  status: ServeStatus,
  machine: string | undefined,
  port = appPort,
): string | undefined {
  for (const [host, web] of Object.entries(status.Web ?? {})) {
    const proxy = web.Handlers?.["/"]?.Proxy;
    if (proxy && new URL(proxy).port === String(port))
      return `https://${host.replace(/:443$/, "")}`;
  }
  if (machine && status.TCP?.[String(port)]?.TCPForward === `127.0.0.1:${port}`)
    return `http://${machine}:${port}`;
  return undefined;
}

/** This Mac's tailnet machine name (the first label of its MagicDNS name). */
function machineName(): string | undefined {
  const result = spawnSync("tailscale", ["status", "--json"], { encoding: "utf8" });
  if (result.status !== 0) return undefined;
  const self = (JSON.parse(result.stdout) as { Self?: { DNSName?: string } }).Self;
  return self?.DNSName?.split(".")[0] || undefined;
}

function serveStatus(): ServeStatus {
  const result = spawnSync("tailscale", ["serve", "status", "--json"], { encoding: "utf8" });
  if (result.status !== 0 || !result.stdout.trim()) return {};
  return JSON.parse(result.stdout) as ServeStatus;
}

export const publicUrl = () =>
  tailnetUrl(serveStatus(), machineName()) ?? `http://127.0.0.1:${appPort}`;

/**
 * The owner's PATH from an interactive login shell, so employees' commands find the same
 * tools (bun, codex, claude, gh…) as the owner's terminal does.
 */
function ownerPath() {
  const shell = process.env.SHELL ?? "/bin/zsh";
  const result = spawnSync(shell, ["-lic", 'printf "%s" "$PATH"'], {
    encoding: "utf8",
    timeout: 10_000,
  });
  const path = result.status === 0 ? result.stdout.trim().split("\n").at(-1) : undefined;
  return path || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
}

/** The LaunchAgent that keeps `run` alive across logins, crashes and reboots. */
export function launchAgent(bun: string, script: string, logs: string, path: string) {
  const escape = (value: string) =>
    value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array><string>${escape(bun)}</string><string>${escape(script)}</string><string>run</string></array>
  <key>WorkingDirectory</key><string>${escape(checkout)}</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>${escape(path)}</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>${escape(join(logs, "launcher.log"))}</string>
  <key>StandardErrorPath</key><string>${escape(join(logs, "launcher.log"))}</string>
</dict>
</plist>
`;
}

function must(command: string, args: string[], env: Record<string, string> = {}) {
  const result = spawnSync(command, args, {
    cwd: checkout,
    env: { ...process.env, ...env },
    stdio: "inherit",
  });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed`);
}

const log = (message: string) => console.log(`${new Date().toISOString()} ${message}`);

/**
 * Publishes the app on the tailnet. Serve must first be enabled for the tailnet, which
 * only its admin can do in a browser; until then the CLI waits, so give up after a
 * moment, print its instructions, and leave Devys reachable on this Mac.
 */
async function serve(explain = true) {
  if (spawnSync("tailscale", ["version"]).status !== 0) {
    if (explain) log("Tailscale is not installed; Devys is reachable on this Mac only.");
    return;
  }
  // Always available: the apps reach Devys at http://<this Mac>:8787 on the tailnet.
  await tailscale(["serve", "--bg", `--tcp=${appPort}`, `tcp://127.0.0.1:${appPort}`], 15_000);
  const result = await tailscale(["serve", "--bg", String(appPort)], 15_000);
  if (result.status === 0 || !explain) return;
  log(`HTTPS Serve is not enabled on this tailnet; the apps use ${publicUrl()}.
${result.output.trim()}
Devys switches to HTTPS within ten minutes of Serve being enabled.`);
}

/**
 * Runs the Tailscale CLI, killing it after `ms`. The `tailscale` on PATH is often a shell
 * wrapper and the CLI ignores SIGTERM while it waits for approval, so the timeout kills
 * the whole process group; otherwise each try leaves a waiting CLI behind.
 */
function tailscale(args: string[], ms: number) {
  return new Promise<{ status: number | null; output: string }>((done) => {
    const child = spawn("tailscale", args, { detached: true, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk) => (output += chunk));
    child.stderr.on("data", (chunk) => (output += chunk));
    const timer = setTimeout(() => process.kill(-child.pid!, "SIGKILL"), ms);
    child.on("close", (status) => {
      clearTimeout(timer);
      done({ status, output });
    });
  });
}

async function install() {
  for (const dir of Object.values(paths)) mkdirSync(dir, { recursive: true });
  must(process.execPath, ["run", "build"]);
  // The running app is a copy, so a later development build cannot change it.
  rmSync(paths.app, { recursive: true, force: true });
  cpSync(join(checkout, "dist"), paths.app, { recursive: true });
  must(process.execPath, [
    "build",
    "src/host.ts",
    "--target=bun",
    `--outfile=${join(paths.app, "host.js")}`,
  ]);
  must(process.execPath, ["scripts/db.ts", "migrate"], postgresEnv);
  await serve();
  mkdirSync(join(homedir(), "Library/LaunchAgents"), { recursive: true });
  writeFileSync(
    agentPath,
    launchAgent(process.execPath, join(checkout, "scripts/local.ts"), paths.logs, ownerPath()),
  );
  const domain = `gui/${userInfo().uid}`;
  spawnSync("launchctl", ["bootout", `${domain}/${label}`]);
  // bootout returns before the old service is gone; bootstrapping too early fails with EIO.
  for (let attempt = 1; ; attempt++) {
    if (spawnSync("launchctl", ["bootstrap", domain, agentPath]).status === 0) break;
    if (attempt === 10) throw new Error(`launchctl bootstrap ${domain} ${agentPath} failed`);
    spawnSync("sleep", ["1"]);
  }
  log(`Devys is starting at ${publicUrl()}. Logs: ${paths.logs}`);
}

function uninstall() {
  spawnSync("launchctl", ["bootout", `gui/${userInfo().uid}/${label}`]);
  rmSync(agentPath, { force: true });
  log(`Stopped. Data is kept in ${home}.`);
}

/** Publishes only /webhooks/ to the internet, on its own port; the app stays tailnet-only. */
function webhooks() {
  must("tailscale", [
    "funnel",
    "--bg",
    `--https=${webhookPort}`,
    "--set-path=/webhooks",
    `http://127.0.0.1:${appPort}/webhooks`,
  ]);
  const base = publicUrl();
  log(
    `Webhooks: ${base}:${webhookPort}/webhooks/… (for example ${base}:${webhookPort}/webhooks/photon)`,
  );
}

/** A one-hour sign-in code for the owner, printed as a code and a link the apps open. */
function code() {
  const file = join(home, `code-${Date.now()}`);
  must(
    process.execPath,
    ["scripts/enroll.ts", "--name", "Owner", "--owner", "--out", file],
    postgresEnv,
  );
  const value = readFileSync(file, "utf8").trim();
  rmSync(file);
  const server = publicUrl();
  console.log(`Server: ${server}\nCode:   ${value}`);
  console.log(`Link:   devys://enroll?server=${encodeURIComponent(server)}&code=${value}`);
}

function backup() {
  mkdirSync(paths.backups, { recursive: true });
  const stamp = new Date().toISOString().replaceAll(":", "-").slice(0, 19);
  must(bin("pg_dump"), [
    "--format=custom",
    `--file=${join(paths.backups, `devys-${stamp}.dump`)}`,
    database,
  ]);
  // Pi state and file bytes. Taken while the Worker runs, so it is crash-consistent at best.
  must("tar", ["-czf", join(paths.backups, `state-${stamp}.tar.gz`), "-C", home, "state"]);
  for (const prefix of ["devys-", "state-"]) {
    const old = readdirSync(paths.backups)
      .filter((name) => name.startsWith(prefix))
      .sort()
      .slice(0, -keepBackups);
    for (const name of old) rmSync(join(paths.backups, name));
  }
  log(`Backup written to ${paths.backups}`);
}

/**
 * A Worker left by a launcher that died hard (wrangler respawns workerd) would hold the
 * port forever. Stop listeners on the app port that run from this checkout, and their
 * wrangler parents; never touch anything else.
 */
function clearPort(port: number) {
  const command = (pid: string) =>
    spawnSync("ps", ["-o", "command=", "-p", pid], { encoding: "utf8" }).stdout;
  const listeners = spawnSync("lsof", ["-nP", "-t", `-iTCP:${port}`, "-sTCP:LISTEN"], {
    encoding: "utf8",
  }).stdout.split("\n");
  for (const pid of listeners.filter(Boolean)) {
    const parent = spawnSync("ps", ["-o", "ppid=", "-p", pid], { encoding: "utf8" }).stdout.trim();
    for (const target of [parent, pid])
      if (target !== "1" && command(target).includes(join(checkout, "node_modules"))) {
        log(`Stopping leftover Devys process ${target} on port ${port}`);
        process.kill(Number(target), "SIGKILL");
      }
  }
}

/** One supervised child in its own process group, restarted with backoff when it exits. */
function supervise(
  name: string,
  start: () => { command: string; args: string[]; env: NodeJS.ProcessEnv },
) {
  let child: ChildProcess | undefined;
  let stopping = false;
  let delay = 1_000;
  const launch = () => {
    const startedAt = Date.now();
    const { command, args, env } = start();
    // Its own process group, so stopping it also stops grandchildren such as workerd.
    child = spawn(command, args, { cwd: checkout, env, stdio: "inherit", detached: true });
    const group = child.pid!;
    child.on("exit", (code) => {
      try {
        process.kill(-group, "SIGKILL");
      } catch {}
      if (stopping) return;
      // Back off only while it keeps failing quickly; a long run resets the delay.
      delay = Date.now() - startedAt > 60_000 ? 1_000 : Math.min(delay * 2, 30_000);
      log(`${name} exited (${code}); restarting in ${delay / 1000}s`);
      setTimeout(launch, delay);
    });
  };
  launch();
  return {
    /** Restart now, for example to pick up a new tailnet address. */
    restart: () => child?.pid && process.kill(-child.pid, "SIGTERM"),
    stop: () =>
      new Promise<void>((resolve) => {
        stopping = true;
        if (!child?.pid || child.exitCode !== null) return resolve();
        child.once("exit", () => resolve());
        process.kill(-child.pid, "SIGTERM");
      }),
  };
}

/** The Mac host's token, created once and kept in the data directory. */
function hostToken() {
  const file = join(home, "host-token");
  if (!existsSync(file))
    writeFileSync(file, Buffer.from(randomBytes(32)).toString("hex"), { mode: 0o600 });
  return readFileSync(file, "utf8").trim();
}

async function run() {
  for (const dir of Object.values(paths)) mkdirSync(dir, { recursive: true });
  clearPort(appPort);
  clearPort(hostPort);
  if (
    !existsSync(join(paths.app, "server/wrangler.json")) ||
    !existsSync(join(paths.app, "host.js"))
  )
    throw new Error("No installed app; run `bun scripts/local.ts install` first.");
  must(process.execPath, ["scripts/db.ts", "migrate"], postgresEnv);
  const token = hostToken();
  let url = publicUrl();
  const host = supervise("Mac host", () => ({
    command: process.execPath,
    args: [join(paths.app, "host.js")],
    env: {
      ...process.env,
      DEVYS_HOST_TOKEN: token,
      DEVYS_HOST_PORT: String(hostPort),
      DEVYS_HOST_DATA: paths.host,
      // Delegate events come back to the Worker on loopback.
      DEVYS_WORKER_URL: `http://127.0.0.1:${appPort}`,
    },
  }));
  const worker = supervise("Worker", () => ({
    command: join(checkout, "node_modules/.bin/wrangler"),
    args: [
      "dev",
      `--config=${join(paths.app, "server/wrangler.json")}`,
      `--persist-to=${paths.state}`,
      "--ip=127.0.0.1",
      `--port=${appPort}`,
      `--var=PUBLIC_URL:${url}`,
      `--var=DEVYS_HOST_TOKEN:${token}`,
      `--var=DEVYS_HOST_HOME:${homedir()}`,
      "--show-interactive-dev-session=false",
    ],
    env: {
      ...process.env,
      CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: database,
      WRANGLER_SEND_METRICS: "false",
    },
  }));
  log(`Devys local mode serving ${url}`);

  let lastBackupDay = "";
  const tick = setInterval(async () => {
    try {
      const response = await fetch(
        `http://127.0.0.1:${appPort}/cdn-cgi/handler/scheduled?cron=*+*+*+*+*`,
      );
      if (!response.ok) log(`Dispatch tick failed: ${response.status}`);
    } catch {
      // The Worker is starting or restarting; the next tick dispatches.
    }
    // Publish on the tailnet once Serve is enabled, and serve the new address. Each try
    // waits up to 15 seconds for an approval only an admin can give, so try every ten minutes.
    if (!url.startsWith("https://") && new Date().getMinutes() % 10 === 0) {
      await serve(false);
      const next = publicUrl();
      if (next !== url) {
        url = next;
        log(`Now reachable on the tailnet at ${url}`);
        worker.restart();
      }
    }
    const now = new Date();
    const day = now.toDateString();
    if (now.getHours() === 3 && day !== lastBackupDay) {
      lastBackupDay = day;
      try {
        backup();
      } catch (error) {
        log(`Backup failed: ${error instanceof Error ? error.message : error}`);
      }
    }
  }, 60_000);

  const stop = async () => {
    clearInterval(tick);
    setTimeout(() => process.exit(0), 10_000).unref();
    await Promise.all([worker.stop(), host.stop()]);
    process.exit(0);
  };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}

async function status() {
  const url = publicUrl();
  const loaded = spawnSync("launchctl", ["print", `gui/${userInfo().uid}/${label}`]).status === 0;
  let reachable = "not responding";
  try {
    reachable = `HTTP ${(await fetch(`http://127.0.0.1:${appPort}/api/status`)).status}`;
  } catch {}
  const backups = existsSync(paths.backups)
    ? readdirSync(paths.backups).filter((name) => name.startsWith("devys-")).length
    : 0;
  console.log(`LaunchAgent ${loaded ? "loaded" : "not loaded"}`);
  console.log(`App ${reachable} on 127.0.0.1:${appPort}; address ${url}`);
  console.log(`Data ${home}; ${backups} database backups`);
}

if (import.meta.main) {
  const command = process.argv[2] ?? "status";
  const commands: Record<string, () => unknown> = {
    install,
    uninstall,
    run,
    backup,
    webhooks,
    code,
    status,
  };
  const selected = commands[command];
  if (!selected) throw new Error(`Unknown command: ${command}`);
  await selected();
}
