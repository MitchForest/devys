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
};
