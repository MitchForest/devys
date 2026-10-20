import { Hand, X } from "lucide-react";
import { lazy, Suspense, useEffect, useState } from "react";
import { api } from "../app/api.ts";
import { DevysButton } from "../design/buttons.tsx";
import type { TerminalState } from "../../surfaces/terminal/view.tsx";

// The WebAssembly terminal loads only in terminal windows.
const TerminalView = lazy(() =>
  import("../../surfaces/terminal/view.tsx").then((module) => ({ default: module.TerminalView })),
);

/**
 * A terminal on the owner's Mac in its own browser window. Closing the window leaves the session
 * running; End closes it. Another device can attach at any time and take control.
 */
export function TerminalWindow({
  businessId,
  terminalId,
}: {
  businessId: string;
  terminalId: string;
}) {
  const [title, setTitle] = useState("Terminal");
  const [state, setState] = useState<TerminalState | null>(null);
  const [control, setControl] = useState(0);
  const [dark, setDark] = useState(false);
  useEffect(() => {
    void api.terminals(businessId).then(({ terminals }) => {
      const found = terminals.find((terminal) => terminal.id === terminalId);
      if (found) setTitle(found.title);
    });
    const media = matchMedia("(prefers-color-scheme: dark)");
    const apply = () =>
      setDark(
        document.documentElement.classList.contains("dark") ||
          (media.matches && !document.documentElement.classList.contains("light")),
      );
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [businessId, terminalId]);
  useEffect(() => {
    document.title = `${title} — Devys`;
  }, [title]);
  const status = !state
    ? "Connecting…"
    : state.exit
      ? `Ended${state.exit.code === null ? "" : ` (exit ${state.exit.code})`}`
      : !state.connected
        ? "Reconnecting…"
        : state.typing
          ? "Typing here"
          : "Watching: another device is typing";
  return (
    <div className="flex h-dvh flex-col bg-sheet">
      <div className="flex items-center gap-2 border-b border-hairline px-3 py-2">
        <span className="truncate text-body font-semibold text-ink">{title}</span>
        <span className="truncate text-caption text-ink-3" data-testid="terminal-status">
          {status}
        </span>
        <span className="ml-auto" />
        {state?.connected && !state.typing && !state.exit && (
          <DevysButton compact onClick={() => setControl((count) => count + 1)}>
            <Hand /> Take control
          </DevysButton>
        )}
        <DevysButton
          kind="quiet"
          compact
          onClick={() => void api.closeTerminal(businessId, terminalId).then(() => window.close())}
        >
          <X /> End
        </DevysButton>
      </div>
      {state?.error && <div className="px-3 py-1 text-detail text-ink-2">{state.error}</div>}
      <div className="min-h-0 flex-1 p-1">
        <Suspense fallback={null}>
          <TerminalView
            socketUrl={(offset) => api.terminalSocket(businessId, terminalId, offset)}
            dark={dark}
            onState={setState}
            control={control}
          />
        </Suspense>
      </div>
    </div>
  );
}

/**
 * Opens a terminal and shows it in a new window. The window is opened before the request so the
 * browser treats it as the click's own window rather than a pop-up.
 */
export async function openTerminalWindow(
  businessId: string,
  open: { work?: string; resume?: string },
): Promise<void> {
  const target = window.open("about:blank", "_blank");
  try {
    const session = await api.openTerminal(businessId, { ...open, cols: 120, rows: 34 });
    const url = `/terminal/${businessId}/${session.id}`;
    if (target) target.location.href = url;
    else window.location.href = url;
  } catch (error) {
    target?.close();
    throw error;
  }
}
