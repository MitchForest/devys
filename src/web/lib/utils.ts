import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

/**
 * The theme's own scales (src/web/styles.css), so `text-control` is a size (not a color that
 * `text-ink` would replace) and `rounded-control` a radius.
 */
const twMerge = extendTailwindMerge({
  extend: {
    theme: {
      text: [
        "greeting",
        "title",
        "heading",
        "body",
        "detail",
        "label",
        "caption",
        "control",
        "data",
      ],
      radius: ["tiny", "small", "control", "row", "workspace", "bubble", "card", "sheet"],
      shadow: ["resting", "raised"],
    },
  },
});

/** Joins class names, letting later Tailwind classes win over earlier ones. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
