import type { AppManifest } from "../protocol/app.ts";

/** A directory entry for one business: the manifest, its skills by name, and its install. */
export interface InstalledApp extends Omit<AppManifest, "skills"> {
  skills: { name: string; description: string }[];
  /** System apps always are. */
  installed: boolean;
  pinned: boolean;
  /** Installed, and it has something to show by its `appears` rule. */
  visible: boolean;
}
