/**
 * What each record kind is called, by `<app>/<kind>`: its title in a layer's header, a card and
 * the reference sent with a message, and the kind of thing it is under that title. Pure, so a
 * permanent view can name the records it lists without importing the layers that show them.
 */
import type { Artifact } from "../../../apps/documents/contract.ts";
import { parseRef, type RecordKind, type Ref } from "../../../protocol/ref.ts";
import type { Project, WorkItem } from "../../../work/contract.ts";
import { useArtifacts, useProjects, useWork } from "../../app/data.ts";

/** What record titles are read from. */
export interface Names {
  artifacts: readonly Artifact[];
  work: readonly WorkItem[] | undefined;
  projects: readonly Project[] | undefined;
}

const fileName = (path: string) => path.split("/").at(-1) ?? path;

export const recordNames: Record<
  RecordKind,
  { title: (id: string, names: Names) => string; detail: (id: string, names: Names) => string }
> = {
  "documents/artifact": {
    title: (id, { artifacts }) => artifacts.find((a) => a.id === id)?.title ?? "Page",
    detail: (id, { artifacts }) => {
      const page = artifacts.find((a) => a.id === id);
      return page && page.version > 1 ? `Page · v${page.version}` : "Page";
    },
  },
  "documents/file": { title: (id) => fileName(id), detail: () => "File" },
  "code/session": { title: () => "Coding session", detail: () => "Coding session" },
  "work/item": {
    title: (id, { work }) => work?.find((w) => w.id === id)?.title ?? "Work item",
    detail: () => "Work item",
  },
  "work/project": {
    title: (id, { projects }) => projects?.find((p) => p.id === id)?.name ?? "Project",
    detail: () => "Project",
  },
};

/** A ref's kind and id, or undefined for a ref of a kind nobody knows. */
export function kindOf(value: Ref | null | undefined) {
  const parts = parseRef(value);
  return parts && { kind: `${parts.app}/${parts.kind}` as RecordKind, id: parts.id };
}

export function useNames(): Names {
  return { artifacts: useArtifacts(), work: useWork().data, projects: useProjects().data };
}

/** A record's title from its ref. */
export function useRecordTitle() {
  const names = useNames();
  return (value: Ref) => {
    const found = kindOf(value);
    return found ? recordNames[found.kind].title(found.id, names) : "Record";
  };
}
