import { ChevronLeft, Maximize2, Minimize2, X } from "lucide-react";
import type { ReactNode } from "react";
import { useArtifactName } from "../app/data.ts";
import { layerOfRef, layerReference, useLayers, useNav, usePlace } from "../app/navigation.ts";
import { ui, useUi } from "../app/ui.ts";
import { usePanel } from "../shell/panel-state.ts";
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
  const { layers, top } = useLayers();
  const place = usePlace();
  const nav = useNav();
  const panel = usePanel();
  const artifact = useArtifactName();
  const wide = useUi((state) => state.wide);
  if (top) {
    const { title, ref } = layerReference(top, { artifact });
    return (
      <section aria-label={title} className="flex h-full flex-col">
        <PanelHeader
          title={title}
          {...(layers.length > 1 ? { back: nav.popLayer } : {})}
          close={() => {
            nav.closeLayers();
            onClose?.();
          }}
          closeLabel="Close (back to the panel)"
        >
          {ref && layerOfRef(ref) && <KeepInProject record={ref} />}
          {!onClose && (
            <ToolbarIconButton label={wide ? "Narrow" : "Widen"} onClick={ui.toggleWide}>
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
  const close = onClose ?? panel.toggle;
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
