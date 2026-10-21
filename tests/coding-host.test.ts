import { execFileSync, spawn } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, expect, it } from "vitest";
import type { CodingEvent, StartRequest } from "../src/apps/code/contract.ts";
import { hostCoding } from "../src/apps/code/host-client.ts";
import type { ProviderAdapter, ProviderEvents } from "../src/apps/code/host/provider.ts";
import { codingHost } from "../src/apps/code/host/server.ts";
import { confine } from "../src/workspace/host/seatbelt.ts";
import { startHost } from "../src/workspace/host/server.ts";

const token = "test-token";
const scope = { businessId: "business-1", employeeId: "employee-1" };
const running: { close(): Promise<void> }[] = [];
afterAll(() => Promise.all(running.map((host) => host.close())));

const git = (cwd: string, ...args: string[]) =>
  execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8" }).trim();

/** A provider that edits files when told to and ends turns when the test says so. */
function fakeProvider() {
  let events!: ProviderEvents;
  const calls: { kind: string; sessionId?: string; text?: string; readOnly?: boolean }[] = [];
  let sessions = 0;
  const turns = new Map<string, string>();
  // Ends each turn before start or send returns, like a harness failing at once.
  const fast = { endAtOnce: undefined as "failed" | undefined };
  const endNow = (sessionId: string, turnId: string) => {
    if (!fast.endAtOnce) return false;
    turns.delete(sessionId);
    events.turnEnded({ sessionId, turnId, status: fast.endAtOnce, reply: null, error: "No login" });
    return true;
  };
  const adapter: ProviderAdapter = {
    async start({ cwd, prompt, readOnly }) {
      const sessionId = `session-${++sessions}`;
      calls.push({ kind: "start", sessionId, text: prompt, readOnly });
      if (!readOnly) writeFileSync(join(cwd, "feature.txt"), `${prompt}\n`);
      turns.set(sessionId, `${sessionId}-turn-1`);
      endNow(sessionId, `${sessionId}-turn-1`);
      return { sessionId, turnId: `${sessionId}-turn-1` };
    },
    async send({ sessionId, text }) {
      const steered = turns.has(sessionId);
      const turnId = steered ? turns.get(sessionId)! : `${sessionId}-turn-${calls.length + 1}`;
      turns.set(sessionId, turnId);
      calls.push({ kind: steered ? "steer" : "turn", sessionId, text });
      endNow(sessionId, turnId);
      return { turnId, steered };
    },
    async interrupt(sessionId) {
      calls.push({ kind: "interrupt", sessionId });
      const turnId = turns.get(sessionId);
      turns.delete(sessionId);
      if (turnId)
        events.turnEnded({ sessionId, turnId, status: "interrupted", reply: null, error: null });
    },
    transcript: async () => [{ kind: "reply", text: "Done." }],
    // Like a real harness process, a closed adapter forgets its running turns.
    async close() {
      turns.clear();
    },
  };
  return {
    calls,
    set endAtOnce(value: "failed" | undefined) {
      fast.endAtOnce = value;
    },
    factory: (given: ProviderEvents) => {
      events = given;
      return { codex: adapter };
    },
    finish(sessionId: string, reply: string) {
      const turnId = turns.get(sessionId)!;
      turns.delete(sessionId);
      events.turnEnded({ sessionId, turnId, status: "completed", reply, error: null });
    },
  };
}

