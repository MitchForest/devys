import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  ChevronDown,
  FileText,
  File,
  CircleMinus,
  FolderOpen,
  MessageCircle,
  Plus,
} from "lucide-react";
import { useState } from "react";
import { api, type Artifact, type Commitment, type Space, type SpaceItem } from "../app/api.ts";
import { employeeOf } from "../app/conversation.ts";
import { formatBytes, isOpen, templateTitle } from "../app/names.ts";
import { useWorkspace, valueOf } from "../app/workspace.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { MarkdownView } from "../design/markdown.tsx";
import { BusinessTile } from "../design/face.tsx";
import { EmptyNote, Metric, PageBody, SectionHeader } from "../design/primitives.tsx";
import { Spinner } from "../design/spinner.tsx";
import { SegmentedTabs } from "../design/tabs.tsx";
import { WorkRow } from "./work.tsx";
import { Composer, ConversationView } from "../shell/chat.tsx";
import { spaceTint } from "../shell/sidebar.tsx";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const refs = (space: Space, kind: SpaceItem["kind"]) =>
  space.items.filter((i) => i.kind === kind).map((i) => i.ref);

/**
 * A persistent place, conversation first: its thread, then its purpose and lead, its work,
 * and its files under the header's tabs.
 */
export function SpacePage({ id }: { id: string }) {
  const { spaces, work, spaceTab, actions, main, employees } = useWorkspace();
  const space = valueOf(spaces)?.find((s) => s.id === id);
  if (!space)
    return (
      <PageBody>
        {spaces.status === "loading" ? (
          <Spinner />
        ) : (
          <EmptyNote>This space no longer exists.</EmptyNote>
        )}
      </PageBody>
    );
  const ids = new Set(refs(space, "commitment"));
  const items = (valueOf(work) ?? []).filter((item) => ids.has(item.id));
  const lead = employees.find((e) => e.id === space.lead_employee_id);
  const tint = spaceTint((valueOf(spaces) ?? []).indexOf(space));
  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-col gap-3 border-b border-hairline px-5 pt-4 pb-3">
        <div className="flex flex-wrap items-center gap-3">
          <Popover>
            <PopoverTrigger
              aria-label={`About ${space.name}`}
              className="-mx-1.5 flex min-w-0 items-center gap-3 rounded-[10px] px-1.5 py-1 text-left hover:bg-sheet-tint"
            >
              <BusinessTile name={space.name} tint={tint} size={30} />
              <h1 className="truncate text-heading font-semibold text-ink">{space.name}</h1>
            </PopoverTrigger>
            <PopoverContent align="start" className="w-80 gap-3 rounded-card bg-sheet p-4">
              <SpaceAbout space={space} />
            </PopoverContent>
          </Popover>
          <span className="ml-auto" />
          <DevysButton compact onClick={() => actions.newTask({ spaceId: space.id })}>
            <Plus /> New task
          </DevysButton>
        </div>
        <SegmentedTabs
          label="Space"
          value={spaceTab}
          options={[
            { value: "conversation", title: "Conversation" },
            { value: "overview", title: "Overview" },
            { value: "work", title: "Work" },
            { value: "files", title: "Files" },
          ]}
          onChange={actions.setSpaceTab}
        />
      </div>
      <div className="min-h-0 flex-1">
        {spaceTab === "conversation" ? (
          <div className="flex h-full flex-col">
            <div className="min-h-0 flex-1">
              <ConversationView
                conversation={main}
                className="max-w-[760px]"
                empty={
                  <>
                    <BusinessTile name={space.name} tint={tint} size={48} />
                    <span className="text-body text-ink-3">
                      No messages in {space.name} yet.
                      {lead ? ` ${lead.name} leads; @mention anyone to bring them in.` : ""}
                    </span>
                  </>
                }
              />
            </div>
            <Composer
              conversation={main}
              which="main"
              label={`Message ${space.name}`}
              className="max-w-[780px]"
            />
          </div>
        ) : (
          <PageBody>
            {spaceTab === "overview" ? (
              <Overview items={items} space={space} />
            ) : spaceTab === "work" ? (
              <SpaceWork items={items} space={space} />
            ) : (
              <SpaceFiles space={space} />
            )}
          </PageBody>
        )}
      </div>
    </div>
  );
}

