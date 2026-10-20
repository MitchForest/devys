import { FolderInput, MessageSquarePlus, Presentation, Save, Send } from "lucide-react";
import { lazy, Suspense, useCallback, useEffect, useState } from "react";
import { api, type FileAnchor, type FileEntry } from "../app/api.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { EmptyNote } from "../design/primitives.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { fileKind } from "../../surfaces/files/kind.ts";
import { FolderTree } from "../../surfaces/files/tree.tsx";
import type { TextSelection } from "../../surfaces/files/markdown.tsx";
import type { PdfRegion } from "../../surfaces/files/pdf.tsx";

// Each viewer carries a heavy library; it loads when a file of its kind opens.
const MarkdownDocument = lazy(() =>
  import("../../surfaces/files/markdown.tsx").then((m) => ({ default: m.MarkdownDocument })),
);
const PdfDocument = lazy(() =>
  import("../../surfaces/files/pdf.tsx").then((m) => ({ default: m.PdfDocument })),
);
const WordDocument = lazy(() =>
  import("../../surfaces/files/office.tsx").then((m) => ({ default: m.WordDocument })),
);
const SheetEditor = lazy(() =>
  import("../../surfaces/files/sheet.tsx").then((m) => ({ default: m.SheetEditor })),
);
const SlidesEditor = lazy(() =>
  import("../../surfaces/files/slides.tsx").then((m) => ({ default: m.SlidesEditor })),
);
const WhiteboardEditor = lazy(() =>
  import("../../surfaces/files/whiteboard.tsx").then((m) => ({ default: m.WhiteboardEditor })),
);
const CodeFile = lazy(() =>
  import("../../surfaces/files/code.tsx").then((m) => ({ default: m.CodeFile })),
);
const slides = () => import("../../surfaces/files/slides.tsx");

interface Comment {
  anchor: FileAnchor;
  text: string;
}

/** A file as it was read: its text or bytes, and the revision a save goes over. */
type Loaded = { text: string; revision: string } | { bytes: ArrayBuffer; revision: string };

const fileAt = (path: string): FileEntry => ({
  name: path.split("/").at(-1)!,
  path,
  kind: "file",
  size: 0,
});

/**
 * The business's files on the owner's Mac: its folder, repositories and worktrees. Documents,
 * decks, spreadsheets and whiteboards edit in place and save over the revision they were opened
 * at; everything else opens in a viewer. Comments on a text range or a PDF region go to an
 * employee as one message.
 */
export function FilesPage({ path }: { path?: string }) {
  const { businessId } = useWorkspace();
  const [root, setRoot] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [file, setFile] = useState<FileEntry | null>(path ? fileAt(path) : null);
  useEffect(() => {
    api.files(businessId).then(
      (result) => setRoot(result.root),
      (error: unknown) =>
        setProblem(error instanceof Error ? error.message : "Files are unavailable."),
    );
  }, [businessId]);
  const list = useCallback(
    (folder: string) => api.files(businessId, folder).then((result) => result.entries),
    [businessId],
  );
  if (problem)
    return (
      <div className="p-6">
        <EmptyNote>{problem}</EmptyNote>
      </div>
    );
  return (
    <div className="grid h-full grid-cols-[minmax(200px,28%)_1fr]">
      <div className="min-h-0 overflow-y-auto border-r border-hairline px-1.5">
        {root && (
          <FolderTree root={root} list={list} selected={file?.path ?? null} onOpen={setFile} />
        )}
      </div>
      <div className="min-h-0">
        {file ? (
          <FileView key={file.path} businessId={businessId} file={file} />
        ) : (
          <div className="p-6">
            <EmptyNote>Choose a file. Documents your employees write appear here.</EmptyNote>
          </div>
        )}
      </div>
    </div>
  );
}

