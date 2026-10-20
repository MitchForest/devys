/**
 * A terminal session in the browser: libghostty-vt in WebAssembly, drawn by the surface ported
 * from T3 Code, connected to a host terminal through a WebSocket. Output arrives as binary
 * frames, events as text frames; keystrokes leave as binary. A dropped connection reconnects
 * from the last byte seen, so nothing is repeated or lost.
 */
import { useEffect, useRef, useState } from "react";
import type { GhosttyTheme } from "./core";
import { GhosttyTerminalSurface } from "./surface";

type Event =
  | { type: "attached"; client: string; offset: number; session: { writer: string | null } }
  | { type: "writer"; writer: string | null }
  | { type: "exit"; code: number | null }
  | { type: "error"; message: string };

const light: GhosttyTheme = {
  foreground: { r: 0x1b, g: 0x1b, b: 0x20 },
  background: { r: 0xff, g: 0xff, b: 0xff },
  cursor: { r: 0x5a, g: 0x68, b: 0xf0 },
  selectionBackground: "rgba(90, 104, 240, 0.25)",
};
const dark: GhosttyTheme = {
  foreground: { r: 0xe8, g: 0xe8, b: 0xee },
  background: { r: 0x1e, g: 0x1e, b: 0x23 },
  cursor: { r: 0x7d, g: 0x89, b: 0xff },
  selectionBackground: "rgba(125, 137, 255, 0.3)",
};

export interface TerminalState {
  connected: boolean;
  /** This device types; otherwise it watches until it takes control. */
  typing: boolean;
  exit: { code: number | null } | null;
  error: string | null;
}

export function TerminalView({
  socketUrl,
  dark: isDark = false,
  onState,
  control,
}: {
  /** The WebSocket address for this session, given the offset to resume from. */
  socketUrl: (offset: number) => string;
  dark?: boolean;
  onState?: (state: TerminalState) => void;
  /** Incremented by the caller to take control of the keyboard. */
  control?: number;
}) {
  const mount = useRef<HTMLDivElement>(null);
  const socket = useRef<WebSocket | null>(null);
  const [surface, setSurface] = useState<GhosttyTerminalSurface | null>(null);
  const report = useRef(onState);
  report.current = onState;

  useEffect(() => {
    let disposed = false;
    let created: GhosttyTerminalSurface | null = null;
    void GhosttyTerminalSurface.create(mount.current!, {
      theme: isDark ? dark : light,
      onData: (data) => {
        if (socket.current?.readyState === WebSocket.OPEN)
          socket.current.send(new TextEncoder().encode(data));
      },
      onResize: (cols, rows) => {
        if (socket.current?.readyState === WebSocket.OPEN)
          socket.current.send(JSON.stringify({ type: "resize", cols, rows }));
      },
      onSelectionChange: () => {},
      beforeKey: () => true,
      onLinkActivate: (text) => {
        if (/^https?:\/\//.test(text)) window.open(text, "_blank", "noopener,noreferrer");
      },
    }).then((made) => {
      if (disposed) made.dispose();
      else {
        created = made;
        setSurface(made);
      }
    });
    return () => {
      disposed = true;
      created?.dispose();
    };
    // The theme changes through setTheme below, not by recreating the surface.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => surface?.setTheme(isDark ? dark : light), [surface, isDark]);

  useEffect(() => {
    if (!surface) return;
    let offset = 0;
    let client = "";
    let ended = false;
    let retry: ReturnType<typeof setTimeout> | undefined;
    let attempts = 0;
    const decoder = new TextDecoder();
    const state: TerminalState = { connected: false, typing: false, exit: null, error: null };
    const publish = (change: Partial<TerminalState>) => {
      Object.assign(state, change);
      report.current?.({ ...state });
    };
    const connect = () => {
      const ws = new WebSocket(socketUrl(offset));
      ws.binaryType = "arraybuffer";
      socket.current = ws;
      ws.onmessage = (message) => {
        if (typeof message.data !== "string") {
          const bytes = new Uint8Array(message.data as ArrayBuffer);
          offset += bytes.length;
          surface.write(decoder.decode(bytes, { stream: true }));
          return;
        }
        const event = JSON.parse(message.data) as Event;
        if (event.type === "attached") {
          attempts = 0;
          client = event.client;
          offset = event.offset;
          publish({ connected: true, typing: event.session.writer === client, error: null });
          surface.resendSize();
        } else if (event.type === "writer") publish({ typing: event.writer === client });
        else if (event.type === "exit") {
          ended = true;
          publish({ exit: { code: event.code }, typing: false });
        } else if (event.type === "error") publish({ error: event.message });
      };
      ws.onclose = () => {
        publish({ connected: false });
        if (ended) return;
        retry = setTimeout(connect, Math.min(10_000, 500 * 2 ** attempts++));
      };
    };
    connect();
    surface.focus();
    return () => {
      ended = true;
      clearTimeout(retry);
      socket.current?.close();
    };
    // Reconnecting is internal; a new socket address means a different session and a new view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [surface]);

  useEffect(() => {
    if (control && socket.current?.readyState === WebSocket.OPEN)
      socket.current.send(JSON.stringify({ type: "takeControl" }));
  }, [control]);

  return (
    <div ref={mount} className="relative size-full overflow-hidden" data-testid="terminal-view" />
  );
}