/** The lead, and every employee who has spoken in the space's conversation. */
/** What a space is for and who is in it, on demand from its header. */
function SpaceAbout({ space }: { space: Space }) {
  const { actions } = useWorkspace();
  const participants = useParticipants(space);
  return (
    <>
      {space.purpose && <p className="text-detail text-ink-2">{space.purpose}</p>}
      <div className="flex flex-col gap-0.5" aria-label="Who's here">
        <span className="text-label font-medium text-ink-3">Who's here</span>
        {participants.map((employee) => (
          <button
            key={employee.id}
            type="button"
            onClick={() => actions.message(employee.id)}
            className="-mx-2 flex items-center gap-2 rounded-[8px] px-2 py-1 text-left text-detail text-ink hover:bg-sheet-tint"
          >
            <EmployeePortrait employee={employee} size={20} />
            <span className="truncate">{employee.name}</span>
            {employee.id === space.lead_employee_id && (
              <span className="ml-auto text-caption text-ink-3">Lead</span>
            )}
          </button>
        ))}
      </div>
    </>
  );
}

function useParticipants(space: Space) {
  const { main, employees } = useWorkspace();
  const ids = new Set([
    ...(space.lead_employee_id ? [space.lead_employee_id] : []),
    ...(valueOf(main.messages) ?? []).flatMap((m) => {
      const id = employeeOf(m.author);
      return id ? [id] : [];
    }),
  ]);
  return employees.filter((e) => ids.has(e.id));
}

