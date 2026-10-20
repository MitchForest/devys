import JSZip from "jszip";
import { expect, it } from "vitest";
import { utils, write } from "xlsx";
import { fromUniver, readSheet, sheetFormat, toUniver } from "../src/surfaces/files/sheet-file.ts";
import { deckSlides, deckToPptx, isDeck, pptxPath } from "../src/surfaces/files/slides.tsx";

it("a spreadsheet keeps its values, formulas, merges and widths through the editor's data", () => {
  const book = utils.book_new();
  const sheet = utils.aoa_to_sheet([
    ["Item", "Cost"],
    ["Domain", 12],
    ["Hosting", 30],
    ["Total", null],
  ]);
  sheet.B4 = { t: "n", v: 42, f: "SUM(B2:B3)" };
  sheet["!merges"] = [{ s: { r: 5, c: 0 }, e: { r: 5, c: 1 } }];
  sheet["!cols"] = [{ wpx: 140 }];
  utils.book_append_sheet(book, sheet, "Budget");
  utils.book_append_sheet(book, utils.aoa_to_sheet([["Notes"], [true]]), "Notes");
  const bytes = write(book, { type: "array", bookType: "xlsx" }) as ArrayBuffer;

  const data = toUniver(readSheet(bytes), "test");
  const budget = data.sheets!["sheet-0"]!;
  expect(budget.name).toBe("Budget");
  expect(budget.cellData![3]![1]).toMatchObject({ v: 42, t: 2, f: "=SUM(B2:B3)" });
  expect(budget.cellData![1]![0]).toMatchObject({ v: "Domain", t: 1 });
  // An edit in the editor, then the file written back.
  budget.cellData![2]![1] = { v: 31, t: 2 };
  // Text typed with formatting is rich text rather than a value.
  budget.cellData![0]![2] = { p: { body: { dataStream: "Owner\r\n" } } } as never;
  const saved = readSheet(fromUniver(data as never, "xlsx"));
  expect(saved.SheetNames).toEqual(["Budget", "Notes"]);
  const out = saved.Sheets.Budget!;
  expect(out.B3!.v).toBe(31);
  expect(out.B4!.f).toBe("SUM(B2:B3)");
  expect(out.A1!.v).toBe("Item");
  expect(out.C1!.v).toBe("Owner");
  expect(out["!merges"]).toEqual([{ s: { r: 5, c: 0 }, e: { r: 5, c: 1 } }]);
  expect(out["!cols"]?.[0]?.wpx).toBe(140);
  expect(saved.Sheets.Notes!.A2!.v).toBe(true);
  // CSV keeps the first sheet's values.
  expect(sheetFormat("budget.csv")).toBe("csv");
  const csv = new TextDecoder().decode(fromUniver(data as never, "csv"));
  expect(csv.split("\n")[0]).toBe("Item,Cost,Owner");
  expect(csv).not.toContain("Notes");
});

it("a markdown deck becomes slides and a PowerPoint file beside it", async () => {
  const deck = [
    "---",
    "marp: true",
    "theme: default",
    "---",
    "",
    "# Acme launch",
    "",
    "Spring 2027",
    "",
    "---",
    "",
    "## Plan",
    "",
    "- Ship the **site**",
    "  - Domain and [hosting](https://example.com)",
    "- Tell schools",
    "",
    "<!-- speaker note -->",
  ].join("\n");
  expect(isDeck("launch.md", deck)).toBe(true);
  expect(isDeck("launch.slides.md", "# Hi")).toBe(true);
  expect(isDeck("notes.md", "# Notes\n\n---\n\nmarp: true")).toBe(false);
  expect(pptxPath("/b/docs/launch.slides.md")).toBe("/b/docs/launch.pptx");
  expect(deckSlides(deck)).toEqual([
    { title: "Acme launch", blocks: [{ kind: "text", text: "Spring 2027" }] },
    {
      title: "Plan",
      blocks: [
        { kind: "bullet", text: "Ship the site", level: 0 },
        { kind: "bullet", text: "Domain and hosting", level: 1 },
        { kind: "bullet", text: "Tell schools", level: 0 },
      ],
    },
  ]);
  const pptx = await JSZip.loadAsync(await deckToPptx(deck));
  const slides = Object.keys(pptx.files).filter((name) =>
    /^ppt\/slides\/slide\d+\.xml$/.test(name),
  );
  expect(slides).toHaveLength(2);
  const second = await pptx.file("ppt/slides/slide2.xml")!.async("string");
  expect(second).toContain("Plan");
  expect(second).toContain("Tell schools");
});
