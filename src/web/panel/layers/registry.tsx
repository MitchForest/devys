/**
 * What the right panel shows, keyed by what is shown: each record kind the app manifests declare
 * (`<app>/<kind>`, the kinds a `Ref` can name) has one view, which draws both its layer and its
 * card in a conversation; the live browser is the one layer that is not a record. A ref of a kind
 * nobody knows is an inert pill.
 */
import {
  Code2,
  FileText,
  FolderKanban,
  ListChecks,
  MessageSquareQuote,
  Plug,
  Repeat,
  type LucideIcon,
} from "lucide-react";
import { useRef, useState, type ComponentType, type ReactNode } from "react";
import { ref, type RecordKind, type Ref } from "../../../protocol/ref.ts";
import { useBusinessId, usePerson, useProjects, useWork } from "../../app/data.ts";
import { isOpen } from "../../app/names.ts";
import { useNav, usePlace, type Layer } from "../../app/navigation.ts";
import { useUi } from "../../app/ui.ts";
import { useAsk } from "../../app/workspace.tsx";
import { EmptyNote } from "../../design/primitives.tsx";
import { ProjectSummary } from "../overview.tsx";
import { RoutineLayer } from "../routines.tsx";
import { WorkCard } from "../work-card.tsx";
import { BrowserLayer } from "./browser.tsx";
import { CodeSessionLayer } from "./code-session.tsx";
import { ArtifactLayer } from "./documents-artifact.tsx";
import { FileView } from "./documents-file.tsx";
import { AppLayer } from "./team-app.tsx";
import { kindOf, recordNames, useNames } from "./titles.ts";

interface RecordView {
  icon: LucideIcon;
  /** Whether a project can keep it (a project's work belongs to it instead). */
  keepable: boolean;
  /** The record, read-only, as a layer. */
  Layer: ComponentType<{ id: string }>;
  /** Its card in a conversation, when it has its own; otherwise a card that opens the layer. */
  Card?: ComponentType<{ id: string; text: string }>;
  testId?: string;
}

const fileName = (path: string) => path.split("/").at(-1) ?? path;

/** Every record kind, by `<app>/<kind>`; the type makes a missing kind a compile error. */
export const records: Record<RecordKind, RecordView> = {
  "documents/artifact": {
    icon: FileText,
    keepable: true,
    Layer: ArtifactLayer,
    testId: "page-card",
  },
  "documents/file": {
    icon: FileText,
    keepable: true,
    Layer: FileLayer,
  },
  "code/session": {
    icon: Code2,
    keepable: true,
    Layer: CodeSessionLayer,
    Card: CodeSessionCard,
  },
  "work/item": {
    icon: ListChecks,
    keepable: false,
    Layer: WorkItemLayer,
  },
  "work/project": {
    icon: FolderKanban,
    keepable: false,
    Layer: ProjectLayer,
  },
  "work/routine": {
    icon: Repeat,
    keepable: false,
    Layer: RoutineLayer,
  },
  "team/app": {
    icon: Plug,
    keepable: false,
    Layer: AppLayer,
  },
};

/** A record's view, names and id, or undefined for a ref of a kind nobody knows. */
export function viewOf(value: Ref | null | undefined) {
  const parsed = kindOf(value);
  return parsed && { view: records[parsed.kind], named: recordNames[parsed.kind], id: parsed.id };
}

/** Whether a project can keep the record a ref points at. */
export const isKeepable = (value: Ref) => viewOf(value)?.view.keepable === true;

/** A layer's name, for its header and the reference chip. */
export function useLayerTitle(layer: Layer | undefined) {
  const names = useNames();
  if (!layer) return undefined;
  if (layer.kind === "browser") return "Browser";
  const found = viewOf(layer.ref);
  return found ? found.named.title(found.id, names) : "Record";
}

/** The layer on top of the right panel. Records are read-only, with Ask on a selection. */
export function LayerView({ layer }: { layer: Layer }) {
  if (layer.kind === "browser") return <BrowserLayer workId={layer.workId} />;
  const found = viewOf(layer.ref);
  if (!found) return null;
  const { Layer: View } = found.view;
  return (
    <Askable>
      <View id={found.id} />
    </Askable>
  );
}

