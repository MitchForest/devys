import { Schema } from "effect";
import { RoleTemplateId } from "../protocol/roles.ts";

/**
 * A directory entry for one business: the manifest (`AppManifest`), its skills by name, and its
 * install.
 */
export const InstalledApp = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  /** An SF Symbol name; clients map it to their icon set. */
  icon: Schema.String,
  summary: Schema.String,
  /** System apps are always installed and never in the sidebar. */
  kind: Schema.Literals(["system", "business"]),
  records: Schema.Array(Schema.Struct({ kind: Schema.String, title: Schema.String })),
  capabilities: Schema.Array(Schema.String),
  /** The skills it ships, which employees load by name. */
  skills: Schema.Array(Schema.Struct({ name: Schema.String, description: Schema.String })),
  connections: Schema.Array(
    Schema.Struct({ provider: Schema.String, scopes: Schema.Array(Schema.String) }),
  ),
  appears: Schema.Literals(["always", "records", "never"]),
  default_grants: Schema.optionalKey(
    Schema.Record(RoleTemplateId, Schema.optionalKey(Schema.Array(Schema.String))),
  ),
  /** System apps always are. */
  installed: Schema.Boolean,
  pinned: Schema.Boolean,
  /** Installed, and it has something to show by its `appears` rule. */
  visible: Schema.Boolean,
});
export type InstalledApp = typeof InstalledApp.Type;
