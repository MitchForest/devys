import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { claudeAdapter } from "../src/delegates/host/claude.ts";
import type { ProviderEvents } from "../src/delegates/host/provider.ts";

const command = join(import.meta.dirname, "fixtures/fake-claude.mjs");
type Ended = Parameters<ProviderEvents["turnEnded"]>[0];

function adapter(env: NodeJS.ProcessEnv = process.env) {
  const ended: Ended[] = [];
  const lost: string[] = [];
  let waiting: ((value: Ended) => void) | undefined;
  const claude = claudeAdapter(
    { configDir: "/owner/.claude-personal", env, command },
    {
      turnEnded: (event) => {
        ended.push(event);
        waiting?.(event);
      },
      lost: (ids) => lost.push(...ids),
    },
  );
  const next = () => new Promise<Ended>((resolve) => (waiting = resolve));
  return { claude, ended, lost, next };
}

const cwd = mkdtempSync(join(tmpdir(), "devys-claude-"));

it("a message during a turn steers it; one after starts the next turn", async () => {
  const { claude, next } = adapter();
  let ended = next();
  const started = await claude.start({
    cwd,
    instructions: "x",
    prompt: "slow build",
    readOnly: false,
  });
  expect(
    await claude.send({ sessionId: started.sessionId, cwd, text: "add tests", readOnly: false }),
  ).toEqual({ turnId: started.turnId, steered: true });
  expect(await ended).toMatchObject({
    turnId: started.turnId,
    status: "completed",
    reply: "did: slow build + add tests",
  });
  ended = next();
  const following = await claude.send({
    sessionId: started.sessionId,
    cwd,
    text: "rename",
    readOnly: false,
  });
  expect(following.steered).toBe(false);
  expect(following.turnId).not.toBe(started.turnId);
  expect(await ended).toMatchObject({ turnId: following.turnId, reply: "did: rename" });
  await claude.close();
});

it("interrupting reports interrupted, and the session resumes by id in a new process", async () => {
  const first = adapter();
  let ended = first.next();
  const started = await first.claude.start({
    cwd,
    instructions: "x",
    prompt: "slow work",
    readOnly: false,
  });
  await first.claude.interrupt(started.sessionId);
  expect(await ended).toMatchObject({ status: "interrupted", reply: null });
  await first.claude.close();
  // A host restart: a new adapter has no process for the session and resumes it.
  const second = adapter();
  ended = second.next();
  const resumed = await second.claude.send({
    sessionId: started.sessionId,
    cwd,
    text: "continue",
    readOnly: false,
  });
  expect(resumed.steered).toBe(false);
  expect(await ended).toMatchObject({ sessionId: started.sessionId, reply: "did: continue" });
  await second.claude.close();
});

it("an exit mid-turn that nobody asked for is reported lost", async () => {
  const { claude, lost } = adapter();
  const started = await claude.start({
    cwd,
    instructions: "x",
    prompt: "slow work",
    readOnly: false,
  });
  await claude.send({ sessionId: started.sessionId, cwd, text: "crash", readOnly: false });
  await new Promise((resolve) => setTimeout(resolve, 100));
  expect(lost).toEqual([started.sessionId]);
  await claude.close();
});

it("runs on the owner's own login: no inherited API key or parent session settings", async () => {
  const { claude, next } = adapter({
    ...process.env,
    ANTHROPIC_API_KEY: "sk-test",
    CLAUDECODE: "1",
  });
  const ended = next();
  await claude.start({ cwd, instructions: "x", prompt: "whoami", readOnly: false });
  expect((await ended).reply).toContain("config /owner/.claude-personal key none parent none");
  await claude.close();
});
