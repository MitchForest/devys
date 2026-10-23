/**
 * A real-model scenario run: `bun run scenario tests/scenarios/<name>.ts`.
 *
 * Starts its own Mac host (the owner's real HOME, so Chrome and the login keychain work, with its
 * own host data folder) and a development server pointed at it (its own port and Workers state;
 * the host's token passes in the environment, never a file), fires the minute tick, seeds a sample
 * business, then plays the owner: each turn says something, taps the suggested reply that matches
 * a persona fact, answers an `askOwner` the scenario scripts, or stops at one. It never types for
 * the owner: a question without a matching chip fails the step. It stops at spend approvals,
 * connects and take-overs unless the next turn scripts them. Everything is torn down after.
 *
 * Results go to `.scratch/scenarios/<name>/<timestamp>/`: `summary.md` (steps and rubric),
 * `transcript.md` (what the owner reads), `wire.json` (every message, request and work item as
 * the clients receive them) and screenshots at each owner touch (1440×900 and 390×844). The
 * owner's local install (:8787, Postgres 54330) is never touched: this uses its own database in
 * the development Postgres and ports 5190 (app) and 8798 (host), or `DEVYS_SCENARIO_APP_PORT` and
 * `DEVYS_SCENARIO_HOST_PORT` beside another run.
 */
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import {
  createWriteStream,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { chromium, type Browser, type BrowserContext } from "@playwright/test";
import pg from "pg";
import { browser } from "../src/apps/browser/app.ts";
import { code } from "../src/apps/code/app.ts";
import { computer } from "../src/apps/computer/app.ts";
import { conversations } from "../src/apps/conversations/app.ts";
import { documents } from "../src/apps/documents/app.ts";
import { memory } from "../src/apps/memory/app.ts";
import { team } from "../src/apps/team/app.ts";
import { web } from "../src/apps/web/app.ts";
import { work } from "../src/apps/work/app.ts";
import type { HireableRoleId } from "../src/protocol/roles.ts";
import type { NewSecret } from "../src/vault/contract.ts";
import { createDatabase, databaseUrl, dropDatabase, migrate } from "./db.ts";
import { hostEnvironment } from "./local.ts";

/** An `askOwner` request's kind, or `spend` for an approve with an amount. */
export type AskKind =
  | "decision"
  | "approve"
  | "spend"
  | "take_over"
  | "secret"
  | "connect"
  | "file";

/** One thing the owner does, then waits for the team to settle. */
export type Turn =
  /** Says this. `to`: an employee's name (their direct chat) or `thread` (the latest work thread); the Chief of Staff by default. */
  | { say: string; to?: string }
  /**
   * Taps the suggested reply matching this persona fact (any other fact if none does), or the
   * first one (the recommendation) for a key the persona lacks. `optional`: skipped when the
   * team's latest message asks nothing, for a question that may or may not come.
   */
  | { tap: string; optional?: boolean }
  /** Ends the run, passing, at the first pending request of this kind (or one of these). */
  | { stop: AskKind | AskKind[] }
  /**
   * Taps Start on the latest plan waiting for it, as the owner who read it. `optional`: skipped
   * when no plan waits.
   */
  | { start: true; optional?: boolean }
  /** Adds the secret a pending secret request asks for, under the name it asks for. */
  | { answer: "secret"; secret: NewSecret }
  /** Answers a pending approve (not a spend: that needs a device signature) or decision. */
  | { answer: "approve" | "reject" };

export interface Scenario {
  /** The results folder's name. */
  name: string;
  business: {
    name: string;
    brief?: string;
    /** Employees hired besides the Chief of Staff. */
    team?: { template: HireableRoleId; name?: string; responsibilities?: string }[];
    /** Secrets and cards already saved. */
    secrets?: NewSecret[];
    /** What the business has already told the Chief of Staff to remember. */
    memories?: string[];
    /** Business apps to install by id. */
    apps?: string[];
    /**
     * Git repositories already in the business folder (`repos/<name>`), each committed once on
     * `main` with these files (path to contents) and no remote.
     */
    repositories?: { name: string; files: Record<string, string> }[];
  };
  /** What the owner knows, by key: the answers a tap looks for. */
  persona: Record<string, string>;
  turns: Turn[];
  /** How long a turn may take before the step fails; 10 by default. */
  turnMinutes?: number;
}

const checkout = resolve(import.meta.dirname, "..");
const ports = {
  app: Number(process.env.DEVYS_SCENARIO_APP_PORT ?? 5190),
  host: Number(process.env.DEVYS_SCENARIO_HOST_PORT ?? 8798),
};
const base = `http://127.0.0.1:${ports.app}`;
/**
 * The run's own database, made fresh and dropped afterwards: a dev server's minute tick hands
 * every business's ready work to its own employees and host, so runs must not share one.
 */
const database = `devys_scenario_${ports.app}`;
const hex = () => Buffer.from(randomBytes(32)).toString("hex");
const sha = (value: string) => createHash("sha256").update(value).digest("hex");
const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));
const log = (message: string) =>
  console.log(`${new Date().toISOString().slice(11, 19)} ${message}`);

