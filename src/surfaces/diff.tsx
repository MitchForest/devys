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

/** A comment anchored to lines of one file in the patch: what it says and where. */
export interface DiffComment {
  path: string;
  side: "additions" | "deletions";
  start: number;
  end: number;
  text: string;
}

export interface DiffSelection {
  path: string;
  side: "additions" | "deletions";
  start: number;
  end: number;
}

/** How a comment reads in the message that carries it. */
export const commentLine = (comment: DiffComment) =>
  `${comment.path} ${comment.side === "deletions" ? "old " : ""}line${comment.start === comment.end ? ` ${comment.start}` : `s ${comment.start}–${comment.end}`}: ${comment.text}`;

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