function FileView({ businessId, file }: { businessId: string; file: FileEntry }) {
  const kind = fileKind(file.name);
  const binary = kind === "pdf" || kind === "word" || kind === "sheet";
  const readable = binary || kind === "markdown" || kind === "text" || kind === "whiteboard";
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  // Changes when the file is replaced from outside, as after a conflict, so editors reload.
  const [version, setVersion] = useState("first");
  // The edited file, written out only when it is saved.
  const [draft, setDraft] = useState<(() => string | ArrayBuffer) | null>(null);
  const [conflict, setConflict] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [selection, setSelection] = useState<FileAnchor | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [saved, setSaved] = useState<string | null>(null);
  const [deck, setDeck] = useState(false);
  const dark =
    typeof document !== "undefined" && document.documentElement.classList.contains("dark");

  const read = useCallback(
    (): Promise<Loaded> =>
      binary
        ? api.fileBytes(businessId, file.path)
        : api
            .fileText(businessId, file.path)
            .then(({ content, revision }) => ({ text: content, revision })),
    [binary, businessId, file.path],
  );
  useEffect(() => {
    if (!readable) return;
    read().then(setLoaded, () =>
      setProblem(binary ? "This file couldn't be opened." : "This file couldn't be read as text."),
    );
  }, [read, readable, binary]);
  useEffect(() => {
    if (kind !== "markdown" || !loaded || !("text" in loaded)) return;
    void slides().then((m) => setDeck(m.isDeck(file.name, loaded.text)));
  }, [kind, loaded, file.name]);

  const edited = (serialize: () => string | ArrayBuffer) => setDraft(() => serialize);
  const write = async (content: string | ArrayBuffer, revision: string) => {
    if (typeof content !== "string")
      return api.saveFileBytes(businessId, file.path, content, revision);
    const result = await api.saveFile(businessId, file.path, content, revision);
    return result.conflict ? { conflict: true as const } : result;
  };
  const save = async (overwrite = false) => {
    if (!draft || !loaded) return;
    const content = draft();
    // Keeping mine saves over whatever is on the Mac now.
    const revision = overwrite ? (await read()).revision : loaded.revision;
    const result = await write(content, revision);
    if (result.conflict) {
      setConflict(true);
      return;
    }
    setLoaded(
      typeof content === "string"
        ? { text: content, revision: result.revision }
        : { bytes: content, revision: result.revision },
    );
    setDraft(null);
    setConflict(false);
    setSaved(new Date().toLocaleTimeString());
  };
  const reload = async () => {
    const newer = await read();
    setLoaded(newer);
    setDraft(null);
    setConflict(false);
    setVersion(newer.revision);
  };
  const exportDeck = async () => {
    if (!loaded || !("text" in loaded)) return;
    const { deckToPptx, pptxPath } = await slides();
    const source = draft ? (draft() as string) : loaded.text;
    const target = pptxPath(file.path);
    await api.saveFileBytes(businessId, target, await deckToPptx(source));
    setSaved(`exported ${target.split("/").at(-1)} at ${new Date().toLocaleTimeString()}`);
  };
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "s") {
        event.preventDefault();
        void save();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const text = loaded && "text" in loaded ? loaded.text : null;
  const bytes = loaded && "bytes" in loaded ? loaded.bytes : null;
  const editable = kind === "markdown" || kind === "sheet" || kind === "whiteboard";
  const viewer = (() => {
    if (problem)
      return (
        <div className="p-6">
          <EmptyNote>{problem}</EmptyNote>
        </div>
      );
    switch (kind) {
      case "markdown":
        if (text === null) return null;
        return deck ? (
          <SlidesEditor
            markdown={text}
            version={version}
            onChange={(next) => (next === text ? setDraft(null) : edited(() => next))}
          />
        ) : (
          <MarkdownDocument
            markdown={text}
            version={version}
            onChange={(next) => (next === text ? setDraft(null) : edited(() => next))}
            onSelect={(picked: TextSelection | null) =>
              setSelection(picked && { kind: "text", ...picked })
            }
          />
        );
      case "text":
        return text !== null ? <CodeFile name={file.name} contents={text} dark={dark} /> : null;
      case "whiteboard":
        return text !== null ? (
          <WhiteboardEditor json={text} version={version} dark={dark} onChange={edited} />
        ) : null;
      case "pdf":
        return bytes ? (
          <PdfDocument
            bytes={bytes}
            regions={comments.flatMap((c) => (c.anchor.kind === "pdf" ? [c.anchor] : []))}
            onRegion={(region: PdfRegion) => setSelection({ kind: "pdf", ...region })}
          />
        ) : null;
      case "word":
        return bytes ? <WordDocument bytes={bytes} /> : null;
      case "sheet":
        return bytes ? (
          <SheetEditor
            bytes={bytes}
            name={file.name}
            version={version}
            dark={dark}
            onChange={edited}
          />
        ) : null;
      case "image":
        return (
          <div className="flex size-full items-center justify-center overflow-auto bg-well p-4">
            <img
              src={api.fileUrl(businessId, file.path)}
              alt={file.name}
              className="max-h-full max-w-full"
            />
          </div>
        );
      default:
        return (
          <div className="p-6">
            <EmptyNote>
              {kind === "presentation"
                ? "Presentations preview in the Mac, iPhone and iPad apps."
                : "No viewer for this kind of file yet."}{" "}
              <a
                className="underline"
                href={api.fileUrl(businessId, file.path)}
                download={file.name}
              >
                Download it
              </a>
              .
            </EmptyNote>
          </div>
        );
    }
  })();

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 border-b border-hairline px-3 py-2">
        <span className="truncate text-body font-semibold text-ink" title={file.path}>
          {file.name}
        </span>
        {editable && (
          <span className="text-caption text-ink-3" data-testid="file-status">
            {draft ? "Edited" : saved ? `Saved ${saved}` : "Saved on the Mac"}
          </span>
        )}
        <span className="ml-auto" />
        <SaveToSpace path={file.path} />
        {deck && (
          <DevysButton compact kind="quiet" onClick={() => void exportDeck()}>
            <Presentation /> Export .pptx
          </DevysButton>
        )}
        {editable && (
          <DevysButton compact disabled={!draft} onClick={() => void save()}>
            <Save /> Save
          </DevysButton>
        )}
      </div>
      {conflict && (
        <div
          className="flex flex-wrap items-center gap-2 border-b border-hairline bg-sheet-tint px-3 py-2 text-detail text-ink"
          role="alert"
        >
          This file changed on the Mac since you opened it.
          <DevysButton compact kind="quiet" onClick={() => void reload()}>
            Load the newer version
          </DevysButton>
          <DevysButton compact onClick={() => void save(true)}>
            Keep mine
          </DevysButton>
        </div>
      )}
      <div className="min-h-0 flex-1">
        <Suspense fallback={<p className="p-4 text-body text-ink-3">Loading…</p>}>
          {viewer}
        </Suspense>
      </div>
      {((kind === "markdown" && !deck) || kind === "pdf") && (
        <CommentBar
          businessId={businessId}
          path={file.path}
          selection={selection}
          comments={comments}
          onAdd={(comment) => {
            setComments((items) => [...items, comment]);
            setSelection(null);
          }}
          onSent={() => setComments([])}
        />
      )}
    </div>
  );
}

