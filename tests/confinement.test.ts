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
import { hostKeyring, openFor } from "../src/vault/host/server.ts";
import { memorySecrets } from "./fixtures/vault.ts";
import { readFileSync } from "node:fs";

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
 * businesses folder, as installed (scripts/local.ts): the host's data with the vault's master key
 * and every business's browser profile, and Postgres beside it.
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
    mkdirSync(join(data, "browser", scope.businessId, "Default"), { recursive: true });
    writeFileSync(
      join(data, "browser", scope.businessId, "Default", "Cookies"),
      `${scope.businessId} cookie\n`,
    );
  }
  mkdirSync(postgres, { recursive: true });
  writeFileSync(join(postgres, "PG_VERSION"), "postgres-marker\n");
  const hidden = [server];
  // The vault's master key, as the host keeps it: a file in its data folder.
  const keyring = await hostKeyring(data);
  const secrets = memorySecrets(keyring);
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
    open: (business, sealed, kinds) => openFor(keyring, business, sealed, kinds),
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
    url,
    work,
    data,
    postgres,
    delivered,
    spawned,
    secrets,
    /** The master key file's contents, as only the host reads it. */
    masterKey: () => readFileSync(join(data, "vault.key"), "utf8"),
    secret: (scope: typeof a) => join(work, scope.businessId, "secret.txt"),
    runner: (scope: typeof a) =>
      hostRunner(
        {
          url,
          token,
          files,
          sealed: (business, names) => secrets.sealed(business, names, ["secret", "spend"]),
        },
        scope,
      ),
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
  await expect(state.runner(a).read(join(state.data, "vault.key"))).rejects.toThrow(
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
      `cat '${join(state.data, "vault.key")}'`,
      `cp '${join(state.data, "vault.key")}' ./stolen.key`,
      `cat '${join(state.data, "browser", "business-a", "Default", "Cookies")}'`,
      `cat '${join(state.data, "browser", "business-b", "Default", "Cookies")}'`,
      `cat '${join(state.postgres, "PG_VERSION")}'`,
      `ls '${state.postgres}'`,
      `echo x > '${join(state.postgres, "planted")}'`,
      `grep -r . '${join(state.data, "..")}' 2>&1`,
    ].join("; "),
  );
  expect(tried).toContain("Operation not permitted");
  expect(tried).not.toContain(state.masterKey());
  expect(existsSync(join(state.work, a.businessId, "stolen.key"))).toBe(false);
  expect(tried).not.toContain("cookie");
  expect(tried).not.toContain("postgres-marker");
  expect(tried).not.toMatch(/^PG_VERSION$/m);
  expect(existsSync(join(state.postgres, "planted"))).toBe(false);
  // Its own folder still works.
  expect(await run(state, a, `cat ${state.secret(a)}`)).toBe("business-a secret\n");
});

it("a command's named secrets are in its environment only and redacted from what it prints", async () => {
  const state = await host();
  const key = "devys-test-secret-value-0123456789";
  await state.secrets.put(a.businessId, "STRIPE_KEY", "secret", key, "owner");
  await state.secrets.put(b.businessId, "STRIPE_KEY", "secret", "b-business-key", "owner");
  await state.secrets.put(
    a.businessId,
    "RAMP_CARD",
    "spend",
    JSON.stringify({ number: "4242424242424242", expiry: "12/30", name: "Sam", postal: "94107" }),
    "owner",
  );
  const used = await state
    .runner(a)
    .run(
      "with-secret",
      'echo "key=$STRIPE_KEY"; printf %s "$STRIPE_KEY" | base64; echo "$STRIPE_KEY" | sed "s/_/%5F/g"; env | grep -c sk_live; printf %s "$STRIPE_KEY" | cut -c1-6 >&2',
      10_000,
      64_000,
      ["STRIPE_KEY"],
    );
  expect(used.exitCode).toBe(0);
  expect(used.stdout).toContain("key=[redacted]");
  expect(used.stdout + used.stderr).not.toContain(key);
  // Another command, of the same employee, has no such variable.
  const after = await state
    .runner(a)
    .run("without", 'echo "key=${STRIPE_KEY:-none}"', 10_000, 64_000);
  expect(after.stdout).toBe("key=none\n");
  // Nor is the value in the receipt the host keeps on disk.
  expect(readFileSync(join(state.data, "receipts.jsonl"), "utf8")).not.toContain(key);
  // A card is never put in a command; another business's secret never opens for this one.
  await expect(state.runner(a).run("card", "true", 10_000, 64_000, ["RAMP_CARD"])).rejects.toThrow(
    /is a card/,
  );
  const theirs = (await state.secrets.sealed(b.businessId, ["STRIPE_KEY"], ["secret"]))[0]!;
  const forged = await fetch(`${state.url}/run`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      scope: a,
      operationId: "forged",
      command: "echo $STRIPE_KEY",
      timeoutMs: 10_000,
      maxBytes: 64_000,
      secrets: [{ ...theirs, business: a.businessId }],
    }),
  });
  expect(forged.status).toBe(403);
  expect(await forged.text()).not.toContain("b-business-key");
});

it("no confined process obtains the vault's master key: commands, coding harnesses and checks", async () => {
  const state = await host();
  const keyFile = join(state.data, "vault.key");
  const master = state.masterKey();
  expect(master).toMatch(/^[a-f0-9]{64}$/);
  const tried = await run(
    state,
    a,
    [
      `cat '${keyFile}'`,
      `head -c 64 '${keyFile}'`,
      `ls -la '${state.data}'`,
      `find '${join(state.data, "..")}' -name 'vault.key' -exec cat {} \\;`,
      `/usr/bin/python3 -c "print(open('${keyFile}').read())"`,
      `ln '${keyFile}' ./linked.key; cat ./linked.key`,
    ].join("; ") + " 2>&1",
  );
  expect(tried).toContain("Operation not permitted");
  expect(tried).not.toContain(master);
  // The coding harness's own shell, and what it runs, are held the same way.
  await state.coding(a).start({
    ...build("key-claude", "claude"),
    objective: `cat '${keyFile}'`,
  });
  const reply = (
    await until(() =>
      state.delivered.find(
        (event) =>
          event.codingSessionId === "key-claude" && ["finished", "failed"].includes(event.kind),
      ),
    )
  ).text;
  expect(reply).toContain("Operation not permitted");
  expect(reply).not.toContain(master);
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
