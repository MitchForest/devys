import { ChevronLeft, Maximize2, Minimize2, X } from "lucide-react";
import type { ReactNode } from "react";
import { layerReference, useWorkspace } from "../app/workspace.tsx";
import { ToolbarIconButton } from "../design/buttons.tsx";
import { Desk } from "./desk.tsx";
import { NeedsYou } from "./home.tsx";
import { KeepInProject } from "./keep.tsx";
import { LayerView } from "./layers.tsx";
import { Overview } from "./overview.tsx";
import { WorkCard } from "./work-card.tsx";

/**
 * The right panel: the permanent view of what the conversation is about, with temporary
 * layers stacked over it. ‹ and Esc go back one layer; × returns to the permanent view.
 */
export function RightPanel({ onClose }: { onClose?: () => void }) {
  const { layers, place, actions, artifactName, wide } = useWorkspace();
  const top = layers.at(-1);
  if (top) {
    const { title } = layerReference(top, { artifact: artifactName });
    return (
      <section aria-label={title} className="flex h-full flex-col">
        <PanelHeader
          title={title}
          {...(layers.length > 1 ? { back: actions.popLayer } : {})}
          close={() => {
            actions.closeLayers();
            onClose?.();
          }}
          closeLabel="Close (back to the panel)"
        >
          {top.kind === "artifact" && <KeepInProject kind="artifact" refId={top.id} />}
          {top.kind === "file" && <KeepInProject kind="file" refId={top.path} />}
          {!onClose && (
            <ToolbarIconButton label={wide ? "Narrow" : "Widen"} onClick={actions.toggleWide}>
              {wide ? <Minimize2 /> : <Maximize2 />}
            </ToolbarIconButton>
          )}
        </PanelHeader>
        <div className="min-h-0 flex-1">
          <LayerView layer={top} />
        </div>
      </section>
    );
  }
  const close = onClose ?? actions.togglePanel;
  return place.kind === "home" ? (
    <NeedsYou close={close} />
  ) : place.kind === "direct" ? (
    <Desk key={place.employeeId} employeeId={place.employeeId} close={close} />
  ) : place.kind === "project" ? (
    <Overview key={place.id} projectId={place.id} close={close} />
  ) : (
    <WorkCard key={place.workId} workId={place.workId} close={close} />
  );
}

/** A panel's header: Back (when layered), the title, its own buttons and ×. */
export function PanelHeader({
  title,
  detail,
  back,
  close,
  closeLabel = "Hide side panel",
  children,
}: {
  title: ReactNode;
  detail?: ReactNode;
  back?: () => void;
  close: () => void;
  closeLabel?: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex h-[52px] shrink-0 items-center gap-1.5 border-b border-hairline px-2.5">
      {back && (
        <ToolbarIconButton label="Back" onClick={back}>
          <ChevronLeft />
        </ToolbarIconButton>
      )}
      <div className={back ? "flex min-w-0 flex-col" : "flex min-w-0 flex-col pl-1.5"}>
        <span className="truncate text-control font-semibold text-ink" data-testid="panel-title">
          {title}
        </span>
        {detail && <span className="truncate text-caption text-ink-3">{detail}</span>}
      </div>
      <span className="ml-auto" />
      {children}
      <ToolbarIconButton label={closeLabel} onClick={close}>
        <X />
      </ToolbarIconButton>
    </div>
  );
}

/** A permanent view's scrolling body. */
export function PanelBody({ children }: { children: ReactNode }) {
  return <div className="flex flex-col gap-5 overflow-y-auto px-4 pt-3.5 pb-6">{children}</div>;
}

/** A labelled group inside a panel; absent when it has nothing. */
export function PanelSection({
  title,
  count,
  action,
  children,
}: {
  title: string;
  count?: number;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <h3 className="text-label font-medium text-ink-3">
          {title}
          {count ? ` · ${count}` : ""}
        </h3>
        <span className="ml-auto" />
        {action}
      </div>
      {children}
    </section>
  );
}
