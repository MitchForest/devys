import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";

export type Mood =
  | "idle"
  | "listening"
  | "thinking"
  | "working"
  | "waiting"
  | "celebrate"
  | "oops"
  | "asleep"
  | "off";
export interface FaceSpec {
  palette: string;
  shape: string;
  seed: number;
}

export const palettes = [
  "brown",
  "red",
  "orange",
  "amber",
  "green",
  "teal",
  "blue",
  "purple",
  "pink",
  "gray",
];
export const shapes = [
  "circle",
  "blob",
  "roundedSquare",
  "capsule",
  "triangle",
  "hexagon",
  "cloud",
  "drop",
];

/** The same default Face the native apps give an employee: Swift's `Employee.face(for:)`. */
export function faceFor(id: string): FaceSpec {
  let value = 0n;
  for (const char of id) value = BigInt.asIntN(64, value * 31n + BigInt(char.codePointAt(0)!));
  const magnitude = value < 0n ? -value : value;
  return {
    palette: palettes[Number(magnitude % 10n)]!,
    shape: shapes[Number((magnitude / 10n) % 8n)]!,
    seed: Number(magnitude % 97n),
  };
}

/** The Face: two morphing eyes on an adaptive tile, drawn by the shared renderer. */
export function Face({
  spec,
  size,
  mood = "idle",
  label,
}: {
  spec: FaceSpec;
  size: number;
  mood?: Mood;
  label?: string;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    let unmount: ((canvas: HTMLCanvasElement) => void) | undefined;
    // The renderer touches browser APIs on import, so it loads only in the browser.
    void import("./face-renderer.js").then((renderer) => {
      renderer.mountFaces(element.parentElement ?? document);
      unmount = renderer.unmountFace;
    });
    return () => unmount?.(element);
  }, [spec.palette, spec.shape, spec.seed, size]);
  return (
    <span className="inline-grid shrink-0" style={{ width: size, height: size }}>
      <canvas
        key={`${spec.palette}-${spec.shape}-${spec.seed}-${size}`}
        ref={canvas}
        className="face"
        data-palette={spec.palette}
        data-shape={spec.shape}
        data-seed={spec.seed}
        data-size={size}
        data-mood={mood}
        aria-label={label ? `${label}, ${mood === "idle" ? "available" : mood}` : undefined}
        aria-hidden={label ? undefined : true}
        width={size}
        height={size}
      />
    </span>
  );
}

export const tileGradients: Record<string, [string, string]> = {
  blue: ["#5a89f5", "#2f55c9"],
  orange: ["#f59a58", "#d9603a"],
  green: ["#4cc27e", "#23864d"],
  purple: ["#a77af0", "#6f45c9"],
  pink: ["#f27db2", "#c9457f"],
};
export const tints = ["blue", "orange", "green", "purple", "pink"];

/** A business's tint, stable for its id, as on native. */
export const tintFor = (id: string) =>
  tints[[...id].reduce((sum, char) => sum + char.codePointAt(0)!, 0) % tints.length]!;

/** Business identity in the rail and switcher. */
export function BusinessTile({
  name,
  tint,
  size = 36,
}: {
  name: string;
  tint: string;
  size?: number;
}) {
  const [from, to] = tileGradients[tint] ?? tileGradients.blue!;
  return (
    <span
      className="grid shrink-0 place-items-center font-semibold text-white shadow-[inset_0_0_0_0.5px_rgb(255_255_255/0.18)]"
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.3,
        fontSize: size * 0.42,
        background: `linear-gradient(135deg, ${from}, ${to})`,
        fontFamily: "ui-rounded, -apple-system, system-ui, sans-serif",
      }}
    >
      {name.charAt(0).toUpperCase() || "·"}
    </span>
  );
}

/** A person: their photo, or their initial on a purple tile. */
export function PersonPortrait({
  name,
  photo,
  size,
}: {
  name: string;
  photo?: string;
  size: number;
}) {
  return photo ? (
    <img
      src={photo}
      alt=""
      className="shrink-0 rounded-full object-cover"
      style={{ width: size, height: size }}
    />
  ) : (
    <span
      className={cn("grid shrink-0 place-items-center rounded-full font-semibold text-white")}
      style={{
        width: size,
        height: size,
        fontSize: size * 0.42,
        background: "linear-gradient(135deg, #a77af0, #6f45c9)",
      }}
    >
      {name.charAt(0).toUpperCase() || "·"}
    </span>
  );
}
