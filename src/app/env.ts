import type { Env as CloudEnv } from "../../infra/api.ts";

/**
 * The Worker's bindings. Both modes declare the same ones (`infra/api.ts` for cloud,
 * `wrangler.local.jsonc` for local); local mode also says where the Mac host is, set by the
 * launcher. Only `src/app` reads them; components declare the few bindings they use.
 */
export type Env = CloudEnv & {
  DEVYS_HOST_URL?: string;
  DEVYS_HOST_TOKEN?: string;
  /** The owner's home folder on the Mac. */
  DEVYS_HOST_HOME?: string;
  /**
   * The key the Mac app reads from the server folder to sign in as the Mac's owner; only the
   * owner's macOS user can read it, never a confined employee process (.docs/AUTHORITY.md).
   */
  DEVYS_OWNER_KEY?: string;
  /** The Mac's name, on the one button other devices show: "Connect to <name>". */
  DEVYS_MACHINE_NAME?: string;
};
