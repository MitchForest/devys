/// <reference types="google.picker" />
import { FileText } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { EmptyNote, SectionHeader, StatusChip } from "../design/primitives.tsx";
import { api } from "../app/api.ts";
import { keys, problemOf } from "../app/query.ts";
import { Button } from "@/components/ui/button";

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
export function DriveConnection({ businessId }: { businessId: string }) {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: keys.google(businessId),
    queryFn: () => api.google(businessId),
  });
  const connection = query.data;
  const [busy, setBusy] = useState(false);
  const [said, setNotice] = useState("");
  const notice =
    said || (query.isError ? problemOf(query.error, "Google Drive is unavailable.") : "");
  const refresh = () => client.invalidateQueries({ queryKey: keys.google(businessId) });
  const act = async (action: "connect" | "disconnect" | "picker") => {
    setBusy(true);
    setNotice("");
    try {
      if (action === "connect") {
        const { url } = await api.connectGoogle(businessId);
        window.location.assign(url);
      } else if (action === "disconnect") {
        const { revoked } = await api.disconnectGoogle(businessId);
        setNotice(
          revoked
            ? "Google Drive disconnected."
            : "Devys access is removed. Google didn't confirm revocation; remove Devys from your Google account's connections too.",
        );
        await refresh();
      } else {
        await loadPicker();
        const { token, key, app_id: appId } = await api.drivePicker(businessId);
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
          await api.selectDrive(businessId, ids);
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
        {connection?.connected && <StatusChip tone="done">Connected</StatusChip>}
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
            <Button size="compact" disabled={busy} onClick={() => void act("picker")}>
              Choose files
            </Button>
            <Button
              variant="quiet"
              size="compact"
              disabled={busy}
              onClick={() => void act("disconnect")}
            >
              Disconnect
            </Button>
          </div>
          {connection.files.map((file) => (
            <div
              key={file.id}
              className="flex items-center gap-2.5 rounded-row bg-sheet-tint px-3 py-2.5 text-body text-ink"
            >
              <FileText className="size-4 text-ink-3" /> {file.name}
            </div>
          ))}
        </>
      ) : connection?.configured ? (
        <Button
          variant="raised"
          disabled={busy}
          onClick={() => void act("connect")}
          className="self-start"
        >
          Connect Google Drive
        </Button>
      ) : (
        <EmptyNote>Google Drive setup is pending.</EmptyNote>
      )}
    </section>
  );
}
