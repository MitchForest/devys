import { ChevronLeft, FileText, Folder, GitBranch } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { parseRef, ref, type Ref } from "../../../protocol/ref.ts";
import { api } from "../../app/api.ts";
import { useArtifacts, useBusinessId, useProjects, useWork } from "../../app/data.ts";
import { chipFor, isOpen } from "../../app/names.ts";
import { useNav } from "../../app/navigation.ts";
import { keys, problemOf } from "../../app/query.ts";
import { shortDate } from "../../lib/format.ts";
import { EmptyNote, StatusChip } from "../../design/primitives.tsx";
import { NewCodingSession, Terminals } from "../coding.tsx";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";

/**
 * The business folder's machine folders: repositories the Code app shows, and coding
 * worktrees nobody browses (the host lays them out: src/apps/code/host/worktree.ts).
 */
const repositories = "repos";
const worktrees = "worktrees";

/** Folders and files under a path, newest listing on each visit. */
function useFolder(path: string | null, enabled = true) {
  const businessId = useBusinessId();
  const folder = useQuery({
    queryKey: keys.folder(businessId, path),
    queryFn: () => api.files(businessId, path ?? undefined),
    enabled,
  });
  return {
    listing: folder.data,
    problem: folder.isError ? problemOf(folder.error, "Files are unavailable.") : undefined,
  };
}

/**
 * The Documents app: the business's pages and documents, filterable by project. Repositories
 * belong to Code and never show here.
 */
export function DocumentsApp() {
  const artifacts = useArtifacts();
  const nav = useNav();
  const open = (record: Ref) => nav.openLayer({ kind: "record", ref: record });
  const [folder, setFolder] = useState<string | null>(null);
  const [project, setProject] = useState<string>();
  const { listing, problem } = useFolder(folder);
  const all = useProjects().data ?? [];
  const chosen = all.find((p) => p.id === project);
  const kept = (chosen?.items ?? []).flatMap((item) => {
    const parts = parseRef(item.ref);
    return parts?.app === "documents" ? [{ id: item.id, kind: parts.kind, of: parts.id }] : [];
  });
  const keptPages = new Set(
    kept.flatMap(({ kind, of }) =>
      kind === "artifact" ? (artifacts.find((a) => a.id === of)?.filename ?? []) : [],
    ),
  );
  // One row per page, its latest version; with a project chosen, the pages it keeps.
  const pages = artifacts
    .filter((a) => a.content_type === "text/html" && a.version === a.versions)
    .filter((a) => !chosen || keptPages.has(a.filename))
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
  const keptFiles = kept.flatMap(({ id, kind, of }) => (kind === "file" ? [{ id, path: of }] : []));
  const atRoot = listing !== undefined && listing.path === listing.root;
  const entries = (listing?.entries ?? []).filter(
    (entry) =>
      entry.kind !== "repository" &&
      !entry.name.startsWith(".") &&
      !(atRoot && (entry.name === repositories || entry.name === worktrees)),
  );
  return (
    <div className="flex h-full flex-col">
      {all.length > 0 && (
        <div className="flex shrink-0 gap-1 overflow-x-auto border-b border-hairline px-3 py-2 [scrollbar-width:none]">
          {[{ id: undefined, name: "All" }, ...all].map((each) => (
            <button
              key={each.id ?? "all"}
              type="button"
              aria-pressed={project === each.id}
              onClick={() => setProject(each.id)}
              className={cn(
                "shrink-0 rounded-full px-2.5 py-1 text-caption transition-colors",
                project === each.id
                  ? "bg-ink text-sheet"
                  : "bg-sheet-tint text-ink-2 hover:text-ink",
              )}
            >
              {each.name}
            </button>
          ))}
        </div>
      )}
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-3 py-3">
        {pages.length > 0 && (
          <Group title="Pages">
            {pages.map((page) => (
              <EntryRow
                key={page.id}
                icon={<FileText className="size-4 text-indigo" />}
                title={page.title}
                detail={shortDate(page.created_at)}
                open={() => open(ref("documents", "artifact", page.id))}
              />
            ))}
          </Group>
        )}
        {chosen
          ? keptFiles.length > 0 && (
              <Group title="Files">
                {keptFiles.map((item) => (
                  <EntryRow
                    key={item.id}
                    icon={<FileText className="size-4 text-ink-3" />}
                    title={item.path.split("/").at(-1)!}
                    detail={item.path}
                    open={() => open(ref("documents", "file", item.path))}
                  />
                ))}
              </Group>
            )
          : // An empty folder shows nothing: no standing description.
            (problem || entries.length > 0 || folder) && (
              <Group
                title={
                  folder && listing ? folder.slice(listing.root.length + 1) || "Files" : "Files"
                }
                back={
                  folder && listing && folder !== listing.root
                    ? () => {
                        const up = folder.slice(0, folder.lastIndexOf("/"));
                        setFolder(up.length > listing.root.length ? up : null);
                      }
                    : undefined
                }
              >
                {problem ? (
                  <EmptyNote>{problem}</EmptyNote>
                ) : (
                  entries.map((entry) => (
                    <EntryRow
                      key={entry.path}
                      icon={
                        entry.kind === "directory" ? (
                          <Folder className="size-4 text-ink-3" />
                        ) : (
                          <FileText className="size-4 text-ink-3" />
                        )
                      }
                      title={entry.name}
                      open={() =>
                        entry.kind === "directory"
                          ? setFolder(entry.path)
                          : open(ref("documents", "file", entry.path))
                      }
                    />
                  ))
                )}
              </Group>
            )}
      </div>
    </div>
  );
}

