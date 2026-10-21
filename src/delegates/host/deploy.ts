/**
 * Deploys on the trusted Mac host: the repository's own deploy command, run in a fresh
 * detached worktree at exactly one commit, with that business's stage secrets in its
 * environment and nowhere else (until V0's broker holds them).
 */
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Stage } from "../contract.ts";

/**
 * A business's deploy secrets: `KEY=VALUE` lines in `<host data>/deploy/<business>.env`,
 * optionally scoped to one stage as `preview.KEY=VALUE` or `production.KEY=VALUE`.
 */
export async function deploySecrets(data: string, businessId: string, stage: Stage) {
  const file = join(data, "deploy", `${businessId}.env`);
  if (!existsSync(file)) return {};
  const secrets: Record<string, string> = {};
  for (const line of (await readFile(file, "utf8")).split("\n")) {
    const match = /^\s*(?:(preview|production)\.)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!match || (match[1] && match[1] !== stage)) continue;
    secrets[match[2]!] = match[3]!.trim().replace(/^(["'])(.*)\1$/, "$2");
  }
  return secrets;
}

/** Output with every secret value replaced, so a command that echoes one leaks nothing. */
export function redact(text: string, secrets: Record<string, string>) {
  return Object.values(secrets)
    .filter((value) => value.length >= 4)
    .reduce((out, value) => out.split(value).join("[redacted]"), text);
}

/** The last https URL a deploy printed (Wrangler and Alchemy print the deployed address). */
export function urlIn(output: string) {
  return [...output.matchAll(/https:\/\/[^\s"'<>`]+/g)].map((match) => match[0]).at(-1) ?? null;
}

/** GETs the deployed URL a few times while it comes up: its status, or null if unreachable. */
export async function smoke(url: string, attempts = 5, delayMs = 3_000) {
  let status: number | null = null;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: "manual",
        signal: AbortSignal.timeout(15_000),
      });
      status = response.status;
      await response.body?.cancel();
      if (status < 400) return status;
    } catch {
      status = null;
    }
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  return status;
}
