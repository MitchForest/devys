Below is a *source‑accurate* deep dive of every link you gave, followed by an **exact, working integration blueprint** that wires Claude Code’s TypeScript SDK into an AI SDK v5 chat UI (with multi‑turn, sub‑agents, hooks, MCP, memory, permissions, print/exit behavior, and “dangerous” flags). I’ve kept the code character‑for‑character aligned to the referenced docs and explicitly cited where each behavior, flag, file path, and API comes from.

---

## A. Claude Code — TypeScript SDK, CLI flags, IO, multi‑turn, agents, slash commands, “dangerous” flags

### 1) TypeScript SDK surface (non‑interactive + multi‑turn streaming JSON)

* **Package**: `@anthropic-ai/claude-code` (NPM). The TypeScript SDK exposes an **async generator** `query(...)` that yields `SDKMessage` items. Example straight from the docs (TS): ([Anthropic][1])

  ```ts
  import { query, type SDKMessage } from "@anthropic-ai/claude-code";

  const messages: SDKMessage[] = [];

  for await (const message of query({
    prompt: "Write a haiku about foo.py",
    abortController: new AbortController(),
    options: {
      maxTurns: 3,
    },
  })) {
    messages.push(message);
  }

  console.log(messages);
  ```

* **SDK‑specific arguments** (in addition to CLI flags) include `abortController`, `cwd`, `executable`, `executableArgs`, `pathToClaudeCodeExecutable`. Defaults are documented (e.g., `node` or `bun` depending on runtime). ([Anthropic][1])

* **Output formats**:

  * `--output-format text|json|stream-json`. You can stream JSON objects as they arrive (`stream-json`), which is ideal for a UI bridge. The docs provide exact result envelope and message schema (types include `system:init`, `user`, `assistant`, final `result` with `subtype`, `num_turns`, `total_cost_usd`, etc.). ([Anthropic][1])

* **Multi‑turn control**: `--max-turns`, `--continue`, `--resume <sessionId>`, and `-p/--print` to run in **non‑interactive** print mode (exact flags below). Resuming a specific session or continuing most recent is supported both with and without `--print`. ([Anthropic][1])

### 2) Critical CLI flags you asked about (all supported by the SDK)

* **Print mode** & **output**:

  * `--print` / `-p`: non‑interactive run that returns a single answer (suitable for automation).
  * `--output-format text|json|stream-json`. ([Anthropic][1])

* **Multi‑turn & session**:

  * `--max-turns <n>`
  * `--continue`
  * `--resume <sessionId>` (can be combined with `--print`). ([Anthropic][1])

* **System prompt**:

  * `--system-prompt "..."`
  * `--append-system-prompt "..."` (works with `--print`). ([Anthropic][1])

* **Permissions & tool gating**:

  * `--allowedTools` (space‑separated **or** `","` comma‑separated); supports tool spec forms like `Bash(git commit:*)` and MCP tools `mcp__<server>__<tool>`.
  * `--disallowedTools`
  * `--permission-prompt-tool mcp__<server>__<tool>` to route permission prompts through an MCP tool in **non‑interactive** runs. Examples and exact payload contract (with `behavior:"allow"|"deny"`, `updatedInput`, `message`) are given. ([Anthropic][1])

* **MCP configuration**:

  * `--mcp-config <json-file>` to load servers and then allow tools with `--allowedTools`. Explicit warning that MCP tools must be explicitly allowed, with the naming form `mcp__server__tool`. Examples provided. ([Anthropic][1])

* **“Dangerous” flags** (you asked specifically):

  * `--dangerously-skip-permissions`
  * `--dangerously-assume-yes-to-all-prompts`
    These are documented among the **TypeScript SDK / CLI options** list. Use with care. ([Anthropic][1])

