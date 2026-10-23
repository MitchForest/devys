import { useQuery } from "@tanstack/react-query";
import { api } from "../app/api.ts";
import type { LiveCodingSession } from "../../apps/code/contract.ts";
import { keys, poll } from "../app/query.ts";
import type { Tone } from "../design/primitives.tsx";

export const providerName = (provider: LiveCodingSession["provider"]) =>
  provider === "codex" ? "Codex" : "Claude Code";

export const stateChip: Record<LiveCodingSession["state"], { tone: Tone; title: string }> = {
  working: { tone: "inProgress", title: "Working" },
  idle: { tone: "done", title: "Turn finished" },
  interrupted: { tone: "waiting", title: "Interrupted" },
  failed: { tone: "failed", title: "Failed" },
  unavailable: { tone: "waiting", title: "Mac host unavailable" },
};

/** Polls a work item's coding sessions while it is shown; the provider is the source. */
export function useSessions(businessId: string, workId: string) {
  return useQuery({
    queryKey: keys.sessions(businessId, workId),
    queryFn: () => api.codingSessions(businessId, workId),
    select: (result) => result.sessions,
    refetchInterval: poll,
  });
}
