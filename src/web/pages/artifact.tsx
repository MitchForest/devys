import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { X } from "lucide-react";
import { useEffect, useState } from "react";
import { sandboxed } from "../../artifacts/contract.ts";
import { api } from "../app/api.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";

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

/** A published page over the workspace: kept in a space, or dashed as not kept yet. */
export function ArtifactViewer() {
  const { viewing, artifacts, spaces, actions, businessId, page } = useWorkspace();
  const [space, setSpace] = useState("");
  const [saving, setSaving] = useState(false);
  if (!viewing) return null;
  const artifact = artifacts.find((each) => each.id === viewing);
  const all = valueOf(spaces) ?? [];
  const keptIn = all.filter((each) =>
    each.items.some((item) => item.kind === "artifact" && item.ref === viewing),
  );
  const target = space || (page.kind === "space" ? page.id : (all[0]?.id ?? ""));
  const save = async () => {
    if (!target) return;
    setSaving(true);
    try {
      await api.addToSpace(businessId, target, "artifact", viewing);
      actions.refresh();
    } finally {
      setSaving(false);
    }
  };
  return (
    <Dialog open onOpenChange={(open) => !open && actions.viewArtifact(undefined)}>
      <DialogContent
        showCloseButton={false}
        className="flex h-[86vh] w-[92vw] max-w-[1100px] flex-col gap-0 overflow-hidden p-0 sm:max-w-[1100px]"
      >
        <div className="flex items-center gap-3 border-b border-hairline px-4 py-2.5">
          <DialogTitle className="truncate text-control font-semibold text-ink">
            {artifact?.filename.replace(/\.html$/, "") ?? "Page"}
          </DialogTitle>
          {keptIn.length ? (
            <span className="text-caption text-ink-3">
              In {keptIn.map((each) => each.name).join(", ")}
            </span>
          ) : (
            <span className="rounded-full border border-dashed border-hairline px-2 py-0.5 text-caption text-ink-3">
              Not kept
            </span>
          )}
          <span className="ml-auto" />
          {all.length > 0 && (
            <>
              <select
                aria-label="Space"
                value={target}
                onChange={(event) => setSpace(event.target.value)}
                className="rounded-[8px] bg-sheet-tint px-2 py-1 text-detail text-ink"
              >
                {all.map((each) => (
                  <option key={each.id} value={each.id}>
                    {each.name}
                  </option>
                ))}
              </select>
              <DevysButton compact disabled={saving} onClick={() => void save()}>
                Save to space
              </DevysButton>
            </>
          )}
          <DevysButton
            kind="quiet"
            compact
            aria-label="Close page"
            onClick={() => actions.viewArtifact(undefined)}
          >
            <X />
          </DevysButton>
        </div>
        <div className="min-h-0 flex-1">
          <ArtifactFrame id={viewing} />
        </div>
      </DialogContent>
    </Dialog>
  );
}