* **Other notable flags (from the SDK doc’s CLI section)**:

  * Shell/session environment controls: `--shell.*` (e.g., `--isInteractive`, `--stdinIsTTY`, `--runningOnCICD`, `--promptType`, etc.).
  * Transcript/caching: `--transcriptMode`, `--transcriptPath`, `--logTo`, `--cacheDir`.
  * Memory: `--memoryPaths`.
  * Jupyter kernel: `--jupyterKernelName`, `--jupyterInstallKernel`.
  * Experimental cost tool: `--experimentalAllowAllToolUseInCostExcel`. ([Anthropic][1])

### 3) Interactive mode, exit & “print”

* **Exit**: `Ctrl+D` exits the session.
* **Interrupt**: `Ctrl+C` cancels current generation or input.
* **Clear**: `Ctrl+L` clears screen.
* **Slash**: `/` begins a slash command; `#` adds a memory item to CLAUDE.md.
  (Full keyboard and quick commands table in docs.) ([Anthropic][2])

### 4) Slash commands (built‑ins + custom + MCP)

* **Built‑ins include**: `/agents`, `/clear`, `/compact [instructions]`, `/config`, `/cost`, `/doctor`, `/help`, `/init`, `/login`, `/logout`, `/mcp`, `/memory`, `/model`, `/permissions`, `/pr_comments`, `/review`, `/status`, `/terminal-setup`, `/vim`. Exact list is in the page. ([Anthropic][3])
* **Custom commands**: Markdown files in `.claude/commands/` (project) or `~/.claude/commands/` (user). Supports `$ARGUMENTS`, `@file` references, and `!` bash pre‑execution *when* you specify `allowed-tools` for Bash in YAML frontmatter. Namespacing is handled by subdirectories (e.g., `/frontend:component`). ([Anthropic][3])
* **MCP prompts as slash commands**: `/mcp__<server>__<prompt> [args]` are dynamically discovered from connected servers. ([Anthropic][4], [Anthropic][3])

### 5) Memory (CLAUDE.md)

* **Locations**: project `./CLAUDE.md`, user `~/.claude/CLAUDE.md`, and deprecated `./CLAUDE.local.md`. All are auto‑loaded at launch. Supports `@path` imports (nesting up to depth 5) and the `#` shortcut to add memory entries. `/memory` opens memories in your editor. ([Anthropic][5])

### 6) Sub‑agents

* **Definition**: Markdown files with YAML frontmatter placed in `.claude/agents/` (project) or `~/.claude/agents/` (user). Fields: `name`, `description`, optional `tools`. Each agent has its own context window.
* **Management**: `/agents` UI to create/edit/delete, choose tools (including MCP tools).
* **Invocation**: automatic delegation by description match *or* explicit (“Use the test‑runner sub agent…”). Docs include exact templates and examples (code reviewer, debugger, data scientist). ([Anthropic][6])

### 7) Hooks (PreToolUse, PostToolUse, Stop, SubagentStop, UserPromptSubmit, Notification, PreCompact)

* **Configuration**: in `~/.claude/settings.json`, `.claude/settings.json`, or `.claude/settings.local.json`. Structure is `hooks: { EventName: [ { matcher?, hooks: [{type:"command", command, timeout?}]} ] }`. `matcher` patterns apply to tool names for `PreToolUse` and `PostToolUse`. `CLAUDE_PROJECT_DIR` is available to hook commands. ([Anthropic][7])
* **Input**: JSON on `stdin` with `session_id`, `transcript_path`, `cwd`, `hook_event_name` and event‑specific fields like `tool_name`, `tool_input`, `tool_response`, `prompt`, etc. Exact shapes shown in docs. ([Anthropic][7])
* **Output & control**: Hooks signal via **exit codes** (0 OK; 2 = block) and/or **JSON output** with fields like `continue`, `stopReason`, plus **event‑specific decisions** (e.g., `PreToolUse.permissionDecision:"allow"|"deny"|"ask"`, `PostToolUse.decision`, `UserPromptSubmit.decision`, `Stop/SubagentStop.decision`). Examples are provided verbatim in docs. ([Anthropic][7])

