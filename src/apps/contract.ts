import type { RoleTemplateId } from "../identity/contract.ts";

/**
 * An installable business function, as a literal in code: the records it owns, the
 * capabilities employees and the owner take on them, and the connections it needs. Its records
 * stay with the components that own them; an app only says which belong to it.
 */
export interface AppManifest {
  id: string;
  name: string;
  /** A symbol name clients map to their icon set, such as "doc.text". */
  icon: string;
  summary: string;
  /** The kinds of record it owns, such as "artifact" or "assignment". */
  records: readonly string[];
  /** Capability names that belong to it: usable only while it is installed. */
  capabilities: readonly string[];
  /** Connections it uses, such as "google" or "github". */
  connections: readonly string[];
  /** When an installed app shows in the sidebar: always, once it has records, or once connected. */
  appears: "always" | "records" | "connected";
  /** Coming apps are listed in the directory and cannot be installed yet. */
  status: "available" | "coming";
  /** The capabilities proposed to each role at hire; the owner can change any grant. */
  defaultGrants?: Partial<Record<RoleTemplateId, readonly string[]>>;
}

/** A directory entry for one business. */
export interface InstalledApp extends AppManifest {
  installed: boolean;
  pinned: boolean;
  /** Installed, and it has something to show by its `appears` rule. */
  visible: boolean;
}
