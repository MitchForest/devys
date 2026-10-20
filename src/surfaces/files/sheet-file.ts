/**
 * Spreadsheet files and Univer's workbook data, through SheetJS CE (Apache-2.0): values,
 * formulas, merges and column widths. Styling does not survive; the editor says so.
 */
import type { IWorkbookData } from "@univerjs/presets";
import { read, utils, write, type CellObject, type WorkSheet } from "xlsx";

export type Book = ReturnType<typeof read>;
type Cell = {
  v?: string | number | boolean | null;
  t?: number;
  f?: string | null;
  /** Rich text, which Univer keeps instead of `v` for text typed with formatting. */
  p?: { body?: { dataStream?: string } } | null;
};
type Sheet = IWorkbookData["sheets"][string];

/** The file format a spreadsheet saves back to, from its name. */
export function sheetFormat(name: string): "xlsx" | "biff8" | "csv" {
  const extension = name.split(".").at(-1)!.toLowerCase();
  return extension === "csv" ? "csv" : extension === "xls" ? "biff8" : "xlsx";
}

/** A SheetJS workbook as Univer's workbook data: values, formulas, merges, column widths. */
export function toUniver(book: Book, id: string): Partial<IWorkbookData> {
  const sheets: Record<string, Partial<Sheet>> = {};
  const sheetOrder = book.SheetNames.map((name, index) => {
    const ws = book.Sheets[name]!;
    const range = utils.decode_range(ws["!ref"] ?? "A1");
    const cellData: Record<number, Record<number, Cell>> = {};
    for (const [address, value] of Object.entries(ws)) {
      if (address.startsWith("!")) continue;
      const cell = value as CellObject;
      const { r, c } = utils.decode_cell(address);
      const v = cell.t === "e" ? (cell.w ?? null) : cell.t === "d" ? (cell.w ?? null) : cell.v;
      (cellData[r] ??= {})[c] = {
        v: v instanceof Date ? v.toISOString() : (v ?? null),
        t: cell.t === "n" ? 2 : cell.t === "b" ? 3 : 1,
        ...(cell.f ? { f: `=${cell.f}` } : {}),
      };
    }
    const sheetId = `sheet-${index}`;
    sheets[sheetId] = {
      id: sheetId,
      name,
      rowCount: Math.max(range.e.r + 50, 1000),
      columnCount: Math.max(range.e.c + 10, 26),
      cellData: cellData as Sheet["cellData"],
      mergeData: (ws["!merges"] ?? []).map((m) => ({
        startRow: m.s.r,
        endRow: m.e.r,
        startColumn: m.s.c,
        endColumn: m.e.c,
      })),
      columnData: Object.fromEntries(
        (ws["!cols"] ?? []).flatMap((col, c) => (col?.wpx ? [[c, { w: col.wpx }]] : [])),
      ),
    };
    return sheetId;
  });
  return {
    id,
    name: id,
    sheetOrder,
    sheets: sheets as IWorkbookData["sheets"],
    styles: {},
  };
}

/** Univer's workbook data back to file bytes in the given format. */
export function fromUniver(data: IWorkbookData, format: "xlsx" | "biff8" | "csv"): ArrayBuffer {
  const book = utils.book_new();
  for (const id of data.sheetOrder) {
    const sheet = data.sheets[id]!;
    const ws: WorkSheet = {};
    let rows = 0;
    let columns = 0;
    for (const [r, row] of Object.entries(sheet.cellData ?? {})) {
      for (const [c, value] of Object.entries(row ?? {})) {
        const cell = value as Cell;
        const formula = cell.f?.startsWith("=") ? cell.f.slice(1) : undefined;
        const rich = cell.p?.body?.dataStream?.replace(/\r?\n$/, "").replace(/\r$/, "");
        const shown = cell.v === null || cell.v === undefined || cell.v === "" ? rich : cell.v;
        if ((shown === undefined || shown === "") && !formula) continue;
        const v = shown ?? 0;
        const t = cell.t === 2 || typeof v === "number" ? "n" : cell.t === 3 ? "b" : "s";
        ws[utils.encode_cell({ r: Number(r), c: Number(c) })] = {
          t,
          v: t === "n" ? Number(v) : t === "b" ? Boolean(v) : String(v),
          ...(formula ? { f: formula } : {}),
        };
        rows = Math.max(rows, Number(r));
        columns = Math.max(columns, Number(c));
      }
    }
    ws["!ref"] = utils.encode_range({ s: { r: 0, c: 0 }, e: { r: rows, c: columns } });
    if (sheet.mergeData?.length)
      ws["!merges"] = sheet.mergeData.map((m) => ({
        s: { r: m.startRow, c: m.startColumn },
        e: { r: m.endRow, c: m.endColumn },
      }));
    const widths = Object.entries(sheet.columnData ?? {});
    if (widths.length)
      ws["!cols"] = Array.from({ length: columns + 1 }, (_, c) => {
        const w = (sheet.columnData?.[c] as { w?: number } | undefined)?.w;
        return w ? { wpx: w } : {};
      });
    utils.book_append_sheet(book, ws, sheet.name);
    if (format === "csv") break;
  }
  return write(book, { type: "array", bookType: format }) as ArrayBuffer;
}

/** Reads a spreadsheet file (xlsx, xls or CSV) with its formulas. */
export const readSheet = (bytes: ArrayBuffer): Book =>
  read(bytes, { type: "array", cellFormula: true, cellStyles: true });
