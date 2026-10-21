import type { Browser } from "../browser/contract.ts";
import { hostBrowser, unavailableBrowser } from "../browser/host-client.ts";
import type { CodingHost } from "../apps/code/contract.ts";
import { hostCoding, unavailableCoding } from "../apps/code/host-client.ts";
import { scopeName, type Scope } from "../identity/contract.ts";
import { isMachineOwner } from "../identity/service.ts";
import { sha256 } from "../protocol/bytes.ts";
import { Unavailable } from "../protocol/host.ts";
import type { Terminals } from "../terminal/contract.ts";
import { hostTerminals, unavailableTerminals } from "../terminal/host-client.ts";
import type { Runner } from "../workspace/contract.ts";
import { hostRunner } from "../workspace/host.ts";
import { Effect } from "effect";
import type { Env } from "./env.ts";

/** Everything that differs between the deployment modes. */
export interface Mode {
  /**
   * Whether this person may act on the machine Devys runs on (coding, terminals, files, the
   * browser) and create businesses: where the Mac host is configured only the Mac's owner; in
   * cloud mode nothing runs as a person, so any member.
   */
  mayUseMachine(personId: string): Promise<boolean>;
  /** Whether a request carries the Mac host's token (the host's own reports); never in cloud. */
  fromHost(request: Request): Promise<boolean>;
  /** Commands and files. `within` confines file access to a folder (the owner's file views). */
  runner(within?: string): Runner;
  coding: (scope: Scope) => CodingHost;
  terminals: (businessId: string) => Terminals;
  /** The business's own browser: Chrome with its profile on the Mac; none in the cloud yet. */
  browser: (businessId: string) => Browser;
  /** The business's folder that owner files, terminals and project files live in, if any. */
  businessFolder(businessId: string): string | undefined;
  /** Where an employee's files and commands live, stated in its instructions. */
  workplace: string;
}

const notConfigured = () => {
  throw new Unavailable("The Mac host is not configured; run `bun run local install`.");
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
        // Without a configured host nothing acts on the Mac, so no one is refused.
        mayUseMachine: async (personId) =>
          !host || (await Effect.runPromise(isMachineOwner(env.HYPERDRIVE, personId))),
        fromHost: async (request) =>
          Boolean(token) &&
          (await sha256(request.headers.get("authorization") ?? "")) ===
            (await sha256(`Bearer ${token}`)),
        // Checked per call so a missing host breaks only file, command and coding tools.
        runner: (within) => (scope) =>
          host ? hostRunner({ ...host, files: env.FILES, within }, scope) : notConfigured(),
        coding: (scope) => (host ? hostCoding(host, scope) : notConfigured()),
        terminals: (businessId) =>
          host ? hostTerminals(host, { businessId, employeeId: "owner" }) : unavailableTerminals(),
        browser: (businessId) => (host ? hostBrowser(host, businessId) : unavailableBrowser()),
        businessFolder: folder,
        workplace: `You work on the owner's Mac, as the owner: run executes zsh with the owner's tools and logins, starting in this business's folder under ${home ?? "the owner's home folder"}/Devys. The owner's files are under ${home ?? "the owner's home folder"}; use absolute paths. The business's skills folder is skills inside that business folder. Changes apply to the owner's real files immediately.`,
      };
    }
    case "cloud":
      return {
        mayUseMachine: async () => true,
        fromHost: async () => false,
        runner: () => (scope) => env.WORKSPACE.getByName(scopeName(scope)),
        coding: () => unavailableCoding(),
        terminals: () => unavailableTerminals(),
        browser: () => unavailableBrowser(),
        businessFolder: () => undefined,
        workplace:
          "You work in a private Linux workspace: run executes bash starting in /workspace, files live under /workspace, and the business's skills folder is /workspace/skills (in your workspace until cloud mode shares one per business). Files persist at workspace checkpoints; snapshots preserve files, not processes.",
      };
    default:
      throw new Error(`Unknown DEVYS_MODE: ${String(env.DEVYS_MODE)}`);
  }
}
