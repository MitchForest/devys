#!/usr/bin/env node
// Stands in for `claude -p --input-format=stream-json --output-format=stream-json` in tests:
// the first line after input names the session; each message is a turn unless one is running
// ("slow" turns take 300 ms; "crash" exits); SIGINT ends a running turn as the CLI does, then exits.
import { randomUUID } from "node:crypto";
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
const resumed = args.indexOf("--resume");
const session = resumed >= 0 ? args[resumed + 1] : randomUUID();
const out = (line) => process.stdout.write(`${JSON.stringify(line)}\n`);
let announced = false;
let running = null;
let texts = [];
// Like the CLI, keeps the session in the config directory's projects folder.
const folder = join(process.env.CLAUDE_CONFIG_DIR ?? "/tmp", "projects", "-fake-cwd");
mkdirSync(folder, { recursive: true });
const record = (line) =>
  appendFileSync(join(folder, `${session}.jsonl`), `${JSON.stringify(line)}\n`);
const finish = () => {
  for (const text of texts) record({ type: "user", message: { role: "user", content: text } });
  record({
    type: "assistant",
    message: { content: [{ type: "text", text: `did: ${texts.join(" + ")}` }] },
  });
  out({
    type: "result",
    subtype: "success",
    is_error: false,
    session_id: session,
    result: `did: ${texts.join(" + ")}`,
  });
  running = null;
  texts = [];
};
let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  for (let end = buffer.indexOf("\n"); end >= 0; end = buffer.indexOf("\n")) {
    const { message } = JSON.parse(buffer.slice(0, end));
    buffer = buffer.slice(end + 1);
    if (!announced) {
      out({ type: "system", subtype: "init", session_id: session });
      announced = true;
    }
    if (message.content === "crash") process.exit(1);
    if (message.content === "whoami")
      texts.push(
        `config ${process.env.CLAUDE_CONFIG_DIR} key ${process.env.ANTHROPIC_API_KEY ?? "none"} parent ${process.env.CLAUDECODE ?? "none"}`,
      );
    texts.push(message.content);
    if (!running) running = setTimeout(finish, message.content.includes("slow") ? 300 : 20);
  }
});
process.on("SIGINT", () => {
  if (running) {
    clearTimeout(running);
    out({ type: "result", subtype: "error_during_execution", is_error: true, session_id: session });
  }
  process.exit(130);
});
