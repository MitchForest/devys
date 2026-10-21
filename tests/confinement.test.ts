/**
 * QF2: on the trusted Mac host, what an employee starts for one business cannot read or write
 * another business's folder (macOS Seatbelt, src/workspace/host/seatbelt.ts). Real host, real
 * `sandbox-exec`; a stand-in harness CLI plays the coding provider's process.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, expect, it } from "vitest";
import type { CodingEvent, StartRequest } from "../src/apps/code/contract.ts";
import { claudeAdapter } from "../src/apps/code/host/claude.ts";
import { codexAdapter } from "../src/apps/code/host/codex.ts";
import { codingHost } from "../src/apps/code/host/server.ts";
import { hostCoding } from "../src/apps/code/host-client.ts";
import { hostRunner } from "../src/workspace/host.ts";
import { confine } from "../src/workspace/host/seatbelt.ts";
import { startHost } from "../src/workspace/host/server.ts";

const token = "test-token";
const fakeCodex = join(import.meta.dirname, "fixtures/fake-codex.mjs");
// Accepting commits as the owner.
Object.assign(process.env, {
  GIT_AUTHOR_NAME: "Owner",
  GIT_AUTHOR_EMAIL: "owner@example.com",
  GIT_COMMITTER_NAME: "Owner",
  GIT_COMMITTER_EMAIL: "owner@example.com",
});
const a = { businessId: "business-a", employeeId: "employee-1" };
const b = { businessId: "business-b", employeeId: "employee-1" };
const running: { close(): Promise<void> }[] = [];
afterAll(() => Promise.all(running.map((host) => host.close())));

/**
 * Stands in for the `claude` CLI: for each message, runs it as a shell command (as the
 * harness's Bash tool would) and replies with the output, in the CLI's stream-json lines.
 */
const harness = `#!/bin/sh
session=$(uuidgen)
while IFS= read -r line; do
  command=$(printf '%s' "$line" | sed -E 's/.*"content":"(.*)"}}$/\\1/')
  output=$(/bin/sh -c "$command" 2>&1 | tr '\\n"\\\\' '   ')
  printf '{"type":"system","session_id":"%s"}\\n' "$session"
  printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s","result":"%s"}\\n' "$session" "$output"
  exit 0
done
`;

/**
 * A Mac host with two businesses, each holding a secret, and the server's own data outside the
 * businesses folder, as installed (scripts/local.ts): the host's data with every business's
 * deploy secrets and browser profiles, and Postgres beside it.
 */
async function host() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "devys-confined-")));
  const work = join(root, "Devys");
  const server = join(root, "Devys Server");
  const data = join(server, "host");
  const postgres = join(server, "postgres");
  for (const scope of [a, b]) {
    mkdirSync(join(work, scope.businessId), { recursive: true });
    writeFileSync(join(work, scope.businessId, "secret.txt"), `${scope.businessId} secret\n`);
    mkdirSync(join(data, "deploy"), { recursive: true });
    writeFileSync(
      join(data, "deploy", `${scope.businessId}.env`),
      `TOKEN=${scope.businessId}-deploy-token\n`,
    );
    mkdirSync(join(data, "browser", scope.businessId, "Default"), { recursive: true });
    writeFileSync(
      join(data, "browser", scope.businessId, "Default", "Cookies"),
      `${scope.businessId} cookie\n`,
    );
  }
  mkdirSync(postgres, { recursive: true });
  writeFileSync(join(postgres, "PG_VERSION"), "postgres-marker\n");
  const hidden = [server];
  const cli = join(root, "fake-claude");
  writeFileSync(cli, harness, { mode: 0o755 });
  const delivered: CodingEvent[] = [];
  /** Which Codex processes were started, each under its business's confinement. */
  const spawned: string[] = [];
  const confined =
    (folder: string, readOnly: boolean) => (command: string, args: readonly string[]) =>
      confine({ root: work, folder, readOnly, hidden }, command, args);
  const host = await startHost({
    token,
    data,
    hidden,
    work,
    port: 0,
    shell: "/bin/sh",
    routes: [
      codingHost({
        work,
        data,
        confine: confined,
        providers: (events, confineTo) => ({
          claude: claudeAdapter(
            { configDir: join(root, "claude"), env: process.env, command: cli, confine: confineTo },
            events,
          ),
          codex: codexAdapter(
            {
              home: join(root, "codex"),
              env: process.env,
              command: fakeCodex,
              confine: (readOnly) => {
                spawned.push(readOnly ? "review" : "build");
                return confineTo(readOnly);
              },
            },
            events,
          ),
        }),
        shell: "/bin/sh",
        retryMs: 20,
        deliver: async (events) => {
          delivered.push(...events);
          return events.map((event) => event.id);
        },
      }),
    ],
  });
  running.push(host);
  const url = `http://127.0.0.1:${host.port}`;
  const files = {} as Parameters<typeof hostRunner>[0]["files"];
  return {
    root,
    work,
    data,
    postgres,
    delivered,
    spawned,
    secret: (scope: typeof a) => join(work, scope.businessId, "secret.txt"),
    runner: (scope: typeof a) => hostRunner({ url, token, files }, scope),
    /** The host's raw file route, as the Worker calls it to copy bytes to and from R2. */
    file: (business: string, path: string) =>
      fetch(`${url}/file?business=${business}&path=${encodeURIComponent(path)}`, {
        headers: { authorization: `Bearer ${token}` },
      }),
    coding: (scope: typeof a) => hostCoding({ url, token }, scope),
  };
}