/** Shows the file in a space; it stays where it is on the Mac. */
function SaveToSpace({ path }: { path: string }) {
  const { spaces, actions } = useWorkspace();
  const all = valueOf(spaces) ?? [];
  const inSpaces = all.filter((space) =>
    space.items.some((item) => item.kind === "file" && item.ref === path),
  );
  if (!all.length) return null;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <DevysButton compact kind="quiet">
            <FolderInput />{" "}
            {inSpaces.length ? `In ${inSpaces.map((s) => s.name).join(", ")}` : "Save to space"}
          </DevysButton>
        }
      />
      <DropdownMenuContent align="end" className="w-auto">
        {all.map((space) => {
          const entry = space.items.find((item) => item.kind === "file" && item.ref === path);
          return (
            <DropdownMenuItem
              key={space.id}
              onClick={() =>
                entry
                  ? actions.removeFromSpace(space.id, entry.id)
                  : actions.addToSpace(space.id, "file", path)
              }
            >
              {entry ? `Remove from ${space.name}` : space.name}
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Comments in progress on this file, and who they go to. */
function CommentBar({
  businessId,
  path,
  selection,
  comments,
  onAdd,
  onSent,
}: {
  businessId: string;
  path: string;
  selection: FileAnchor | null;
  comments: Comment[];
  onAdd: (comment: Comment) => void;
  onSent: () => void;
}) {
  const { employees } = useWorkspace();
  const [text, setText] = useState("");
  const [to, setTo] = useState(
    employees.find((e) => e.template === "engineering")?.id ?? employees[0]?.id ?? "",
  );
  const [problem, setProblem] = useState<string | null>(null);
  const where = selection
    ? selection.kind === "text"
      ? `“${selection.quote.slice(0, 60)}${selection.quote.length > 60 ? "…" : ""}”`
      : `page ${selection.page} region`
    : null;
  const send = async () => {
    try {
      await api.commentOnFile(businessId, {
        id: crypto.randomUUID(),
        path,
        employee: to,
        comments,
      });
      onSent();
      setProblem(null);
    } catch (error) {
      setProblem(error instanceof Error ? error.message : "The comments couldn't be sent.");
    }
  };
  return (
    <div
      className="flex flex-col gap-2 border-t border-hairline px-3 py-2"
      data-testid="comment-bar"
    >
      {where ? (
        <div className="flex items-center gap-2">
          <span className="max-w-[40%] shrink-0 truncate text-caption text-ink-3">{where}</span>
          <input
            value={text}
            onChange={(event) => setText(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && text.trim()) {
                onAdd({ anchor: selection!, text: text.trim() });
                setText("");
              }
            }}
            placeholder="Comment on this"
            aria-label="Comment on the selection"
            className="min-w-0 flex-1 rounded-[8px] bg-sheet-tint px-2.5 py-1.5 text-detail text-ink outline-none"
          />
          <DevysButton
            compact
            disabled={!text.trim()}
            onClick={() => {
              onAdd({ anchor: selection!, text: text.trim() });
              setText("");
            }}
          >
            <MessageSquarePlus /> Add
          </DevysButton>
        </div>
      ) : (
        <span className="text-caption text-ink-3">
          Select text, or drag over part of a PDF page, to comment on it.
        </span>
      )}
      {comments.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-caption text-ink-3">
            {comments.length} comment{comments.length === 1 ? "" : "s"} for
          </span>
          <select
            value={to}
            onChange={(event) => setTo(event.target.value)}
            aria-label="Send comments to"
            className="rounded-[8px] bg-sheet-tint px-2 py-1 text-detail text-ink"
          >
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.name}
              </option>
            ))}
          </select>
          <DevysButton compact onClick={() => void send()}>
            <Send /> Send
          </DevysButton>
        </div>
      )}
      {problem && <span className="text-detail text-ink-2">{problem}</span>}
    </div>
  );
}
