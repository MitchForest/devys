/**
 * The diff surface: a unified patch rendered by Pierre's diffs, one file at a time, with line
 * selection for review comments. The web client uses it directly; the Apple apps load the same
 * code from their bundle (.docs/COMPONENTS.md#surfaces). It holds no state of its own beyond
 * the selection: the patch comes from its owner and comments leave as messages.
 */
import { parsePatchFiles } from "@pierre/diffs";
import {
  FileDiff,
  Virtualizer,
  WorkerPoolContextProvider,
  type DiffLineAnnotation,
  type SelectedLineRange,
} from "@pierre/diffs/react";
import { useMemo } from "react";

/**
 * A comment anchored to lines of one file in the patch: what it says and where, with the hunk
 * it was written against so the reader can tell whether those lines have moved since.
 */
export interface DiffComment {
  path: string;
  side: "additions" | "deletions";
  start: number;
  end: number;
  /** The first 8 hex digits of the SHA-256 of the hunk's text (`hunkText`). */
  hunk: string;
  /** The base commit the patch is against, when the client knows it. */
  base?: string;
  text: string;
}

export interface DiffSelection {
  path: string;
  side: "additions" | "deletions";
  start: number;
  end: number;
}

/**
 * How a comment reads in the message that carries it; the native client writes the same line:
 * `<path> <lines a–b | line a> (<new|old>, base <commit>, hunk <hash>): <text>`.
 */
export const commentLine = (comment: DiffComment) =>
  `${comment.path} ${comment.start === comment.end ? `line ${comment.start}` : `lines ${comment.start}–${comment.end}`} (${comment.side === "deletions" ? "old" : "new"}, ${comment.base ? `base ${comment.base.slice(0, 8)}, ` : ""}hunk ${comment.hunk}): ${comment.text}`;

/** The one message pending comments leave as: a heading, then one line per comment. */
export const reviewBundle = (title: string, comments: readonly DiffComment[]) =>
  [`Review comments on ${title}:`, ...comments.map(commentLine)].join("\n");

const hunkHeader = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
const stripPrefix = (path: string, prefix: string) =>
  path.startsWith(prefix) ? path.slice(prefix.length) : path;

/**
 * The text of the hunk holding a selection's first line: its `@@` header through its last line,
 * joined by newlines with no trailing newline. Empty when the patch has no such hunk.
 */
export function hunkText(patch: string, selection: DiffSelection): string {
  const lines = patch.split("\n");
  let oldPath = "";
  let newPath = "";
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]!;
    if (line.startsWith("diff --git ")) [oldPath, newPath] = ["", ""];
    else if (line.startsWith("--- ")) oldPath = stripPrefix(line.slice(4).trim(), "a/");
    else if (line.startsWith("+++ ")) newPath = stripPrefix(line.slice(4).trim(), "b/");
    const header = hunkHeader.exec(line);
    if (!header) continue;
    const oldStart = Number(header[1]);
    const oldCount = header[2] === undefined ? 1 : Number(header[2]);
    const newStart = Number(header[3]);
    const newCount = header[4] === undefined ? 1 : Number(header[4]);
    // The hunk runs until both sides' line counts are used up.
    let end = index + 1;
    for (
      let old = oldCount, added = newCount;
      end < lines.length && (old > 0 || added > 0);
      end++
    ) {
      const kind = lines[end]![0];
      if (kind === "-") old--;
      else if (kind === "+") added--;
      else if (kind === " " || lines[end] === "") [old, added] = [old - 1, added - 1];
    }
    while (lines[end]?.startsWith("\\")) end++;
    const [start, count] =
      selection.side === "deletions" ? [oldStart, oldCount] : [newStart, newCount];
    const inFile = selection.path === newPath || selection.path === oldPath;
    if (inFile && selection.start >= start && selection.start < start + Math.max(count, 1))
      return lines.slice(index, end).join("\n");
    index = end - 1;
  }
  return "";
}

/** The first 8 hex digits of the SHA-256 of a hunk's UTF-8 text, through Web Crypto. */
export async function hunkHash(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest).slice(0, 4), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function DiffSurface({
  patch,
  comments = [],
  dark = false,
  onSelect,
}: {
  patch: string;
  comments?: readonly DiffComment[];
  dark?: boolean;
  onSelect?: (selection: DiffSelection | null) => void;
}) {
  const files = useMemo(() => parsePatchFiles(patch).flatMap((parsed) => parsed.files), [patch]);
  if (!files.length) return <p className="p-4 text-body text-ink-3">No changes yet.</p>;
  // Only the files in view are rendered, and highlighting happens off the main thread, so a
  // long patch stays responsive on a phone.
  return (
    <WorkerPoolContextProvider poolOptions={{ workerFactory, poolSize: 2 }} highlighterOptions={{}}>
      <Virtualizer
        className="h-full overflow-y-auto"
        contentClassName="flex flex-col gap-3"
        data-testid="diff-surface"
      >
        {files.map((file) => {
          const annotations: DiffLineAnnotation<string>[] = comments
            .filter((comment) => comment.path === file.name)
            .map((comment) => ({
              side: comment.side,
              lineNumber: comment.end,
              metadata: comment.text,
            }));
          return (
            <FileDiff<string>
              key={file.name}
              fileDiff={file}
              lineAnnotations={annotations}
              renderAnnotation={(annotation) => (
                <div className="mx-2 my-1 rounded-[8px] bg-sheet-tint px-2.5 py-1.5 text-detail text-ink">
                  {annotation.metadata}
                </div>
              )}
              options={{
                diffStyle: "unified",
                themeType: dark ? "dark" : "light",
                enableLineSelection: Boolean(onSelect),
                onLineSelected: (range: SelectedLineRange | null) =>
                  onSelect?.(
                    range
                      ? {
                          path: file.name,
                          side: range.side === "deletions" ? "deletions" : "additions",
                          start: Math.min(range.start, range.end),
                          end: Math.max(range.start, range.end),
                        }
                      : null,
                  ),
              }}
            />
          );
        })}
      </Virtualizer>
    </WorkerPoolContextProvider>
  );
}

const workerFactory = () =>
  new Worker(new URL("@pierre/diffs/worker/worker.js", import.meta.url), { type: "module" });