async function host() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "devys-coding-")));
  const repository = join(root, "repo");
  mkdirSync(repository);
  git(repository, "init", "--initial-branch=main");
  writeFileSync(join(repository, "README.md"), "hello\n");
  git(repository, "add", ".");
  git(repository, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-m", "init");
  const delivered: CodingEvent[] = [];
  let refuse = false;
  // Event kinds the stand-in Worker fails to deliver, as with an event it cannot process.
  const poison = new Set<string>();
  const provider = fakeProvider();
  const data = join(root, "data");
  // Stands in for the owner's `gh`: one repository, pull requests kept in a file.
  const gh = join(root, "gh");
  writeFileSync(
    gh,
    `#!/bin/sh
echo "$*" >> "${root}/gh-calls"
case "$1 $2" in
  "repo view") echo '{"id":"R_test","defaultBranchRef":{"name":"main"}}' ;;
  "pr list") cat "${root}/prs" 2>/dev/null || echo '[]' ;;
  "pr create") echo '[{"url":"https://github.com/acme/site/pull/1"}]' > "${root}/prs"
    echo "Creating pull request"; echo "https://github.com/acme/site/pull/1" ;;
esac
`,
    { mode: 0o755 },
  );
  const env = {
    ...process.env,
    GIT_AUTHOR_NAME: "Owner",
    GIT_AUTHOR_EMAIL: "owner@example.com",
    GIT_COMMITTER_NAME: "Owner",
    GIT_COMMITTER_EMAIL: "owner@example.com",
  };
  Object.assign(process.env, {
    GIT_AUTHOR_NAME: env.GIT_AUTHOR_NAME,
    GIT_AUTHOR_EMAIL: env.GIT_AUTHOR_EMAIL,
    GIT_COMMITTER_NAME: env.GIT_COMMITTER_NAME,
    GIT_COMMITTER_EMAIL: env.GIT_COMMITTER_EMAIL,
  });
  const open = async () => {
    const server = await startHost({
      token,
      data,
      work: join(root, "work"),
      port: 0,
      shell: "/bin/sh",
      env,
      routes: [
        codingHost({
          work: join(root, "work"),
          data,
          providers: provider.factory,
          confine: (folder, readOnly) => (command, args) =>
            confine({ root: join(root, "work"), folder, readOnly, hidden: [data] }, command, args),
          shell: "/bin/sh",
          env,
          gh,
          retryMs: 20,
          // Stands in for the network: example.com previews answer, others don't.
          smoke: async (url) => (url.includes("example.com") ? 200 : null),
          deliver: async (events) => {
            if (refuse) throw new Error("Worker down");
            const accepted = events.filter((event) => !poison.has(event.kind));
            delivered.push(...accepted);
            return accepted.map((event) => event.id);
          },
        }),
      ],
    });
    running.push(server);
    return server;
  };
  let server = await open();
  const client = (as = scope) => hostCoding({ url: `http://127.0.0.1:${server.port}`, token }, as);
  return {
    root,
    repository,
    provider,
    delivered,
    data,
    client,
    refuse: (value: boolean) => {
      refuse = value;
    },
    poison,
    restart: async () => {
      await server.close();
      server = await open();
    },
  };
}

const request = (id: string, repository: StartRequest["repository"]): StartRequest => ({
  id,
  scope,
  provider: "codex",
  purpose: "build",
  repository,
  objective: "Add the feature",
  instructions: "Work only in the worktree.",
});

const until = async <T>(read: () => T, done: (value: T) => boolean) => {
  for (let attempt = 0; attempt < 200; attempt++) {
    const value = read();
    if (done(value)) return value;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out");
};

it("each coding session gets its own worktree and branch from the repository's head, once", async () => {
  const state = await host();
  const head = git(state.repository, "rev-parse", "HEAD");
  const started = await state.client().start(request("a-1", { path: state.repository }));
  expect(started).toMatchObject({
    repository: state.repository,
    baseCommit: head,
    branch: "devys/a-1",
  });
  expect(git(started.worktree, "rev-parse", "--abbrev-ref", "HEAD")).toBe("devys/a-1");
  // Starting the same coding session again returns it without a second session.
  expect(await state.client().start(request("a-1", { path: state.repository }))).toEqual(started);
  expect(state.provider.calls.filter((call) => call.kind === "start")).toHaveLength(1);
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "started"),
  );
  // Another business cannot see it.
  await expect(
    state.client({ businessId: "business-2", employeeId: "employee-1" }).inspect("a-1"),
  ).rejects.toThrow(/No such coding session/);
});

it("a new repository starts empty with a first commit to branch from", async () => {
  const state = await host();
  const started = await state.client().start(request("a-new", { create: "launch-site" }));
  expect(started.repository).toBe(
    join(state.root, "work", scope.businessId, "repos", "launch-site"),
  );
  expect(git(started.repository, "log", "--format=%s")).toBe("Start");
  await expect(state.client().start(request("a-bad", { create: "../escape" }))).rejects.toThrow();
});

