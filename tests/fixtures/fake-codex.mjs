#!/usr/bin/env node
// Stands in for `codex app-server` in tests: JSON-RPC lines over stdio with the methods the
// adapter uses. A turn's text becomes its reply ("slow" turns take 300 ms; "crash" exits; "whoami"
// reports CODEX_HOME and whether an approval request was declined). Threads resume by id, as
// they do from the Codex home.
import { randomUUID } from "node:crypto";
const out = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const running = new Map(); // threadId -> { turn, texts, timer }
const history = new Map(); // threadId -> turns, for thread/read
let approvals = 0;
let declined = "unasked";

function finish(threadId, status) {
  const current = running.get(threadId);
  if (!current) return;
  clearTimeout(current.timer);
  running.delete(threadId);
  const items = current.texts.map((text) => ({
    type: "userMessage",
    id: randomUUID(),
    clientId: null,
    content: [{ type: "text", text }],
  }));
  if (status === "completed")
    items.push({
      type: "agentMessage",
      id: randomUUID(),
      text: `did: ${current.texts.join(" + ")}`,
    });
  history.set(threadId, [...(history.get(threadId) ?? []), { id: current.turn, items }]);
  if (status === "completed")
    out({
      method: "item/completed",
      params: {
        threadId,
        turnId: current.turn,
        item: { type: "agentMessage", id: randomUUID(), text: `did: ${current.texts.join(" + ")}` },
      },
    });
  out({
    method: "turn/completed",
    params: { threadId, turn: { id: current.turn, status, items: [], error: null } },
  });
}

function startTurn(threadId, text) {
  const turn = randomUUID();
  const texts = [];
  if (text === "whoami") {
    // Ask for an approval, as Codex might; the adapter must decline it.
    out({
      id: `approval-${++approvals}`,
      method: "item/commandExecution/requestApproval",
      params: { threadId, command: "rm -rf /tmp/outside" },
    });
    texts.push(`home ${process.env.CODEX_HOME}`);
  }
  // "env" reports what the harness inherited, as a delegate's shell would see it.
  if (text === "env")
    texts.push(
      Object.keys(process.env)
        .filter((name) => /DEVYS_|TOKEN|KEY/.test(name))
        .join(","),
    );
  texts.push(text);
  const timer = setTimeout(
    () => {
      if (text === "whoami") running.get(threadId)?.texts.push(`approval ${declined}`);
      finish(threadId, "completed");
    },
    text.includes("slow") ? 300 : 40,
  );
  running.set(threadId, { turn, texts, timer });
  out({ method: "turn/started", params: { threadId, turn: { id: turn, status: "inProgress" } } });
  return turn;
}

const handle = ({ id, method, params, result }) => {
  if (method === undefined) {
    if (String(id).startsWith("approval-")) declined = result?.decision ?? "missing";
    return;
  }
  if (id === undefined) return; // notifications such as "initialized"
  const text = params?.input?.[0]?.text;
  if (text === "crash") process.exit(1);
  switch (method) {
    case "initialize":
      return out({ id, result: {} });
    case "thread/start":
      return out({ id, result: { thread: { id: randomUUID() } } });
    case "thread/read":
      return out({
        id,
        result: { thread: { id: params.threadId, turns: history.get(params.threadId) ?? [] } },
      });
    case "thread/resume":
      return out({ id, result: { thread: { id: params.threadId } } });
    case "turn/start":
      return out({ id, result: { turn: { id: startTurn(params.threadId, text) } } });
    case "turn/steer": {
      const current = running.get(params.threadId);
      if (!current || current.turn !== params.expectedTurnId)
        return out({ id, error: { message: "no running turn" } });
      current.texts.push(text);
      return out({ id, result: { turnId: current.turn } });
    }
    case "turn/interrupt":
      out({ id, result: {} });
      return finish(params.threadId, "interrupted");
    default:
      return out({ id, error: { message: `unknown method ${method}` } });
  }
};

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  for (let end = buffer.indexOf("\n"); end >= 0; end = buffer.indexOf("\n")) {
    const line = buffer.slice(0, end);
    buffer = buffer.slice(end + 1);
    if (line.trim()) handle(JSON.parse(line));
  }
});
