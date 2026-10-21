import type { RoleTemplateId } from "./roles.ts";
import type { Skill } from "./skill.ts";

/**
 * The one installable unit (.docs/APPS_AND_CAPABILITIES.md#app): the capabilities it owns,
 * the record kinds it owns, the skills it ships and the connections it needs, as a literal in
 * its folder's `app.ts`. Its records stay with the code that owns them.
 */
export interface AppManifest {
  /** Lowercase, and its folder's name: "documents". */
  id: string;
  name: string;
  /** An SF Symbol name; clients map it to their icon set. */
  icon: string;
  summary: string;
  /** System apps are always installed, never uninstalled and not in the sidebar. */
  kind: "system" | "business";
  /** The `Ref` kinds it owns (`devys:<id>/<kind>/…`). */
  records: readonly { kind: string; title: string }[];
  /** Every capability belongs to exactly one app. */
  capabilities: readonly string[];
  /** `SKILL.md` folders shipped with the app. */
  skills: readonly Skill[];
  connections: readonly { provider: string; scopes: readonly string[] }[];
  /** When the sidebar lists it once installed: always, once it has records, or never. */
  appears: "always" | "records" | "never";
  /** The capabilities proposed to each role at hire, never granted by installing. */
  defaultGrants?: Partial<Record<RoleTemplateId, readonly string[]>>;
}

/** Declares an app. The manifest is the literal it is given. */
export const defineApp = <const M extends AppManifest>(manifest: M): M => manifest;