it("a finished turn is delivered with what changed; steering only while it works", async () => {
  const state = await host();
  const started = await state.client().start(request("a-2", { path: state.repository }));
  expect(await state.client().send("a-2", "Also add tests")).toEqual({ steered: true });
  state.provider.finish(started.providerSessionId, "Added the feature and its tests.");
  const finished = await until(
    () => state.delivered.find((event) => event.kind === "finished"),
    Boolean,
  );
  expect(finished).toMatchObject({
    codingSessionId: "a-2",
    text: "Added the feature and its tests.",
  });
  expect(finished!.diffStat).toContain("feature.txt (new)");
  expect(await state.client().inspect("a-2")).toMatchObject({
    state: "idle",
    reply: "Added the feature and its tests.",
  });
  expect(await state.client().send("a-2", "Rename it")).toEqual({ steered: false });
});

it("a turn that ends before its start or follow-up returns is not lost", async () => {
  const state = await host();
  state.provider.endAtOnce = "failed";
  await state.client().start(request("a-fast", { path: state.repository }));
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "failed"),
  );
  expect(await state.client().inspect("a-fast")).toMatchObject({
    state: "failed",
    error: expect.stringContaining("Codex isn't signed in on this Mac"),
  });
  expect(state.delivered.find((event) => event.kind === "failed")?.text).toContain("codex login");
  await state.client().send("a-fast", "Try again");
  expect(await state.client().inspect("a-fast")).toMatchObject({ state: "failed" });
  expect(state.delivered.filter((event) => event.kind === "failed")).toHaveLength(2);
});

it("deploys run the accepted commit with the business's secrets, check the URL, and roll back", async () => {
  const state = await host();
  const started = await state.client().start(request("a-d", { path: state.repository }));
  const deploy = (command: string, extra: { commit?: string } = {}) =>
    state.client().deploy("a-d", { stage: "preview", command, ...extra });
  await expect(deploy("true")).rejects.toThrow(/still working|accept it first/);
  state.provider.finish(started.providerSessionId, "Done.");
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "finished"),
  );
  await expect(deploy("true")).rejects.toThrow(/accept it first/);
  const accepted = await state.client().accept("a-d", { message: "Add it", check: "true" });
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "checked"),
  );
  // The business's secrets reach the deploy and nothing else; output never shows them.
  mkdirSync(join(state.data, "deploy"), { recursive: true });
  writeFileSync(
    join(state.data, "deploy", `${scope.businessId}.env`),
    "TOKEN=hunter2222\nproduction.ONLY_PROD=nope\n",
  );
  // An uncommitted edit in the session's worktree is not what ships.
  writeFileSync(join(started.worktree, "uncommitted.txt"), "draft\n");
  const deployed = () => state.delivered.filter((event) => event.kind === "deployed");
  expect(
    await deploy(
      'test ! -f uncommitted.txt && echo "token $TOKEN prod ${ONLY_PROD:-none} at $(git rev-parse HEAD)" && echo https://acme-preview.example.com',
    ),
  ).toEqual({ commit: accepted.commit });
  const first = (await until(deployed, (events) => events.length === 1))[0]!;
  expect(first.deploy).toMatchObject({
    stage: "preview",
    commit: accepted.commit,
    exitCode: 0,
    url: "https://acme-preview.example.com",
    status: 200,
    live: true,
  });
  expect(first.deploy!.output).toContain(`token [redacted] prod none at ${accepted.commit}`);
  expect(first.deploy!.output).not.toContain("hunter2222");
  // A deploy that fails, or whose URL doesn't answer, is not live.
  await deploy("echo https://broken.invalid");
  const second = (await until(deployed, (events) => events.length === 2))[1]!;
  expect(second.deploy).toMatchObject({ exitCode: 0, live: false, status: null });
  // Rolling back deploys exactly the earlier commit.
  const base = started.baseCommit;
  await deploy('echo "at $(git rev-parse HEAD)" && echo https://acme-preview.example.com', {
    commit: base.slice(0, 12),
  });
  const third = (await until(deployed, (events) => events.length === 3))[2]!;
  expect(third.deploy).toMatchObject({ commit: base, live: true });
  expect(third.deploy!.output).toContain(`at ${base}`);
  await expect(deploy("true", { commit: "0".repeat(40) })).rejects.toThrow(
    /isn't in this repository/,
  );
});

