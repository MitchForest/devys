import type { Business, Employee, Look } from "../app/api.ts";
import { BusinessTile, Face, faceFor, tileGradients, tintFor, type Mood } from "./face.tsx";
import { cn } from "@/lib/utils";

/** Any look an employee or business can wear, as native `PortraitSource`. */
type Source =
  | { kind: "face"; spec: ReturnType<typeof faceFor> }
  | { kind: "emoji"; emoji: string; tint: string }
  | { kind: "photo"; url: string }
  | { kind: "initials"; text: string; tint: string };

const photoUrl = (path: string, look: Extract<Look, { kind: "photo" }>) =>
  `${path}/look/photo?v=${look.version}`;

function employeeSource(employee: Employee): Source {
  const look = employee.look;
  if (look?.kind === "face") return { kind: "face", spec: look };
  if (look?.kind === "emoji") return look;
  if (look?.kind === "photo")
    return {
      kind: "photo",
      url: photoUrl(`/api/businesses/${employee.business_id}/employees/${employee.id}`, look),
    };
  return { kind: "face", spec: faceFor(employee.id) };
}

function businessSource(business: Business): Source {
  const look = business.look;
  if (look?.kind === "emoji") return look;
  if (look?.kind === "photo")
    return { kind: "photo", url: photoUrl(`/api/businesses/${business.id}`, look) };
  return {
    kind: "initials",
    text: business.name.charAt(0).toUpperCase() || "·",
    tint: tintFor(business.id),
  };
}

/**
 * Renders a look at any size. The Face shows mood with its eyes; emoji, photos and
 * initials show it with a turning ring (working) or a dot (waiting, oops).
 */
function Portrait({
  source,
  size,
  mood = "idle",
  label,
}: {
  source: Source;
  size: number;
  mood?: Mood;
  label?: string;
}) {
  if (source.kind === "face")
    return <Face spec={source.spec} size={size} mood={mood} {...(label ? { label } : {})} />;
  const radius = size * 0.3;
  return (
    <span
      className="relative inline-grid shrink-0"
      style={{ width: size, height: size }}
      role={label ? "img" : undefined}
      aria-label={label ? `${label}, ${mood === "idle" ? "available" : mood}` : undefined}
      aria-hidden={label ? undefined : true}
    >
      {source.kind === "initials" ? (
        <BusinessTile name={source.text} tint={source.tint} size={size} />
      ) : source.kind === "emoji" ? (
        <span
          className="grid place-items-center overflow-hidden border border-hairline bg-sheet"
          style={{ borderRadius: radius, fontSize: size * 0.56, lineHeight: 1 }}
        >
          <span
            className="absolute inset-0"
            style={{
              borderRadius: radius,
              background: tileGradients[source.tint]?.[0],
              opacity: 0.14,
            }}
          />
          <span className="relative">{source.emoji}</span>
        </span>
      ) : (
        <img
          src={source.url}
          alt=""
          className="size-full border border-hairline bg-sheet-tint object-cover"
          style={{ borderRadius: radius }}
        />
      )}
      <MoodMark mood={mood} size={size} radius={radius} />
    </span>
  );
}

function MoodMark({ mood, size, radius }: { mood: Mood; size: number; radius: number }) {
  if (mood === "working" || mood === "thinking")
    return (
      <svg
        className="pointer-events-none absolute -inset-[3px] overflow-visible"
        width={size + 6}
        height={size + 6}
        aria-hidden
      >
        <rect
          x={1}
          y={1}
          width={size + 4}
          height={size + 4}
          rx={radius + 3}
          fill="none"
          stroke="var(--indigo)"
          strokeWidth={Math.max(1.5, size * 0.05)}
          strokeDasharray={`${size * 0.12} ${size * 0.08}`}
          className="animate-[dash_1.6s_linear_infinite] motion-reduce:animate-none"
          style={{ ["--dash" as string]: `${-size}px` }}
        />
      </svg>
    );
  if (mood === "waiting" || mood === "oops") {
    const dot = Math.max(7, size * 0.26);
    return (
      <span
        className={cn("absolute rounded-full", mood === "waiting" ? "bg-amber" : "bg-red")}
        style={{
          width: dot,
          height: dot,
          right: -size * 0.08,
          bottom: -size * 0.08,
          boxShadow: `0 0 0 ${Math.max(1.5, size * 0.05)}px var(--sheet)`,
        }}
      />
    );
  }
  return null;
}

export function EmployeePortrait({
  employee,
  size,
  mood,
  label,
}: {
  employee: Employee;
  size: number;
  mood?: Mood;
  label?: string;
}) {
  return (
    <Portrait
      source={employeeSource(employee)}
      size={size}
      {...(mood ? { mood } : {})}
      {...(label ? { label } : {})}
    />
  );
}

export function BusinessPortrait({ business, size }: { business: Business; size: number }) {
  return <Portrait source={businessSource(business)} size={size} />;
}
