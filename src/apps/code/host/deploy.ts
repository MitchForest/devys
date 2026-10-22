/**
 * Deploys on the trusted Mac host: the repository's own deploy command, run in a fresh
 * detached worktree at exactly one commit, with the secrets it names from the vault in its
 * environment and nowhere else.
 */

/** The last https URL a deploy printed (Wrangler and Alchemy print the deployed address). */
export function urlIn(output: string) {
  return [...output.matchAll(/https:\/\/[^\s"'<>`]+/g)].map((match) => match[0]).at(-1) ?? null;
}

/** GETs the deployed URL a few times while it comes up: its status, or null if unreachable. */
export async function smoke(url: string, attempts = 5, delayMs = 3_000) {
  let status: number | null = null;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: "manual",
        signal: AbortSignal.timeout(15_000),
      });
      status = response.status;
      await response.body?.cancel();
      if (status < 400) return status;
    } catch {
      status = null;
    }
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  return status;
}
