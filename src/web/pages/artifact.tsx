import { useQuery } from "@tanstack/react-query";
import { sandboxed } from "../../apps/documents/contract.ts";
import { api } from "../app/api.ts";
import { useBusinessId } from "../app/data.ts";
import { keys, problemOf } from "../app/query.ts";

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