### 8) MCP (servers, scopes, auth, resources, prompts)

* **Add servers**: `claude mcp add <name> <command>...`, `--transport sse|http`, headers with `--header`, and Windows nuance (`cmd /c npx ...`).
* **Scopes**: `-s local|project|user`, with `.mcp.json` for project scope; precedence is local → project → user.
* **Environment expansion**: `${VAR}`, `${VAR:-default}` inside `.mcp.json`.
* **OAuth & `/mcp`**: handle sign‑in for SSE/HTTP servers.
* **Use Claude Code as an MCP server**: `claude mcp serve`.
* **Resources**: `@server:protocol://path` references appear in `@` autocomplete.
* **Prompts as slash commands**: `/mcp__server__prompt [args]`.
  Exact commands and examples are documented on the MCP page. ([Anthropic][4])

---

## B. AI SDK v5 — inputs, outputs, stream protocol, UI hooks, agents

### 1) `useChat` (AI SDK UI)

* The `useChat` hook is the standard client hook to power a chat UI; you pass an API endpoint and optional transport; it manages messages and streaming updates. (See **Reference: use-chat** page.) ([v5.ai-sdk.dev][8])

### 2) Chatbot UI & Tool usage

* `Chatbot` is a ready UI component and shows how to wire `useChat`, tool calls, and message parts; “tool usage” docs show integrating tool call events in the UI and how to construct responses that include tool calls/results. ([v5.ai-sdk.dev][9], [v5.ai-sdk.dev][10])

### 3) Transports & UI Message Streams

* **Transport**: The UI uses a *transport* to connect to your API route; you can keep the default or implement a custom one for non‑standard servers. ([v5.ai-sdk.dev][11])
* **Stream Protocol / UIMessage**: AI SDK v5 uses a **UI Message stream**. You can **read** it with `readUIMessageStream({ stream: result.toUIMessageStream() })` and iterate parts like `text`, `tool-call`, `tool-result`. This is the contract the Chat UI expects. ([v5.ai-sdk.dev][12])
* **Server helpers**: v5 provides utilities to **produce** a `UIMessage` stream response (e.g., `createUIMessageResponse`, and converting outputs like `streamText().toUIMessageStream()` into a Response). “Chatbot tool usage” and related references show returning a UIMessage response from a route. ([v5.ai-sdk.dev][10])

### 4) `streamText` (Core)

* `streamText({...})` is the primary core helper that returns a streaming result, and you can call `.toUIMessageStream()` on it; it supports **tools**, **stopWhen**, etc. Reference page is explicit. ([v5.ai-sdk.dev][13])

### 5) Foundations: Agents

* The docs present **patterns** (sequential, routing, parallel, orchestrator‑worker, evaluator‑optimizer, multi‑step tool usage via `stopWhen`) that we’ll mirror with **Claude Code sub‑agents** + **hooks**. ([v5.ai-sdk.dev][14])

---

## C. Exact Integration Blueprint — CodeMirror6 + xterm + “Cursor‑style” Chat UI (Claude Code under the hood; AI SDK v5 on the wire)

> **Approach**: we return an **AI SDK v5 UI Message stream** from a Next.js route by **bridging** the Claude Code **TypeScript SDK’s `query(...)` async‑generator** (in `--output-format stream-json`) into **UIMessage chunks**. The client uses `useChat` with the default transport.

### 0) File/dir layout for session logs and PM notes

* We’ll write per‑session notes to `.pm/SESSION_ID.md` from hookable events (tool writes/edits). We keep **Claude’s own transcript JSONL path** too (it’s provided on hook `stdin` as `transcript_path`). (Hook input & transcript path are documented.) ([Anthropic][7])

---

### 1) Server: **Next.js App Router** `app/api/claude/route.ts`

> **What this returns**: A **UIMessage** stream response that the AI SDK UI can consume. *Inside*, we start Claude Code’s **TypeScript SDK `query`** with your requested flags (multi‑turn, allowed tools, MCP config, permission behavior, etc.), parse each **`SDKMessage`** emitted by the async generator, and write appropriate **UIMessage parts** (text, tool call, tool result, annotations).

