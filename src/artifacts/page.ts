/**
 * HTML pages employees publish (U3): one self-contained page, rendered in an opaque-origin
 * sandbox with no network. Anything that would leave the page or reach Devys is refused here.
 */
export const pageBytes = 512_000;

const refused: [RegExp, string][] = [
  [/<\s*form\b/i, "forms"],
  [/<\s*i?frame(set)?\b/i, "frames"],
  [/<\s*(object|embed)\b/i, "embedded objects"],
  [/<\s*base\b/i, "<base>"],
  [/<\s*meta[^>]+http-equiv\s*=\s*["']?refresh/i, "meta refresh"],
];

/** Why the page can't be published, or undefined when it can. */
export function pageProblem(html: string) {
  if (!html.trim()) return "The page is empty.";
  if (new TextEncoder().encode(html).byteLength > pageBytes)
    return `The page is larger than ${pageBytes / 1000} KB; make it smaller.`;
  const found = refused.filter(([pattern]) => pattern.test(html)).map(([, name]) => name);
  return found.length
    ? `Pages can't contain ${found.join(", ")}: they render offline and alone. Use plain HTML, CSS, inline scripts and data: images.`
    : undefined;
}