/** Every capability name the employees could mention: none belongs in what the owner reads. */
const capabilityNames = [
  ...[browser, code, computer, conversations, documents, memory, team, web, work].flatMap(
    (app) => app.capabilities,
  ),
  "askOwner",
  "suggestReplies",
  "describe_capabilities",
  "execute",
];

// Processes.

/** A child in its own process group (so its own children stop with it), logging to a file. */
function start(name: string, args: string[], env: NodeJS.ProcessEnv, logFile: string) {
  const out = createWriteStream(logFile);
  const child = spawn(args[0]!, args.slice(1), {
    cwd: checkout,
    env,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout!.pipe(out);
  child.stderr!.pipe(out);
  child.on("exit", (status) => log(`${name} exited (${status})`));
  return child;
}

async function stop(child: ChildProcess | undefined) {
  if (!child?.pid || child.exitCode !== null) return;
  const exited = new Promise((done) => child.once("exit", done));
  try {
    process.kill(-child.pid, "SIGTERM");
  } catch {}
  await Promise.race([exited, sleep(10_000)]);
  try {
    process.kill(-child.pid, "SIGKILL");
  } catch {}
}

async function until(what: string, check: () => Promise<boolean>, ms: number) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (await check().catch(() => false)) return;
    await sleep(1_000);
  }
  throw new Error(`Timed out waiting for ${what}`);
}

const portFree = (port: number) =>
  !spawnSync("lsof", ["-nP", "-t", `-iTCP:${port}`, "-sTCP:LISTEN"], {
    encoding: "utf8",
  }).stdout.trim();

// The owner's API.

type Message = {
  id: string;
  conversation: string;
  author: string;
  kind: string;
  text: string;
  replies: string[];
  created_at: string;
};
type Decision = {
  id: string;
  kind: string;
  employee_id: string;
  capability: string;
  input: Record<string, unknown>;
  work_item_id: string | null;
  conversation: string | null;
  status: string;
  requested_at: string;
};
type WorkItem = Record<string, unknown> & {
  id: string;
  title: string;
  state: string;
  steps: { title: string; state: string; by?: "owner" }[];
};
type Employee = { id: string; name: string; template: string };

function owner(token: string, businessId: string) {
  const call = async <T>(path: string, init: { method?: string; body?: unknown } = {}) => {
    const response = await fetch(`${base}/api/businesses/${businessId}${path}`, {
      method: init.method ?? (init.body === undefined ? "GET" : "POST"),
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
    });
    if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
    return (await response.json()) as T;
  };
  return {
    business: businessId,
    token,
    call,
    employees: async () => (await call<{ employees: Employee[] }>("")).employees,
    conversations: async () =>
      (await call<{ conversations: { key: string; last: Message | null }[] }>("/conversations"))
        .conversations,
    messages: async (key: string) =>
      (await call<{ messages: Message[] }>(`/conversations/${encodeURIComponent(key)}`)).messages,
    decisions: async () => (await call<{ decisions: Decision[] }>("/decisions")).decisions,
    work: async () => (await call<{ work_items: WorkItem[] }>("/work")).work_items,
    status: (employee: string) =>
      call<{
        state: { run: { stopped: boolean } | null; inbox: { status: string }[] };
      }>(`/employees/${employee}/status`),
    post: (key: string, text: string, replyTo?: string) =>
      call<{ message: Message }>(`/conversations/${encodeURIComponent(key)}/messages`, {
        body: { id: randomUUID(), text, ...(replyTo ? { reply_to: replyTo } : {}) },
      }),
  };
}
type Owner = ReturnType<typeof owner>;

const kindOf = (decision: Decision): AskKind =>
  decision.kind === "approve" && decision.input.amount ? "spend" : (decision.kind as AskKind);
const matches = (wanted: AskKind | AskKind[], decision: Decision) =>
  [wanted]
    .flat()
    .some(
      (kind) => kindOf(decision) === kind || (kind === "approve" && decision.kind === "approve"),
    );

/** The minute tick, as the local launcher fires it. */
const tick = () =>
  fetch(`${base}/cdn-cgi/handler/scheduled?cron=*+*+*+*+*`).then(
    (response) => response.ok,
    () => false,
  );

/**
 * Waits until the team is quiet: no employee running or holding queued input and no ready work
 * waiting for the minute tick (fired at once), twice in a row.
 */
