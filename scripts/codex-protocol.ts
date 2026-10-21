/**
 * Pins the Codex app-server protocol types the delegate adapter uses to the installed Codex.
 * Generates the full protocol with `codex app-server generate-ts` into a temporary folder and
 * copies only the import closure of the messages Devys sends and reads, plus the version.
 *
 *   bun run codex:protocol
 */
import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, normalize, relative } from "node:path";

const roots = [
  "InitializeParams",
  "InitializeResponse",
  "v2/ThreadStartParams",
  "v2/ThreadStartResponse",
  "v2/ThreadResumeParams",
  "v2/ThreadResumeResponse",
  "v2/ThreadReadParams",
  "v2/ThreadReadResponse",
  "v2/TurnStartParams",
  "v2/TurnStartResponse",
  "v2/TurnSteerParams",
  "v2/TurnSteerResponse",
  "v2/TurnInterruptParams",
  "v2/TurnStartedNotification",
  "v2/TurnCompletedNotification",
  "v2/ItemCompletedNotification",
  "v2/TurnDiffUpdatedNotification",
  "v2/ThreadTokenUsageUpdatedNotification",
  "v2/ErrorNotification",
];

const target = join(import.meta.dirname, "../src/apps/code/host/codex-protocol");
const version = execFileSync("codex", ["--version"], { encoding: "utf8" })
  .trim()
  .split(" ")
  .at(-1)!;
const generated = mkdtempSync(join(tmpdir(), "codex-protocol-"));
try {
  execFileSync("codex", ["app-server", "generate-ts", "--out", generated], { stdio: "ignore" });
  const closure = new Set<string>();
  const pending = roots.map((root) => join(generated, `${root}.ts`));
  while (pending.length) {
    const file = pending.pop()!;
    if (closure.has(file)) continue;
    closure.add(file);
    for (const [, path] of readFileSync(file, "utf8").matchAll(/from "(\.[^"]+)"/g)) {
      const next = normalize(join(dirname(file), path!.endsWith(".ts") ? path! : `${path}.ts`));
      if (existsSync(next)) pending.push(next);
    }
  }
  rmSync(target, { recursive: true, force: true });
  for (const file of closure) {
    const destination = join(target, relative(generated, file));
    mkdirSync(dirname(destination), { recursive: true });
    cpSync(file, destination);
  }
  writeFileSync(join(target, "VERSION"), `${version}\n`);
  console.log(
    `Pinned Codex ${version}: ${closure.size} protocol files in ${relative(process.cwd(), target)}`,
  );
} finally {
  rmSync(generated, { recursive: true, force: true });
}