it("an event the Worker cannot deliver is retried without holding up later events", async () => {
  const state = await host();
  state.poison.add("started");
  const started = await state.client().start(request("a-poison", { path: state.repository }));
  state.provider.finish(started.providerSessionId, "Done.");
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "finished"),
  );
  expect(state.delivered.some((event) => event.kind === "started")).toBe(false);
  state.poison.clear();
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "started"),
  );
});

it("accepting commits on the branch and reports the check against that commit", async () => {
  const state = await host();
  const started = await state.client().start(request("a-3", { path: state.repository }));
  await expect(state.client().accept("a-3", { message: "x", check: "true" })).rejects.toThrow(
    /still working/,
  );
  state.provider.finish(started.providerSessionId, "Done.");
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "finished"),
  );
  const accepted = await state.client().accept("a-3", {
    message: "Add the feature",
    check: "test -f feature.txt && echo checked",
  });
  expect(git(started.worktree, "log", "-1", "--format=%H %s")).toBe(
    `${accepted.commit} Add the feature`,
  );
  expect(accepted.patch).toContain("+Add the feature");
  const checked = await until(
    () => state.delivered.find((event) => event.kind === "checked"),
    Boolean,
  );
  expect(checked!.check).toMatchObject({ commit: accepted.commit, exitCode: 0 });
  expect(checked!.check!.output).toContain("checked");
  // The repository's own branch is untouched; the work lives on the coding session's branch.
  expect(git(state.repository, "log", "-1", "--format=%s", "main")).toBe("init");
});