/**
 * A file as a layer. In the thread of a work item the owner has taken over it is editable and
 * saves for that work item; a finished turn reads it again (an employee may have changed it).
 */
function FileLayer({ id }: { id: string }) {
  const businessId = useBusinessId();
  const turns = useUi((state) => state.turns);
  const place = usePlace();
  const person = usePerson();
  const item = useWork().data?.find((w) => place.kind === "thread" && w.id === place.workId);
  const handEditing =
    item && person && item.taken_over_by === person.id && isOpen(item.state) ? item.id : undefined;
  return (
    <FileView
      key={`${id}:${turns}`}
      turn={turns}
      businessId={businessId}
      work={handEditing}
      file={{ name: fileName(id), path: id, kind: "file", size: 0 }}
    />
  );
}

/** A work item as a layer is its card, which opens its thread. */
function WorkItemLayer({ id }: { id: string }) {
  return (
    <div className="h-full overflow-y-auto px-4 pt-3.5 pb-6">
      <WorkCard id={id} inThread={false} />
    </div>
  );
}

function ProjectLayer({ id }: { id: string }) {
  const project = useProjects().data?.find((p) => p.id === id);
  return (
    <div className="flex h-full flex-col gap-5 overflow-y-auto px-4 pt-3.5 pb-6">
      {project ? (
        <ProjectSummary project={project} />
      ) : (
        <EmptyNote>This project no longer exists.</EmptyNote>
      )}
    </div>
  );
}

const card =
  "mx-auto flex w-full max-w-[520px] items-center gap-2.5 rounded-card border border-hairline bg-sheet px-3 py-2 text-left shadow-resting transition-colors hover:bg-sheet-tint";

/**
 * An event in a conversation: the record's own card where its view has one, otherwise a card
 * that opens its layer.
 */
export function RecordCard({ value, text }: { value: Ref | null; text: string }) {
  const nav = useNav();
  const names = useNames();
  const found = viewOf(value);
  if (!found)
    return (
      <div className="mx-auto flex max-w-[90%] items-center gap-2 rounded-full border border-hairline bg-sheet-tint px-3 py-1.5 text-detail text-ink-2">
        <ListChecks className="size-3.5 shrink-0 text-indigo" />
        <span className="min-w-0 truncate">{text}</span>
      </div>
    );
  const { view, id } = found;
  if (view.Card) return <view.Card id={id} text={text} />;
  const Icon = view.icon;
  return (
    <button
      type="button"
      data-testid={view.testId}
      title="Open"
      onClick={() => nav.openLayer({ kind: "record", ref: value! })}
      className={card}
    >
      <span className="grid size-[22px] shrink-0 place-items-center rounded-control bg-indigo/12">
        <Icon className="size-3.5 text-indigo" />
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-control font-semibold text-ink">
          {found.named.title(id, names) || text}
        </span>
        <span className="truncate text-caption text-ink-3">{found.named.detail(id, names)}</span>
      </span>
    </button>
  );
}

/**
 * A coding session's milestone ("Claude Code finished · 2 files changed"): the line in words,
 * and View opens the session layer with the provider's own record.
 */
function CodeSessionCard({ id, text }: { id: string; text: string }) {
  const nav = useNav();
  return (
    <button
      type="button"
      data-testid="coding-card"
      title="View the coding session"
      onClick={() => nav.openLayer({ kind: "record", ref: ref("code", "session", id) })}
      className={card}
    >
      <span className="grid size-[22px] shrink-0 place-items-center rounded-control bg-indigo/12">
        <Code2 className="size-3.5 text-indigo" />
      </span>
      <span className="min-w-0 flex-1 truncate text-control font-semibold text-ink">{text}</span>
      <span className="shrink-0 text-caption font-medium text-ink-3">View</span>
    </button>
  );
}

/** The record an owner's message was about ("Viewing …"), which opens its layer. */
export function ViewedRecord({ value }: { value: Ref }) {
  const nav = useNav();
  const names = useNames();
  const found = viewOf(value);
  if (!found) return null;
  return (
    <button
      type="button"
      data-testid="viewed-record"
      onClick={() => nav.openLayer({ kind: "record", ref: value })}
      className="max-w-full truncate text-caption text-ink-3 hover:text-ink-2"
    >
      Viewing {found.named.title(found.id, names)}
    </button>
  );
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