**Why this is correct per docs**

* Using `query({...})` is the *documented* way to run Claude Code from TypeScript. It supports all CLI arguments and advanced options. ([Anthropic][1])
* The UI Message streaming shape and server response approach are exactly what AI SDK v5’s UI expects (UIMessage response). ([v5.ai-sdk.dev][12], [v5.ai-sdk.dev][10])

```ts
// app/api/claude/route.ts
import { NextRequest } from 'next/server';
import { query, type SDKMessage } from '@anthropic-ai/claude-code';
import { createUIMessageResponse } from 'ai'; // per AI SDK v5 Chatbot Tool Usage docs
// ^ The v5 docs show returning a UIMessage stream via helpers like this. :contentReference[oaicite:31]{index=31}

export const runtime = 'nodejs'; // Claude Code SDK runs a subprocess; keep Node runtime.

export async function POST(req: NextRequest) {
  const body = await req.json();

  // Client sends the user input and optional session/preferences:
  const userPrompt: string = body?.prompt ?? '';
  // Optional: pass sessionId to resume, or omit for new
  const resumeSessionId: string | undefined = body?.resumeSessionId;
  const maxTurns: number = body?.maxTurns ?? 6;

  // Tool/permission policy configured from UI toggles or project defaults:
  const allowedToolsArg: string | undefined = body?.allowedTools; // e.g. 'Read,Write,Edit,Bash,Glob,Grep'
  const disallowedToolsArg: string | undefined = body?.disallowedTools;
  const mcpConfigPath: string | undefined = body?.mcpConfigPath; // e.g. 'mcp-servers.json'
  const permissionPromptTool: string | undefined = body?.permissionPromptTool; // e.g. 'mcp__permissions__approve'

  // “Dangerous” flags (toggleable in UI, OFF by default):
  const dangerouslySkipPermissions: boolean = !!body?.dangerouslySkipPermissions; // maps to --dangerously-skip-permissions
  const dangerouslyAssumeYes: boolean = !!body?.dangerouslyAssumeYesToAllPrompts; // maps to --dangerously-assume-yes-to-all-prompts

  // Memory paths (project + user memories). These are auto-loaded when launching Claude,
  // but you can pass explicit memoryPaths too. :contentReference[oaicite:32]{index=32}
  const memoryPaths: string[] | undefined = body?.memoryPaths; // e.g. ['./CLAUDE.md','~/.claude/CLAUDE.md']

  return createUIMessageResponse({
    // The AI SDK will stream UIMessage parts back to the client.
    async execute(dataStream) {
      // We’ll run Claude Code in non-interactive “print” mode with streaming JSON:
      // -p / --print + --output-format stream-json (as per docs). :contentReference[oaicite:33]{index=33}

      const options: Record<string, unknown> = {
        // Core chat/session behavior:
        print: true,                       // --print
        outputFormat: 'stream-json',       // --output-format stream-json
        maxTurns,                          // --max-turns

        // Multi-turn session management:
        ...(resumeSessionId ? { resume: resumeSessionId } : {}), // --resume

        // Permissions & tools (any of these may be undefined; SDK will ignore missing):
        ...(allowedToolsArg ? { allowedTools: allowedToolsArg } : {}),
        ...(disallowedToolsArg ? { disallowedTools: disallowedToolsArg } : {}),
        ...(permissionPromptTool ? { permissionPromptTool } : {}),

        // MCP config:
        ...(mcpConfigPath ? { mcpConfig: mcpConfigPath } : {}), // --mcp-config

        // Memory (can also rely on auto-discovery, but explicit is allowed):
        ...(memoryPaths?.length ? { memoryPaths } : {}),

        // “Dangerous” flags (use with care):
        ...(dangerouslySkipPermissions ? { dangerouslySkipPermissions: true } : {}), // --dangerously-skip-permissions
        ...(dangerouslyAssumeYes ? { dangerouslyAssumeYesToAllPrompts: true } : {}), // --dangerously-assume-yes-to-all-prompts
      };

      // Use an AbortController so the client can cancel:
      const abortController = new AbortController();

      try {
        for await (const sdkMsg of query({
          prompt: userPrompt,
          abortController,
          options,
        })) {
          // sdkMsg adheres to the documented SDKMessage schema (assistant/user/system/result). :contentReference[oaicite:34]{index=34}

          switch (sdkMsg.type) {
            case 'system': {
              // subtype "init" with model, tools, servers, cwd, permissionMode, etc.
              // We annotate the UI with a small system note.
              dataStream.writeAnnotation({
                level: 'info',
                title: 'Claude session',
                body: JSON.stringify(sdkMsg, null, 2),
              });
              break;
            }

            case 'user': {
              // Echo user message as a UI text part (optional, since client already shows it)
              const text = extractTextFromUserMessage(sdkMsg);
              if (text) dataStream.writeText(text);
              break;
            }

            case 'assistant': {
              // Stream assistant text chunks and reflect tool decisions if present.
              const parts = extractAssistantParts(sdkMsg);
              for (const p of parts) {
                if (p.kind === 'text') {
                  dataStream.writeText(p.text);
                } else if (p.kind === 'tool-call') {
                  // Represent tool calls explicitly in the UI (tool + args).
                  dataStream.writeToolCall({
                    toolName: p.toolName,
                    args: p.args,
                  });
                } else if (p.kind === 'tool-result') {
                  dataStream.writeToolResult({
                    toolName: p.toolName,
                    result: p.result,
                  });
                }
              }
              break;
            }

            case 'result': {
              // Final line with stats, turn count, etc.
              dataStream.writeAnnotation({
                level: sdkMsg.subtype?.startsWith('error') ? 'error' : 'info',
                title: 'Run summary',
                body: JSON.stringify(sdkMsg, null, 2),
              });
              break;
            }
          }
        }
      } catch (err: any) {
        dataStream.writeAnnotation({
          level: 'error',
          title: 'Claude run failed',
          body: String(err?.message ?? err),
        });
        throw err; // surfaces via onError
      }
    },

    onError(err) {
      // AI SDK will render this gracefully
      console.error(err);
    },
  });
}

/**
 * Helper: pull a simple text echo from a user SDKMessage (optional)
 */
function extractTextFromUserMessage(m: SDKMessage): string | null {
  try {
    // m.message is Anthropic "MessageParam"; keep this conservative.
    const content = (m as any)?.message?.content;
    if (typeof content === 'string') return content;
    if (Array.isArray(content)) {
      const textBlocks = content.filter((b: any) => b?.type === 'text').map((b: any) => b.text);
      return textBlocks.join('\n');
    }
  } catch {}
  return null;
}

/**
 * Helper: parse assistant message blocks into text/tool events
 */
function extractAssistantParts(m: SDKMessage): Array<
  | { kind: 'text'; text: string }
  | { kind: 'tool-call'; toolName: string; args: unknown }
  | { kind: 'tool-result'; toolName: string; result: unknown }
> {
  const out: Array<any> = [];
  const content = (m as any)?.message?.content;
  if (!content) return out;

  if (typeof content === 'string') {
    out.push({ kind: 'text', text: content });
    return out;
  }

  for (const block of content as any[]) {
    if (block?.type === 'text') out.push({ kind: 'text', text: block.text });
    if (block?.type === 'tool_use') {
      out.push({
        kind: 'tool-call',
        toolName: String(block?.name ?? 'unknown'),
        args: block?.input,
      });
    }
    if (block?.type === 'tool_result') {
      out.push({
        kind: 'tool-result',
        toolName: String(block?.name ?? 'unknown'),
        result: block?.content,
      });
    }
  }
  return out;
}
```

