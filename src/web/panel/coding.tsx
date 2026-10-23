import { SquareTerminal } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { api } from "../app/api.ts";
import type { LiveCodingSession } from "../../apps/code/contract.ts";
import { openTerminalWindow } from "../shell/terminal-window.tsx";
import { useBusinessId, useEmployees } from "../app/data.ts";
import { useNav } from "../app/navigation.ts";
import { keys, poll, problemOf } from "../app/query.ts";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import type { Tone } from "../design/primitives.tsx";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";

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

/**
 * "New coding session": the owner drives a session from the start. It becomes a work item
 * owned by the chosen employee but taken over by the owner; handing it back lets the employee
 * verify and ship.
 */
export function NewCodingSession({ open, onClose }: { open: boolean; onClose: () => void }) {
  const businessId = useBusinessId();
  const employees = useEmployees();
  const nav = useNav();
  const client = useQueryClient();
  const engineering = employees.find((e) => e.template === "engineering") ?? employees[0];
  const [employee, setEmployee] = useState(engineering?.id ?? "");
  const [provider, setProvider] = useState<"codex" | "claude">("codex");
  const [where, setWhere] = useState<"existing" | "new">("existing");
  const [repository, setRepository] = useState("");
  const [objective, setObjective] = useState("");
  const [clientId] = useState(() => crypto.randomUUID());
  const starting = useMutation({
    mutationFn: () =>
      api.startCoding(businessId, {
        client_id: clientId,
        employee: employee || engineering?.id || "",
        provider,
        objective: objective.trim(),
        ...(where === "existing"
          ? { repository: repository.trim() }
          : { new_repository: repository.trim() }),
      }),
    onSuccess: (started) => {
      void client.invalidateQueries({ queryKey: keys.business(businessId) });
      nav.openThread(started.work);
      onClose();
    },
  });
  const error = starting.isError
    ? starting.error instanceof Error
      ? starting.error.message
      : "The session couldn't start."
    : null;
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogTitle>New coding session</DialogTitle>
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Coding agent
            <NativeSelect
              value={provider}
              onChange={(e) => setProvider(e.target.value as "codex" | "claude")}
            >
              <option value="codex">Codex</option>
              <option value="claude">Claude Code</option>
            </NativeSelect>
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Repository
            <NativeSelect
              value={where}
              onChange={(e) => setWhere(e.target.value as "existing" | "new")}
            >
              <option value="existing">An existing repository on the Mac</option>
              <option value="new">A new, empty repository</option>
            </NativeSelect>
            <Input
              aria-label={where === "existing" ? "Repository path" : "New repository name"}
              placeholder={where === "existing" ? "/Users/you/Code/project" : "my-app"}
              value={repository}
              onChange={(e) => setRepository(e.target.value)}
            />
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            What to build
            <Textarea
              value={objective}
              onChange={(e) => setObjective(e.target.value)}
              placeholder="Describe the change and how to check it"
            />
          </label>
          <label className="flex flex-col gap-1 text-detail text-ink-3">
            Hand it to, when you hand back
            <NativeSelect value={employee} onChange={(e) => setEmployee(e.target.value)}>
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.name}
                </option>
              ))}
            </NativeSelect>
          </label>
          {error && <span className="text-detail text-ink-2">{error}</span>}
          <Button
            disabled={!objective.trim() || !repository.trim()}
            onClick={() => starting.mutate()}
          >
            Start session
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** The business's open terminals, any of which a device can reopen; and a new one. */
export function Terminals() {
  const businessId = useBusinessId();
  const list = useQuery({
    queryKey: keys.terminals(businessId),
    queryFn: () => api.terminals(businessId),
    select: (result) => result.terminals.filter((t) => !t.exit),
    refetchInterval: 10_000,
  });
  const terminals = list.data ?? [];
  const [opening, setError] = useState<string | null>(null);
  const error =
    opening ?? (list.isError ? problemOf(list.error, "Terminals are unavailable.") : null);
  return (
    <div className="flex flex-col gap-1.5" data-testid="terminals">
      <div className="flex items-center gap-2">
        {terminals.length > 0 && (
          <span className="text-label font-medium text-ink-3">Terminals · {terminals.length}</span>
        )}
        <Button
          variant="quiet"
          size="compact"
          onClick={() =>
            void openTerminalWindow(businessId, {}).catch((cause: unknown) =>
              setError(cause instanceof Error ? cause.message : "The terminal couldn't open."),
            )
          }
        >
          <SquareTerminal /> New terminal
        </Button>
      </div>
      {error && <span className="text-detail text-ink-2">{error}</span>}
      {terminals.map((terminal) => (
        <a
          key={terminal.id}
          href={`/terminal/${businessId}/${terminal.id}`}
          target="_blank"
          rel="noopener"
          className="flex items-center gap-2 rounded-small px-2 py-1.5 text-detail text-ink hover:bg-sheet-tint"
        >
          <SquareTerminal className="size-4 text-ink-3" />
          <span className="truncate">{terminal.title}</span>
          <span className="ml-auto truncate text-caption text-ink-3">{terminal.cwd}</span>
        </a>
      ))}
    </div>
  );
}
