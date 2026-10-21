/**
 * Spreadsheets the owner edits (.docs/PRODUCT_EXPERIENCE.md#files-and-documents): Univer OSS
 * (Apache-2.0) draws and edits the sheet, and SheetJS CE (Apache-2.0) reads and writes the file.
 * (`sheet-file.ts`). Values, formulas, merges and column widths survive a save; styling does not
 * yet, which the editor says. CSV keeps one sheet of values.
 */
import { createUniver, LocaleType, mergeLocales } from "@univerjs/presets";
import { UniverSheetsCorePreset } from "@univerjs/preset-sheets-core";
import sheetsEnglish from "@univerjs/preset-sheets-core/locales/en-US";
import "@univerjs/preset-sheets-core/lib/index.css";
import { useEffect, useRef, useState } from "react";
import { fromUniver, readSheet, sheetFormat, toUniver, type Book } from "./sheet-file.ts";

// Sheet commands and undo change the workbook; the cell editor's own `doc.*` commands run even
// at load. Of the sheet commands, switching sheets, zooming, scrolling and copying change nothing.
const edits = /^(sheet\.command\.|univer\.command\.(undo|redo)$)/;
const viewOnly = /activate|zoom|scroll|select|copy|auto-height|set-cell-edit-visible/;

/**
 * Shows a spreadsheet, editable unless `readOnly` (layers are read-only until the owner takes the
 * work over; Univer's workbook permission refuses edits). `onChange` fires on the first edit after `version` and hands over a
 * function that writes the current sheet as file bytes, so nothing serialises per keystroke.
 */
export function SheetEditor({
  bytes,
  name,
  version,
  dark,
  readOnly = false,
  onChange,
}: {
  bytes: ArrayBuffer;
  name: string;
  version: string;
  dark: boolean;
  readOnly?: boolean;
  onChange: (serialize: () => ArrayBuffer) => void;
}) {
  const root = useRef<HTMLDivElement>(null);
  const changed = useRef(onChange);
  changed.current = onChange;
  const locked = useRef(readOnly);
  locked.current = readOnly;
  const [problem, setProblem] = useState(false);
  const [api, setApi] = useState<ReturnType<typeof createUniver>["univerAPI"] | null>(null);
  const darkAtStart = useRef(dark);
  darkAtStart.current = dark;
  useEffect(() => {
    if (!root.current) return;
    let book: Book;
    try {
      book = readSheet(bytes);
    } catch {
      setProblem(true);
      return;
    }
    const { univer, univerAPI } = createUniver({
      locale: LocaleType.EN_US,
      locales: { [LocaleType.EN_US]: mergeLocales(sheetsEnglish) },
      darkMode: darkAtStart.current,
      presets: [UniverSheetsCorePreset({ container: root.current, header: true, footer: {} })],
    });
    univerAPI.createWorkbook(toUniver(book, `devys-${version}`)).setEditable(!locked.current);
    const format = sheetFormat(name);
    const serialize = () => fromUniver(univerAPI.getActiveWorkbook()!.save(), format);
    const listener = univerAPI.addEvent(univerAPI.Event.CommandExecuted, (event) => {
      if (!locked.current && event.type === 0 && edits.test(event.id) && !viewOnly.test(event.id))
        changed.current(serialize);
    });
    setApi(univerAPI);
    return () => {
      setApi(null);
      listener.dispose();
      univerAPI.dispose();
      univer.dispose();
    };
  }, [bytes, name, version]);
  useEffect(() => api?.toggleDarkMode(dark), [api, dark]);
  useEffect(() => void api?.getActiveWorkbook()?.setEditable(!readOnly), [api, readOnly]);
  if (problem)
    return <p className="p-4 text-body text-ink-2">This spreadsheet couldn't be read.</p>;
  return (
    <div className="flex size-full flex-col" data-testid="sheet-editor">
      <div
        ref={root}
        className="min-h-0 flex-1"
        title={
          sheetFormat(name) === "csv"
            ? "CSV saves the first sheet's values."
            : "Saving keeps values, formulas, merged cells and column widths, not cell styling."
        }
      />
    </div>
  );
}