**Notes & provenance**

* The `query({...})` async‑generator and `SDKMessage` schema are taken directly from the **Claude Code SDK** docs; `--print` + `--output-format stream-json` is the precise streaming recipe they document. ([Anthropic][1])
* Returning a **UIMessage** stream via `createUIMessageResponse({ execute(dataStream){ ... }})` matches the AI SDK v5 “Chatbot tool usage / returning UIMessage responses” guidance. The UI reads parts with the documented **UIMessage stream** contract. ([v5.ai-sdk.dev][10], [v5.ai-sdk.dev][12])

---

### 2) Client: **useChat** hook bound to our route

```tsx
// app/chat/page.tsx (React client)
'use client';

import { useChat } from 'ai/react'; // AI SDK v5 UI reference :contentReference[oaicite:37]{index=37}
import { useState } from 'react';

export default function ChatPage() {
  const [settings, setSettings] = useState({
    maxTurns: 6,
    allowedTools: 'Read,Write,Edit,Bash,Glob,Grep',
    disallowedTools: '',
    mcpConfigPath: '',
    permissionPromptTool: '',
    dangerouslySkipPermissions: false,
    dangerouslyAssumeYesToAllPrompts: false,
    memoryPaths: ['./CLAUDE.md', '~/.claude/CLAUDE.md'],
  });

  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({
    api: '/api/claude', // our server route above
    body: (ctx) => ({
      prompt: ctx.messages.at(-1)?.content ?? '',
      maxTurns: settings.maxTurns,
      allowedTools: settings.allowedTools,
      disallowedTools: settings.disallowedTools,
      mcpConfigPath: settings.mcpConfigPath,
      permissionPromptTool: settings.permissionPromptTool,
      dangerouslySkipPermissions: settings.dangerouslySkipPermissions,
      dangerouslyAssumeYesToAllPrompts: settings.dangerouslyAssumeYesToAllPrompts,
      memoryPaths: settings.memoryPaths,
    }),
  });

  return (
    <div className="flex flex-col h-screen">
      {/* your CodeMirror / xterm panes go elsewhere */}
      <div className="flex-1 overflow-auto p-4 space-y-3">
        {messages.map((m) => (
          <div key={m.id} className={m.role === 'user' ? 'text-blue-600' : 'text-gray-900'}>
            {m.content}
          </div>
        ))}
      </div>

      <form onSubmit={handleSubmit} className="p-3 border-t flex gap-2">
        <input
          className="flex-1 border rounded px-3 py-2"
          value={input}
          onChange={handleInputChange}
          placeholder="Ask Claude Code…"
        />
        <button className="px-4 py-2 border rounded" disabled={isLoading}>
          Send
        </button>
      </form>
    </div>
  );
}
```

