import type { Browser } from "../browser/contract.ts";
import { hostBrowser, unavailableBrowser } from "../browser/host-client.ts";
import type { Delegates } from "../delegates/contract.ts";
import { hostDelegates, unavailableDelegates } from "../delegates/host-client.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import type { Terminals } from "../terminal/contract.ts";
import { hostTerminals, unavailableTerminals } from "../terminal/host-client.ts";
import type { Runner } from "../workspace/contract.ts";
import { hostRunner } from "../workspace/host.ts";
import type { Env } from "./env.ts";

/** Where the Mac host listens, its token, and the owner's home folder (local mode). */
export interface MacHost {
  url: string;
  token: string;
  home: string;
}

/** Everything that differs between the deployment modes. */
export interface Mode {
  /** The Mac host when local mode has one configured; employees and owner surfaces run there. */
  host: MacHost | undefined;
  /** Commands and files. `within` confines file access to a folder (the owner's file views). */
  runner(within?: string): Runner;
  delegates: (scope: Scope) => Delegates;
  terminals: (businessId: string) => Terminals;
  /** The business's own browser: Chrome with its profile on the Mac; none in the cloud yet. */
  browser: (businessId: string) => Browser;
  /** The business's folder that owner files, terminals and space files live in, if any. */
  businessFolder(businessId: string): string | undefined;
  /** Where an employee's files and commands live, stated in its instructions. */
  workplace: string;
}

const notConfigured = () => {
  throw new Error("The Mac host is not configured; run `bun run local install`.");
};

/**
 * The deployment mode picks the whole adapter set (.docs/COMPONENTS.md#deployment-modes):
 * the trusted Mac host in local mode, the Cloudflare Sandbox in cloud mode. One switch, no
 * per-component settings and no fallback between modes.
 */
export function modeOf(env: Env): Mode {
  switch (env.DEVYS_MODE) {
    case "local": {
      const { DEVYS_HOST_URL: url, DEVYS_HOST_TOKEN: token, DEVYS_HOST_HOME: home } = env;
      const host = url && token && home ? { url, token, home } : undefined;
      // The host keeps each business in ~/Devys/<business>; see src/host.ts.
      const folder = (businessId: string) => (home ? `${home}/Devys/${businessId}` : undefined);
      return {
        host,
        // Checked per call so a missing host breaks only file, command and coding tools.
        runner: (within) => (scope) =>
          host ? hostRunner({ ...host, files: env.FILES, within }, scope) : notConfigured(),
        delegates: (scope) => (host ? hostDelegates(host, scope) : notConfigured()),
        terminals: (businessId) =>
          host ? hostTerminals(host, { businessId, employeeId: "owner" }) : unavailableTerminals(),
        browser: (businessId) => (host ? hostBrowser(host, businessId) : unavailableBrowser()),
        businessFolder: folder,
        workplace: `You work on the owner's Mac, as the owner: run executes zsh with the owner's tools and logins, starting in this business's folder under ${home ?? "the owner's home folder"}/Devys. The owner's files are under ${home ?? "the owner's home folder"}; use absolute paths. Your skills folder is ${home ?? "the owner's home folder"}/Devys/skills. Changes apply to the owner's real files immediately.`,
      };
    }
    case "cloud":
      return {
        host: undefined,
        runner: () => (scope) => env.WORKSPACE.getByName(scopeName(scope)),
        delegates: () => unavailableDelegates(),
        terminals: () => unavailableTerminals(),
        browser: () => unavailableBrowser(),
        businessFolder: () => undefined,
        workplace:
          "You work in a private Linux workspace: run executes bash starting in /workspace, files live under /workspace, and your skills folder is /workspace/skills. Files persist at workspace checkpoints; snapshots preserve files, not processes.",
      };
    default:
      throw new Error(`Unknown DEVYS_MODE: ${String(env.DEVYS_MODE)}`);
  }
}