/**
 * The Code app: repositories, the work being coded (each opening its thread), terminals,
 * and a coding session the owner drives from the start.
 */
export function CodeApp() {
  const work = useWork().data;
  const nav = useNav();
  const businessId = useBusinessId();
  const [starting, setStarting] = useState(false);
  const withSessions =
    useQuery({ queryKey: keys.codingWork(businessId), queryFn: () => api.codingWork(businessId) })
      .data?.work ?? [];
  const { listing: root } = useFolder(null);
  const { listing } = useFolder(root ? `${root.root}/${repositories}` : null, Boolean(root));
  const repos = root ? (listing?.entries ?? []).filter((entry) => entry.kind === "repository") : [];
  const coding = (work ?? [])
    .filter((item) => withSessions.includes(item.id))
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto px-3 py-3">
      <div className="flex gap-1.5">
        <Button size="compact" onClick={() => setStarting(true)}>
          New coding session
        </Button>
      </div>
      <NewCodingSession open={starting} onClose={() => setStarting(false)} />
      {repos.length > 0 && (
        <Group title="Repositories">
          {repos.map((repository) => (
            <EntryRow
              key={repository.path}
              icon={<GitBranch className="size-4 text-ink-3" />}
              title={repository.name}
              detail={repository.path}
            />
          ))}
        </Group>
      )}
      {coding.length > 0 && (
        <Group title="Work">
          {coding.map((item) => {
            const chip = chipFor(item.state);
            return (
              <EntryRow
                key={item.id}
                icon={<StatusDot open={isOpen(item.state)} />}
                title={item.title}
                trailing={
                  <StatusChip tone={chip.tone} small>
                    {chip.title}
                  </StatusChip>
                }
                open={() => nav.openThread(item.id)}
              />
            );
          })}
        </Group>
      )}
      <Terminals />
    </div>
  );
}

function StatusDot({ open }: { open: boolean }) {
  return <span className={cn("mx-[5px] size-1.5 rounded-full", open ? "bg-indigo" : "bg-gray")} />;
}

function Group({
  title,
  back,
  children,
}: {
  title: string;
  back?: (() => void) | undefined;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-0.5">
      <div className="flex items-center gap-1 px-1 pb-0.5">
        {back && (
          <button
            type="button"
            aria-label="Up a folder"
            onClick={back}
            className="grid size-5 place-items-center rounded text-ink-3 hover:text-ink"
          >
            <ChevronLeft className="size-3.5" />
          </button>
        )}
        <h3 className="truncate text-label font-medium text-ink-3">{title}</h3>
      </div>
      {children}
    </section>
  );
}

function EntryRow({
  icon,
  title,
  detail,
  trailing,
  open,
}: {
  icon: ReactNode;
  title: string;
  detail?: string;
  trailing?: ReactNode;
  open?: () => void;
}) {
  return (
    <button
      type="button"
      disabled={!open}
      onClick={open}
      className="flex items-center gap-2.5 rounded-small px-2 py-1.5 text-left enabled:hover:bg-sheet-tint"
    >
      <span className="grid w-4 shrink-0 place-items-center">{icon}</span>
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-detail text-ink">{title}</span>
        {detail && <span className="truncate text-caption text-ink-3">{detail}</span>}
      </span>
      <span className="ml-auto" />
      {trailing}
    </button>
  );
}
