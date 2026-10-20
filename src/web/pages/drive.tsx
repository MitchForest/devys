/// <reference types="google.picker" />
import { FileText } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { DevysButton } from "../design/buttons.tsx";
import { EmptyNote, LiveTag, SectionHeader, StatusChip } from "../design/primitives.tsx";

declare const gapi: {
  load(
    name: string,
    options: { callback: () => void; onerror: () => void; timeout: number; ontimeout: () => void },
  ): void;
};
let pickerScript: Promise<void> | undefined;
function loadPicker() {
  return (pickerScript ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://apis.google.com/js/api.js";
    script.onerror = () => {
      pickerScript = undefined;
      reject(new Error("Couldn't load Google's file picker"));
    };
    script.onload = () =>
      gapi.load("picker", {
        callback: resolve,
        onerror: () => reject(new Error("Google Picker unavailable")),
        timeout: 15_000,
        ontimeout: () => reject(new Error("Google Picker timed out")),
      });
    document.head.appendChild(script);
  }));
}
interface Connection {
  configured: boolean;
  connected: boolean;
  files: { id: string; name: string }[];
}
export function DriveConnection({ businessId }: { businessId: string }) {
  const [connection, setConnection] = useState<Connection>();
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const refresh = useCallback(async () => {
    const response = await fetch(`/api/businesses/${businessId}/connections/google`);
    if (!response.ok) throw new Error("Couldn't load Google Drive connection");
    setConnection(await response.json());
  }, [businessId]);
  useEffect(() => {
    void refresh().catch((error: Error) => setNotice(error.message));
  }, [refresh]);
  const post = async (action: string, body?: unknown) => {
    const response = await fetch(`/api/businesses/${businessId}/connections/google/${action}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) throw new Error(await response.text());
    return response;
  };
  const act = async (action: "connect" | "disconnect" | "picker") => {
    setBusy(true);
    setNotice("");
    try {
      if (action === "connect") {
        const { url } = (await (await post(action)).json()) as { url: string };
        window.location.assign(url);
      } else if (action === "disconnect") {
        const { revoked } = (await (await post(action)).json()) as { revoked: boolean };
        setNotice(
          revoked
            ? "Google Drive disconnected."
            : "Devys access is removed. Google didn't confirm revocation; remove Devys from your Google account's connections too.",
        );
        await refresh();
      } else {
        await loadPicker();
        const { token, key, appId } = (await (await post(action)).json()) as {
          token: string;
          key: string;
          appId: string;
        };
        const ids = await new Promise<string[]>((resolve) => {
          const picker = new google.picker.PickerBuilder()
            .setDeveloperKey(key)
            .setAppId(appId)
            .setOAuthToken(token)
            .setOrigin(window.location.origin)
            .addView(
              new google.picker.DocsView().setMimeTypes(
                "text/plain,text/markdown,text/csv,application/json,application/vnd.google-apps.document",
              ),
            )
            .enableFeature(google.picker.Feature.MULTISELECT_ENABLED)
            .setCallback((data) => {
              if (data.action === google.picker.Action.PICKED) {
                resolve((data.docs ?? []).map((doc) => doc.id));
                picker.dispose();
              }
              if (data.action === google.picker.Action.CANCEL) {
                resolve([]);
                picker.dispose();
              }
            })
            .build();
          picker.setVisible(true);
        });
        if (ids.length) {
          await post("select", { ids });
          await refresh();
        }
      }
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Couldn't update Google Drive");
    } finally {
      setBusy(false);
    }
  };
  return (
    <section aria-label="Google Drive" className="flex flex-col gap-3">
      <SectionHeader title="Google Drive">
        {connection?.connected ? <StatusChip tone="done">Connected</StatusChip> : <LiveTag />}
      </SectionHeader>
      <p className="text-body text-ink-2">
        Choose documents for Devys to read. Save new text files to your Drive and ask Devys to
        update them later.
      </p>
      {notice && (
        <p role="status" className="text-detail text-ink-2">
          {notice}
        </p>
      )}
      {connection?.connected ? (
        <>
          <div className="flex gap-2">
            <DevysButton compact disabled={busy} onClick={() => void act("picker")}>
              Choose files
            </DevysButton>
            <DevysButton
              kind="quiet"
              compact
              disabled={busy}
              onClick={() => void act("disconnect")}
            >
              Disconnect
            </DevysButton>
          </div>
          {connection.files.map((file) => (
            <div
              key={file.id}
              className="flex items-center gap-2.5 rounded-[12px] bg-sheet-tint px-3 py-2.5 text-body text-ink"
            >
              <FileText className="size-4 text-ink-3" /> {file.name}
            </div>
          ))}
        </>
      ) : connection?.configured ? (
        <DevysButton
          kind="raised"
          disabled={busy}
          onClick={() => void act("connect")}
          className="self-start"
        >
          Connect Google Drive
        </DevysButton>
      ) : (
        <EmptyNote>Google Drive setup is pending.</EmptyNote>
      )}
    </section>
  );
}
