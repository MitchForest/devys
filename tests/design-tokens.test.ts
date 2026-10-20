import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

/** The native color tokens are the source of truth; the web must use the same values. */
function nativeTokens() {
  const swift = readFileSync(
    "apple/Packages/DevysKit/Sources/DevysDesignSystem/DevysColors.swift",
    "utf8",
  );
  const tokens = new Map<string, { light: string; dark: string }>();
  const pattern =
    /static let (\w+) = Color\(light: 0x([0-9A-F]{6}), dark: 0x([0-9A-F]{6})(?:, lightAlpha: ([\d.]+), darkAlpha: ([\d.]+))?\)/g;
  for (const [, name, light, dark, lightAlpha, darkAlpha] of swift.matchAll(pattern)) {
    const css = (hex: string, alpha?: string) => {
      if (!alpha) return `#${hex.toLowerCase()}`;
      const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
      return `rgb(${r} ${g} ${b} / ${alpha})`;
    };
    const kebab = name!.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
    tokens.set(kebab, { light: css(light!, lightAlpha), dark: css(dark!, darkAlpha) });
  }
  return tokens;
}

function webBlock(css: string, selector: string) {
  const start = css.indexOf(`${selector} {`);
  const body = css.slice(start, css.indexOf("}", start));
  return new Map(
    [...body.matchAll(/--([\w-]+):\s*([^;]+);/g)].map(([, name, value]) => [name!, value!.trim()]),
  );
}

it("the web's color tokens are exactly the native apps' colors, light and dark", () => {
  const native = nativeTokens();
  expect(native.size).toBeGreaterThan(15);
  const css = readFileSync("src/web/styles.css", "utf8");
  const light = webBlock(css, ":root");
  const dark = webBlock(css, ".dark");
  const system = webBlock(css, ":root:not(.light)");
  for (const [name, value] of native) {
    expect(light.get(name), `light --${name}`).toBe(value.light);
    expect(dark.get(name), `dark --${name}`).toBe(value.dark);
    expect(system.get(name), `system dark --${name}`).toBe(value.dark);
  }
});

it("the marketing site's color tokens are the native apps' colors, light and dark", () => {
  const native = nativeTokens();
  const css = readFileSync("site/styles.css", "utf8");
  const light = webBlock(css, ":root");
  const dark = webBlock(css, ".scope-dark");
  for (const [name, value] of native) {
    expect(light.get(name), `site light --${name}`).toBe(value.light);
    expect(dark.get(name), `site dark --${name}`).toBe(value.dark);
  }
});