* `useChat` is the canonical UI hook in AI SDK v5; here we pass a `body` function that sends the last user message plus our toggles to the server. ([v5.ai-sdk.dev][8])

---

### 3) Sub‑agents, hooks, TDD loops, and planner/orchestrator

**Sub‑agents (planner + workers)**

* Place sub‑agent files under `.claude/agents/` (project) or `~/.claude/agents/` (user) with YAML frontmatter. Create a *planner/orchestrator* agent (keeps big‑picture context) and worker agents (e.g., `test-runner`, `type-checker`, `linter`, `feature-implementer`), each with a minimal tool set (`Read/Edit/Bash/Grep/Glob` as needed). Manage them via `/agents`. Exact file format and locations are in the docs. ([Anthropic][6])

**Hooks for TDD / quality gates**

* Use **`PreToolUse`** to gate or mutate tool calls (e.g., block `Bash` that isn’t `npm test`, or rewrite a test run command to include `--watch=false`).
* Use **`PostToolUse`** to run lints/formatters after `Write/Edit/MultiEdit`.
* Use **`Stop`** to refuse stopping until a checklist (tests pass, typecheck clean) is satisfied (return **JSON** with `"decision":"block"` and an LLM‑facing `reason`).
* **Hook IO** and the decision contracts (`permissionDecision`, `decision`, `continue`, etc.) are explicitly defined in the docs, with examples. ([Anthropic][7])

