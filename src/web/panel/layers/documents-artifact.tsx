import { ChevronLeft, ChevronRight } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { sandboxed } from "../../../apps/documents/contract.ts";
import { ref } from "../../../protocol/ref.ts";
import { api } from "../../app/api.ts";
import { useArtifacts, useBusinessId } from "../../app/data.ts";
import { useLayers, useNav } from "../../app/navigation.ts";
import { keys, problemOf } from "../../app/query.ts";

/**
 * A page an employee published, following its versions: a new version arriving in the
 * conversation replaces the one on screen and says who changed it. The server numbers versions.
 */
export function ArtifactLayer({ id }: { id: string }) {
  const artifacts = useArtifacts();
  const nav = useNav();
  const { updatedBy } = useLayers();
  const current = artifacts.find((a) => a.id === id);
  const sibling = (version: number) =>
    current && artifacts.find((a) => a.filename === current.filename && a.version === version);
  const step = (by: number) => {
    const next = current && sibling(current.version + by);
    if (next) nav.replaceLayer({ kind: "record", ref: ref("documents", "artifact", next.id) });
  };
  const versioned = current !== undefined && current.versions > 1;
  return (
    <div className="flex h-full flex-col">
      {(versioned || updatedBy) && (
        <div className="flex h-9 shrink-0 items-center gap-1.5 border-b border-hairline px-3">
          {versioned && (
            <span className="flex items-center gap-0.5 text-caption text-ink-3 tabular-nums">
              <button
                type="button"
                aria-label="Earlier version"
                disabled={!sibling(current.version - 1)}
                onClick={() => step(-1)}
                className="grid size-5 place-items-center rounded disabled:opacity-30 enabled:hover:text-ink"
              >
                <ChevronLeft className="size-3.5" />
              </button>
              v{current.version} of {current.versions}
              <button
                type="button"
                aria-label="Later version"
                disabled={!sibling(current.version + 1)}
                onClick={() => step(1)}
                className="grid size-5 place-items-center rounded disabled:opacity-30 enabled:hover:text-ink"
              >
                <ChevronRight className="size-3.5" />
              </button>
            </span>
          )}
          {updatedBy && (
            <span className="truncate text-caption text-indigo" data-testid="updated-by">
              Updated by {updatedBy}
            </span>
          )}
        </div>
      )}
      <div className="min-h-0 flex-1">
        <ArtifactFrame id={id} />
      </div>
    </div>
  );
}

/**
 * A page an employee published, rendered alone: an opaque-origin frame (no same-origin, so it
 * can't reach Devys or its cookies) under a policy that fetches nothing.
 */
export function ArtifactFrame({ id, className }: { id: string; className?: string }) {
  const businessId = useBusinessId();
  // A published version never changes, so it is read once.
  const page = useQuery({
    queryKey: keys.artifact(businessId, id),
    queryFn: () => api.artifactText(businessId, id),
    staleTime: Infinity,
  });
  if (page.isError)
    return (
      <p role="alert" className="p-4 text-body text-ink-3">
        {problemOf(page.error, "This file couldn't be opened.")}
      </p>
    );
  if (page.isPending) return <p className="p-4 text-body text-ink-3">Loading…</p>;
  const html = page.data;
  return (
    <iframe
      title="Published page"
      sandbox="allow-scripts"
      referrerPolicy="no-referrer"
      srcDoc={sandboxed(html)}
      className={className ?? "size-full border-0 bg-white"}
      data-testid="artifact-frame"
    />
  );
}
