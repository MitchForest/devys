/** A folder tree that loads each folder when it opens; the caller says how to list one. */
import { useEffect, useState } from "react";

export interface TreeEntry {
  name: string;
  path: string;
  kind: "file" | "directory" | "other";
  size: number;
}

/** Folders that are never worth opening in a file browser. */
const hidden = new Set([
  ".git",
  "node_modules",
  ".DS_Store",
  ".wrangler",
  "dist",
  ".build",
  "DerivedData",
]);

export function FolderTree({
  root,
  list,
  selected,
  onOpen,
}: {
  root: string;
  list: (path: string) => Promise<TreeEntry[]>;
  selected: string | null;
  onOpen: (entry: TreeEntry) => void;
}) {
  return (
    <div
      role="tree"
      aria-label="Files"
      className="flex flex-col py-1 text-detail"
      data-testid="folder-tree"
    >
      <Folder path={root} depth={0} list={list} selected={selected} onOpen={onOpen} />
    </div>
  );
}

function Folder({
  path,
  depth,
  list,
  selected,
  onOpen,
}: {
  path: string;
  depth: number;
  list: (path: string) => Promise<TreeEntry[]>;
  selected: string | null;
  onOpen: (entry: TreeEntry) => void;
}) {
  const [entries, setEntries] = useState<TreeEntry[] | null>(null);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  useEffect(() => {
    void list(path).then(
      (items) => setEntries(items.filter((item) => !hidden.has(item.name))),
      () => setEntries([]),
    );
  }, [path, list]);
  if (!entries)
    return (
      <span className="px-2 py-1 text-ink-3" style={{ paddingLeft: 8 + depth * 14 }}>
        Loading…
      </span>
    );
  if (!entries.length && depth === 0)
    return <span className="px-2 py-1 text-ink-3">No files yet.</span>;
  return (
    <>
      {entries.map((entry) => (
        <div
          key={entry.path}
          role="treeitem"
          aria-expanded={entry.kind === "directory" ? Boolean(open[entry.path]) : undefined}
        >
          <button
            type="button"
            onClick={() =>
              entry.kind === "directory"
                ? setOpen((state) => ({ ...state, [entry.path]: !state[entry.path] }))
                : onOpen(entry)
            }
            className={`flex w-full items-center gap-1.5 rounded-[6px] py-1 pr-2 text-left hover:bg-sheet-tint ${
              selected === entry.path ? "bg-sheet-tint font-medium text-ink" : "text-ink-2"
            }`}
            style={{ paddingLeft: 8 + depth * 14 }}
          >
            <span className="w-3 shrink-0 text-ink-3">
              {entry.kind === "directory" ? (open[entry.path] ? "▾" : "▸") : ""}
            </span>
            <span className="truncate">{entry.name}</span>
          </button>
          {entry.kind === "directory" && open[entry.path] && (
            <Folder
              path={entry.path}
              depth={depth + 1}
              list={list}
              selected={selected}
              onOpen={onOpen}
            />
          )}
        </div>
      ))}
    </>
  );
}
