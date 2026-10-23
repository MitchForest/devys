import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, it } from "vitest";
import { InlineMarkdown } from "../src/web/design/markdown.tsx";

const html = (text: string) => renderToStaticMarkup(createElement(InlineMarkdown, { text }));

it("a chat bubble keeps a list's items apart, bulleted or numbered", () => {
  const bulleted = html("Two ways to pay:\n\n- **Ramp**, the fund\n- A card");
  expect(bulleted).toContain("<ul");
  expect(bulleted.match(/<li/g)).toHaveLength(2);
  expect(bulleted).toContain("<strong>Ramp</strong>");
  const numbered = html("3. Third\n4. Fourth");
  expect(numbered).toMatch(/<ol start="3"/);
  expect(numbered.match(/<li/g)).toHaveLength(2);
});

it("other blocks still unwrap to their text, and raw HTML never renders", () => {
  expect(html("# Title\n\n<b>raw</b>")).not.toMatch(/<h1|<b>/);
});
