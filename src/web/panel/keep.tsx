import { FolderInput } from "lucide-react";
import type { Ref } from "../../protocol/ref.ts";
import { useProjects } from "../app/data.ts";
import { useKeep } from "../app/mutations.ts";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";

/**
 * Keeps a page or file on a project's overview: a reference, so the record stays in its app.
 * Says where it is kept; dashed while it is kept nowhere.
 */
export function KeepInProject({ record }: { record: Ref }) {
  const all = useProjects().data ?? [];
  const keep = useKeep();
  const keptIn = all.filter((project) => project.items.some((item) => item.ref === record));
  if (!all.length) return null;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            size="compact"
            variant="quiet"
            className={keptIn.length ? undefined : "border border-dashed border-hairline"}
          >
            <FolderInput /> {keptIn.length ? keptIn.map((p) => p.name).join(", ") : "Keep"}
          </Button>
        }
      />
      <DropdownMenuContent align="end" className="w-auto">
        {all.map((project) => {
          const entry = project.items.find((item) => item.ref === record);
          return (
            <DropdownMenuItem
              key={project.id}
              onClick={() =>
                keep.mutate(
                  entry
                    ? { projectId: project.id, remove: entry.id }
                    : { projectId: project.id, add: record },
                )
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