const until = async <T>(read: () => T | undefined) => {
  for (let attempt = 0; attempt < 500; attempt++) {
    const value = read();
    if (value !== undefined) return value;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out");
};

const run = async (state: Awaited<ReturnType<typeof host>>, scope: typeof a, command: string) => {
  const result = await state.runner(scope).run(crypto.randomUUID(), command, 10_000, 64_000);
  return result.stdout + result.stderr;
};

it("an employee's run reads its own business folder and nothing of another business's", async () => {
  const state = await host();
  const own = await state.runner(a).run("own", `cat ${state.secret(a)}`, 10_000, 64_000);
  expect(own).toMatchObject({ exitCode: 0, stdout: "business-a secret\n" });
  const other = await state.runner(a).run("other", `cat ${state.secret(b)}`, 10_000, 64_000);
  expect(other.exitCode).not.toBe(0);
  expect(other.stderr).toContain("Operation not permitted");
  // The live-run failure: a recursive search over the businesses folder finds nothing of B's.
  const grep = await state
    .runner(a)
    .run("grep", `grep -r secret ${state.work} 2>/dev/null; true`, 10_000, 64_000);
  expect(grep.stdout).not.toContain("business-b");
  // Through a symbolic link made in its own folder, via the unresolved /tmp-style path, by
  // writing, moving or listing: still nothing.
  const escapes = await run(
    state,
    a,
    [
      `ln -s ${join(state.work, b.businessId)} other && cat other/secret.txt`,
      `cat ${join(tmpdir(), state.secret(b).slice(realpathSync(tmpdir()).length))}`,
      `echo x > ${join(state.work, b.businessId, "planted.txt")}`,
      `mv ${state.secret(a)} ${join(state.work, b.businessId, "moved.txt")}`,
      `ls ${state.work}`,
      `cat '${join(state.data, "receipts.jsonl")}'`,
    ].join("; "),
  );
  expect(escapes).not.toContain("business-b secret");
  expect(escapes).not.toContain("operationId");
  expect(existsSync(join(state.work, b.businessId, "planted.txt"))).toBe(false);
  expect(existsSync(join(state.work, b.businessId, "moved.txt"))).toBe(false);
  // The owner's toolchain outside the businesses folder is untouched.
  const outside = await state
    .runner(a)
    .run("tools", "git --version && ls /usr/bin >/dev/null", 10_000, 64_000);
  expect(outside.exitCode).toBe(0);
  // Business B is held the same way the other direction.
  expect(
    (await state.runner(b).run("b-own", `cat ${state.secret(b)}`, 10_000, 64_000)).stdout,
  ).toBe("business-b secret\n");
  expect(
    (await state.runner(b).run("b-other", `cat ${state.secret(a)}`, 10_000, 64_000)).exitCode,
  ).not.toBe(0);
});

it("an employee's file tools refuse another business's folder", async () => {
  const state = await host();
  expect((await state.runner(a).read(state.secret(a))).content).toBe("business-a secret\n");
  await expect(state.runner(a).read(state.secret(b))).rejects.toThrow(/another business/);
  await expect(state.runner(a).write(join(state.work, b.businessId, "x.txt"), "x")).rejects.toThrow(
    /another business/,
  );
  await expect(state.runner(a).list(join(state.work, b.businessId))).rejects.toThrow(
    /another business/,
  );
  await expect(state.runner(a).list(state.data)).rejects.toThrow(/server's own data/);
  await expect(state.runner(a).read(join(state.data, "deploy", "business-a.env"))).rejects.toThrow(
    /server's own data/,
  );
  // The raw file route that moves bytes to and from R2 is held to the same folder.
  expect((await state.file(a.businessId, state.secret(a))).status).toBe(200);
  expect((await state.file(a.businessId, state.secret(b))).status).toBe(403);
  expect((await state.file("", state.secret(a))).status).toBe(400);
});

it("an employee's run reads nothing of the server's own data, its own business's included", async () => {
  const state = await host();
  const tried = await run(
    state,
    a,
    [
      `cat '${join(state.data, "deploy", "business-a.env")}'`,
      `cat '${join(state.data, "deploy", "business-b.env")}'`,
      `cat '${join(state.data, "browser", "business-a", "Default", "Cookies")}'`,
      `cat '${join(state.data, "browser", "business-b", "Default", "Cookies")}'`,
      `cat '${join(state.postgres, "PG_VERSION")}'`,
      `ls '${state.postgres}'`,
      `echo x > '${join(state.postgres, "planted")}'`,
      `grep -r . '${join(state.data, "..")}' 2>&1`,
    ].join("; "),
  );
  expect(tried).toContain("Operation not permitted");
  expect(tried).not.toContain("deploy-token");
  expect(tried).not.toContain("cookie");
  expect(tried).not.toContain("postgres-marker");
  expect(tried).not.toMatch(/^PG_VERSION$/m);
  expect(existsSync(join(state.postgres, "planted"))).toBe(false);
  // Its own folder still works.
  expect(await run(state, a, `cat ${state.secret(a)}`)).toBe("business-a secret\n");
});

const build = (id: string, provider: StartRequest["provider"]): StartRequest => ({
  id,
  scope: a,
  provider,
  purpose: "build",
  repository: { create: "site" },
  objective: "",
  instructions: "Work only in the worktree.",
});

it("a coding session's harness and its commands stay in their business", async () => {
  const state = await host();
  const replyTo = async (id: string) =>
    (
      await until(() =>
        state.delivered.find(
          (event) => event.codingSessionId === id && ["finished", "failed"].includes(event.kind),
        ),
      )
    ).text;
  // The stand-in harness runs what it is told, as its shell tool would, inside the session.
  for (const provider of ["claude"] as const) {
    const id = `confined-${provider}`;
    await state.coding(a).start({
      ...build(id, provider),
      objective: `cat ${state.secret(a)}; cat ${state.secret(b)}; ls ${state.work}`,
    });
    const reply = await replyTo(id);
    expect(reply).toContain("business-a secret");
    expect(reply).not.toContain("business-b secret");
    expect(reply).toContain("Operation not permitted");
  }
  // Codex's app-server runs confined too: one process for builds, one for reviews.
  await state.coding(a).start({ ...build("confined-codex", "codex"), objective: "hello" });
  expect(await replyTo("confined-codex")).toContain("hello");
  await state.coding(a).start({
    ...build("confined-codex-review", "codex"),
    purpose: "review",
    reviews: "confined-codex",
    objective: "look",
  });
  expect(await replyTo("confined-codex-review")).toContain("look");
  expect(state.spawned).toEqual(["build", "review"]);
  // A review cannot write, even in its own business's folder.
  const review = await state.coding(a).start({
    ...build("confined-review", "claude"),
    purpose: "review",
    reviews: "confined-claude",
    objective: `touch ${join(state.work, a.businessId, "review-wrote.txt")}; echo tried`,
  });
  expect(await replyTo("confined-review")).toContain("Operation not permitted");
  expect(review.worktree).toContain(join(state.work, a.businessId));
  expect(existsSync(join(state.work, a.businessId, "review-wrote.txt"))).toBe(false);
  // The check run when work is accepted is confined the same way.
  await state.coding(a).accept("confined-claude", {
    message: "Accept",
    check: `cat ${state.secret(b)}`,
  });
  const checked = await until(() =>
    state.delivered.find(
      (event) => event.kind === "checked" && event.codingSessionId === "confined-claude",
    ),
  );
  expect(checked.check).toMatchObject({ exitCode: 1 });
  expect(checked.check!.output).toContain("Operation not permitted");
  // Another business's repository is not a place to start a session.
  mkdirSync(join(state.work, b.businessId, "repos", "theirs"), { recursive: true });
  execFileSync("git", ["init", "--quiet", join(state.work, b.businessId, "repos", "theirs")]);
  await expect(
    state.coding(a).start({
      ...build("confined-theirs", "claude"),
      repository: { path: join(state.work, b.businessId, "repos", "theirs") },
    }),
  ).rejects.toThrow(/another business's folder/);
});
