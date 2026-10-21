// Terminal sessions on a real host process with Bun's PTY. Run by `bun test tests/bun`.
import { afterAll, expect, it, setDefaultTimeout } from "bun:test";
import { mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { stopProcessesIn } from "../../src/apps/code/host/worktree.ts";
import type { ServerMessage, TerminalSession } from "../../src/terminal/contract.ts";
import { hostTerminals } from "../../src/terminal/host-client.ts";
import { bunPty, terminalsHost } from "../../src/terminal/host/server.ts";
import { startHost } from "../../src/workspace/host/server.ts";

setDefaultTimeout(30_000);
const token = "test-token";
const scope = { businessId: "business-1", employeeId: "owner" };
const root = realpathSync(mkdtempSync(join(tmpdir(), "devys-terminal-")));
const terminals = terminalsHost({
  spawn: bunPty,
  env: { ...process.env, PS1: "$ ", PROMPT: "$ " },
  shell: "/bin/sh",
  resume: ({ provider, session }) => ({
    argv: ["/bin/echo", `resumed ${provider} ${session}`],
    env: process.env,
  }),
  exitedKeptMs: 1_500,
});
const host = await startHost({
  token,
  data: join(root, "data"),
  work: root,
  port: 0,
  routes: [terminals],
});
afterAll(() => host.close());
const where = { url: `http://127.0.0.1:${host.port}`, token };
const client = hostTerminals(where, scope);

/** Reads host frames from a stream: output bytes and events, until told to stop. */
function attach(id: string, offset = 0, business = scope.businessId) {
  const controller = new AbortController();
  const events: ServerMessage[] = [];
  let output = "";
  const done = (async () => {
    const response = await fetch(
      `${where.url}/terminals/stream?id=${id}&business=${business}&offset=${offset}&client=c-${crypto.randomUUID()}`,
      {
        headers: { authorization: `Bearer ${token}` },
        signal: controller.signal,
      },
    );
    if (!response.ok) throw new Error(await response.text());
    const reader = response.body!.getReader();
    let pending = new Uint8Array(0);
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) return;
        const joined = new Uint8Array(pending.length + value.length);
        joined.set(pending);
        joined.set(value, pending.length);
        let at = 0;
        while (joined.length - at >= 5) {
          const length = new DataView(joined.buffer, at + 1, 4).getUint32(0);
          if (joined.length - at - 5 < length) break;
          const payload = joined.subarray(at + 5, at + 5 + length);
          if (joined[at] === 0) output += new TextDecoder().decode(payload);
          else events.push(JSON.parse(new TextDecoder().decode(payload)));
          at += 5 + length;
        }
        pending = joined.slice(at);
      }
    } catch {}
  })();
  return {
    events,
    output: () => output,
    clientId: async () =>
      (await Promise.race([
        until(() => events.find((e) => e.type === "attached")),
        done.then(() => {
          throw new Error(`stream ended before attaching: ${output}`);
        }),
      ])) as Extract<ServerMessage, { type: "attached" }>,
    stop: () => controller.abort(),
    done,
  };
}

async function until<T>(read: () => T | undefined, seconds = 5): Promise<T> {
  for (let i = 0; i < seconds * 20; i++) {
    const value = read();
    if (value) return value;
    await Bun.sleep(50);
  }
  throw new Error("Timed out");
}

const post = async (path: string, body: Record<string, unknown>) =>
  fetch(`${where.url}/terminals/${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ scope, ...body }),
  });
const type = (id: string, client: string, text: string) =>
  post("write", { id, client, data: Buffer.from(text).toString("base64") });

it("a session outlives its client and replays what a returning client missed", async () => {
  const session = await client.open({ scope, title: "Shell", cwd: root, cols: 80, rows: 24 });
  const first = attach(session.id);
  const { client: writer } = await first.clientId();
  expect((await type(session.id, writer, "echo first-$((40+2))\n")).status).toBe(200);
  await until(() => first.output().includes("first-42")).catch(() => {
    throw new Error(
      `saw: ${JSON.stringify(first.output())} events ${JSON.stringify(first.events)}`,
    );
  });
  first.stop();
  // Typed after the first client left: a returning client sees it, from where it asked.
  const later = attach(session.id);
  const { client: second } = await later.clientId();
  // The first client's departure may not have reached the host yet; the returning device takes over.
  await post("control", { id: session.id, client: second });
  await type(session.id, second, "echo second-$((40+3))\n");
  await until(() => later.output().includes("second-43"));
  const offset = (await client.list(scope)).find((t) => t.id === session.id)!.offset;
  const resumed = attach(session.id, offset);
  await type(session.id, second, "echo third-$((40+4))\n");
  await until(() => resumed.output().includes("third-44"));
  expect(resumed.output()).not.toContain("second-43");
  later.stop();
  resumed.stop();
  await client.close(scope, session.id);
});

it("one device types at a time until another takes control", async () => {
  const session = await client.open({ scope, title: "Shell", cwd: root, cols: 80, rows: 24 });
  const one = attach(session.id);
  const two = attach(session.id);
  const { client: a } = await one.clientId();
  const { client: b } = await two.clientId();
  expect((await type(session.id, b, "echo nope\n")).status).toBe(409);
  expect((await post("control", { id: session.id, client: b })).status).toBe(200);
  await until(() => one.events.find((e) => e.type === "writer" && e.writer === b));
  expect((await type(session.id, a, "echo nope\n")).status).toBe(409);
  expect((await type(session.id, b, "echo yes-$((1+1))\n")).status).toBe(200);
  await until(() => one.output().includes("yes-2"));
  one.stop();
  two.stop();
  await client.close(scope, session.id);
});

it("an exit is reported, resumed agents run their own command, and other businesses see nothing", async () => {
  const resumed = await client.open({
    scope,
    title: "Codex",
    cwd: root,
    cols: 80,
    rows: 24,
    resume: { provider: "codex", session: "t-1" },
  });
  const stream = attach(resumed.id);
  await until(() => stream.events.find((e) => e.type === "exit"));
  expect(stream.output()).toContain("resumed codex t-1");
  const otherBusiness = { businessId: "business-2", employeeId: "owner" };
  expect(await hostTerminals(where, otherBusiness).list(otherBusiness)).toEqual([]);
  const other = attach(resumed.id, 0, "business-2");
  await expect(other.done).rejects.toThrow("No such terminal");
  // An exited session is dropped after a while, with its output.
  expect((await client.list(scope)).some((each) => each.id === resumed.id)).toBe(true);
  await Bun.sleep(1_800);
  expect((await client.list(scope)).some((each) => each.id === resumed.id)).toBe(false);
});

it("worktree cleanup spares the owner's terminals and stops everything else", async () => {
  const folder = realpathSync(mkdtempSync(join(tmpdir(), "devys-worktree-")));
  const session: TerminalSession = await client.open({
    scope,
    title: "Shell",
    cwd: folder,
    cols: 80,
    rows: 24,
  });
  const stream = attach(session.id);
  const { client: writer } = await stream.clientId();
  await type(session.id, writer, "sleep 30 & echo started-$((2*3))\n");
  await until(() => stream.output().includes("started-6"));
  const stray = Bun.spawn(["sleep", "30"], { cwd: folder });
  const stopped = await stopProcessesIn(folder, await terminals.ttys());
  expect(stopped).toEqual([stray.pid]);
  await stray.exited;
  stream.stop();
  await client.close(scope, session.id);
});
