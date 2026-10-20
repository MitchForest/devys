import { join } from "node:path";
import { expect, it } from "vitest";
import { claudeAdapter } from "../src/delegates/host/claude.ts";
import { codexAdapter } from "../src/delegates/host/codex.ts";
import { providerConformance, recorded } from "./conformance/provider.ts";

const fakeClaude = join(import.meta.dirname, "fixtures/fake-claude.mjs");
const fakeCodex = join(import.meta.dirname, "fixtures/fake-codex.mjs");

const claude = (env: NodeJS.ProcessEnv = process.env) =>
  recorded((events) =>
    claudeAdapter({ configDir: "/owner/.claude-personal", env, command: fakeClaude }, events),
  );
const codex = () =>
  recorded((events) =>
    codexAdapter({ home: "/owner/.codex-personal", env: process.env, command: fakeCodex }, events),
  );

providerConformance("Claude Code CLI", () => claude());
providerConformance("Codex app-server", codex);

it("Claude runs on the owner's own login: no inherited API key or parent session settings", async () => {
  const { adapter, next } = claude({
    ...process.env,
    ANTHROPIC_API_KEY: "sk-test",
    CLAUDECODE: "1",
  });
  const ended = next();
  await adapter.start({
    cwd: import.meta.dirname,
    instructions: "x",
    prompt: "whoami",
    readOnly: false,
  });
  expect((await ended).reply).toContain("config /owner/.claude-personal key none parent none");
  await adapter.close();
});

it("Codex runs in the owner's Codex home and declines anything it asks to approve", async () => {
  const { adapter, next } = codex();
  const ended = next();
  await adapter.start({
    cwd: import.meta.dirname,
    instructions: "x",
    prompt: "whoami",
    readOnly: false,
  });
  const { reply } = await ended;
  expect(reply).toContain("home /owner/.codex-personal");
  expect(reply).toContain("approval decline");
  await adapter.close();
});
