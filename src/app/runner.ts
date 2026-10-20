import type { Env } from "../../infra/api.ts";
import { scopeName } from "../identity/contract.ts";
import { hostRunner } from "../workspace/host.ts";
import type { Runner } from "../workspace/contract.ts";

/** Local mode adds the Mac host's address, its token and the owner's home folder. */
type LocalVariables = Partial<
  Record<"DEVYS_HOST_URL" | "DEVYS_HOST_TOKEN" | "DEVYS_HOST_HOME", string>
>;

/**
 * The deployment mode decides the runner (.docs/COMPONENTS.md#deployment-modes): the
 * trusted Mac host in local mode, the Cloudflare Sandbox in cloud mode. No fallback.
 */
export function runnerFor(env: Env, within?: string): Runner {
  const mode = env.DEVYS_MODE;
  switch (mode) {
    case "local": {
      const { DEVYS_HOST_URL: url, DEVYS_HOST_TOKEN: token } = env as Env & LocalVariables;
      return (scope) => {
        // Checked per call so a missing host breaks only file and command tools.
        if (!url || !token)
          throw new Error("The Mac host is not configured; run `bun run local install`.");
        return hostRunner({ url, token, files: env.FILES, within }, scope);
      };
    }
    case "cloud":
      return (scope) => env.WORKSPACE.getByName(scopeName(scope));
    default:
      throw new Error(`Unknown DEVYS_MODE: ${String(mode)}`);
  }
}

/** Whether commands run on the owner's Mac: local mode with its host configured. */
export const onTheMac = (env: Env) => {
  const { DEVYS_HOST_URL: url, DEVYS_HOST_TOKEN: token } = env as Env & LocalVariables;
  return env.DEVYS_MODE === "local" && Boolean(url && token);
};

/** Where an employee's files and commands live, stated in its instructions. */
export function workplaceFor(env: Env): string {
  if (env.DEVYS_MODE === "local") {
    const home = (env as Env & LocalVariables).DEVYS_HOST_HOME || "the owner's home folder";
    return `You work on the owner's Mac, as the owner: run executes zsh with the owner's tools and logins, starting in this business's folder under ${home}/Devys. The owner's files are under ${home}; use absolute paths. Your skills folder is ${home}/Devys/skills. Changes apply to the owner's real files immediately.`;
  }
  return "You work in a private Linux workspace: run executes bash starting in /workspace, files live under /workspace, and your skills folder is /workspace/skills. Files persist at workspace checkpoints; snapshots preserve files, not processes.";
}