async function settle(api: Owner, minutes: number) {
  const deadline = Date.now() + minutes * 60_000;
  let quiet = 0;
  while (Date.now() < deadline) {
    // A request failing while the Worker reloads counts as busy.
    const looked = await look(api).catch(() => undefined);
    const busy = looked?.busy ?? true;
    const ready = looked?.ready ?? false;
    if (ready && !busy) await tick();
    quiet = busy || ready ? 0 : quiet + 1;
    if (quiet >= 3) return true;
    await sleep(2_000);
  }
  return false;
}

/** Whether anyone is working, and whether ready work waits for the minute tick. */
async function look(api: Owner) {
  const employees = await api.employees();
  const statuses = await Promise.all(employees.map((employee) => api.status(employee.id)));
  const items = await api.work();
  // A coding session works outside the employee's run; its employee hears when its turn ends.
  const coding = await Promise.all(
    items.map((item) =>
      api
        .call<{ sessions: { state: string }[] }>(`/work/${item.id}/sessions`)
        .then(({ sessions }) => sessions.some((session) => session.state === "working")),
    ),
  );
  const busy =
    coding.some(Boolean) ||
    statuses.some(
      ({ state }) =>
        (state.run && !state.run.stopped) ||
        state.inbox.some((item) => item.status === "queued" || item.status === "running"),
    );
  return { busy, ready: items.some((item) => item.state === "ready") };
}

// Reading what the owner reads.

/** Every message in every conversation, oldest first. */
async function everything(api: Owner) {
  const keys = (await api.conversations()).map((conversation) => conversation.key);
  const all = (await Promise.all(keys.map((key) => api.messages(key)))).flat();
  return all.sort((a, b) => a.created_at.localeCompare(b.created_at));
}

/** The words of a request card the owner reads. */
const requestText = (decision: Decision) =>
  ["action", "counterparty", "renewal", "reason", "why", "purpose", "question", "url"]
    .flatMap((key) =>
      typeof decision.input[key] === "string" ? [String(decision.input[key])] : [],
    )
    .concat(Array.isArray(decision.input.steps) ? decision.input.steps.map(String) : []);

/** A work item's words the owner reads: no ids, times, states, authors or commands. */
function workText(value: unknown, key = ""): string[] {
  if (
    /(^id$|_id$|_at$|^ref$|^state$|^status$|^kind$|^source$|^created_by$|^by$|^conditions$|^command$)/.test(
      key,
    )
  )
    return [];
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap((each) => workText(each));
  if (value && typeof value === "object")
    return Object.entries(value).flatMap(([name, each]) => workText(each, name));
  return [];
}

/** Internals the owner should never read: commands, paths, ids, JSON and tool names. */
export function internals(text: string) {
  const found: string[] = [];
  const patterns: [string, RegExp][] = [
    ["command", /(^|\s|`|\$ )(curl|npm|npx|bunx?|git|sudo|brew|python3?)\s+-{0,2}[\w./]/],
    ["code", /`[^`]+`/],
    ["path", /(~\/|\/Users\/|\/tmp\/|\/private\/|\/var\/folders\/)[\w./-]*/],
    ["id", /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i],
    ["json", /[{[]\s*"[\w-]+"\s*:/],
  ];
  for (const [what, pattern] of patterns) {
    const match = pattern.exec(text);
    if (match) found.push(`${what}: ${match[0].trim()}`);
  }
  // A one-word name (run, write, recall) is also plain English: flagged only when called.
  for (const name of capabilityNames)
    if (new RegExp(/^[a-z]+$/.test(name) ? `\\b${name}\\(` : `\\b${name}\\b`).test(text))
      found.push(`tool name: ${name}`);
  return found;
}

/** Sentences that ask the owner something. */
const questions = (text: string) =>
  (text.match(/[^.!?\n]*\?/g) ?? []).map((sentence) => sentence.trim()).filter(Boolean);

// Seeding and removing the sample business.

async function seed(db: pg.Client, scenario: Scenario) {
  // The Mac's owner (the earliest person): only they may create businesses and use the Mac
  // where a host is configured. Removed with the business afterwards.
  const person = randomUUID();
  await db.query(
    "INSERT INTO people (id, display_name, created_at) VALUES ($1, $2, '2000-01-01')",
    [person, "Sam"],
  );
  const token = hex();
  await db.query(
    "INSERT INTO web_sessions (token_hash, person_id, expires_at, label) VALUES ($1, $2, now() + interval '1 day', 'scenario')",
    [sha(token), person],
  );
  const created = await fetch(`${base}/api/businesses`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ name: scenario.business.name }),
  });
  if (!created.ok) {
    await db.query("DELETE FROM web_sessions WHERE person_id = $1", [person]);
    await db.query("DELETE FROM people WHERE id = $1", [person]);
    throw new Error(`Creating the business failed: ${created.status}`);
  }
  const { business, chief_of_staff: chiefOfStaff } = (await created.json()) as {
    business: { id: string };
    chief_of_staff: Employee;
  };
  const api = owner(token, business.id);
  const {
    brief,
    team = [],
    secrets = [],
    memories = [],
    apps = [],
    repositories = [],
  } = scenario.business;
  if (brief) await api.call("", { method: "PUT", body: { brief } });
  for (const hire of team) await api.call("/employees", { body: hire });
  for (const secret of secrets) await api.call("/secrets", { body: secret });
  for (const app of apps) await api.call(`/apps/${app}/install`, { body: {} });
  for (const [index, content] of memories.entries()) {
    const response = await fetch(`${base}/api/businesses/${business.id}/memory/remember`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "idempotency-key": `scenario-${index}`,
      },
      body: JSON.stringify({ key: `scenario.fact.${index}`, content, source: "user" }),
    });
    if (!response.ok) throw new Error(`Remembering failed: ${response.status}`);
  }
  for (const repository of repositories) seedRepository(business.id, repository);
  return { person, token, business: business.id, chiefOfStaff, api };
}

