import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, FileText, Folder } from "lucide-react";
import { useState } from "react";
import { ref, type Ref } from "../../protocol/ref.ts";
import { api } from "../app/api.ts";
import { useArtifacts, useBusinessId } from "../app/data.ts";
import { keys, problemOf } from "../app/query.ts";
import { ui } from "../app/ui.ts";
import { Spinner } from "../design/spinner.tsx";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";

/** The business folder's machine folders, which nobody attaches from. */
const hidden = new Set(["repos", "worktrees"]);

/**
 * The composer's +: a page or a file from the business folder goes with the next message, as
 * its ref, so the employee reads exactly that record.
 */
export function AttachDialog({ open, close }: { open: boolean; close: () => void }) {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent
        showCloseButton={false}
        className="flex h-[min(520px,calc(100dvh-4rem))] w-[440px] max-w-[calc(100%-2rem)] flex-col gap-0 overflow-hidden rounded-card! bg-sheet p-0 shadow-raised sm:max-w-[440px]"
      >
        {open && (
          <Picker
            choose={(record) => {
              ui.attach(record);
              ui.focusComposer();
              close();
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function Picker({ choose }: { choose: (record: Ref) => void }) {
  const businessId = useBusinessId();
  const artifacts = useArtifacts();
  const [folder, setFolder] = useState<string | null>(null);
  const listing = useQuery({
    queryKey: keys.folder(businessId, folder),
    queryFn: () => api.files(businessId, folder ?? undefined),
  });
  const pages = artifacts
    .filter((a) => a.content_type === "text/html" && a.version === a.versions)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
  const root = listing.data?.root;
  const atRoot = folder === null || folder === root;
  const entries = (listing.data?.entries ?? []).filter(
    (entry) =>
      entry.kind !== "repository" &&
      !entry.name.startsWith(".") &&
      !(atRoot && hidden.has(entry.name)),
  );
  const up = () => {
    if (!folder || !root) return;
    const parent = folder.slice(0, folder.lastIndexOf("/"));
    setFolder(parent.length > root.length ? parent : null);
  };
  return (
    <>
      <div className="flex shrink-0 items-center gap-1.5 px-5 pt-5 pb-3">
        {!atRoot && (
          <button
            type="button"
            aria-label="Up"
            onClick={up}
            className="-ml-1.5 grid size-7 place-items-center rounded-full text-ink-2 hover:bg-track"
          >
            <ChevronLeft className="size-4" />
          </button>
        )}
        <DialogTitle className="truncate text-heading font-semibold text-ink">
          {atRoot || !root ? "Attach a file" : folder.slice(root.length + 1)}
        </DialogTitle>
      </div>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto px-3 pb-4">
        {atRoot &&
          pages.map((page) => (
            <Row
              key={page.id}
              title={page.title}
              icon={<FileText className="size-4 text-indigo" />}
              onClick={() => choose(ref("documents", "artifact", page.id))}
            />
          ))}
        {listing.isPending ? (
          <div className="flex justify-center pt-8">
            <Spinner />
          </div>
        ) : listing.isError ? (
          <p className="px-2 pt-2 text-body text-ink-3">
            {problemOf(listing.error, "Files are unavailable.")}
          </p>
        ) : (
          entries.map((entry) => (
            <Row
              key={entry.path}
              title={entry.name}
              icon={
                entry.kind === "directory" ? (
                  <Folder className="size-4 text-ink-3" />
                ) : (
                  <FileText className="size-4 text-ink-3" />
                )
              }
              onClick={() =>
                entry.kind === "directory"
                  ? setFolder(entry.path)
                  : choose(ref("documents", "file", entry.path))
              }
            />
          ))
        )}
        {!listing.isPending && !pages.length && !entries.length && (
          <p className="px-2 pt-2 text-body text-ink-3">Nothing here yet.</p>
        )}
      </div>
    </>
  );
}

function Row({
  title,
  icon,
  onClick,
}: {
  title: string;
  icon: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-2.5 rounded-control px-2 py-2 text-left text-body text-ink hover:bg-sheet-tint"
    >
      {icon}
      <span className="truncate">{title}</span>
    </button>
  );
}
