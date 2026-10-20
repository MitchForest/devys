/**
 * Slide decks as markdown (.docs/PRODUCT_EXPERIENCE.md#files-and-documents): the source is the
 * file, Marp core (MIT) draws the slides in a sandboxed frame with no scripts or raw HTML, and
 * pptxgenjs (MIT) writes a PowerPoint copy of titles, bullets and paragraphs.
 */
import { Marp } from "@marp-team/marp-core";
import PptxGenJS from "pptxgenjs";
import { useEffect, useMemo, useRef, useState } from "react";

/** A markdown file is a deck when it is named `*.slides.md` or its front matter says `marp: true`. */
export function isDeck(name: string, markdown: string) {
  return (
    name.toLowerCase().endsWith(".slides.md") ||
    /^---\r?\n(?:[^\n]*\r?\n)*?marp:\s*true\s*\r?\n(?:[^\n]*\r?\n)*?---/.test(markdown)
  );
}

/** Where a deck's PowerPoint copy goes: beside it, with the same name. */
export function pptxPath(path: string) {
  return path.replace(/(\.slides)?\.(md|markdown)$/i, "") + ".pptx";
}

type Block = { kind: "bullet"; text: string; level: number } | { kind: "text"; text: string };

/** The slides of a deck: each one's title and its bullets and paragraphs, as plain text. */
export function deckSlides(markdown: string) {
  const plain = (text: string) =>
    text
      .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
      .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/(\*\*|__|\*|_|`)(.+?)\1/g, "$2")
      .trim();
  const body = markdown
    .replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "")
    .replace(/<!--[\s\S]*?-->/g, "");
  return body
    .split(/^\s*---\s*$/m)
    .map((source) => {
      let title = "";
      const blocks: Block[] = [];
      for (const line of source.split(/\r?\n/)) {
        const heading = /^#{1,6}\s+(.*)$/.exec(line);
        const bullet = /^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/.exec(line);
        if (heading && !title) title = plain(heading[1]!);
        else if (bullet && plain(bullet[2]!))
          blocks.push({
            kind: "bullet",
            text: plain(bullet[2]!),
            level: Math.floor(bullet[1]!.length / 2),
          });
        else if (heading || plain(line))
          blocks.push({ kind: "text", text: plain(heading ? heading[1]! : line) });
      }
      return { title, blocks };
    })
    .filter((slide) => slide.title || slide.blocks.length);
}

/** A PowerPoint copy of a deck. */
export async function deckToPptx(markdown: string): Promise<ArrayBuffer> {
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_16x9";
  for (const each of deckSlides(markdown)) {
    const slide = pptx.addSlide();
    if (each.title)
      slide.addText(each.title, { x: 0.5, y: 0.3, w: 9, h: 0.9, fontSize: 30, bold: true });
    if (each.blocks.length)
      slide.addText(
        each.blocks.map((block) => ({
          text: block.text,
          options: {
            breakLine: true,
            ...(block.kind === "bullet" ? { bullet: true, indentLevel: block.level } : {}),
          },
        })),
        {
          x: 0.5,
          y: each.title ? 1.3 : 0.4,
          w: 9,
          h: each.title ? 3.9 : 4.8,
          fontSize: 18,
          valign: "top",
        },
      );
  }
  return (await pptx.write({ outputType: "arraybuffer" })) as ArrayBuffer;
}

const frame = `
  html, body { margin: 0; background: #8a8a8e; }
  div.marpit > svg { display: block; width: calc(100% - 24px); height: auto; margin: 12px auto;
    box-shadow: 0 1px 4px rgb(0 0 0 / 0.3); }
`;

/** Edits a deck's markdown beside its slides. */
export function SlidesEditor({
  markdown,
  version,
  onChange,
}: {
  markdown: string;
  version: string;
  onChange: (markdown: string) => void;
}) {
  const [source, setSource] = useState(markdown);
  const shown = useRef(version);
  useEffect(() => {
    if (shown.current === version) return;
    shown.current = version;
    setSource(markdown);
  }, [markdown, version]);
  // One renderer per editor; the frame allows nothing, so slides cannot run code or fetch.
  const marp = useMemo(() => new Marp({ html: false, script: false }), []);
  const document = useMemo(() => {
    const { html, css } = marp.render(source);
    return `<!doctype html><meta charset="utf-8"><style>${css}${frame}</style>${html}`;
  }, [marp, source]);
  return (
    <div className="grid size-full grid-cols-2" data-testid="slides-editor">
      <textarea
        value={source}
        onChange={(event) => {
          setSource(event.target.value);
          onChange(event.target.value);
        }}
        spellCheck={false}
        aria-label="Deck source"
        className="size-full resize-none border-r border-hairline bg-sheet p-4 font-mono text-detail text-ink outline-none"
      />
      <iframe
        title="Slides"
        sandbox=""
        srcDoc={document}
        className="size-full border-0"
        data-testid="slides-preview"
      />
    </div>
  );
}