/** A repository already in the business folder, as the owner would have it: one commit, no remote. */
function seedRepository(
  business: string,
  { name, files }: { name: string; files: Record<string, string> },
) {
  const folder = join(homedir(), "Devys", business, "repos", name);
  for (const [path, contents] of Object.entries(files)) {
    mkdirSync(dirname(join(folder, path)), { recursive: true });
    writeFileSync(join(folder, path), contents);
  }
  const git = (...args: string[]) => {
    const result = spawnSync("git", ["-C", folder, ...args], { encoding: "utf8" });
    if (result.status) throw new Error(`git ${args[0]} failed: ${result.stderr}`);
  };
  git("init", "--initial-branch=main");
  git("add", "--all");
  git("-c", "user.name=Sam", "-c", "user.email=sam@example.com", "commit", "-m", "First version");
}

/** Removes the business and everything it owns, children first, and its folder on the Mac. */
async function remove(db: pg.Client, person: string, business: string) {
  const run = (text: string, values: unknown[]) => db.query(text, values);
  for (const table of [
    "memories",
    "memory_state",
    "memory_sources",
    "memory_links",
    "memory_operations",
    "memory_exclusions",
  ])
    await run(`DELETE FROM ${table} WHERE scope_id = $1`, [business]);
  const owned = await db.query<{ table_name: string }>(
    `SELECT table_name FROM information_schema.columns
     WHERE column_name = 'business_id' AND table_schema = 'public' AND table_name <> 'businesses'`,
  );
  // Children before parents: retry the ones a foreign key still holds.
  let left = owned.rows.map((row) => row.table_name);
  for (let pass = 0; pass < 5 && left.length; pass++) {
    const failed: string[] = [];
    for (const table of left)
      await run(`DELETE FROM "${table}" WHERE business_id = $1`, [business]).catch(() =>
        failed.push(table),
      );
    left = failed;
  }
  await run("DELETE FROM businesses WHERE id = $1", [business]);
  for (const table of ["device_keys", "web_sessions", "sign_in_links"])
    await run(`DELETE FROM ${table} WHERE person_id = $1`, [person]);
  await run("DELETE FROM join_requests WHERE allowed_by = $1", [person]);
  await run("DELETE FROM people WHERE id = $1", [person]);
  if (/^[0-9a-f-]{36}$/.test(business))
    rmSync(join(homedir(), "Devys", business), { recursive: true, force: true });
}

// Screenshots.

async function screens(db: pg.Client, person: string) {
  const browser: Browser = await chromium.launch({ channel: "chrome" });
  const link = hex();
  await db.query(
    "INSERT INTO sign_in_links (token_hash, person_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [sha(link), person],
  );
  const desk = await browser.newContext({ viewport: { width: 1440, height: 900 }, baseURL: base });
  const page = await desk.newPage();
  await page.goto(`/#signin=${link}`);
  await page.getByTestId("place-title").waitFor({ timeout: 60_000 });
  const state = await desk.storageState();
  const phone: BrowserContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
    baseURL: base,
    storageState: state,
    isMobile: true,
    hasTouch: true,
  });
  return {
    async take(path: string, file: string) {
      for (const [context, size] of [
        [desk, "1440x900"],
        [phone, "390x844"],
      ] as const) {
        const shot = context.pages()[0] ?? (await context.newPage());
        await shot.goto(path);
        await shot.waitForLoadState("networkidle").catch(() => undefined);
        await sleep(1_500);
        await shot.screenshot({ path: `${file}-${size}.png` });
      }
    },
    close: () => browser.close(),
  };
}

