/**
 * Keeps what an employee starts on the trusted Mac host (local mode) out of other businesses'
 * folders: macOS Seatbelt, the mechanism Codex CLI uses for its own sandbox
 * (`codex-rs/sandboxing/src/seatbelt.rs`: `/usr/bin/sandbox-exec` by absolute path, an inline
 * SBPL policy, paths passed as `-D` parameters). Codex starts from `(deny default)`; this host is
 * trusted by design, so everything the owner's toolchain needs (logins, Xcode, caches, the
 * network) stays allowed and only the businesses folder is closed, except the business's own
 * folder. A behaviour guarantee, not isolation: see .docs/ARCHITECTURE.md "Native and host
 * boundaries".
 *
 * Seatbelt matches resolved paths (`/var` is `/private/var`), so both folders are passed as
 * real paths. A sandboxed process cannot apply another sandbox (`sandbox_apply: Operation not
 * permitted`), so nothing started here may rely on its own Seatbelt profile.
 */
import { mkdirSync, realpathSync } from "node:fs";

export const sandboxExec = "/usr/bin/sandbox-exec";

/** Where a confined process may reach. */
export interface Place {
  /** The folder holding every business (`~/Devys`), including the host's own data. */
  root: string;
  /** This business's folder inside `root`. */
  folder: string;
  /** Also nothing under `root` may be written, the business's own folder included (reviews). */
  readOnly: boolean;
}

/**
 * The SBPL policy for one business folder: reading or writing anything under the businesses
 * folder other than `OWN` is denied; the businesses folder itself can be stat'ed (a path through
 * it resolves) but not listed. Read-only also denies every write under it.
 */
export function seatbeltPolicy(readOnly: boolean) {
  return [
    "(version 1)",
    "(allow default)",
    '(deny file-read* file-write* (require-all (subpath (param "ROOT")) (require-not (subpath (param "OWN")))))',
    '(allow file-read-metadata (literal (param "ROOT")))',
    ...(readOnly ? ['(deny file-write* (subpath (param "ROOT")))'] : []),
  ].join("\n");
}

/**
 * The one place a process an employee starts is wrapped: `command args` under the business's
 * Seatbelt policy, as the file and arguments to spawn. Both folders are created if missing so
 * their real paths exist.
 */
export function confine(
  place: Place,
  command: string,
  args: readonly string[],
): [string, string[]] {
  mkdirSync(place.folder, { recursive: true });
  const root = realpathSync(place.root);
  const own = realpathSync(place.folder);
  if (!own.startsWith(`${root}/`))
    throw new Error("A business folder sits inside the businesses folder");
  return [
    sandboxExec,
    [
      "-p",
      seatbeltPolicy(place.readOnly),
      `-DROOT=${root}`,
      `-DOWN=${own}`,
      "--",
      command,
      ...args,
    ],
  ];
}
