import { FolderInput } from "lucide-react";
import type { ProjectItem } from "../app/api.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * Keeps a page or file on a project's overview: a reference, so the record stays in its app.
 * Says where it is kept; dashed while it is kept nowhere.
 */
export function KeepInProject({ kind, refId }: { kind: ProjectItem["kind"]; refId: string }) {
  const { projects, actions } = useWorkspace();
  const all = valueOf(projects) ?? [];
  const keptIn = all.filter((project) =>
    project.items.some((item) => item.kind === kind && item.ref === refId),
  );
  if (!all.length) return null;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <DevysButton
            compact
            kind="quiet"
            className={keptIn.length ? undefined : "border border-dashed border-hairline"}
          >
            <FolderInput /> {keptIn.length ? keptIn.map((p) => p.name).join(", ") : "Keep"}
          </DevysButton>
        }
      />
      <DropdownMenuContent align="end" className="w-auto">
        {all.map((project) => {
          const entry = project.items.find((item) => item.kind === kind && item.ref === refId);
          return (
            <DropdownMenuItem
              key={project.id}
              onClick={() =>
                entry
                  ? actions.removeFromProject(project.id, entry.id)
                  : actions.addToProject(project.id, kind, refId)
              }
            >
              {entry ? `Remove from ${project.name}` : `Keep in ${project.name}`}
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
