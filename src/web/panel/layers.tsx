import {
  ChevronLeft,
  ChevronRight,
  FileText,
  Folder,
  GitBranch,
  MessageSquareQuote,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { api } from "../app/api.ts";
import { useArtifacts, useBusinessId, useProjects, useWork } from "../app/data.ts";
import { chipFor, isOpen } from "../app/names.ts";
import { layerOfRef, useLayers, useNav, type Layer } from "../app/navigation.ts";
import { keys, problemOf } from "../app/query.ts";
import { useUi } from "../app/ui.ts";
import { useAsk } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { EmptyNote, StatusChip } from "../design/primitives.tsx";
import { ArtifactFrame } from "../pages/artifact.tsx";
import { BrowserLayer } from "../pages/browser.tsx";
import { NewCodingSession, SessionLayer, Terminals } from "../pages/coding.tsx";
import { FileView } from "../pages/files.tsx";
import { cn } from "@/lib/utils";

/** The layer on top of the right panel. */
export function LayerView({ layer }: { layer: Layer }) {
  const businessId = useBusinessId();
  const turns = useUi((state) => state.turns);
  const { updatedBy } = useLayers();
  switch (layer.kind) {
    case "artifact":
      return <ArtifactLayer id={layer.id} updatedBy={updatedBy} />;
    case "file":
      return (
        <Askable>
          <FileView
            // A finished turn reads the file again: an employee may have just changed it.
            key={`${layer.path}:${turns}`}
            turn={turns}
            businessId={businessId}
            file={{ name: layer.path.split("/").at(-1)!, path: layer.path, kind: "file", size: 0 }}
          />
        </Askable>
      );
    case "app":
      return layer.app === "code" ? <CodeApp /> : <DocumentsApp />;
    case "session":
      return (
        <Askable>
          <SessionLayer workId={layer.workId} sessionId={layer.sessionId} />
        </Askable>
      );
    case "browser":
      return <BrowserLayer workId={layer.workId} />;
  }
}

/**
 * Selecting text in a layer offers **Ask**: the selection is quoted into the composer, so the
 * owner changes things by asking the employee rather than by editing.
 */
function Askable({ children }: { children: ReactNode }) {
  const ask = useAsk();
  const box = useRef<HTMLDivElement>(null);
  const [offer, setOffer] = useState<{ text: string; x: number; y: number }>();
  const look = () => {
    const selection = window.getSelection();
    const text = selection?.toString().trim() ?? "";
    if (!text || !selection?.rangeCount || !box.current?.contains(selection.anchorNode))
      return setOffer(undefined);
    const rect = selection.getRangeAt(0).getBoundingClientRect();
    const frame = box.current.getBoundingClientRect();
    setOffer({
      text,
      x: Math.min(Math.max(rect.left - frame.left + rect.width / 2, 40), frame.width - 40),
      y: Math.max(rect.top - frame.top - 36, 4),
    });
  };
  return (
    <div ref={box} className="relative h-full" onMouseUp={look} onKeyUp={look}>
      {children}
      {offer && (
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => {
            ask(offer.text);
            setOffer(undefined);
            window.getSelection()?.removeAllRanges();
          }}
          style={{ left: offer.x, top: offer.y }}
          className="absolute z-20 flex -translate-x-1/2 animate-in items-center gap-1 rounded-full bg-ink px-2.5 py-1 text-caption font-semibold text-sheet shadow-raised fade-in"
        >
          <MessageSquareQuote className="size-3.5" /> Ask
        </button>
      )}
    </div>
  );
}

/**
 * A page an employee published, following its versions: a new version arriving in the
 * conversation replaces the one on screen and says who changed it.
 */
function ArtifactLayer({ id, updatedBy }: { id: string; updatedBy?: string | undefined }) {
  const artifacts = useArtifacts();
  const nav = useNav();
  const current = artifacts.find((a) => a.id === id);
  const versions = current
    ? artifacts
        .filter((a) => a.filename === current.filename)
        .sort((a, b) => a.created_at.localeCompare(b.created_at))
    : [];
  const at = versions.findIndex((a) => a.id === id);
  const step = (by: number) => {
    const next = versions[at + by];
    if (next) nav.replaceLayer({ kind: "artifact", id: next.id });
  };
  return (
    <div className="flex h-full flex-col">
      {(versions.length > 1 || updatedBy) && (
        <div className="flex h-9 shrink-0 items-center gap-1.5 border-b border-hairline px-3">
          {versions.length > 1 && (
            <span className="flex items-center gap-0.5 text-caption text-ink-3 tabular-nums">
              <button
                type="button"
                aria-label="Earlier version"
                disabled={at <= 0}
                onClick={() => step(-1)}
                className="grid size-5 place-items-center rounded disabled:opacity-30 enabled:hover:text-ink"
              >
                <ChevronLeft className="size-3.5" />
              </button>
              v{at + 1} of {versions.length}
              <button
                type="button"
                aria-label="Later version"
                disabled={at >= versions.length - 1}
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
function DocumentsApp() {
  const artifacts = useArtifacts();
  const nav = useNav();
  const [folder, setFolder] = useState<string | null>(null);
  const [project, setProject] = useState<string>();
  const { listing, problem } = useFolder(folder);
  const all = useProjects().data ?? [];
  const chosen = all.find((p) => p.id === project);
  const kept = (chosen?.items ?? []).map((item) => ({ id: item.id, layer: layerOfRef(item.ref) }));
  const pages = artifacts
    .filter((a) => a.content_type === "text/html")
    // One row per page: its latest version.
    .filter(
      (a, _, list) => !list.some((b) => b.filename === a.filename && b.created_at > a.created_at),
    )
    .filter(
      (a) =>
        !chosen ||
        kept.some(
          ({ layer }) =>
            layer?.kind === "artifact" &&
            artifacts.some((b) => b.id === layer.id && b.filename === a.filename),
        ),
    )
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
  const keptFiles = kept.flatMap(({ id, layer }) =>
    layer?.kind === "file" ? [{ id, path: layer.path }] : [],
  );
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
                title={page.filename.replace(/\.html$/, "")}
                detail={new Date(page.created_at).toLocaleDateString()}
                open={() => nav.openLayer({ kind: "artifact", id: page.id })}
              />
            ))}
          </Group>
        )}
        {chosen ? (
          keptFiles.length > 0 && (
            <Group title="Files">
              {keptFiles.map((item) => (
                <EntryRow
                  key={item.id}
                  icon={<FileText className="size-4 text-ink-3" />}
                  title={item.path.split("/").at(-1)!}
                  detail={item.path}
                  open={() => nav.openLayer({ kind: "file", path: item.path })}
                />
              ))}
            </Group>
          )
        ) : (
          <Group
            title={folder && listing ? folder.slice(listing.root.length + 1) || "Files" : "Files"}
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
            ) : entries.length === 0 && listing ? (
              <span className="text-detail text-ink-3">
                Documents your employees write appear here.
              </span>
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
                      : nav.openLayer({ kind: "file", path: entry.path })
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
function CodeApp() {
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
        <DevysButton compact onClick={() => setStarting(true)}>
          New coding session
        </DevysButton>
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
      className="flex items-center gap-2.5 rounded-[9px] px-2 py-1.5 text-left enabled:hover:bg-sheet-tint"
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