function Overview({ items, space }: { items: Commitment[]; space: Space }) {
  const { employees, actions } = useWorkspace();
  const participants = useParticipants(space);
  const lead = employees.find((e) => e.id === space.lead_employee_id);
  const count = (state: Commitment["state"]) => items.filter((item) => item.state === state).length;
  return (
    <>
      <div className="flex flex-col gap-3 rounded-card bg-sheet-tint px-4 py-3">
        <div className="flex flex-col gap-0.5">
          <span className="text-detail text-ink-3">Purpose</span>
          <span className="text-body text-ink">{space.purpose || "No purpose written yet."}</span>
        </div>
        <div className="flex items-center gap-3">
          {lead && <EmployeePortrait employee={lead} size={30} />}
          <div className="flex min-w-0 flex-col gap-0.5">
            <span className="text-detail text-ink-3">Lead</span>
            <span className="text-body font-semibold text-ink" data-testid="space-lead">
              {lead?.name ?? "No lead"}
            </span>
          </div>
          <span className="ml-auto" />
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <DevysButton kind="quiet" compact aria-label="Change lead">
                  Change <ChevronDown />
                </DevysButton>
              }
            />
            <DropdownMenuContent align="end" className="w-auto min-w-48">
              {employees.map((employee) => (
                <DropdownMenuItem
                  key={employee.id}
                  onClick={() => void actions.updateSpace(space.id, { lead: employee.id })}
                >
                  <EmployeePortrait employee={employee} size={18} />
                  {employee.name}
                  <span className="ml-auto pl-3 text-caption text-ink-3">
                    {templateTitle(employee.template)}
                  </span>
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
        <p className="text-detail text-ink-3">
          The lead answers in the space's conversation until someone else speaks or you mention
          someone.
        </p>
      </div>
      <div className="flex flex-col gap-2">
        <SectionHeader title="Participants" count={participants.length}>
          <DevysButton kind="quiet" compact onClick={() => actions.setSpaceTab("conversation")}>
            <MessageCircle /> Conversation
          </DevysButton>
        </SectionHeader>
        <div className="flex flex-wrap gap-2" aria-label="Participants">
          {participants.map((employee) => (
            <button
              key={employee.id}
              type="button"
              onClick={() => actions.selectPage({ kind: "employee", id: employee.id })}
              className="flex items-center gap-2 rounded-full bg-sheet-tint py-1 pr-3 pl-1 text-control text-ink hover:bg-track"
            >
              <EmployeePortrait employee={employee} size={22} />
              {employee.name}
              {employee.id === space.lead_employee_id && (
                <span className="text-caption text-ink-3">Lead</span>
              )}
            </button>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-[repeat(auto-fill,minmax(170px,1fr))] gap-3">
        <Metric
          label="Open"
          value={String(items.filter((i) => isOpen(i.state)).length)}
          note={`${count("needs_decision")} need you`}
        />
        <Metric
          label="In progress"
          value={String(count("in_progress"))}
          note={`${count("waiting")} waiting`}
        />
        <Metric label="Done" value={String(count("completed"))} note="with evidence" />
      </div>
      <div className="flex flex-col gap-2">
        <SectionHeader title="Recent" count={items.length} />
        {items.length === 0 && (
          <EmptyNote>No work here yet. Create a task, or add one from any task's menu.</EmptyNote>
        )}
        {items.slice(0, 6).map((item) => (
          <WorkRow key={item.id} item={item} />
        ))}
      </div>
    </>
  );
}

function SpaceWork({ items, space }: { items: Commitment[]; space: Space }) {
  const { actions } = useWorkspace();
  return (
    <div className="flex flex-col gap-2">
      <SectionHeader title="Tasks" count={items.length}>
        <DevysButton kind="quiet" compact onClick={() => actions.newTask({ spaceId: space.id })}>
          <Plus /> New task
        </DevysButton>
      </SectionHeader>
      {items.length === 0 && (
        <EmptyNote>
          Nothing here yet. Create a task, or right-click one under Work and choose Add to space.
        </EmptyNote>
      )}
      {items.map((item) => {
        const entry = space.items.find((i) => i.kind === "commitment" && i.ref === item.id);
        return (
          <WorkRow
            key={item.id}
            item={item}
            extra={
              entry && (
                <>
                  <ContextMenuSeparator />
                  <ContextMenuItem onClick={() => actions.removeFromSpace(space.id, entry.id)}>
                    <CircleMinus /> Remove from {space.name}
                  </ContextMenuItem>
                </>
              )
            }
          />
        );
      })}
    </div>
  );
}

/**
 * The space's files: saved files (markdown opens inline) and files on the Mac, which open in
 * Files. Each file keeps one home; the space only shows it.
 */
function SpaceFiles({ space }: { space: Space }) {
  const { artifacts, actions } = useWorkspace();
  const ids = new Set(refs(space, "artifact"));
  const files = artifacts.filter((file) => ids.has(file.id));
  const others = artifacts.filter((file) => !ids.has(file.id));
  const onMac = space.items.filter((item) => item.kind === "file");
  return (
    <div className="flex flex-col gap-2">
      <SectionHeader title="Files" count={files.length + onMac.length}>
        {others.length > 0 && (
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <DevysButton kind="quiet" compact>
                  <Plus /> Add file
                </DevysButton>
              }
            />
            <DropdownMenuContent align="end" className="w-auto">
              {others.map((file) => (
                <DropdownMenuItem
                  key={file.id}
                  onClick={() => actions.addToSpace(space.id, "artifact", file.id)}
                >
                  {file.filename}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </SectionHeader>
      {files.length + onMac.length === 0 && (
        <EmptyNote>
          Files your employees save can be shown here, and any file in Files through Save to space.
        </EmptyNote>
      )}
      {onMac.map((item) => (
        <ContextMenu key={item.id}>
          <ContextMenuTrigger
            render={
              <button
                type="button"
                onClick={() => actions.selectPage({ kind: "files", path: item.ref })}
              />
            }
            className="flex items-center gap-2.5 rounded-[12px] bg-sheet-tint p-2.5 text-left"
            data-testid="space-file"
          >
            <FolderOpen className="size-4 shrink-0 text-ink-3" />
            <div className="flex min-w-0 flex-col gap-px">
              <span className="truncate text-body font-semibold text-ink">
                {item.ref.split("/").at(-1)}
              </span>
              <span className="truncate text-detail text-ink-3">On the Mac</span>
            </div>
          </ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuItem onClick={() => actions.removeFromSpace(space.id, item.id)}>
              <CircleMinus /> Remove from space
            </ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      ))}
      {files.map((file) => (
        <FileRow
          key={file.id}
          file={file}
          remove={() => {
            const entry = space.items.find((i) => i.kind === "artifact" && i.ref === file.id);
            if (entry) actions.removeFromSpace(space.id, entry.id);
          }}
        />
      ))}
    </div>
  );
}

function FileRow({ file, remove }: { file: Artifact; remove: () => void }) {
  const { artifactTexts, actions, businessId } = useWorkspace();
  const [open, setOpen] = useState(false);
  const markdown = file.content_type.startsWith("text/markdown") || file.filename.endsWith(".md");
  const text = artifactTexts[file.id];
  const Icon = markdown ? FileText : File;
  return (
    <ContextMenu>
      <ContextMenuTrigger
        render={<div />}
        className="flex flex-col gap-2 rounded-[12px] bg-sheet-tint p-2.5 select-auto"
      >
        <div className="flex items-center gap-2.5">
          <Icon className="size-4 shrink-0 text-ink-3" />
          <div className="flex min-w-0 flex-col gap-px">
            <a
              href={api.artifactUrl(businessId, file.id)}
              className="truncate text-body font-semibold text-ink hover:underline"
            >
              {file.filename}
            </a>
            <span className="text-detail text-ink-3">{formatBytes(file.byte_length)}</span>
          </div>
          <span className="ml-auto" />
          {markdown && (
            <DevysButton
              kind="quiet"
              compact
              onClick={() => {
                setOpen(!open);
                if (!open) actions.openArtifact(file.id);
              }}
            >
              {open ? "Close" : "Open"}
            </DevysButton>
          )}
        </div>
        {open &&
          (text?.status === "loaded" ? (
            <MarkdownView text={text.value} />
          ) : text?.status === "failed" ? (
            <EmptyNote>{text.message}</EmptyNote>
          ) : (
            <Spinner />
          ))}
      </ContextMenuTrigger>
      <ContextMenuContent>
        <ContextMenuItem onClick={remove}>
          <CircleMinus /> Remove from space
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  );
}
