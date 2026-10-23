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
  /** Its logo, served by Devys (a remote app's); built-in apps draw their symbol. */
  logo: Schema.NullOr(Schema.String),
  /** A remote app's state; null for a built-in app. */
  state: Schema.NullOr(Schema.Literals(["connecting", "review", "on", "lapsed"])),
});
export type InstalledApp = typeof InstalledApp.Type;

/**
 * Where a remote app stands: added (`connecting`), signed in and waiting for the owner's Turn on
 * (`review`), on, or `lapsed` (its sign-in stopped working; the owner reconnects).
 */
export const RemoteState = Schema.Literals(["connecting", "review", "on", "lapsed"]);
export type RemoteState = typeof RemoteState.Type;

/**
 * A remote app's line for one of its tools, as the owner set it: employees use it on their own,
 * ask the owner first, or never have it.
 */
export const Line = Schema.Literals(["own", "ask", "never"]);
export type Line = typeof Line.Type;

/** The owner's acceptance of a remote app, which is its policy: each tool's line, and who uses it. */
export const RemotePolicy = Schema.Struct({
  lines: Schema.Record(Schema.String, Line),
  employees: Schema.Array(Schema.String),
});
export type RemotePolicy = typeof RemotePolicy.Type;

/**
 * Tools that hand out payment credentials (a card number, a payment token): never offered to
 * employees, whatever the owner chooses. A card from one reaches only a checkout, through the
 * host's fill against a signed spend approval (.docs/AUTHORITY.md#credentials).
 */
export const paymentCredentialTools: readonly string[] = [
  "ramp_get_agent_card_creds",
  "ramp_mpp_creds",
];

/** The card tool a card app (Ramp) has, which the host calls for a fill. */
export const cardTool = "ramp_get_agent_card_creds";

/**
 * A remote tool's capability name: its app's id, an underscore and the tool's name (characters
 * other than letters, digits and `_` become `_`). Built-in names have no underscore and remote
 * app ids none either, so the name is unique across every app. Undefined when it would be longer
 * than tools may be named (64).
 */
export function remoteCapabilityName(appId: string, tool: string) {
  const name = `${appId}_${tool.replace(/[^A-Za-z0-9_]/g, "_")}`;
  return name.length <= 64 ? name : undefined;
}

/**
 * The line Devys suggests for a tool, from its own hints (descriptive, never policy): a tool that
 * says it only reads runs on its own; anything else asks first; a payment credential, never.
 */
export function suggestedLine(tool: { name: string; hints: { readOnlyHint?: boolean } }): Line {
  if (paymentCredentialTools.includes(tool.name)) return "never";
  return tool.hints.readOnlyHint === true ? "own" : "ask";
}

/** One app a search found: installed, added, or in the MCP Registry. */
export const FoundApp = Schema.Struct({
  /** What `askOwner` connect takes: an app's id, its registry name or its address. */
  app: Schema.String,
  name: Schema.String,
  description: Schema.String,
  /** Its logo as Devys serves it, when it has one. */
  logo: Schema.NullOr(Schema.String),
  /** Installed (a built-in app) or on (a remote app): its capabilities are there to use. */
  installed: Schema.Boolean,
});
export type FoundApp = typeof FoundApp.Type;

/** One app in the Connect apps sheet: a found app, in its category. */
export const ListedApp = Schema.Struct({
  ...FoundApp.fields,
  category: Schema.String,
});
export type ListedApp = typeof ListedApp.Type;

/**
 * How a remote app's MCP server describes itself (`serverInfo`): display only, never trusted for
 * a decision. `icons` are its logo candidates.
 */
export interface RemoteServer {
  name: string;
  title?: string;
  description?: string;
  website?: string;
  icons: { src: string }[];
}

/**
 * One tool a remote app lists. `hints` are its annotations: descriptive, used only to suggest the
 * owner's defaults (imported metadata is not policy).
 */
export interface RemoteTool {
  name: string;
  title?: string;
  description: string;
  /** Its JSON Schema, as the server declares it. */
  input: Record<string, unknown>;
  hints: {
    readOnlyHint?: boolean;
    destructiveHint?: boolean;
    idempotentHint?: boolean;
    openWorldHint?: boolean;
  };
}

/** What a tool answered: its text, its structured data and whether it reported an error. */
export interface ToolResult {
  text: string;
  data?: unknown;
  error: boolean;
}