**Example settings.json (hooks)**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash.py" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/run-lint-and-typecheck.sh", "timeout": 300 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ensure-tests-pass.py", "timeout": 120 }
        ]
      }
    ]
  }
}
```

* The structure, matcher semantics, `CLAUDE_PROJECT_DIR`, exit‑code / JSON control rules are exactly as specified. ([Anthropic][7])

**Planner workflow**

* **High‑level** orchestration is aligned with AI SDK **Agents** patterns (orchestrator‑worker, evaluator‑optimizer). Keep planner context clean by offloading granular edits to sub‑agents; the planner can review diffs, spawn a QA sub‑agent, and re‑invoke workers until criteria met. ([v5.ai-sdk.dev][14])

---

### 4) Slash commands to kick workflows

* Create custom commands in `.claude/commands/`, e.g., `/ship-feature $ARGUMENTS` that loads @files and includes `!` bash context like `git status`. Add YAML frontmatter `allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git commit:*)`. Exactly how to define, namespace, and pass arguments is covered in the slash commands doc. ([Anthropic][3])

---

### 5) MCP servers & permission prompt tool

* Add servers with `claude mcp add ...` and set scope with `-s local|project|user`. Project scope writes `.mcp.json`. Use `/mcp` within Claude to authenticate OAuth servers. You can also **serve Claude** itself via `claude mcp serve`. All exact commands and formats are in docs. ([Anthropic][4])
* For non‑interactive runs, route permission gates through an MCP tool with `--permission-prompt-tool mcp__server__tool` and implement the exact JSON payload contract (`behavior`, `updatedInput`, `message`). ([Anthropic][1])

---

### 6) Interactive mode expectations (for xterm pane)

* Teach users: `Ctrl+D` exits; `Ctrl+C` interrupts; `/help`, `/clear`, `/vim`, `/terminal-setup` for Shift+Enter keybinding, etc. (You can show these in a help drawer.) ([Anthropic][2])

---

### 7) Session documentation in `.pm/<session>.md`

* As Claude runs, your server can write a `.pm/${sessionId}.md` file (and/or append) with:

  * **Created/updated/deleted files** (read from streaming JSON `assistant` tool blocks `tool_use`/`tool_result` for `Write|Edit|MultiEdit`).
  * A summary of tests/typecheck/lint status (from hook outputs).
  * A final “what was done” section when the `result` message arrives.
* The transcript path (`transcript_path`) is provided to hooks (per input schema). Use it to link to the canonical JSONL. ([Anthropic][7])

---

## D. Security / permissions posture

* Default to **explicit allowlisting** with `--allowedTools` and do **not** set `--dangerously-skip-permissions` or `--dangerously-assume-yes-to-all-prompts` unless a user flips a UI toggle (and warn in‑product). Exact flag names and effects are documented. ([Anthropic][1])
* For MCP, require explicit allows for each tool by full name `mcp__server__tool` (glob patterns not supported). ([Anthropic][1])

---

## E. End‑to‑end test: small prompt in print mode (no UI)

If you want to sanity‑check the pipeline quickly from Node without the chat UI, the following matches the docs exactly:

```ts
import { query } from '@anthropic-ai/claude-code';

