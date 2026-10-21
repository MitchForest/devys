/**
 * Keeps what an employee starts on the trusted Mac host (local mode) out of other businesses'
 * folders: macOS Seatbelt, the mechanism Codex CLI uses for its own sandbox
 * (`codex-rs/sandboxing/src/seatbelt.rs`: `/usr/bin/sandbox-exec` by absolute path, an inline
 * SBPL policy, paths passed as `-D` parameters). Codex starts from `(deny default)`; this host is
 * trusted by design, so everything the owner's toolchain needs (logins, Xcode, caches, the
 * network) stays allowed and only the businesses folder is closed, except the business's own
 * folder, together with the server's own data outside it (every business's deploy secrets and
 * browser profiles, Postgres, logs, backups), which no confined process needs: the host reads
 * deploy secrets and drives browsers itself. A behaviour guarantee, not isolation: see .docs/ARCHITECTURE.md "Native and host
 * boundaries".
 *
 * Seatbelt matches resolved paths (`/var` is `/private/var`), so all folders are passed as
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
  /** Folders outside `root` no confined process may read or write at all (the server's data). */
  hidden: readonly string[];
}

/**
 * The SBPL policy for one business folder: reading or writing anything under the businesses
 * folder other than `OWN` is denied; the businesses folder itself can be stat'ed (a path through
 * it resolves) but not listed. Each of the `hidden` folders, `HIDDEN0`…, is denied entirely.
 * Read-only also denies every write under the businesses folder.
 */
export function seatbeltPolicy(readOnly: boolean, hidden: number) {
  return [
    "(version 1)",
    "(allow default)",
    '(deny file-read* file-write* (require-all (subpath (param "ROOT")) (require-not (subpath (param "OWN")))))',
    '(allow file-read-metadata (literal (param "ROOT")))',
    ...Array.from(
      { length: hidden },
      (_, index) => `(deny file-read* file-write* (subpath (param "HIDDEN${index}")))`,
    ),
    ...(readOnly ? ['(deny file-write* (subpath (param "ROOT")))'] : []),
  ].join("\n");
}

/**
 * The one place a process an employee starts is wrapped: `command args` under the business's
 * Seatbelt policy, as the file and arguments to spawn. Every folder is created if missing so
 * its real path exists.
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
  const hidden = place.hidden.map((folder) => {
    mkdirSync(folder, { recursive: true });
    return realpathSync(folder);
  });
  return [
    sandboxExec,
    [
      "-p",
      seatbeltPolicy(place.readOnly, hidden.length),
      `-DROOT=${root}`,
      `-DOWN=${own}`,
      ...hidden.map((folder, index) => `-DHIDDEN${index}=${folder}`),
      "--",
      command,
      ...args,
    ],
  ];
}