/** Where a conversation opens in the web app. */
function placeOf(business: string, key: string, chiefOfStaff: string) {
  const [kind, id] = key.split(":");
  if (kind === "direct") return id === chiefOfStaff ? `/${business}` : `/${business}/chat/${id}`;
  if (kind === "work") return `/${business}/thread/${id}`;
  return `/${business}/project/${id}`;
}

// Playing the owner.

type Step = { turn: string; outcome: "ok" | "failed" | "stopped"; note: string; seconds: number };

async function play(scenario: Scenario, out: string) {
  const db = new pg.Client({ connectionString: databaseUrl(database) });
  await db.connect();
  const seeded = await seed(db, scenario);
  const { api, business, chiefOfStaff, person } = seeded;
  log(`Seeded ${scenario.business.name} (${business})`);
  const steps: Step[] = [];
  let firstReply: number | undefined;
  let firstPost: number | undefined;
  let status = "completed";
  const shooter = await screens(db, person);
  let touch = 0;
  /** The conversation the owner is looking at: where the team last spoke to them. */
  let place = `direct:${chiefOfStaff.id}`;
  const minutes = scenario.turnMinutes ?? 10;
  const pending = async () => (await api.decisions()).filter((d) => d.status === "pending");
  try {
    for (const [index, turn] of scenario.turns.entries()) {
      const started = Date.now();
      const label = JSON.stringify(turn);
      const shot = async () => {
        touch++;
        await shooter.take(
          placeOf(business, place, chiefOfStaff.id),
          join(out, `${String(touch).padStart(2, "0")}-touch`),
        );
      };
      const step = (outcome: Step["outcome"], note: string) => {
        steps.push({
          turn: label,
          outcome,
          note,
          seconds: Math.round((Date.now() - started) / 1000),
        });
        log(`${outcome}: ${label} ${note}`);
      };
      await shot();
      if ("stop" in turn) {
        const found = (await pending()).find((decision) => matches(turn.stop, decision));
        if (found) {
          step("stopped", `${kindOf(found)} request: ${requestText(found).join(" | ")}`);
          status = `stopped as planned at ${kindOf(found)}`;
        } else {
          step("failed", `no pending ${[turn.stop].flat().join(" or ")} request`);
          status = "failed";
        }
        break;
      }
      if ("start" in turn) {
        const proposed = (await api.work()).filter((item) => item.state === "proposed").at(-1);
        if (!proposed) {
          step(turn.optional ? "ok" : "failed", "no plan waiting for Start");
          if (turn.optional) continue;
          status = "failed";
          break;
        }
        await api.call(`/work/${proposed.id}/start`, { body: {} });
        place = `work:${proposed.id}`;
        step("ok", `started the plan: ${proposed.steps.map((s) => s.title).join(" → ")}`);
      } else if ("answer" in turn) {
        const want: AskKind = turn.answer === "secret" ? "secret" : "approve";
        const found = (await pending()).find(
          (decision) =>
            matches(want, decision) || (want === "approve" && decision.kind === "decision"),
        );
        if (!found || kindOf(found) === "spend") {
          step("failed", found ? "a spend needs a device signature" : `no pending ${want} request`);
          status = "failed";
          break;
        }
        // Saved under the name the request asks for: the scenario can't know it in advance.
        if (turn.answer === "secret")
          await api.call("/secrets", {
            body: {
              ...turn.secret,
              name: typeof found.input.name === "string" ? found.input.name : turn.secret.name,
            },
          });
        else await api.call(`/decisions/${found.id}/${turn.answer}`, { body: {} });
        step("ok", `answered ${kindOf(found)}`);
      } else if ("say" in turn) {
        const employees = await api.employees();
        const key =
          turn.to === "thread"
            ? place.startsWith("work:")
              ? place
              : `work:${(await api.work()).at(-1)?.id}`
            : `direct:${employees.find((employee) => employee.name === turn.to)?.id ?? chiefOfStaff.id}`;
        const posted = await api.post(key, turn.say);
        firstPost ??= Date.parse(posted.message.created_at);
        place = key;
        step("ok", "said");
      } else {
        // The owner answers the latest question still open since they last spoke: a later
        // update ("the check passed") leaves it standing.
        const spoken = (await everything(api)).filter((m) => m.kind !== "card");
        const since = spoken.slice(
          spoken.findLastIndex((m) => m.author === `person:${person}`) + 1,
        );
        const latest = since.findLast((m) => m.replies.length) ?? spoken.at(-1);
        const chips = latest?.replies ?? [];
        const wanted = scenario.persona[turn.tap];
        // A chip fits a fact when either contains the other, or the chip has all its words.
        const words = (text: string): string[] =>
          text.toLowerCase().match(/[\p{L}\p{N}@.'-]{3,}/gu) ?? [];
        const fits = (fact: string | undefined) =>
          fact === undefined
            ? chips[0]
            : chips.find(
                (chip) =>
                  chip.toLowerCase().includes(fact.toLowerCase()) ||
                  fact.toLowerCase().includes(chip.toLowerCase()) ||
                  (words(fact).length > 0 &&
                    words(fact).every((word) => words(chip).includes(word))),
              );
        const chosen = fits(wanted) ?? Object.values(scenario.persona).map(fits).find(Boolean);
        const asked = latest?.author.startsWith("employee:") && questions(latest.text).length > 0;
        if (turn.optional && !chips.length && !asked) {
          step("ok", "nothing asked");
          continue;
        }
        if (!latest || !chosen) {
          step(
            "failed",
            chips.length
              ? `owner had to type: no chip matches "${wanted}" (${chips.join(" / ")})`
              : `owner had to type: no chips offered${latest ? ` after "${latest.text.slice(0, 120)}"` : ""}`,
          );
          status = "failed";
          break;
        }
        await api.post(latest.conversation, chosen, latest.id);
        place = latest.conversation;
        step(
          "ok",
          `tapped "${chosen}"${wanted === undefined ? " (the recommendation)" : fits(wanted) ? "" : " (another persona fact)"}`,
        );
      }
      const settled = await settle(api, minutes);
      // A step takes as long as the team took to answer it.
      steps.at(-1)!.seconds = Math.round((Date.now() - started) / 1000);
      const messages = await everything(api);
      if (firstPost && firstReply === undefined) {
        const reply = messages.find(
          (m) => m.author.startsWith("employee:") && Date.parse(m.created_at) > firstPost!,
        );
        if (reply) firstReply = Date.parse(reply.created_at) - firstPost;
      }
      const spoke = messages.filter((m) => m.author !== `person:${person}`).at(-1);
      if (spoke) place = spoke.conversation;
      if (!settled) {
        steps.push({
          turn: "(waiting)",
          outcome: "failed",
          note: `still working after ${minutes} min`,
          seconds: minutes * 60,
        });
        status = "failed";
        break;
      }
      // Spend approvals, connects and take-overs are the owner's own; stop unless scripted next.
      const next = scenario.turns[index + 1];
      const blocking = (await pending()).find((decision) =>
        ["spend", "connect", "take_over"].includes(kindOf(decision)),
      );
      if (blocking) {
        const scripted =
          next && (("stop" in next && matches(next.stop, blocking)) || "answer" in next);
        if (!scripted) {
          touch++;
          await shooter.take(
            placeOf(business, blocking.conversation ?? place, chiefOfStaff.id),
            join(out, `${String(touch).padStart(2, "0")}-touch`),
          );
          steps.push({
            turn: "(owner action)",
            outcome: "stopped",
            note: `${kindOf(blocking)} request: ${requestText(blocking).join(" | ")}`,
            seconds: 0,
          });
          status = `stopped at an owner action (${kindOf(blocking)})`;
          break;
        }
      }
    }
  } catch (error) {
    // Still report and clean up: a run that broke is a failed run.
    status = `failed: ${error instanceof Error ? error.message : String(error)}`;
  } finally {
    await shooter.close().catch(() => undefined);
  }
  try {
    return await collect(api, scenario, steps, status, firstReply, out, person);
  } finally {
    await remove(db, person, business);
    await db.end();
  }
}

/** The transcript, every card's wire JSON, the rubric and the summary. */
async function collect(
  api: Owner,
  scenario: Scenario,
  steps: Step[],
  status: string,
  firstReply: number | undefined,
  out: string,
  person: string,
) {
  const [messages, decisions, items, employees] = await Promise.all([
    everything(api),
    api.call<{ decisions: Decision[] }>("/decisions"),
    api.work(),
    api.employees(),
  ]);
  const asked = await Promise.all(
    items.map((item) =>
      api
        .call<{ decisions: Decision[] }>(`/decisions?work_item=${item.id}`)
        .then((d) => d.decisions),
    ),
  );
  const requests = [
    ...new Map([...decisions.decisions, ...asked.flat()].map((d) => [d.id, d])).values(),
  ];
  const name = (author: string) =>
    author === `person:${person}`
      ? "Owner"
      : author === "system"
        ? "Devys"
        : (employees.find((employee) => `employee:${employee.id}` === author)?.name ?? author);
  const transcript = [
    `# ${scenario.name}: what the owner reads`,
    "",
    ...messages.flatMap((m) => [
      `**${name(m.author)}** · ${m.conversation} · ${m.kind}`,
      "",
      m.text,
      ...(m.replies.length ? ["", `Chips: ${m.replies.map((r) => `[${r}]`).join(" ")}`] : []),
      "",
    ]),
    "## Requests (askOwner and decisions)",
    "",
    ...requests.flatMap((d) => [
      `- ${kindOf(d)} (${d.status}): ${requestText(d).join(" | ")}${d.input.preview ? " (with a preview)" : ""}`,
    ]),
    "",
    "## Work items",
    "",
    ...items.flatMap((item) => [
      `- ${item.title} (${item.state}): ${String(item.objective ?? "")}`,
      ...(Array.isArray(item.steps) ? item.steps : []).map(
        (step: { title: string; state: string }) => `  - step (${step.state}): ${step.title}`,
      ),
      ...(Array.isArray(item.results) ? item.results : []).map(
        (result: { label: string; value?: string; url?: string; ok?: boolean | null }) =>
          `  - result (${result.ok === undefined ? "fact" : String(result.ok)}): ${result.label}${result.value ? `: ${result.value}` : ""}${result.url ? ` ${result.url}` : ""}`,
      ),
    ]),
  ].join("\n");
  writeFileSync(join(out, "transcript.md"), `${transcript}\n`);
  const wire = { messages, requests, work_items: items };
  writeFileSync(join(out, "wire.json"), `${JSON.stringify(wire, null, 2)}\n`);
  // The employees' own reasoning in their direct chats (tool calls and results), for debugging.
  const exported = await fetch(`${base}/api/businesses/${api.business}/export`, {
    headers: { authorization: `Bearer ${api.token}` },
  }).then(
    (response) => (response.ok ? response.text() : `export failed: ${response.status}`),
    (error: unknown) => `export failed: ${String(error)}`,
  );
  writeFileSync(join(out, "logs", "export.jsonl"), exported);

  // The rubric: mechanical checks of what the owner reads.
  const said = messages.filter((m) => m.author !== `person:${person}`);
  const leaks = [
    ...said.map((m) => ({
      where: `${name(m.author)} in ${m.conversation}`,
      found: internals(m.text),
    })),
    ...requests.map((d) => ({
      where: `${kindOf(d)} request`,
      found: internals(requestText(d).join("\n")),
    })),
    ...items.map((item) => ({
      where: `work item "${item.title}"`,
      found: internals(workText(item).join("\n")),
    })),
  ].filter((leak) => leak.found.length);
  const employeeMessages = said.filter((m) => m.author.startsWith("employee:"));
  const manyQuestions = employeeMessages
    .map((m) => ({ m, asked: questions(m.text) }))
    .filter(({ asked }) => asked.length > 1);
  const chipless = employeeMessages.filter((m) => {
    if (!questions(m.text).length || m.replies.length) return false;
    // A question carried by a request card the same turn needs no chips.
    const at = Date.parse(m.created_at);
    return !requests.some((d) => Math.abs(Date.parse(d.requested_at) - at) < 120_000);
  });
  const secretValues = (scenario.business.secrets ?? []).flatMap((secret) =>
    secret.kind === "secret" ? [secret.value] : [secret.card.number, secret.card.cvc ?? ""],
  );
  const everythingRead = JSON.stringify(wire);
  const exposed = secretValues.filter(
    (value) => value.length >= 3 && everythingRead.includes(value),
  );
  const typed = steps.filter((step) => step.note.startsWith("owner had to type"));
  // One request to the owner at a time on a work item: never two waiting at once.
  const overlapping = items.filter(
    (item) =>
      requests.filter(
        (d) => d.work_item_id === item.id && d.capability === "askOwner" && d.status === "pending",
      ).length > 1,
  );

  const check = (pass: boolean) => (pass ? "pass" : "FAIL");
  const shots = readdirSync(out)
    .filter((file) => file.endsWith(".png"))
    .sort();
  const summary = [
    `# Scenario ${scenario.name}`,
    "",
    `- Result: **${status}**`,
    `- Time to first reply: ${firstReply === undefined ? "no reply" : `${Math.round(firstReply / 1000)}s`}`,
    `- Messages the owner read: ${said.length}; requests: ${requests.length}; work items: ${items.length}`,
    "",
    "## Steps",
    "",
    "| # | Turn | Outcome | Seconds | Note |",
    "| - | ---- | ------- | ------- | ---- |",
    ...steps.map(
      (step, index) =>
        `| ${index + 1} | \`${step.turn}\` | ${step.outcome} | ${step.seconds} | ${step.note.replaceAll("|", "/").replaceAll("\n", " ")} |`,
    ),
    "",
    "## Rubric",
    "",
    `- ${check(!typed.length)} Owner never had to type (rubric 2/4)${typed.length ? `: ${typed.length} step(s)` : ""}`,
    `- ${check(!leaks.length)} No internals in what the owner reads${leaks.length ? ":" : ""}`,
    ...leaks.map((leak) => `  - ${leak.where}: ${leak.found.join("; ")}`),
    `- ${check(!exposed.length)} Secrets never in the transcript or wire`,
    `- ${check(!overlapping.length)} One request to the owner at a time per work item${overlapping.length ? `: ${overlapping.map((item) => `"${item.title}"`).join(", ")}` : ""}`,
    `- ${check(!chipless.length)} Chips offered with every question${chipless.length ? ":" : ""}`,
    ...chipless.map((m) => `  - ${name(m.author)}: "${questions(m.text).join(" ")}"`),
    `- ${manyQuestions.length ? "note" : "pass"} One question per turn (heuristic, reported only)${manyQuestions.length ? ":" : ""}`,
    ...manyQuestions.map(
      ({ m, asked }) => `  - ${name(m.author)} asked ${asked.length}: ${asked.join(" ")}`,
    ),
    "",
    "## Files",
    "",
    "- [transcript.md](transcript.md), [wire.json](wire.json), logs in `logs/`",
    ...shots.map((file) => `- [${file}](${file})`),
    "",
  ].join("\n");
  writeFileSync(join(out, "summary.md"), summary);
  return summary;
}

async function main(file: string) {
  const scenario = ((await import(resolve(file))) as { default: Scenario }).default;
  const stamp = new Date().toISOString().replaceAll(":", "-").slice(0, 19);
  const out = join(checkout, ".scratch/scenarios", scenario.name, stamp);
  const run = join(checkout, ".scratch/scenarios/.run", stamp);
  const logs = join(out, "logs");
  for (const dir of [out, logs, join(run, "host"), join(run, "state")])
    mkdirSync(dir, { recursive: true });
  for (const port of [ports.app, ports.host])
    if (!portFree(port)) throw new Error(`Port ${port} is in use: is another scenario running?`);
  if (
    spawnSync(process.execPath, ["scripts/db.ts", "ensure"], { cwd: checkout, stdio: "inherit" })
      .status
  )
    throw new Error("The development Postgres did not start");
  await createDatabase(database, true);
  await migrate(database);
  const token = hex();
  const dotenv = join(checkout, ".env");
  // The owner's real HOME (Chrome and its keychain, the owner's CLI logins); its own host data.
  const host = start(
    "Mac host",
    [process.execPath, "--no-env-file", "src/host.ts"],
    hostEnvironment(process.env, existsSync(dotenv) ? readFileSync(dotenv, "utf8") : "", {
      DEVYS_HOST_TOKEN: token,
      DEVYS_HOST_PORT: String(ports.host),
      DEVYS_HOST_DATA: join(run, "host"),
      DEVYS_WORKER_URL: base,
    }),
    join(logs, "host.log"),
  );
  const app = start(
    "Dev server",
    [
      process.execPath,
      "run",
      "dev:local",
      "--host",
      "127.0.0.1",
      "--port",
      String(ports.app),
      "--strictPort",
    ],
    {
      ...process.env,
      DEVYS_DEV_STATE: join(run, "state"),
      DEVYS_DEV_DATABASE: databaseUrl(database),
      DEVYS_DEV_VARS: JSON.stringify({
        PUBLIC_URL: base,
        DEVYS_HOST_URL: `http://127.0.0.1:${ports.host}`,
        DEVYS_HOST_TOKEN: token,
        DEVYS_HOST_HOME: homedir(),
      }),
    },
    join(logs, "app.log"),
  );
  const minute = setInterval(() => void tick(), 60_000);
  try {
    await until(
      "the Mac host",
      async () => Boolean(await fetch(`http://127.0.0.1:${ports.host}/`)),
      60_000,
    );
    await until("the dev server", async () => (await fetch(`${base}/health`)).ok, 180_000);
    // The first request builds the Worker; the API answers once it has.
    await until(
      "the Worker",
      async () => (await fetch(`${base}/api/models`)).status === 401,
      180_000,
    );
    const summary = await play(scenario, out);
    console.log(`\n${summary}\nResults: ${relative(checkout, out)}`);
  } finally {
    clearInterval(minute);
    await Promise.all([stop(app), stop(host)]);
    rmSync(run, { recursive: true, force: true });
    await dropDatabase(database);
  }
}

if (import.meta.main) {
  const file = process.argv[2];
  if (!file) throw new Error("Usage: bun run scenario tests/scenarios/<name>.ts");
  await main(file);
}
