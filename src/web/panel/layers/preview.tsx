import { FileText } from "lucide-react";
import type { Ref } from "../../../protocol/ref.ts";
import { useBusinessId } from "../../app/data.ts";
import { useNav } from "../../app/navigation.ts";
import { ArtifactLayer } from "./documents-artifact.tsx";
import { FileView } from "./documents-file.tsx";
import { kindOf, recordNames, useCurrentRef, useNames } from "./titles.ts";

/**
 * The draft an approval shows (an email, a post, an invoice), drawn by its layer's own view in a
 * short, inert frame: what the owner approves, as it is now. Tapping it opens the layer.
 */
export function DraftPreview({ value }: { value: Ref }) {
  const nav = useNav();
  const names = useNames();
  const businessId = useBusinessId();
  const current = useCurrentRef()(value);
  const found = kindOf(current);
  if (found?.kind !== "documents/artifact" && found?.kind !== "documents/file") return null;
  const title = recordNames[found.kind].title(found.id, names);
  const open = () => nav.openLayer({ kind: "record", ref: current });
  return (
    <div
      data-testid="draft-preview"
      className="flex w-full flex-col overflow-hidden rounded-control border border-hairline bg-sheet"
    >
      <button
        type="button"
        onClick={open}
        className="flex items-center gap-1.5 border-b border-hairline px-2.5 py-1.5 text-left text-caption text-ink-2 hover:bg-sheet-tint"
      >
        <FileText className="size-3.5 shrink-0 text-indigo" />
        <span className="min-w-0 flex-1 truncate">{title}</span>
        <span className="shrink-0 text-ink-3">Open</span>
      </button>
      {/* The draft itself is inert here: a tap anywhere opens it as a layer. */}
      <div onClick={open} className="h-44 cursor-pointer overflow-hidden">
        <div aria-hidden inert className="pointer-events-none h-full">
          {found.kind === "documents/artifact" ? (
            <ArtifactLayer id={found.id} />
          ) : (
            <FileView
              businessId={businessId}
              file={{ name: title, path: found.id, kind: "file", size: 0 }}
            />
          )}
        </div>
      </div>
    </div>
  );
}
