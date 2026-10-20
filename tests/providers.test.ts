import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { claudeAdapter } from "../src/delegates/host/claude.ts";
import { codexAdapter } from "../src/delegates/host/codex.ts";
import { providerConformance, recorded } from "./conformance/provider.ts";

const fakeClaude = join(import.meta.dirname, "fixtures/fake-claude.mjs");
const fakeCodex = join(import.meta.dirname, "fixtures/fake-codex.mjs");

const claudeConfig = mkdtempSync(join(tmpdir(), "devys-claude-config-"));
const claude = (env: NodeJS.ProcessEnv = process.env) =>
  recorded((events) =>
    claudeAdapter({ configDir: claudeConfig, env, command: fakeClaude }, events),
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
  expect((await ended).reply).toContain(`config ${claudeConfig} key none parent none`);
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
  expect(reply).toContain("Devys declined what Codex asked to approve");
  expect(reply).toContain("rm -rf /tmp/outside");
  await adapter.close();
});

it("a Claude session file reads as prompts, replies and tool calls with their results", async () => {
  const { claudeEntries } = await import("../src/delegates/host/claude.ts");
  const lines = [
    { type: "user", message: { content: "Fix the test" } },
    {
      type: "assistant",
      message: {
        content: [
          { type: "text", text: "Running it." },
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "bun test" } },
          { type: "tool_use", id: "t2", name: "Edit", input: { file_path: "/w/a.ts" } },
        ],
      },
    },
    {
      type: "user",
      message: {
        content: [{ type: "tool_result", tool_use_id: "t1", content: "1 failed", is_error: true }],
      },
    },
    { type: "summary", summary: "ignored" },
  ];
  expect(claudeEntries(lines.map((line) => JSON.stringify(line)).join("\n"))).toEqual([
    { kind: "prompt", text: "Fix the test" },
    { kind: "reply", text: "Running it." },
    { kind: "command", text: "bun test", detail: "1 failed", failed: true },
    { kind: "files", text: "/w/a.ts" },
  ]);
});

it("a coding delegate sees none of the host's settings or the Worker's secrets", async () => {
  const { forgetHostSettings } = await import("../src/protocol/host.ts");
  // The launcher's host environment never had .env's secrets; the host drops its own settings.
  const env = forgetHostSettings({
    ...process.env,
    DEVYS_HOST_TOKEN: "host-token",
    DEVYS_HOST_PORT: "8788",
    PATH: process.env.PATH,
  });
  expect(Object.keys(env).filter((name) => name.startsWith("DEVYS_"))).toEqual([]);
  const { adapter, next } = recorded((events) =>
    codexAdapter({ home: "/owner/.codex-personal", env, command: fakeCodex }, events),
  );
  const ended = next();
  await adapter.start({
    cwd: import.meta.dirname,
    instructions: "x",
    prompt: "env",
    readOnly: false,
  });
  expect((await ended).reply).not.toMatch(/host-token|DEVYS_/);
  await adapter.close();
});

it("Codex commands read without the shell wrapper they run in", async () => {
  const { unwrapped } = await import("../src/delegates/host/codex.ts");
  expect(unwrapped(`/bin/zsh -lc "rg --files -g 'a.md' && git status"`)).toBe(
    "rg --files -g 'a.md' && git status",
  );
  expect(unwrapped(`/bin/zsh -lc "echo \\"hi\\""`)).toBe(`echo "hi"`);
  expect(unwrapped("bun test")).toBe("bun test");
});
