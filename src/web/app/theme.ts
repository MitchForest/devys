import { useEffect, useState } from "react";

export type Theme = "system" | "light" | "dark";

const read = (): Theme => {
  try {
    const saved = localStorage.getItem("appearance");
    return saved === "light" || saved === "dark" ? saved : "system";
  } catch {
    return "system";
  }
};

/** Applies the owner's appearance as a class on the root, so Devys tokens switch with it. */
function applyTheme(theme: Theme) {
  const root = document.documentElement;
  root.classList.toggle("light", theme === "light");
  root.classList.toggle("dark", theme === "dark");
}

export function useTheme() {
  const [theme, setTheme] = useState<Theme>("system");
  useEffect(() => setTheme(read()), []);
  const change = (next: Theme) => {
    setTheme(next);
    applyTheme(next);
    try {
      localStorage.setItem("appearance", next);
    } catch {
      // Appearance is a per-browser convenience.
    }
    // The Face picks eye ink or glow from the theme.
    void import("../design/face-renderer.js").then((renderer) => renderer.redrawFaces());
  };
  return [theme, change] as const;
}

/** Runs before first paint so a dark preference never flashes light. */
export const themeScript = `try{var t=localStorage.getItem("appearance");if(t==="light"||t==="dark")document.documentElement.classList.add(t)}catch(e){}`;

/** Whether the page renders dark right now: the owner's choice, else the system setting. */
const rendersDark = () => {
  const root = document.documentElement;
  return (
    root.classList.contains("dark") ||
    (!root.classList.contains("light") && matchMedia("(prefers-color-scheme: dark)").matches)
  );
};

/** Follows the rendered theme, so surfaces that draw their own colors redraw when it changes. */
export function useDark() {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    const apply = () => setDark(rendersDark());
    apply();
    const media = matchMedia("(prefers-color-scheme: dark)");
    media.addEventListener("change", apply);
    const observer = new MutationObserver(apply);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => {
      media.removeEventListener("change", apply);
      observer.disconnect();
    };
  }, []);
  return dark;
}
