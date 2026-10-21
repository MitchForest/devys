import { useEffect, useState } from "react";
import { sandboxed } from "../../apps/documents/contract.ts";
import { api } from "../app/api.ts";
import { useWorkspace } from "../app/workspace.tsx";

/**
 * A page an employee published, rendered alone: an opaque-origin frame (no same-origin, so it
 * can't reach Devys or its cookies) under a policy that fetches nothing.
 */
export function ArtifactFrame({ id, className }: { id: string; className?: string }) {
  const { businessId } = useWorkspace();
  const [html, setHtml] = useState<string | null>(null);
  const [problem, setProblem] = useState<string>();
  useEffect(() => {
    let live = true;
    setHtml(null);
    api
      .artifactText(businessId, id)
      .then((text) => live && setHtml(text))
      .catch(
        (error: unknown) =>
          live && setProblem(error instanceof Error ? error.message : "Unavailable"),
      );
    return () => {
      live = false;
    };
  }, [businessId, id]);
  if (problem) return <p className="p-4 text-body text-ink-3">{problem}</p>;
  if (html === null) return <p className="p-4 text-body text-ink-3">Loading…</p>;
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