it("a coding session clones the business's GitHub repository and publishes accepted work once", async () => {
  const state = await host();
  // A bare repository stands in for github.com/acme/site.
  const remote = join(state.root, "remote.git");
  execFileSync("git", ["clone", "--quiet", "--bare", state.repository, remote]);
  Object.assign(process.env, {
    GIT_CONFIG_COUNT: "1",
    GIT_CONFIG_KEY_0: `url.${remote}.insteadOf`,
    GIT_CONFIG_VALUE_0: "https://github.com/acme/site.git",
  });
  try {
    const started = await state.client().start(request("a-p", { clone: "acme/site" }));
    const clone = join(state.root, "work", scope.businessId, "repos", "site");
    expect(started.repository).toBe(clone);
    expect(git(clone, "config", "--get", "remote.origin.url")).toBe(
      "https://github.com/acme/site.git",
    );
    const publish = () =>
      state.client().publish("a-p", { repository: "acme/site", title: "Add it", body: "Checked." });
    await expect(publish()).rejects.toThrow(/still working/);
    state.provider.finish(started.providerSessionId, "Done.");
    await until(
      () => state.delivered,
      (events) => events.some((event) => event.kind === "finished"),
    );
    await expect(publish()).rejects.toThrow(/Nothing is accepted yet/);
    // A failed check is never published.
    await state.client().accept("a-p", { message: "Try it", check: "false" });
    await until(
      () => state.delivered,
      (events) => events.some((event) => event.kind === "checked"),
    );
    await expect(publish()).rejects.toThrow(/check failed/);
    const accepted = await state.client().accept("a-p", { message: "Add it", check: "true" });
    await until(
      () => state.delivered.filter((event) => event.kind === "checked"),
      (events) => events.length === 2,
    );
    await expect(
      state.client().publish("a-p", { repository: "acme/other", title: "x", body: "x" }),
    ).rejects.toThrow(/origin is https:\/\/github.com\/acme\/site.git/);
    // A commit made after accepting was never checked, so the accepted one is pushed.
    writeFileSync(join(started.worktree, "later.txt"), "unchecked\n");
    git(started.worktree, "add", ".");
    git(started.worktree, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-m", "later");
    const published = await publish();
    expect(published).toEqual({
      repository: "acme/site",
      repositoryId: "R_test",
      branch: "devys/a-p",
      base: "main",
      commit: accepted.commit,
      pullRequest: "https://github.com/acme/site/pull/1",
    });
    expect(git(remote, "rev-parse", "devys/a-p")).toBe(accepted.commit);
    // Published again (a retry): the same pull request, never a second one.
    expect((await publish()).pullRequest).toBe(published.pullRequest);
    const calls = readFileSync(join(state.root, "gh-calls"), "utf8");
    expect(calls.match(/^pr create/gm)).toHaveLength(1);
    // A folder already holding another repository is not reused for a different clone.
    await expect(state.client().start(request("a-q", { clone: "someone/site" }))).rejects.toThrow(
      /already holds https:\/\/github.com\/acme\/site.git/,
    );
  } finally {
    delete process.env.GIT_CONFIG_COUNT;
    delete process.env.GIT_CONFIG_KEY_0;
    delete process.env.GIT_CONFIG_VALUE_0;
  }
});

it("events wait for the Worker, and a host restart reports a working session interrupted", async () => {
  const state = await host();
  state.refuse(true);
  await state.client().start(request("a-4", { path: state.repository }));
  await new Promise((resolve) => setTimeout(resolve, 50));
  expect(state.delivered).toHaveLength(0);
  expect(readFileSync(join(state.data, "coding-events.json"), "utf8")).toContain("a-4:started");
  await state.restart();
  state.refuse(false);
  const kinds = await until(
    () =>
      state.delivered.filter((event) => event.codingSessionId === "a-4").map((event) => event.kind),
    (seen) => seen.includes("started") && seen.includes("interrupted"),
  );
  expect(kinds.filter((kind) => kind === "started")).toHaveLength(1);
  expect(await state.client().inspect("a-4")).toMatchObject({ state: "interrupted" });
  // A follow-up continues the same native session; nothing was replayed.
  expect(await state.client().send("a-4", "Continue")).toEqual({ steered: false });
});

it("interrupting ends the turn; a review reads the build's worktree without editing", async () => {
  const state = await host();
  const build = await state.client().start(request("a-5", { path: state.repository }));
  await state.client().interrupt("a-5");
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "interrupted"),
  );
  const review = await state.client().start({
    ...request("a-6", { path: state.repository }),
    purpose: "review",
    reviews: "a-5",
  });
  expect(review.worktree).toBe(build.worktree);
  expect(state.provider.calls.at(-1)).toMatchObject({ kind: "start", readOnly: true });
  await expect(state.client().accept("a-6", { message: "x", check: "true" })).rejects.toThrow(
    /nothing to accept/,
  );
  expect(existsSync(join(build.worktree, "feature.txt"))).toBe(true);
});

it("interrupting a build stops what still runs in its worktree", async () => {
  const state = await host();
  const started = await state.client().start(request("a-7", { path: state.repository }));
  const leftover = spawn("sleep", ["30"], { cwd: started.worktree, stdio: "ignore" });
  const exited = new Promise((resolve) => leftover.on("exit", resolve));
  await state.client().interrupt("a-7");
  expect(
    await Promise.race([
      exited.then(() => "stopped"),
      new Promise((r) => setTimeout(() => r("running"), 5_000)),
    ]),
  ).toBe("stopped");
});

it("a moving repository head doesn't move a coding session's base", async () => {
  const state = await host();
  const started = await state.client().start(request("a-8", { path: state.repository }));
  writeFileSync(join(state.repository, "other.txt"), "meanwhile\n");
  git(state.repository, "add", ".");
  git(state.repository, "commit", "-m", "Someone else's change");
  state.provider.finish(started.providerSessionId, "Done.");
  await until(
    () => state.delivered,
    (events) => events.some((event) => event.kind === "finished"),
  );
  const accepted = await state.client().accept("a-8", { message: "Feature", check: "true" });
  expect(git(started.worktree, "rev-parse", `${accepted.commit}~1`)).toBe(started.baseCommit);
  expect(accepted.patch).not.toContain("other.txt");
});