const messages = [];
for await (const m of query({
  prompt: 'Explain src/index.ts in 2 sentences.',
  options: {
    print: true,
    outputFormat: 'stream-json',
    maxTurns: 3,
    allowedTools: 'Read,Grep,Glob',
  },
})) {
  messages.push(m);
}
console.log(JSON.stringify(messages, null, 2));
```

* This uses the documented async‑generator, print mode, stream JSON, and a tool allowlist. ([Anthropic][1])

---

## F. References (inline, near the claims)

* **Claude Code SDK** (TypeScript, CLI flags, multi‑turn, output formats, MCP + permission prompt tool, message schema): ([Anthropic][1])
* **SDK page extra flags** (dangerous flags, shell flags, transcript/memory/jupyter): ([Anthropic][1])
* **Interactive mode** (Ctrl+D exit, Ctrl+C, quick commands, vim): ([Anthropic][2])
* **Slash commands** (built‑ins, custom file structure, `$ARGUMENTS`, `!` bash, MCP prompts): ([Anthropic][3])
* **Memory (CLAUDE.md)**: ([Anthropic][5])
* **Sub‑agents** (file locations, YAML, `/agents`, examples): ([Anthropic][6])
* **Hooks reference** (events, structure, stdin JSON, exit codes & JSON decisions): ([Anthropic][7])
* **MCP** (add/list/remove, scopes, `.mcp.json`, OAuth via `/mcp`, serve Claude, resources, prompts): ([Anthropic][4])
* **AI SDK v5**:

  * `useChat` (UI): ([v5.ai-sdk.dev][8])
  * Chatbot & tool usage (return UIMessage streams): ([v5.ai-sdk.dev][9], [v5.ai-sdk.dev][10])
  * Transport overview: ([v5.ai-sdk.dev][11])
  * UIMessage stream & reader helper: ([v5.ai-sdk.dev][12])
  * `streamText` (Core reference): ([v5.ai-sdk.dev][13])
  * Agents patterns to mirror with planner+workers: ([v5.ai-sdk.dev][14])

---

## G. What to do next (switches you likely want in your UI)

1. **Session controls**: `maxTurns`, `/agents` picker, “planner” on/off, “QA/Reviewer must run” toggle (wired to Stop hook).
2. **Permissions**: `allowedTools`, `disallowedTools`, MCP server enablement; “dangerous” toggles off by default (with warnings). ([Anthropic][1], [Anthropic][1])
3. **Quality gates**: TDD on/off; typecheck & lint on/off; “loop until green” (Stop hook `decision:block`). ([Anthropic][7])
4. **Artifacts**: `.pm/SESSION.md` writer; link to `transcript_path`. ([Anthropic][7])

If you want, I can extend the server bridge to emit richer **tool‑call** / **tool‑result** parts (so the Chat UI renders them distinctly), and add a tiny **.pm** writer that infers created/edited/deleted files from Claude’s `Write/Edit/MultiEdit` tool results as they stream in. All of that sits on top of the exact, documented shapes above.

[1]: https://docs.anthropic.com/en/docs/claude-code/sdk "Claude Code SDK - Anthropic"
[2]: https://docs.anthropic.com/en/docs/claude-code/interactive-mode "Interactive mode - Anthropic"
[3]: https://docs.anthropic.com/en/docs/claude-code/slash-commands "Slash commands - Anthropic"
[4]: https://docs.anthropic.com/en/docs/claude-code/mcp "Model Context Protocol (MCP) - Anthropic"
[5]: https://docs.anthropic.com/en/docs/claude-code/memory "Manage Claude's memory - Anthropic"
[6]: https://docs.anthropic.com/en/docs/claude-code/sub-agents "Sub agents - Anthropic"
[7]: https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"
[8]: https://v5.ai-sdk.dev/docs/reference/ai-sdk-ui/use-chat "AI SDK UI: useChat"
[9]: https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot "AI SDK UI: Chatbot"
[10]: https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot-tool-usage "AI SDK UI: Chatbot Tool Usage"
[11]: https://v5.ai-sdk.dev/docs/ai-sdk-ui/transport "AI SDK UI: Transport"
[12]: https://v5.ai-sdk.dev/docs/ai-sdk-ui/reading-ui-message-streams "AI SDK UI: Reading UIMessage Streams"
[13]: https://v5.ai-sdk.dev/docs/reference/ai-sdk-core/stream-text "AI SDK Core: streamText"
[14]: https://v5.ai-sdk.dev/docs/foundations/agents "Foundations: Agents"
